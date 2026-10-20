import AppKit

/// The pill: white rounded outline, stopwatch icon and time, with a soft drop shadow.
final class StopwatchView: NSView {
    /// A second click starting within this time after the first one ends counts as a double-click.
    static let doubleClickInterval: TimeInterval = 0.3
    /// A press only counts as a click (start/stop) if released within this time.
    static let maxClickDuration: TimeInterval = 0.4
    /// Moving at least this far while pressed turns the press into a drag.
    static let dragThreshold: CGFloat = 3

    /// Empty space around the pill so the shadow is not clipped.
    static let shadowMargin: CGFloat = 4

    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    /// Called while dragging, with the window origin the pill should move to.
    var onDrag: ((NSPoint) -> Void)?

    var time = "00:00" { didSet { if time != oldValue { needsDisplay = true } } }
    var colonVisible = true { didSet { if colonVisible != oldValue { needsDisplay = true } } }

    private let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    private let icon: NSImage? = {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        return NSImage(systemSymbolName: "stopwatch", accessibilityDescription: "Stopwatch")?
            .withSymbolConfiguration(config)
    }()

    private let pillHeight: CGFloat = 24
    private let lineWidth: CGFloat = 1.5
    let cornerRadius: CGFloat = 7
    private let leftPadding: CGFloat = 7
    private let iconTextGap: CGFloat = 5
    private let rightPadding: CGFloat = 9

    /// When the last click ended, for double-click detection.
    private var lastClickEnd: TimeInterval?
    private var press: (mouse: NSPoint, origin: NSPoint, time: TimeInterval, dragging: Bool)?

    init() {
        super.init(frame: .zero)
        setFrameSize(fittingSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var fittingSize: NSSize {
        let textWidth = ("00:00" as NSString).size(withAttributes: [.font: font]).width
        let iconWidth = icon?.size.width ?? 0
        let pillWidth = leftPadding + iconWidth + iconTextGap + ceil(textWidth) + rightPadding
        let m = Self.shadowMargin * 2
        return NSSize(width: ceil(pillWidth) + m, height: pillHeight + m)
    }

    /// The area inside the outline, where the frosted background goes (same shape as the outline).
    var backgroundRect: NSRect {
        let pill = bounds.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin)
        return pill.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
    }

    // MARK: Clicks

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Decided on release: moved ≥ 3 px = drag (never starts/stops);
    /// released within 0.4 s without moving = click; a quick second click = double-click (reset).
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        press = (NSEvent.mouseLocation, window.frame.origin, event.timestamp, false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var press else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - press.mouse.x
        let dy = mouse.y - press.mouse.y
        if !press.dragging, hypot(dx, dy) >= Self.dragThreshold {
            press.dragging = true
            lastClickEnd = nil
            self.press = press
        }
        if press.dragging {
            onDrag?(NSPoint(x: press.origin.x + dx, y: press.origin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let press else { return }
        self.press = nil
        guard !press.dragging, event.timestamp - press.time <= Self.maxClickDuration else { return }

        if let last = lastClickEnd, press.time - last <= Self.doubleClickInterval {
            lastClickEnd = nil
            onDoubleClick?()
        } else {
            lastClickEnd = event.timestamp
            onClick?()
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let pill = bounds.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin)
        let outline = NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = NSSize(width: 0.75, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.set()

        NSColor.white.setStroke()
        outline.lineWidth = lineWidth
        outline.stroke()

        var x = pill.minX + leftPadding
        if let icon {
            let y = pill.midY - icon.size.height / 2
            icon.draw(in: NSRect(x: x, y: y, width: icon.size.width, height: icon.size.height))
            x += icon.size.width + iconTextGap
        }

        let text = NSMutableAttributedString(
            string: time, attributes: [.font: font, .foregroundColor: NSColor.white])
        if !colonVisible {
            let colon = (time as NSString).range(of: ":")
            if colon.location != NSNotFound {
                text.addAttribute(.foregroundColor, value: NSColor.clear, range: colon)
            }
        }
        // Center the digits (cap height) vertically.
        let baseline = pill.midY - font.capHeight / 2
        text.draw(at: NSPoint(x: x, y: baseline + font.descender))
    }
}
