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

    /// Owns the session motion and decides whether/when it transitions, and whether the bubble
    /// shows, hides, or is held back, in response to commands — see `PetSessionStateMachine` and
    /// `PetStateBehavior`. Set right after `super.init()` since it needs `self` as its `Context`.
    private var sessionStateMachine: PetSessionStateMachine!

    // MARK: - BubbleControlling storage (exposed read-only via the extension below)
    private var bubblePriority: BubblePriority?
    private var bubbleShownAt: Date?
    private var pendingBubbleWork: DispatchWorkItem?
    private var pendingTransitionWork: DispatchWorkItem?

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
        sessionStateMachine = PetSessionStateMachine(context: self)
        sessionStateMachine.onMotionChange = { [weak self] motion in self?.petView.setSessionState(motion) }
        configurePetPanel(size: size, index: index)
        configureBubblePanel()
        panel.contentView = petView
        bubblePanel.contentView = bubbleView
        bubbleView.onDismiss = { [weak self] in self?.hideBubble() }
        petView.menu = makeContextMenu()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    /// Tears down this pet's windows (bubble + pet). The controller should then be released.
    func close() {
        if isBubbleShowing {
            panel.removeChildWindow(bubblePanel)
        }
        bubblePanel.orderOut(nil)
        bubblePanel.close()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - External command handling

    /// Applies a command: requests a session-motion transition and/or shows a bubble. Body and
    /// bubble are independent (docs/MOTION.md §3) — the session state machine decides whether the
    /// transition applies now, later, or not at all, and what happens to the bubble.
    func handle(_ command: PetCommand) {
        if let stateString = command.state?.lowercased() {
            switch Self.resolveState(stateString) {
            case .clear:
                sessionStateMachine.requestTransition(to: nil)
                log("state=\(stateString) → idle (requested)")
            case .set(let motion):
                sessionStateMachine.requestTransition(to: motion)
                log("state=\(stateString) → \(motion) (requested)")
            case .unknown:
                log("state=\(stateString) → (unknown, ignored)")
            }
        }

        if let text = command.message {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = MessageSource(rawValue: command.source)
            sessionStateMachine.receive(message: trimmed, source: source)
            log(trimmed.isEmpty ? "message cleared" : "message=\(truncatedForLog(trimmed)) source=\(source)")
        }
    }

    private func truncatedForLog(_ text: String) -> String {
        text.count > 60 ? "\(text.prefix(60))…" : text
    }

    private enum StateResolution {
        case clear
        case set(MotionState)
        case unknown
    }

    /// Maps a command's `state` string to a motion. Accepts the docs/MOTION.md state names and the
    /// docs/SPEC.md §6 reaction vocabulary as synonyms.
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

    // MARK: - Bubble positioning

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
        sessionStateMachine.forceTransition(to: nil)
        hideBubble()
    }

    @objc private func closeFromMenu() {
        onClose?()
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("RPets [\(petName) | \(sessionId)]: \(message)\n".utf8))
    }
}

// MARK: - BubbleControlling

extension PetWindowController: BubbleControlling {
    /// True while the bubble is attached to the pet panel as a child window — the bubble is only
    /// ever attached/detached together with being shown/hidden, so this doubles as its visibility.
    var isBubbleShowing: Bool { bubblePanel.parent != nil }

    var currentBubblePriority: BubblePriority? { bubblePriority }

    var currentBubbleShownAt: Date? { bubbleShownAt }

    func showBubble(_ text: String, priority: BubblePriority) {
        bubblePriority = priority
        bubbleShownAt = Date()
        let size = bubbleView.update(text: text)
        bubblePanel.setContentSize(size)
        positionBubble(size: size)
        if !isBubbleShowing {
            panel.addChildWindow(bubblePanel, ordered: .above)   // follows the pet when dragged
        }
    }

    @objc func hideBubble() {
        bubblePriority = nil
        bubbleShownAt = nil
        cancelScheduled()
        if isBubbleShowing {
            panel.removeChildWindow(bubblePanel)
        }
        bubblePanel.orderOut(nil)
    }

    func scheduleDelayed(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        pendingBubbleWork?.cancel()
        let work = DispatchWorkItem(block: action)
        pendingBubbleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelScheduled() {
        pendingBubbleWork?.cancel()
        pendingBubbleWork = nil
    }
}

// MARK: - TransitionScheduling

extension PetWindowController: TransitionScheduling {
    func scheduleTransition(after delay: TimeInterval, _ action: @escaping () -> Void) {
        pendingTransitionWork?.cancel()
        let work = DispatchWorkItem(block: action)
        pendingTransitionWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelScheduledTransition() {
        pendingTransitionWork?.cancel()
        pendingTransitionWork = nil
    }
}
