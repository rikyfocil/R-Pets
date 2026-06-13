import Foundation

/// What a currently-visible bubble represents — drives auto-dismiss and replacement-priority
/// rules (MOTION.md §3, §4.6).
enum BubblePriority {
    /// A normal status message (`say` / plain `message`). Replaceable at any time, and does not
    /// survive a session-state transition on its own.
    case normal
    /// A sticky approval prompt. No auto-dismiss TTL — it persists until the session leaves
    /// `permission` (MOTION.md §4.6) — and briefly protects a fresh `normal` bubble from being
    /// replaced (§3, "message priorities").
    case permission
}

/// The surface a `PetStateBehavior` uses to show/hide the speech bubble and schedule delayed
/// bubble work. Implemented by `PetWindowController`; behaviors never touch AppKit directly,
/// which keeps them unit-testable.
protocol BubbleControlling: AnyObject {
    /// Whether the bubble is currently visible.
    var isBubbleShowing: Bool { get }
    /// The priority tag of the currently-visible bubble, if any.
    var currentBubblePriority: BubblePriority? { get }
    /// When the currently-visible bubble's text was last set.
    var currentBubbleShownAt: Date? { get }

    /// Shows `text` immediately, tagged with `priority`.
    func showBubble(_ text: String, priority: BubblePriority)
    /// Hides the bubble, if shown, and cancels any pending `scheduleDelayed` work.
    func hideBubble()

    /// Schedules `action` to run after `delay`, replacing any previously-scheduled action.
    func scheduleDelayed(_ delay: TimeInterval, _ action: @escaping () -> Void)
    /// Cancels a pending `scheduleDelayed` action, if any.
    func cancelScheduled()
}

/// Where a command's message originated — together with the current session motion, this informs
/// a `PetStateBehavior`'s bubble priority decision (MOTION.md §3, "message priorities"). Parsed
/// from `PetCommand.source`; missing or unrecognized values are treated as `.hook`, the more
/// conservative choice (see `PermissionBubbleBehavior`).
enum MessageSource: Equatable {
    /// An `rpets_say` / `rpets_react` MCP tool call — Claude deliberately addressing the user.
    case mcp
    /// A Claude Code lifecycle hook (`.claude/hooks/rpets-hook.py`) — automatic, not deliberate.
    case hook

    init(rawValue: String?) {
        self = rawValue?.lowercased() == "mcp" ? .mcp : .hook
    }
}

/// What happens to a request to transition the session motion to a new state, decided by the
/// currently-active `PetStateBehavior`.
enum TransitionDecision: Equatable {
    /// Apply the transition immediately.
    case allow
    /// Ignore the request — stay in the current motion.
    case reject
    /// Stay in the current motion for now, but apply this same transition automatically after
    /// `delay` if nothing else preempts it first.
    case delay(TimeInterval)
}

/// A policy for how the pet behaves while its session motion is in a particular state: which
/// transitions are allowed, delayed, or rejected, and how the speech bubble reacts to messages.
/// Exactly one behavior is active at a time; `PetSessionStateMachine` swaps it whenever the
/// session motion changes, forwarding every transition request and message to it.
protocol PetStateBehavior: AnyObject {
    /// The session motion just changed to the state this behavior governs.
    func didActivate(_ bubble: BubbleControlling)
    /// The session motion is about to change away from the state this behavior governs.
    func willDeactivate(_ bubble: BubbleControlling)

    /// Decides what happens to a request to transition to `motion` while this behavior is active.
    func decide(transitionTo motion: MotionState?) -> TransitionDecision

    /// A command carried a `message` (already trimmed) from `source`. Empty means "hide the bubble".
    func receive(message text: String, source: MessageSource, bubble: BubbleControlling)
}

/// Default policy for states with no transition restrictions of their own: every transition is
/// allowed immediately, and messages show/hide immediately.
///
/// When `dismissesPermissionBubble` is set (idle and `working` — MOTION.md §4.6), a still-sticky
/// permission bubble is dismissed on activation: "claude waiting input → working dismisses
/// bubble". Other states (`failure`, `reviewing`, …) leave a sticky permission bubble for the
/// user to dismiss.
final class StandardBubbleBehavior: PetStateBehavior {
    private let dismissesPermissionBubble: Bool

    init(dismissesPermissionBubble: Bool) {
        self.dismissesPermissionBubble = dismissesPermissionBubble
    }

    func didActivate(_ bubble: BubbleControlling) {
        if dismissesPermissionBubble, bubble.isBubbleShowing, bubble.currentBubblePriority == .permission {
            bubble.hideBubble()
        }
    }

    func willDeactivate(_ bubble: BubbleControlling) {
        bubble.cancelScheduled()
    }

    func decide(transitionTo motion: MotionState?) -> TransitionDecision { .allow }

