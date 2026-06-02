import SwiftUI

/// A super-simple control panel: one button per hardcoded test command.
struct TesterView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("RPets Tester").font(.headline)

            Button("➕  Create Pet") { CommandSender.create() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            Button("✖️  Close Pet") { CommandSender.close() }
                .frame(maxWidth: .infinity)

            Divider()

            stateButton("🙂  Idle",        state: "idle",       message: "")
            stateButton("⚙️  Working",     state: "working",    message: "Refactoring the parser…")
            stateButton("🔍  Reviewing",   state: "reviewing",  message: "Reading the diff 👀")
            stateButton("✅  Completed",   state: "completed",  message: "All tests passed!")
            stateButton("❌  Failure",     state: "failure",    message: "Build failed")
            stateButton("🔐  Permission",  state: "permission", message: "Approve this edit?")
            stateButton("👋  Wave",        state: "wave",       message: "Hi there! This is a kinda long message to see the limits of the bubble")

            Divider()

            Button("💬  Show Bubble") { CommandSender.showBubble("Hi, I'm Pebble! 🦦") }
                .frame(maxWidth: .infinity)

            Button("Hide Bubble") { CommandSender.hideBubble() }
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(width: 220)
    }

    private func stateButton(_ title: String, state: String, message: String) -> some View {
        Button(title) { CommandSender.setState(state, message: message) }
            .frame(maxWidth: .infinity)
    }
}
