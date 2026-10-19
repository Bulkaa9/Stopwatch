import AppKit

/// Borderless, transparent window that floats above everything,
/// including full-screen apps, on every desktop (Space).
///
/// Clicks pass through to the app behind it. While the mouse is over it the pill fades,
/// and holding ⌘ makes it solid and clickable.
final class StopwatchPanel: NSPanel {
    static let hoverAlpha: CGFloat = 0.2

    init(view: StopwatchView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: view.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        contentView = Self.makeContent(view)
    }

    /// Dark frosted-glass background, shaped like the outline, under the stopwatch drawing.
    private static func makeContent(_ view: StopwatchView) -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: view.frame.size))

        let background = NSVisualEffectView(frame: view.backgroundRect)
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.appearance = NSAppearance(named: .darkAqua)
        background.maskImage = roundedMask(radius: view.cornerRadius)

        container.addSubview(background)
        container.addSubview(view)
        return container
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // Clicking the stopwatch must never take focus away from the app you're working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// False while hidden for the menu bar, a drop-down menu, or by the user.
    var isShown = true { didSet { applyState() } }
    var isHovered = false { didSet { applyState() } }
    var isCommandHeld = false { didSet { applyState() } }

    private var targetAlpha: CGFloat = 1

    private func applyState() {
        ignoresMouseEvents = !(isShown && isHovered && isCommandHeld)

        let alpha: CGFloat
        if !isShown {
            alpha = 0
        } else if isHovered && !isCommandHeld {
            alpha = Self.hoverAlpha
        } else {
            alpha = 1
        }
        guard alpha != targetAlpha else { return }
        targetAlpha = alpha
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = alpha
        }
    }
}
