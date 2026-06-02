import AppKit

/// Layer-backed view that loops a sprite animation and lets the user drag the pet around.
final class PetView: NSView {
    private let spriteLayer = CALayer()
    private let frames: [CGImage]
    private let durationMs: Int
    private var animationStarted = false

    private var dragMouseStart: NSPoint = .zero
    private var dragWindowStart: NSPoint = .zero

    init(frames: [CGImage], durationMs: Int) {
        self.frames = frames
        self.durationMs = durationMs
        super.init(frame: .zero)
        wantsLayer = true
        setupLayer()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayer() {
        spriteLayer.contentsGravity = .resizeAspect
        spriteLayer.magnificationFilter = .nearest    // crisp pixel art when scaling up
        spriteLayer.minificationFilter = .trilinear   // smooth when scaling down
        spriteLayer.contents = frames.first
        layer?.addSublayer(spriteLayer)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        spriteLayer.frame = bounds
        spriteLayer.contentsScale = window?.backingScaleFactor ?? 2
        startIdleAnimationIfNeeded()
    }

    override func layout() {
        super.layout()
        spriteLayer.frame = bounds
    }

    private func startIdleAnimationIfNeeded() {
        guard !animationStarted, !frames.isEmpty else { return }
        animationStarted = true

        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.calculationMode = .discrete
        animation.keyTimes = (0..<frames.count).map { NSNumber(value: Double($0) / Double(frames.count)) }
        animation.duration = Double(durationMs) / 1000.0
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        spriteLayer.add(animation, forKey: "idle")
    }

    // MARK: - Dragging (move the borderless window with the cursor)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragMouseStart = NSEvent.mouseLocation
        dragWindowStart = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let current = NSEvent.mouseLocation
        let origin = NSPoint(
            x: dragWindowStart.x + (current.x - dragMouseStart.x),
            y: dragWindowStart.y + (current.y - dragMouseStart.y)
        )
        window.setFrameOrigin(origin)
    }
}
