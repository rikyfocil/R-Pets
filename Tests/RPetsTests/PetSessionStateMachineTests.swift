import Foundation
import Testing

@testable import RPets

/// In-memory `PetSessionStateMachine.Context` double. Records every show/hide and lets tests
/// fire or inspect scheduled bubble and transition work synchronously, without waiting on real
/// timers.
final class MockBubble: BubbleControlling, TransitionScheduling {
    var isBubbleShowing = false
    var currentBubblePriority: BubblePriority?
    var currentBubbleShownAt: Date?

    private(set) var shown: [(text: String, priority: BubblePriority)] = []
    private(set) var hideCount = 0
    private(set) var cancelCount = 0

    private(set) var scheduledDelay: TimeInterval?
    private var scheduledAction: (() -> Void)?

    private(set) var scheduledTransitionDelay: TimeInterval?
    private var scheduledTransitionAction: (() -> Void)?
    private(set) var transitionCancelCount = 0

    func showBubble(_ text: String, priority: BubblePriority) {
        isBubbleShowing = true
        currentBubblePriority = priority
        currentBubbleShownAt = Date()
        shown.append((text, priority))
    }

    func hideBubble() {
        isBubbleShowing = false
        currentBubblePriority = nil
        currentBubbleShownAt = nil
        cancelScheduled()
        hideCount += 1
    }

    func scheduleDelayed(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        scheduledDelay = delay
        scheduledAction = action
    }

    func cancelScheduled() {
        scheduledDelay = nil
        scheduledAction = nil
        cancelCount += 1
    }

    /// True while a `scheduleDelayed` bubble action is pending.
    var hasScheduledWork: Bool { scheduledAction != nil }

    /// Simulates the bubble-reveal timer firing.
    func fireScheduled() {
        let action = scheduledAction
        scheduledAction = nil
        scheduledDelay = nil
        action?()
    }

    func scheduleTransition(after delay: TimeInterval, _ action: @escaping () -> Void) {
        scheduledTransitionDelay = delay
        scheduledTransitionAction = action
    }

    func cancelScheduledTransition() {
        scheduledTransitionDelay = nil
        scheduledTransitionAction = nil
        transitionCancelCount += 1
    }

    /// True while a `scheduleTransition` action is pending.
    var hasScheduledTransition: Bool { scheduledTransitionAction != nil }

    /// Simulates the delayed-transition timer firing.
    func fireScheduledTransition() {
        let action = scheduledTransitionAction
        scheduledTransitionAction = nil
        scheduledTransitionDelay = nil
        action?()
    }
}

@Suite("PetSessionStateMachine")
struct PetSessionStateMachineTests {

    @Test("a normal message shows and hides immediately")
    func normalMessageShowsAndHides() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.receive(message: "Refactoring the auth module", source: .mcp)
        #expect(bubble.shown.last?.text == "Refactoring the auth module")
        #expect(bubble.shown.last?.priority == .normal)
        #expect(bubble.isBubbleShowing)

