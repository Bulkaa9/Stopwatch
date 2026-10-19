import AppKit

/// Watches the main screen's menu bar: whether it is showing and whether a drop-down menu is open.
///
/// Signals (from the window list, no permissions needed):
/// - Menu bar showing: status-item windows (Control Center, other apps' icons) sit at the top edge.
///   In full screen they disappear while the menu bar is hidden.
/// - Drop-down open: a window at the pop-up menu level exists.
///
/// To stay light it only polls while the mouse is in the menu bar area, while a menu is open,
/// and briefly after switching desktops. Otherwise it does nothing.
@MainActor
final class MenuBarWatcher {
    struct State: Equatable {
        var menuBarVisible = true
        var menuOpen = false
        /// Open drop-down menus, in screen coordinates (same as window frames).
        var menuFrames: [NSRect] = []
        /// Mouse touching the top edge (in full screen this is what reveals the menu bar).
        var mouseAtTop = false
        /// Nothing has changed for a moment and the mouse is away from the menu bar.
        var settled = false
    }

    var onChange: ((State) -> Void)?
    /// The stopwatch's own window, ignored when reading the window list.
    var ownWindowNumber = 0

    private(set) var state = State()
    private(set) var menuBarHeight: CGFloat = 24

    private let pollInterval: TimeInterval = 0.15
    private let settleDelay: TimeInterval = 0.6
    private let stopDelay: TimeInterval = 1.2

    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var lastActivity: TimeInterval = 0

    func start() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseActivity() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.mouseActivity() }
            return event
        }) {
            monitors.append(local)
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.kick() }
        }
        kick()
    }

    /// Re-check now and keep checking until things settle.
    func kick() {
        lastActivity = Self.now()
        if pollTimer == nil {
            let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            timer.tolerance = 0.03
            // Common modes so polling continues while a menu is being tracked.
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
        poll()
    }

    private func mouseActivity() {
        if isMouseInMenuBarArea() { kick() }
    }

    private func poll() {
        let now = Self.now()
        let screen = CGDisplayBounds(CGMainDisplayID())
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))

        var menuBarVisible = false
        var menuFrames: [NSRect] = []
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let number = window[kCGWindowNumber as String] as? Int,
                  number != ownWindowNumber,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.intersects(screen)
            else { continue }

            if layer == mainMenuLevel, bounds.minY == screen.minY, bounds.height > 0 {
                menuBarHeight = bounds.height
            } else if layer == statusLevel, bounds.minY == screen.minY, bounds.height > 0 {
                menuBarVisible = true
            } else if layer == menuLevel {
                // Window list uses top-left origin; screen coordinates use bottom-left.
                menuFrames.append(NSRect(
                    x: bounds.minX, y: screen.maxY - bounds.maxY,
                    width: bounds.width, height: bounds.height))
            }
        }

        let menuOpen = !menuFrames.isEmpty
        let inMenuBarArea = isMouseInMenuBarArea()
        if menuBarVisible != state.menuBarVisible || menuFrames != state.menuFrames {
            lastActivity = now
        }
        let quiet = !inMenuBarArea && !menuOpen
        var newState = State()
        newState.menuBarVisible = menuBarVisible
        newState.menuOpen = menuOpen
        newState.menuFrames = menuFrames
        newState.mouseAtTop = isMouseAtTopEdge()
        newState.settled = quiet && now - lastActivity >= settleDelay

        if newState != state {
            state = newState
            onChange?(newState)
        }
        if quiet && now - lastActivity >= stopDelay {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func isMouseInMenuBarArea() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let p = NSEvent.mouseLocation
        let f = screen.frame
        return p.x >= f.minX && p.x <= f.maxX && p.y <= f.maxY && p.y >= f.maxY - menuBarHeight
    }

    private func isMouseAtTopEdge() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let p = NSEvent.mouseLocation
        let f = screen.frame
        return p.x >= f.minX && p.x <= f.maxX && p.y >= f.maxY - 1
    }

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
