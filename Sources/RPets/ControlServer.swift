import Foundation
import Network

enum ControlServerError: Error {
    case invalidPort(UInt16)
}

/// Loopback TCP server that receives newline-delimited JSON commands and forwards each one to a
/// handler on the main queue. See SPEC.md §5–6.
///
/// Test from a shell:
/// ```
/// printf '{"state":"working","message":"Refactoring"}\n' | nc 127.0.0.1 51789
/// ```
final class ControlServer {
    static let defaultPort: UInt16 = 51789
    private static let maxBufferBytes = 16 * 1024

    private let listener: NWListener
    private let port: UInt16
    private let handler: (PetCommand) -> Void
    private let queue = DispatchQueue(label: "com.rpets.control")

    init(port: UInt16, handler: @escaping (PetCommand) -> Void) throws {
        self.port = port
        self.handler = handler

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ControlServerError.invalidPort(port)
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        listener = try NWListener(using: parameters)
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:             self.log("control server listening on 127.0.0.1:\(self.port)")
            case .failed(let error): self.log("control server failed: \(error)")
            default:                 break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: queue)
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { connection.cancel() }
        }
        connection.start(queue: queue)
        receiveLoop(connection, buffer: Data())
    }

    private func receiveLoop(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data, !data.isEmpty {
                accumulated.append(data)
                accumulated = self.consumeLines(from: accumulated)
            }
            if accumulated.count > Self.maxBufferBytes {
                accumulated.removeAll(keepingCapacity: false)   // drop oversized garbage
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receiveLoop(connection, buffer: accumulated)
        }
    }

    /// Splits complete `\n`-terminated lines out of the buffer, returning the trailing partial line.
    private func consumeLines(from buffer: Data) -> Data {
        var remaining = buffer
        while let newlineIndex = remaining.firstIndex(of: 0x0A) {
            var lineData = remaining.subdata(in: remaining.startIndex..<newlineIndex)
            if lineData.last == 0x0D { lineData.removeLast() }   // tolerate CRLF
            dispatchCommand(from: lineData)
            let nextStart = remaining.index(after: newlineIndex)
            remaining = remaining.subdata(in: nextStart..<remaining.endIndex)
        }
        return remaining
    }

    private func dispatchCommand(from lineData: Data) {
        guard !lineData.isEmpty,
              let command = try? JSONDecoder().decode(PetCommand.self, from: lineData) else { return }
        log("received state=\(command.state ?? "-") message=\(command.message ?? "-")")
        DispatchQueue.main.async { self.handler(command) }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("RPets: \(message)\n".utf8))
    }
}
