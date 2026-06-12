import SwiftUI

/// A control panel: create pets per session id, pick which one to target, and fire commands at it.
struct TesterView: View {
    /// Controls what `message` (if any) the state buttons send alongside `state`.
    enum MessageMode: String, CaseIterable, Identifiable {
        case noMessage = "No message"
        case defaultMessage = "Default message"
        case customMessage = "Custom message"
        var id: String { rawValue }
    }

    @State private var sessions: [String] = []
    @State private var selected: String = ""
    @State private var newSession: String = TesterView.randomSessionId()
    @State private var messageMode: MessageMode = .defaultMessage
    @State private var customMessage: String = ""

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

                Picker("Message", selection: $messageMode) {
                    ForEach(MessageMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)

                if messageMode == .customMessage {
                    TextField("Custom message", text: $customMessage)
                        .textFieldStyle(.roundedBorder)
                }

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

    private static func randomSessionId() -> String {
        "test-\(UUID().uuidString.lowercased())"
    }

    private func createSession() {
        let id = trimmedNew
        guard !id.isEmpty else { return }
        CommandSender.create(session: id)
        if !sessions.contains(id) { sessions.append(id) }
        selected = id
        newSession = Self.randomSessionId()
    }

    private func closeSelected() {
        guard !selected.isEmpty else { return }
        CommandSender.close(session: selected)
        sessions.removeAll { $0 == selected }
        selected = sessions.first ?? ""
    }

    private func stateButton(_ title: String, state: String, message: String) -> some View {
        Button(title) {
            let resolvedMessage: String?
            switch messageMode {
            case .noMessage: resolvedMessage = nil
            case .defaultMessage: resolvedMessage = message
            case .customMessage: resolvedMessage = customMessage
            }
            CommandSender.setState(state, message: resolvedMessage, session: selected)
        }
        .frame(maxWidth: .infinity)
    }
}
