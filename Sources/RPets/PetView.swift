import AppKit

/// Layer-backed view that loops the pet's sprite animation, reacts to hover and drag, and lets the
/// user drag the pet around. Precedence and per-state behavior follow MOTION.md §§2–4.
final class PetView: NSView {
    /// Minimum per-event horizontal movement (points) to commit a drag direction — hysteresis (MOTION.md §4.2).
    private static let dragDeadzone: CGFloat = 2.5

    private let spriteLayer = CALayer()
    private let sprites: [MotionState: LoadedSprite]

    private var currentMotion: MotionState = .idle
    private var didStartAnimating = false

    private var sessionState: MotionState?       // externally-set state (ControlServer); nil == idle
    private var isHovering = false
    private var isDragging = false
    private var dragDirection: MotionState?       // .runRight / .runLeft once a direction is detected
    private var dragMouseStart: NSPoint = .zero
    private var dragWindowStart: NSPoint = .zero
    private var lastPointerX: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    init(sprites: [MotionState: LoadedSprite]) {
        self.sprites = sprites
        super.init(frame: .zero)
        wantsLayer = true
        setupLayer()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayer() {
        spriteLayer.contentsGravity = .resizeAspect
        spriteLayer.magnificationFilter = .nearest    // crisp pixel art when scaling up
        spriteLayer.minificationFilter = .trilinear   // smooth when scaling down
        spriteLayer.contents = sprites[.idle]?.frames.first
        layer?.addSublayer(spriteLayer)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        spriteLayer.frame = bounds
        spriteLayer.contentsScale = window?.backingScaleFactor ?? 2
        if !didStartAnimating {
            didStartAnimating = true
            play(currentMotion)
        }
    }

    override func layout() {
        super.layout()
        spriteLayer.frame = bounds
    }

    // MARK: - State resolution & playback

    /// Sets the externally-driven session state (`nil` falls back to idle), then re-resolves.
    func setSessionState(_ motion: MotionState?) {
        sessionState = motion
        resolveMotion()
    }

    /// Picks the motion to display, by precedence: drag > hover > session state > idle (MOTION.md §3).
    private func resolveMotion() {
        if isDragging {
            // Keep the pre-drag/last animation until a clear horizontal direction is detected.
            guard let dragDirection else { return }
            play(dragDirection)
        } else if isHovering {
            play(.wave)
        } else if let sessionState {
            play(sessionState)
        } else {
            play(.idle)
        }
    }

    /// Swaps the looping animation, only when the target motion actually changes.
    private func play(_ motion: MotionState) {
        guard motion != currentMotion || spriteLayer.animation(forKey: "sprite") == nil else { return }
        guard let sprite = sprites[motion], !sprite.frames.isEmpty else { return }
        currentMotion = motion

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = sprite.frames
        animation.calculationMode = .discrete
        animation.keyTimes = (0..<sprite.frames.count).map { NSNumber(value: Double($0) / Double(sprite.frames.count)) }
        animation.duration = Double(sprite.durationMs) / 1000.0
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        spriteLayer.contents = sprite.frames.first
        spriteLayer.removeAnimation(forKey: "sprite")
        spriteLayer.add(animation, forKey: "sprite")
    }

    // MARK: - Hover (MOTION.md §4.3)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        resolveMotion()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        resolveMotion()
    }

    // MARK: - Dragging — move the window + run toward the drag direction (MOTION.md §4.2)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragDirection = nil
        dragMouseStart = NSEvent.mouseLocation
        dragWindowStart = window?.frame.origin ?? .zero
        lastPointerX = dragMouseStart.x
        // No direction yet → keep the current (pre-drag) animation.
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation

        // Move the borderless window with the cursor.
        window.setFrameOrigin(NSPoint(
            x: dragWindowStart.x + (current.x - dragMouseStart.x),
            y: dragWindowStart.y + (current.y - dragMouseStart.y)
        ))

        // Commit a run direction from horizontal motion; keep-last on vertical/stationary moves.
        let dx = current.x - lastPointerX
        lastPointerX = current.x
        if dx > Self.dragDeadzone {
            dragDirection = .runRight
        } else if dx < -Self.dragDeadzone {
            dragDirection = .runLeft
        }
        resolveMotion()
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        dragDirection = nil
        resolveMotion()
    }
}
