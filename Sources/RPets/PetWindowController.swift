import AppKit

/// Builds and shows a single pet: a transparent, always-on-top, draggable panel.
final class PetWindowController {
    /// Display scale applied to the native 192×208 frame.
    private static let scale: CGFloat = 1

    private let panel: NSPanel
    private let petView: PetView

    init(petDirectory: URL) throws {
        let sheetURL = try PetAsset.resolveSpritesheet(at: petDirectory)
        let sprites = try SpriteLoader.loadSprites(sheetURL: sheetURL, motions: [.idle, .runRight, .runLeft, .wave])

        let size = NSSize(
            width: CGFloat(SpriteSheet.frameWidth) * Self.scale,
            height: CGFloat(SpriteSheet.frameHeight) * Self.scale
        )

        petView = PetView(sprites: sprites)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel(size: size)
        panel.contentView = petView
    }

    private func configurePanel(size: NSSize) {
        // Always-on-top, transparent, follows the user across Spaces — see SPEC.md §2.
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false   // dragging handled explicitly in PetView
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.setFrame(NSRect(origin: defaultOrigin(for: size), size: size), display: false)
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 80)
    }

    func show() {
        panel.orderFrontRegardless()
    }
}
