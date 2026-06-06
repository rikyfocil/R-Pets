import AppKit

/// A rounded speech bubble that sizes itself to its text. Measured via the text cell's
/// `cellSize(forBounds:)` — the same path the field uses to render — so content never clips.
/// Shows a dismiss "×" button when the cursor enters the bubble.
final class BubbleView: NSView {
    static let maxWidth: CGFloat = 300
    static let padding: CGFloat = 14
    static let cornerRadius: CGFloat = 14
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let dismissSize: CGFloat = 16
    private static let dismissMargin: CGFloat = 5

    /// Called when the user clicks the dismiss button.
    var onDismiss: (() -> Void)?

    private let label: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.drawsBackground = false
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.font = BubbleView.font
        field.textColor = .black
        field.alignment = .center
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.autoresizingMask = []
        return field
    }()

    private let dismissButton: NSButton = {
        let button = NSButton()
        button.title = "×"
        button.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = dismissSize / 2
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = NSColor(white: 0, alpha: 0.18).cgColor
        button.contentTintColor = .black
        button.alphaValue = 0
        return button
    }()

    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.96).cgColor
        layer?.cornerRadius = Self.cornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 0, alpha: 0.12).cgColor
        addSubview(label)
        addSubview(dismissButton)
        dismissButton.target = self
        dismissButton.action = #selector(dismissTapped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Updates the text, resets the hover button, and returns the bubble's new size.
    @discardableResult
    func update(text: String) -> NSSize {
        label.stringValue = text
        dismissButton.alphaValue = 0   // always start hidden; hover re-shows it

        let innerMaxWidth = Self.maxWidth - 2 * Self.padding
        let measureBounds = NSRect(x: 0, y: 0, width: innerMaxWidth, height: .greatestFiniteMagnitude)
        let cellSize = label.cell?.cellSize(forBounds: measureBounds) ?? .zero
        let labelWidth = min(ceil(cellSize.width), innerMaxWidth)
        let labelHeight = ceil(cellSize.height)

        let size = NSSize(width: labelWidth + 2 * Self.padding,
                          height: labelHeight + 2 * Self.padding)
        frame = NSRect(origin: .zero, size: size)
        label.frame = NSRect(x: Self.padding, y: Self.padding, width: labelWidth, height: labelHeight)

        let d = Self.dismissSize
        let m = Self.dismissMargin
        // Top-right corner (AppKit: y=0 is bottom, so top = size.height - d - m)
        dismissButton.frame = NSRect(x: size.width - d - m, y: size.height - d - m, width: d, height: d)

        return size
    }

    // MARK: - Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            dismissButton.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            dismissButton.animator().alphaValue = 0
        }
    }

    // Only the dismiss button captures clicks; everything else passes through to the window below.
    override func hitTest(_ point: NSPoint) -> NSView? {
        dismissButton.frame.contains(point) ? super.hitTest(point) : nil
    }

    // MARK: - Dismiss

    @objc private func dismissTapped() {
        onDismiss?()
    }
}
