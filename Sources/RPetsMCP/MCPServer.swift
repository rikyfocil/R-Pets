import Foundation

/// Stdio MCP server that exposes rpets_state / rpets_react / rpets_say / rpets_status tools
/// and forwards them to the running RPets app via loopback TCP.
final class MCPServer {
    let sessionId: String
    private let client: RPetsClient
    private let encoder = JSONEncoder()

    init(sessionId: String) {
        self.sessionId = sessionId
        self.client = RPetsClient(sessionId: sessionId)
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                  let msg = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) else {
                log("failed to parse: \(line)")
                continue
            }
            handle(msg)
        }

        // stdin EOF — parent process gone or closed the pipe
        client.close()
        log("session \(sessionId) closed")
    }

    // MARK: - Dispatch

    private func handle(_ msg: JSONRPCMessage) {
        switch msg.method {
        case "initialize":
            reply(id: msg.id, result: initializeResult())
        case "notifications/initialized":
            break // notification — no response
        case "ping":
            reply(id: msg.id, result: .object([:]))
        case "tools/list":
            reply(id: msg.id, result: toolsListResult())
        case "tools/call":
            reply(id: msg.id, result: handleToolCall(params: msg.params))
        default:
            if msg.id != nil {
                replyError(id: msg.id, code: -32601, message: "Method not found: \(msg.method)")
            }
        }
    }

    // MARK: - initialize

    private func initializeResult() -> JSONValue {
        .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object(["name": .string("rpets-mcp"), "version": .string("1.0.0")])
        ])
    }

    // MARK: - tools/list

    private func toolsListResult() -> JSONValue {
        .object(["tools": .array([stateTool(), reactTool(), sayTool(), statusTool()])])
    }

    private func stateTool() -> JSONValue {
        tool(
            name: "rpets_state",
            description: "Set the pet's persistent looping animation state.",
            properties: [
                "value": .object([
                    "type": .string("string"),
                    "enum": .array(["idle","thinking","working","editing","running","testing","waiting"].map { .string($0) }),
                    "description": .string("Animation state")
                ])
            ],
            required: ["value"]
        )
    }

    private func reactTool() -> JSONValue {
        tool(
            name: "rpets_react",
            description: "Play a one-shot reaction animation, then return to current state.",
            properties: [
                "value": .object([
                    "type": .string("string"),
                    "enum": .array(["waving","success","error","celebrating"].map { .string($0) }),
                    "description": .string("One-shot reaction")
                ])
            ],
            required: ["value"]
        )
    }

    private func sayTool() -> JSONValue {
        tool(
            name: "rpets_say",
            description: "Show a transient speech bubble. Keep it short and user-facing — no code, logs, paths, or secrets.",
            properties: [
                "text": .object([
                    "type": .string("string"),
                    "description": .string("Short status message to display (max 140 chars, no newlines)")
                ])
            ],
            required: ["text"]
        )
    }

    private func statusTool() -> JSONValue {
        tool(
            name: "rpets_status",
            description: "Check if the RPets app is running and the pet for this session is alive.",
            properties: [:],
            required: []
        )
    }

    private func tool(name: String, description: String, properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "name": .string(name),
            "description": .string(description),
            "inputSchema": .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required.map { .string($0) })
            ])
        ])
    }

    // MARK: - tools/call

    private func handleToolCall(params: JSONValue?) -> JSONValue {
        guard let name = params?["name"]?.stringValue else {
            return errorContent("Missing tool name")
        }
        let arguments = params?["arguments"]
        switch name {
        case "rpets_state":  return callState(arguments)
        case "rpets_react":  return callReact(arguments)
        case "rpets_say":    return callSay(arguments)
        case "rpets_status": return callStatus()
        default:             return errorContent("Unknown tool: \(name)")
        }
    }

    private func callState(_ arguments: JSONValue?) -> JSONValue {
        guard let value = arguments?["value"]?.stringValue else {
            return errorContent("Missing required argument: value")
        }
        client.setState(value)
        return successContent("State set to \(value)")
    }

    private func callReact(_ arguments: JSONValue?) -> JSONValue {
        guard let value = arguments?["value"]?.stringValue else {
            return errorContent("Missing required argument: value")
        }
        client.react(value)
        return successContent("Reaction \(value) triggered")
    }

    private func callSay(_ arguments: JSONValue?) -> JSONValue {
        guard let text = arguments?["text"]?.stringValue else {
            return errorContent("Missing required argument: text")
        }
        guard text.count <= 140, !text.contains("\n") else {
            return errorContent("Message too long or contains newlines (max 140 chars)")
        }
        client.say(text)
        return successContent("Message displayed")
    }

    private func callStatus() -> JSONValue {
        let running = client.isRunning()
        let status = running ? "RPets is running, session \(sessionId) is active" : "RPets is not running"
        return successContent(status)
    }

    // MARK: - Content helpers

    private func successContent(_ text: String) -> JSONValue {
        .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(false)
        ])
    }

    private func errorContent(_ text: String) -> JSONValue {
        .object([
            "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
            "isError": .bool(true)
        ])
    }

    // MARK: - Wire output

    private func reply(id: JSONRPCId?, result: JSONValue) {
        write(JSONRPCResponse(id: id, result: result))
    }

    private func replyError(id: JSONRPCId?, code: Int, message: String) {
        write(JSONRPCResponse(id: id, error: JSONRPCErrorBody(code: code, message: message)))
    }

    private func write<T: Encodable>(_ value: T) {
        guard let data = try? encoder.encode(value),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
        fflush(stdout)
    }

    private func log(_ message: String) {
        fputs("RPetsMCP: \(message)\n", stderr)
    }
}
