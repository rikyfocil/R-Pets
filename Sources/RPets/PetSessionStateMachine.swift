import Foundation

/// Lets `PetSessionStateMachine` auto-apply a `TransitionDecision.delay` later, unless it's
/// preempted first. Implemented by `PetWindowController` alongside `BubbleControlling`, using its
/// own independent timer slot so a delayed transition and a held-back bubble reveal don't collide.
protocol TransitionScheduling: AnyObject {
    /// Schedules `action` to run after `delay`, replacing any previously-scheduled action.
    func scheduleTransition(after delay: TimeInterval, _ action: @escaping () -> Void)
    /// Cancels a pending `scheduleTransition` action, if any.
    func cancelScheduledTransition()
}

/// Owns the pet's session motion and the active `PetStateBehavior` for it.
///
/// `PetWindowController.handle(_:)` resolves an incoming command into a transition request and/or
/// a message, then forwards both here. This is the single authority over `sessionMotion`: a
/// request can be applied immediately, delayed, or rejected by the currently-active behavior, and
/// `onMotionChange` fires only when the motion actually changes — whether right away or after a
/// delayed transition auto-applies. See `PetStateBehavior` for the per-state policies.
final class PetSessionStateMachine {
    typealias Context = BubbleControlling & TransitionScheduling

    /// `unowned`: `context` is the `PetWindowController` that owns this state machine, so a
    /// strong reference here would create a retain cycle (controller → state machine →
    /// controller). The state machine never outlives its owner.
    private unowned let context: Context
    private var behavior: PetStateBehavior

    /// The pet's current session motion (`nil` == idle).
    private(set) var sessionMotion: MotionState?

    /// Called whenever `sessionMotion` actually changes — immediately, or later when a delayed
    /// transition auto-applies — so the caller can update the pet's body animation.
    var onMotionChange: ((MotionState?) -> Void)?

    init(context: Context) {
        self.context = context
        self.behavior = Self.behavior(for: nil)
    }

    /// Requests a transition to `motion` (`nil` == idle). No-op if it matches the current motion.
    /// Otherwise the active behavior decides: apply immediately, ignore, or apply later unless a
    /// further request preempts it first.
    func requestTransition(to motion: MotionState?) {
        guard motion != sessionMotion else { return }
        switch behavior.decide(transitionTo: motion) {
        case .allow:
            apply(motion)
        case .reject:
            break
        case .delay(let delay):
            context.scheduleTransition(after: delay) { [weak self] in
                self?.apply(motion)
            }
        }
    }

    /// Forces the session motion to `motion`, bypassing the active behavior's transition
    /// decision. For explicit user actions (e.g. "Go Idle" from the context menu) that should
    /// never be delayed or rejected.
    func forceTransition(to motion: MotionState?) {
        guard motion != sessionMotion else { return }
        apply(motion)
    }

    /// Routes an incoming, already-trimmed `message` from `source` to the active behavior. Empty
    /// means "hide".
    func receive(message text: String, source: MessageSource) {
        behavior.receive(message: text, source: source, bubble: context)
    }

    private func apply(_ motion: MotionState?) {
        context.cancelScheduledTransition()
        behavior.willDeactivate(context)
        sessionMotion = motion
        behavior = Self.behavior(for: motion)
        behavior.didActivate(context)
        onMotionChange?(motion)
    }

    /// Selects the `PetStateBehavior` for a session motion. `permission` gets the sticky/hold-back
    /// bubble policy; `completed` holds briefly before settling to idle; idle and `working`
    /// dismiss a leftover permission bubble on entry; everything else leaves the bubble alone and
    /// allows every transition immediately.
    private static func behavior(for motion: MotionState?) -> PetStateBehavior {
        switch motion {
        case .permission:
            return PermissionBubbleBehavior()
        case .completed:
            return CompletedStateBehavior()
        case nil, .working:
            return StandardBubbleBehavior(dismissesPermissionBubble: true)
        default:
            return StandardBubbleBehavior(dismissesPermissionBubble: false)
        }
    }
}
