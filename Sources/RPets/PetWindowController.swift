import AppKit

/// Builds and shows a single pet: a transparent, always-on-top, draggable panel, plus a speech
/// bubble that floats above it. Routes external commands (ControlServer) to pet state + bubble.
final class PetWindowController: NSObject {
    /// Display scale applied to the native 192×208 frame.
    private static let scale: CGFloat = 1

    let petName: String
    let sessionId: String

    /// Called when the user chooses "Close Pet" from the context menu.
    var onClose: (() -> Void)?

    private let panel: NSPanel
    private let petView: PetView

    private let bubblePanel: NSPanel
    private let bubbleView = BubbleView()

    // Tracks the current pet state so handle() can decide when to auto-dismiss.
    private var currentSessionMotion: MotionState?
    // True when the visible bubble was tagged as a permission-request bubble (via a
    // "waiting" state transition while the bubble was showing). Only those bubbles
    // are auto-dismissed when state returns to idle or working.
    private var lastBubbleWasPermission = false

    init(sprites: [MotionState: LoadedSprite], index: Int, petName: String, sessionId: String) {
        self.petName = petName
        self.sessionId = sessionId
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
        bubblePanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()
        configurePetPanel(size: size, index: index)
        configureBubblePanel()
        panel.contentView = petView
        bubblePanel.contentView = bubbleView
        petView.menu = makeContextMenu()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    /// Tears down this pet's windows (bubble + pet). The controller should then be released.
    func close() {
        if bubblePanel.parent != nil {
            panel.removeChildWindow(bubblePanel)
        }
        bubblePanel.orderOut(nil)
        bubblePanel.close()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - External command handling

    /// Applies a command: sets pet state and/or shows a bubble. Body and bubble are independent (MOTION.md §3).
    func handle(_ command: PetCommand) {
        if let stateString = command.state?.lowercased() {
            switch Self.resolveState(stateString) {
            case .clear:
                currentSessionMotion = nil
                petView.setSessionState(nil)
                log("state=\(stateString) → idle")
            case .set(let motion):
                // Tag the current bubble as permission-sourced when we enter the waiting state.
                if motion == .permission && bubblePanel.parent != nil {
                    lastBubbleWasPermission = true
                }
                currentSessionMotion = motion
                petView.setSessionState(motion)
                log("state=\(stateString) → \(motion)")
            case .unknown:
                log("state=\(stateString) → (unknown, ignored)")
            }
        }

        switch command.message {
        case .some(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                hideBubble()
                log("message cleared")
            } else {
                showBubble(trimmed)
                log("message=\(trimmed.prefix(60))\(trimmed.count > 60 ? "…" : "")")
            }
        case .none:
            // Auto-dismiss only when returning to idle/working after a permission-request bubble.
            let isIdleOrWorking = currentSessionMotion == nil || currentSessionMotion == .working
            if lastBubbleWasPermission && isIdleOrWorking && bubblePanel.parent != nil {
                hideBubble()
            }
        }
    }

    private enum StateResolution {
        case clear
        case set(MotionState)
        case unknown
    }

    /// Maps a command's `state` string to a motion. Accepts the MOTION.md state names and the
    /// SPEC.md §6 reaction vocabulary as synonyms.
    private static func resolveState(_ value: String) -> StateResolution {
        switch value {
        case "idle":                                                    return .clear
        case "working", "editing", "running":                           return .set(.working)
        case "reviewing", "review", "thinking":                         return .set(.reviewing)
        case "completed", "complete", "done", "success", "celebrating": return .set(.completed)
        case "failure", "failed", "error":                              return .set(.failure)
        case "permission", "approval", "waiting", "blocked", "testing": return .set(.permission)
        case "wave", "waving", "hello", "hi", "greeting":               return .set(.wave)
        default:                                                        return .unknown
        }
    }

    // MARK: - Bubble

    private func showBubble(_ text: String) {
        bubbleView.onDismiss = { [weak self] in self?.hideBubble() }
        let size = bubbleView.update(text: text)
        bubblePanel.setContentSize(size)
        positionBubble(size: size)
        if bubblePanel.parent == nil {
            panel.addChildWindow(bubblePanel, ordered: .above)   // follows the pet when dragged
        }
    }

    @objc func hideBubble() {
        lastBubbleWasPermission = false
        if bubblePanel.parent != nil {
            panel.removeChildWindow(bubblePanel)
        }
        bubblePanel.orderOut(nil)
    }

    private func positionBubble(size: NSSize) {
        let petFrame = panel.frame
        let gap: CGFloat = 4
        var x = petFrame.midX - size.width / 2
        var y = petFrame.maxY + gap

        // Keep the bubble on-screen: flip below the pet if it would clip the top edge.
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            if y + size.height > visible.maxY { y = petFrame.minY - size.height - gap }
            x = min(max(x, visible.minX), visible.maxX - size.width)
        }
        bubblePanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Panels

    private func configurePetPanel(size: NSSize, index: Int) {
        panel.isReleasedWhenClosed = false   // ARC owns the controller; avoid double-free on close()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false   // dragging handled explicitly in PetView
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.setFrame(NSRect(origin: defaultOrigin(for: size, index: index), size: size), display: false)
    }

    private func configureBubblePanel() {
        bubblePanel.isReleasedWhenClosed = false
        bubblePanel.isFloatingPanel = true
        bubblePanel.level = .floating
        bubblePanel.isOpaque = false
        bubblePanel.backgroundColor = .clear
        bubblePanel.hasShadow = false
        bubblePanel.ignoresMouseEvents = false      // needed for hover tracking and dismiss button
        bubblePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        bubblePanel.hidesOnDeactivate = false
    }

    private func defaultOrigin(for size: NSSize, index: Int) -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let stagger = CGFloat(index) * 48   // offset each new pet so they don't perfectly overlap
        return NSPoint(x: visible.midX - size.width / 2 + stagger, y: visible.maxY - size.height - 140 - stagger)
    }

    // MARK: - Context menu

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        let labelItem = NSMenuItem(title: "\(petName)  ·  \(sessionId)", action: nil, keyEquivalent: "")
        labelItem.isEnabled = false
        menu.addItem(labelItem)

        menu.addItem(.separator())

        let idleItem = NSMenuItem(title: "Go Idle", action: #selector(goIdleFromMenu), keyEquivalent: "")
        idleItem.target = self
        idleItem.isEnabled = true
        menu.addItem(idleItem)

        let hideItem = NSMenuItem(title: "Hide Bubble", action: #selector(hideBubble), keyEquivalent: "")
        hideItem.target = self
        hideItem.isEnabled = true
        menu.addItem(hideItem)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: "Close Pet", action: #selector(closeFromMenu), keyEquivalent: "")
        closeItem.target = self
        closeItem.isEnabled = true
        menu.addItem(closeItem)

        return menu
    }

    @objc private func goIdleFromMenu() {
        petView.setSessionState(nil)
        hideBubble()
    }

    @objc private func closeFromMenu() {
        onClose?()
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("RPets [\(petName) | \(sessionId)]: \(message)\n".utf8))
    }
}
