import SwiftUI

/// A control panel: create pets per session id, pick which one to target, and fire commands at it.
struct TesterView: View {
    @State private var sessions: [String] = []
    @State private var selected: String = ""
    @State private var newSession: String = "session-1"
    /// When off, state buttons send `state` only — no `message` key at all (e.g. PostToolBatch);
    /// when on, they send `state` + `message` together (e.g. the Notification hook).
    @State private var sendMessageWithState = true

    var body: some View {
        VStack(spacing: 10) {
            Text("RPets Tester").font(.headline)

            HStack(spacing: 6) {
                TextField("session id", text: $newSession)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createSession() }
                Button("➕ Create") { createSession() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedNew.isEmpty)
            }

            Divider()

            if sessions.isEmpty {
                Text("No pets yet — create one above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                Picker("Send to", selection: $selected) {
                    ForEach(sessions, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)

                Toggle("Send message with state", isOn: $sendMessageWithState)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                stateButton("🙂  Idle",       state: "idle",       message: "")
                stateButton("⚙️  Working",    state: "working",    message: "Refactoring the parser…")
                stateButton("🔍  Reviewing",  state: "reviewing",  message: "Reading the diff 👀")
                stateButton("✅  Completed",  state: "completed",  message: "All tests passed!")
                stateButton("❌  Failure",    state: "failure",    message: "Build failed")
                stateButton("🔐  Permission", state: "permission", message: "Approve this edit?")
                stateButton("👋  Wave",       state: "wave",       message: "Hi there! This is a kinda long message to see the limits of the bubble")

                Divider()

                Button("💬  Show Bubble") { CommandSender.showBubble("Hi from \(selected)! 🦦", session: selected) }
                    .frame(maxWidth: .infinity)
                Button("Hide Bubble") { CommandSender.hideBubble(session: selected) }
                    .frame(maxWidth: .infinity)
                Button("✖️  Close Pet") { closeSelected() }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    private var trimmedNew: String { newSession.trimmingCharacters(in: .whitespaces) }

    private func createSession() {
        let id = trimmedNew
        guard !id.isEmpty else { return }
        CommandSender.create(session: id)
        if !sessions.contains(id) { sessions.append(id) }
        selected = id
        newSession = ""
    }

    private func closeSelected() {
        guard !selected.isEmpty else { return }
        CommandSender.close(session: selected)
        sessions.removeAll { $0 == selected }
        selected = sessions.first ?? ""
    }

    private func stateButton(_ title: String, state: String, message: String) -> some View {
        Button(title) {
            CommandSender.setState(state, message: sendMessageWithState ? message : nil, session: selected)
        }
        .frame(maxWidth: .infinity)
    }
}