        machine.receive(message: "", source: .mcp)
        #expect(!bubble.isBubbleShowing)
        #expect(bubble.hideCount == 1)
    }

    @Test("a permission message shows immediately when no other bubble is showing")
    func permissionMessageShowsImmediatelyWhenIdle() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.requestTransition(to: .permission)
        machine.receive(message: "Waiting for your approval.", source: .hook)

        #expect(bubble.shown.last?.priority == .permission)
        #expect(!bubble.hasScheduledWork)
    }

    @Test("a fresh normal bubble holds back an incoming permission prompt, then reveals it")
    func freshNormalBubbleHoldsBackPermissionPrompt() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.receive(message: "Running the test suite", source: .mcp)
        #expect(bubble.shown.last?.priority == .normal)

        machine.requestTransition(to: .permission)
        machine.receive(message: "Waiting for your approval.", source: .hook)

        // Held back: the normal bubble is still showing, the prompt hasn't replaced it yet.
        #expect(bubble.shown.count == 1)
        #expect(bubble.currentBubblePriority == .normal)
        #expect(bubble.hasScheduledWork)

        // Once the hold window elapses, the queued prompt is revealed.
        bubble.fireScheduled()
        #expect(bubble.shown.last?.text == "Waiting for your approval.")
        #expect(bubble.shown.last?.priority == .permission)
    }

    @Test("a stale normal bubble does not hold back a permission prompt")
    func staleNormalBubbleDoesNotHoldBackPermissionPrompt() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.receive(message: "Running the test suite", source: .mcp)
        // Backdate the bubble past the hold window.
        bubble.currentBubbleShownAt = Date().addingTimeInterval(-PermissionBubbleBehavior.holdWindow - 1)

        machine.requestTransition(to: .permission)
        machine.receive(message: "Waiting for your approval.", source: .hook)

        #expect(bubble.shown.last?.text == "Waiting for your approval.")
        #expect(bubble.shown.last?.priority == .permission)
        #expect(!bubble.hasScheduledWork)
    }

    @Test("leaving permission for working dismisses a sticky permission bubble")
    func workingDismissesPermissionBubble() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.requestTransition(to: .permission)
        machine.receive(message: "Waiting for your approval.", source: .hook)
        #expect(bubble.isBubbleShowing)

        machine.requestTransition(to: .working)
        #expect(!bubble.isBubbleShowing)
        #expect(bubble.hideCount == 1)
    }

    @Test("leaving permission for idle dismisses a sticky permission bubble")
    func idleDismissesPermissionBubble() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.requestTransition(to: .permission)
        machine.receive(message: "Waiting for your approval.", source: .hook)

        machine.requestTransition(to: nil)
        #expect(!bubble.isBubbleShowing)
    }

    @Test("leaving permission for a state other than idle/working leaves the bubble alone")
    func failureDoesNotDismissPermissionBubble() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.requestTransition(to: .permission)
        machine.receive(message: "Waiting for your approval.", source: .hook)

        machine.requestTransition(to: .failure)
        #expect(bubble.isBubbleShowing)
        #expect(bubble.currentBubblePriority == .permission)
    }

    @Test("leaving permission cancels a held-back reveal before it fires")
    func leavingPermissionCancelsHeldReveal() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.receive(message: "Running the test suite", source: .mcp)
        machine.requestTransition(to: .permission)
        machine.receive(message: "Waiting for your approval.", source: .hook)
        #expect(bubble.hasScheduledWork)

        machine.requestTransition(to: .working)
        #expect(!bubble.hasScheduledWork)

        // The original normal bubble was dismissed by the idle/working transition, not replaced
        // by the held permission prompt.
        #expect(bubble.shown.count == 1)
    }

    @Test("explicitly hiding the bubble while a prompt is held back cancels the reveal")
    func explicitHideCancelsHeldReveal() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.receive(message: "Running the test suite", source: .mcp)
        machine.requestTransition(to: .permission)
        machine.receive(message: "Waiting for your approval.", source: .hook)
        #expect(bubble.hasScheduledWork)

        machine.receive(message: "", source: .mcp)
        #expect(!bubble.isBubbleShowing)
        #expect(!bubble.hasScheduledWork)

        bubble.fireScheduled()
        #expect(bubble.shown.count == 1)
    }

    @Test("a second permission message overwrites a still-pending held message")
    func secondPermissionMessageOverwritesHeldMessage() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.receive(message: "Running the test suite", source: .mcp)
        machine.requestTransition(to: .permission)
        machine.receive(message: "Need approval for A", source: .hook)
        machine.receive(message: "Need approval for B", source: .hook)

        bubble.fireScheduled()
        #expect(bubble.shown.last?.text == "Need approval for B")
    }

    @Test("a deliberate MCP message takes over a sticky permission bubble as a normal-priority bubble")
    func mcpMessageTakesOverStickyPermissionBubble() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.requestTransition(to: .permission)
        machine.receive(message: "Waiting for your approval.", source: .hook)
        #expect(bubble.currentBubblePriority == .permission)

        // MCP is the freshest source of truth, so it takes over immediately — but as a normal
        // (replaceable) bubble, not a sticky permission one.
        machine.receive(message: "Still need your OK on this one", source: .mcp)
        #expect(bubble.shown.last?.text == "Still need your OK on this one")
        #expect(bubble.currentBubblePriority == .normal)
    }

    @Test("a generic hook message is held back briefly after an MCP message takes over during permission")
    func hookMessageHeldBackAfterMcpTakeoverDuringPermission() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)

        machine.requestTransition(to: .permission)
        machine.receive(message: "Waiting for your approval.", source: .hook)
        machine.receive(message: "Still need your OK on this one", source: .mcp)
        #expect(bubble.shown.count == 2)

        // The fresh MCP bubble protects itself, just like any other fresh normal bubble.
        machine.receive(message: "Waiting for your approval.", source: .hook)
        #expect(bubble.shown.count == 2)
        #expect(bubble.currentBubblePriority == .normal)
        #expect(bubble.hasScheduledWork)

        bubble.fireScheduled()
        #expect(bubble.shown.last?.text == "Waiting for your approval.")
        #expect(bubble.currentBubblePriority == .permission)
    }

    @Test("a transition request to the current motion is a no-op")
    func transitionToCurrentMotionIsNoOp() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)
        var motions: [MotionState?] = []
        machine.onMotionChange = { motions.append($0) }

        machine.requestTransition(to: nil) // already idle
        #expect(motions.isEmpty)
        #expect(machine.sessionMotion == nil)
    }

    @Test("onMotionChange fires when a transition is applied immediately")
    func onMotionChangeFiresImmediately() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)
        var motions: [MotionState?] = []
        machine.onMotionChange = { motions.append($0) }

        machine.requestTransition(to: .working)
        #expect(motions == [.working])
        #expect(machine.sessionMotion == .working)
    }

    @Test("completing work holds idle for a grace period, then settles once it elapses")
    func completedHoldsIdleUntilScheduledTransitionFires() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)
        var motions: [MotionState?] = []
        machine.onMotionChange = { motions.append($0) }

        machine.requestTransition(to: .completed)
        #expect(motions == [.completed])

        // A routine "go idle" right after completion is held, not applied immediately.
        machine.requestTransition(to: nil)
        #expect(machine.sessionMotion == .completed)
        #expect(motions == [.completed])
        #expect(bubble.hasScheduledTransition)

        // Once the grace period elapses, the held transition settles to idle.
        bubble.fireScheduledTransition()
        #expect(machine.sessionMotion == nil)
        #expect(motions == [.completed, nil])
    }

    @Test("a transition away from completed to another state applies immediately and cancels the held idle transition")
    func completedAllowsImmediateTransitionToOtherStates() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)
        var motions: [MotionState?] = []
        machine.onMotionChange = { motions.append($0) }

        machine.requestTransition(to: .completed)
        machine.requestTransition(to: nil)
        #expect(bubble.hasScheduledTransition)

        machine.requestTransition(to: .permission)
        #expect(machine.sessionMotion == .permission)
        #expect(motions == [.completed, .permission])
        #expect(!bubble.hasScheduledTransition)
    }

    @Test("forceTransition bypasses completed's idle grace period")
    func forceTransitionBypassesGracePeriod() {
        let bubble = MockBubble()
        let machine = PetSessionStateMachine(context: bubble)
        var motions: [MotionState?] = []
        machine.onMotionChange = { motions.append($0) }

        machine.requestTransition(to: .completed)
        machine.forceTransition(to: nil)

        #expect(machine.sessionMotion == nil)
        #expect(motions == [.completed, nil])
    }
}

