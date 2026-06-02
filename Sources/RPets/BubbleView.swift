import AppKit

/// A rounded speech bubble that sizes itself to its text. Measured via the text cell's
/// `cellSize(forBounds:)` — the same path the field uses to render — so content never clips.
final class BubbleView: NSView {
    static let maxWidth: CGFloat = 300
    static let padding: CGFloat = 14
    static let cornerRadius: CGFloat = 14
    static let font = NSFont.systemFont(ofSize: 13, weight: .medium)

    private let label: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.drawsBackground = false
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.font = BubbleView.font
        field.textColor = .black                 // readable on the white bubble in any appearance
        field.alignment = .center
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.autoresizingMask = []
        return field
    }()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.96).cgColor
        layer?.cornerRadius = Self.cornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 0, alpha: 0.12).cgColor
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Updates the text and returns the bubble's size, measured with the text cell (matches rendering).
    @discardableResult
    func update(text: String) -> NSSize {
        label.stringValue = text

        let innerMaxWidth = Self.maxWidth - 2 * Self.padding
        let measureBounds = NSRect(x: 0, y: 0, width: innerMaxWidth, height: .greatestFiniteMagnitude)
        let cellSize = label.cell?.cellSize(forBounds: measureBounds) ?? .zero
        let labelWidth = min(ceil(cellSize.width), innerMaxWidth)
        let labelHeight = ceil(cellSize.height)

        let size = NSSize(width: labelWidth + 2 * Self.padding,
                          height: labelHeight + 2 * Self.padding)
        frame = NSRect(origin: .zero, size: size)
        label.frame = NSRect(x: Self.padding, y: Self.padding, width: labelWidth, height: labelHeight)
        return size
    }
}
