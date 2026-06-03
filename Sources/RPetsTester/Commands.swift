import Foundation
import Network

/// A command to send to the running RPets app. Optionals are omitted from JSON when nil.
struct OutgoingCommand: Encodable {
    var action: String? = nil
    var session: String? = nil
    var state: String? = nil
    var message: String? = nil
}

/// Fires test commands at the RPets control server over loopback TCP. Each targets a session id.
enum CommandSender {
    static let port: UInt16 = 51789

    static func create(session: String) { send(OutgoingCommand(action: "create", session: session)) }
    static func close(session: String)  { send(OutgoingCommand(action: "close", session: session)) }
    static func setState(_ state: String, message: String, session: String) {
        send(OutgoingCommand(session: session, state: state, message: message))
    }
    static func showBubble(_ text: String, session: String) { send(OutgoingCommand(session: session, message: text)) }
    static func hideBubble(session: String)                 { send(OutgoingCommand(session: session, message: "")) }

    private static func send(_ command: OutgoingCommand) {
        guard let data = try? JSONEncoder().encode(command),
              let json = String(data: data, encoding: .utf8) else { return }
        let line = Data((json + "\n").utf8)

        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: line, completion: .contentProcessed { _ in connection.cancel() })
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }
}