@Suite("CompletedStateBehavior")
struct CompletedStateBehaviorTests {

    @Test("a request to go idle right after activation is delayed")
    func idleRequestIsDelayedAfterActivation() {
        let bubble = MockBubble()
        let behavior = CompletedStateBehavior(idleGracePeriod: 2)
        behavior.didActivate(bubble)

        let decision = behavior.decide(transitionTo: nil)
        guard case .delay(let remaining) = decision else {
            Issue.record("expected .delay, got \(decision)")
            return
        }
        #expect(remaining > 0)
        #expect(remaining <= 2)
    }

    @Test("requests to states other than idle are allowed immediately")
    func nonIdleRequestsAreAllowedImmediately() {
        let bubble = MockBubble()
        let behavior = CompletedStateBehavior(idleGracePeriod: 2)
        behavior.didActivate(bubble)

        #expect(behavior.decide(transitionTo: .permission) == .allow)
        #expect(behavior.decide(transitionTo: .working) == .allow)
        #expect(behavior.decide(transitionTo: .failure) == .allow)
    }

    @Test("once the grace period elapses, idle is allowed")
    func idleAllowedAfterGracePeriodElapses() async throws {
        let bubble = MockBubble()
        let behavior = CompletedStateBehavior(idleGracePeriod: 0.05)
        behavior.didActivate(bubble)

        try await Task.sleep(for: .milliseconds(100))

        #expect(behavior.decide(transitionTo: nil) == .allow)
    }

    @Test("messages show and hide as a normal bubble would")
    func messagesBehaveLikeStandardBubble() {
        let bubble = MockBubble()
        let behavior = CompletedStateBehavior()
        behavior.didActivate(bubble)

        behavior.receive(message: "All tests passing!", source: .mcp, bubble: bubble)
        #expect(bubble.shown.last?.text == "All tests passing!")
        #expect(bubble.shown.last?.priority == .normal)

        behavior.receive(message: "", source: .mcp, bubble: bubble)
        #expect(!bubble.isBubbleShowing)
    }
}
