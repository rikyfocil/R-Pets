import Foundation
import Network

/// Sends fire-and-forget commands to the running RPets app over loopback TCP.
struct RPetsClient {
    let sessionId: String
    private let port: UInt16

    init(sessionId: String) {
        self.sessionId = sessionId
        self.port = UInt16(ProcessInfo.processInfo.environment["RPETS_PORT"] ?? "") ?? 51789
    }

    func create()              { send(OutgoingCommand(action: "create", session: sessionId)) }
    func close()               { send(OutgoingCommand(action: "close",  session: sessionId)) }
    func setState(_ state: String) { send(OutgoingCommand(session: sessionId, state: state)) }
    func say(_ text: String)   { send(OutgoingCommand(session: sessionId, message: text)) }

    /// React maps to a state command for now (the backend doesn't have a separate react field yet).
    func react(_ value: String) { send(OutgoingCommand(session: sessionId, state: value)) }

    /// Returns true if the RPets app is accepting connections on its control port.
    func isRunning() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var reachable = false
        let connection = makeConnection()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                reachable = true
                connection.cancel()
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: .global())
        _ = semaphore.wait(timeout: .now() + 2)
        return reachable
    }

    // MARK: - Private

    private func send(_ command: OutgoingCommand) {
        guard let data = try? JSONEncoder().encode(command),
              let json = String(data: data, encoding: .utf8) else { return }
        let payload = Data((json + "\n").utf8)

        let semaphore = DispatchSemaphore(value: 0)
        let connection = makeConnection()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: payload, completion: .contentProcessed { _ in
                    connection.cancel()
                    semaphore.signal()
                })
            case .failed, .cancelled:
                semaphore.signal()
            default:
                break
            }
        }
        connection.start(queue: .global())
        _ = semaphore.wait(timeout: .now() + 2)
    }

    private func makeConnection() -> NWConnection {
        NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }
}

// MARK: - Wire format (matches RPets ControlServer / PetCommand)

private struct OutgoingCommand: Encodable {
    var action: String?
    var session: String?
    var state: String?
    var message: String?
}