    func receive(message text: String, source: MessageSource, bubble: BubbleControlling) {
        if text.isEmpty {
            bubble.hideBubble()
        } else {
            bubble.showBubble(text, priority: .normal)
        }
    }
}

/// Policy for the `permission` session state (MOTION.md §4.6): the approval bubble is sticky
/// (no auto-dismiss TTL), and a fresh `normal` bubble gets a brief grace period — `holdWindow` —
/// before an incoming permission prompt is allowed to replace it, so the user has time to read
/// it first. Resolving permission (a transition away) is always allowed immediately — only the
/// bubble is sticky, per MOTION.md §4.6 ("When permission resolves … the body follows the new
/// state").
final class PermissionBubbleBehavior: PetStateBehavior {
    /// How long a fresh `normal` bubble protects itself from being replaced by a permission prompt.
    static let holdWindow: TimeInterval = 10

    /// A permission message held back behind a still-fresh `normal` bubble, awaiting reveal.
    private var heldMessage: String?

    func didActivate(_ bubble: BubbleControlling) {
        heldMessage = nil
    }

    func willDeactivate(_ bubble: BubbleControlling) {
        heldMessage = nil
        bubble.cancelScheduled()
    }

    func decide(transitionTo motion: MotionState?) -> TransitionDecision { .allow }

    func receive(message text: String, source: MessageSource, bubble: BubbleControlling) {
        guard !text.isEmpty else {
            heldMessage = nil
            bubble.cancelScheduled()
            bubble.hideBubble()
            return
        }

        // A deliberate Claude `say` (MCP) is the freshest signal we have, so it takes over
        // immediately — but as a normal (replaceable) bubble, not a sticky permission one. This
        // also starts that bubble's hold window, so a generic hook message right after doesn't
        // immediately bump it (see `isHoldingBack`).
        if source == .mcp {
            heldMessage = nil
            bubble.showBubble(text, priority: .normal)
            return
        }

        guard isHoldingBack(bubble) else {
            heldMessage = nil
            bubble.showBubble(text, priority: .permission)
            return
        }

        // A fresh, non-permission bubble says something specific — let it ride out the rest of
        // its hold window before this prompt takes over the spotlight.
        heldMessage = text
        let elapsed = bubble.currentBubbleShownAt.map { Date().timeIntervalSince($0) } ?? Self.holdWindow
        let remaining = max(0, Self.holdWindow - elapsed)
        bubble.scheduleDelayed(remaining) { [weak self] in
            guard let self, let message = self.heldMessage else { return }
            self.heldMessage = nil
            bubble.showBubble(message, priority: .permission)
        }
    }

    /// True while a fresh `normal` bubble is still within its grace window and should not be
    /// immediately replaced by this permission prompt.
    private func isHoldingBack(_ bubble: BubbleControlling) -> Bool {
        guard bubble.isBubbleShowing, bubble.currentBubblePriority == .normal,
              let shownAt = bubble.currentBubbleShownAt else { return false }
        return Date().timeIntervalSince(shownAt) < Self.holdWindow
    }
}

/// Policy for the `completed` session state ("work done"): holds the celebratory animation for
/// a short grace period before letting the session settle back to `idle`, so a routine `idle`
/// ping right after completion doesn't cut the celebration short. Every other transition (a new
/// `permission`, `failure`, re-issued `completed`, …) applies immediately — only the return to
/// idle is held. Bubble handling otherwise matches `StandardBubbleBehavior`.
final class CompletedStateBehavior: PetStateBehavior {
    /// How long `completed` resists settling back to `idle` by default.
    static let defaultIdleGracePeriod: TimeInterval = 20

    private let idleGracePeriod: TimeInterval
    private let bubbleBehavior = StandardBubbleBehavior(dismissesPermissionBubble: false)
    private var activatedAt: Date?

    init(idleGracePeriod: TimeInterval = CompletedStateBehavior.defaultIdleGracePeriod) {
        self.idleGracePeriod = idleGracePeriod
    }

    func didActivate(_ bubble: BubbleControlling) {
        activatedAt = Date()
        bubbleBehavior.didActivate(bubble)
    }

    func willDeactivate(_ bubble: BubbleControlling) {
        activatedAt = nil
        bubbleBehavior.willDeactivate(bubble)
    }

    func decide(transitionTo motion: MotionState?) -> TransitionDecision {
        guard motion == nil, let activatedAt else { return .allow }
        let remaining = idleGracePeriod - Date().timeIntervalSince(activatedAt)
        return remaining > 0 ? .delay(remaining) : .allow
    }

    func receive(message text: String, source: MessageSource, bubble: BubbleControlling) {
        bubbleBehavior.receive(message: text, source: source, bubble: bubble)
    }
}
