import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let leftGap: CGFloat = 12
    /// Space between the bottom of the menu bar and the top of the pill.
    private let topGap: CGFloat = 6
    /// In full screen, the pill hides when the menu bar slides down if it sits within this distance
    /// below the menu bar (apps' toolbars slide down with it).
    private let slideDownDepth: CGFloat = 100

    private let stopwatch = Stopwatch()
    private let view = StopwatchView()
    private lazy var panel = StopwatchPanel(view: view)
    private let watcher = MenuBarWatcher()
    private var statusItem: NSStatusItem?
    private var tickTimer: Timer?
    /// True in full screen (or with an auto-hiding menu bar): the menu bar slides down only when the mouse goes up.
    private var menuBarAutoHides = false
    private var userHidden = false
    /// Where the pill was dragged to (window origin). Nil = default top-left spot. Not saved between launches.
    private var draggedOrigin: NSPoint?
    private var hoverMonitor: Any?
    /// Runs only while the mouse is over the pill, to notice ⌘ being pressed or released.
    private var hoverTimer: Timer?

    private let toggleItem = NSMenuItem(title: "Start", action: #selector(toggle), keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "Reset", action: #selector(reset), keyEquivalent: "")
    private let visibilityItem = NSMenuItem(title: "Hide Stopwatch", action: #selector(toggleVisibility), keyEquivalent: "")
    private let resetPositionItem = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        view.onClick = { [weak self] in self?.toggle() }
        view.onDoubleClick = { [weak self] in self?.reset() }
        view.onDrag = { [weak self] origin in
            self?.draggedOrigin = origin
            self?.reposition()
        }
        refreshTime()

        setUpStatusItem()

        watcher.ownWindowNumber = panel.windowNumber
        watcher.onChange = { [weak self] state in self?.menuBarChanged(state) }
        watcher.start()
        menuBarAutoHides = !watcher.state.menuBarVisible
        reposition()
        panel.orderFrontRegardless()
        startHoverTracking()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reposition()
                self?.watcher.kick()
            }
        }
    }

    // MARK: Stopwatch

    @objc private func toggle() {
        stopwatch.toggle()
        refreshTime()
        scheduleTick()
    }

    @objc private func reset() {
        stopwatch.reset()
        refreshTime()
        scheduleTick()
    }

    private func refreshTime() {
        let elapsed = stopwatch.elapsed
        view.time = Stopwatch.format(elapsed)
        // Past one hour only minutes show, so the colon blinks to show it's still running.
        view.colonVisible = !(stopwatch.isRunning && elapsed >= 3600 && Int(elapsed) % 2 == 1)
    }

    /// Wakes up once per second, right after each whole second of elapsed time. No timer while stopped.
    private func scheduleTick() {
        tickTimer?.invalidate()
        tickTimer = nil
        guard stopwatch.isRunning else { return }
        let elapsed = stopwatch.elapsed
        let delay = elapsed.rounded(.down) + 1 - elapsed + 0.005
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshTime()
                self?.scheduleTick()
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    // MARK: Position and visibility

    private func menuBarChanged(_ state: MenuBarWatcher.State) {
        if state.settled {
            menuBarAutoHides = !state.menuBarVisible
        }
        updateVisibility()
    }

    /// Hides the pill only when something actually covers it: an open drop-down menu,
    /// or (in full screen) the menu bar sliding down while the pill sits near the top.
    private func updateVisibility() {
        guard let screen = NSScreen.screens.first else { return }
        let state = watcher.state
        let pill = pillFrame
        let menuCoversPill = state.menuFrames.contains { $0.intersects(pill) }
        let nearTop = pill.maxY >= screen.frame.maxY - watcher.menuBarHeight - slideDownDepth
        let menuBarSlidDown = menuBarAutoHides && nearTop && (state.menuBarVisible || state.mouseAtTop)
        panel.isShown = !userHidden && !menuCoversPill && !menuBarSlidDown
    }

    /// The visible pill, without the shadow margin.
    private var pillFrame: NSRect {
        let margin = StopwatchView.shadowMargin
        return panel.frame.insetBy(dx: margin, dy: margin)
    }

    private func reposition() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        let margin = StopwatchView.shadowMargin
        let size = panel.frame.size

        // Default: top-left, fully below the menu bar area so it stays clickable in full screen too.
        let pillTop = frame.maxY - watcher.menuBarHeight - topGap
        let origin = draggedOrigin ?? NSPoint(
            x: frame.minX + leftGap - margin,
            y: pillTop + margin - size.height)

        // Keep it on the main screen and below the menu bar.
        let maxY = frame.maxY - watcher.menuBarHeight - size.height + margin
        let clamped = NSPoint(
            x: min(max(origin.x, frame.minX - margin), frame.maxX - size.width + margin),
            y: min(max(origin.y, frame.minY - margin), maxY))
        panel.setFrameOrigin(clamped)
        updateVisibility()
    }

    @objc private func resetPosition() {
        draggedOrigin = nil
        reposition()
    }

    // MARK: Hover and ⌘

    private func startHoverTracking() {
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHover() }
        }
    }

    private func checkHover() {
        let margin = StopwatchView.shadowMargin
        let pill = panel.frame.insetBy(dx: margin, dy: margin)
        let hovered = pill.contains(NSEvent.mouseLocation)
        panel.isHovered = hovered
        panel.isCommandHeld = NSEvent.modifierFlags.contains(.command)

        if hovered, hoverTimer == nil {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkHover() }
            }
            RunLoop.main.add(timer, forMode: .common)
            hoverTimer = timer
        } else if !hovered {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    // MARK: Menu bar icon

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "Stopwatch")
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        for menuItem in [toggleItem, resetItem, visibilityItem] {
            menuItem.target = self
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())
        resetPositionItem.target = self
        menu.addItem(resetPositionItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Stopwatch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        toggleItem.title = stopwatch.isRunning ? "Pause" : "Start"
        visibilityItem.title = userHidden ? "Show Stopwatch" : "Hide Stopwatch"
        resetPositionItem.isEnabled = draggedOrigin != nil
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleVisibility() {
        userHidden.toggle()
        updateVisibility()
    }

    @objc private func toggleOpenAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
