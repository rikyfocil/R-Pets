import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Default pet asset for the skeleton. Override by passing a pet directory as the first argument.
    private static let defaultPetPath = "/Users/rikyfocil/.codex/pets/pebble-otter"

    private var petsBySession: [String: PetWindowController] = [:]
    private var sessionOrder: [String] = []
    private var anonymousCounter = 0
    private var sprites: [MotionState: LoadedSprite] = [:]
    private var statusItem: NSStatusItem?
    private var controlServer: ControlServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let petDirectory = resolvePetDirectory()
        do {
            let sheetURL = try PetAsset.resolveSpritesheet(at: petDirectory)
            sprites = try SpriteLoader.loadSprites(sheetURL: sheetURL, motions: MotionState.allCases)
        } catch {
            FileHandle.standardError.write(Data("RPets: failed to load pet at \(petDirectory.path): \(error)\n".utf8))
            NSApp.terminate(nil)
            return
        }
        setupStatusItem()
        startControlServer()
    }

    // MARK: - Pets (keyed by session id)

    @discardableResult
    private func ensurePet(for session: String) -> PetWindowController {
        if let existing = petsBySession[session] { return existing }
        let controller = PetWindowController(sprites: sprites, index: sessionOrder.count)
        controller.show()
        petsBySession[session] = controller
        sessionOrder.append(session)
        log("created pet for session '\(session)' (total \(petsBySession.count))")
        return controller
    }

    private func closePet(for session: String) {
        guard let controller = petsBySession.removeValue(forKey: session) else {
            log("close ignored — no pet for session '\(session)'")
            return
        }
        controller.close()
        sessionOrder.removeAll { $0 == session }
        log("closed pet for session '\(session)' (total \(petsBySession.count))")
    }

    /// Routes a command. With a session it targets (and auto-creates) that pet; without one it
    /// falls back to the legacy broadcast + LIFO create/close.
    private func handle(_ command: PetCommand) {
        if let session = command.session?.trimmingCharacters(in: .whitespacesAndNewlines), !session.isEmpty {
            if command.action?.lowercased() == "close" {
                closePet(for: session)
            } else {
                ensurePet(for: session).handle(command)
            }
            return
        }

        switch command.action?.lowercased() {
        case "create":
            anonymousCounter += 1
            ensurePet(for: "anon-\(anonymousCounter)")
        case "close":
            if let last = sessionOrder.last { closePet(for: last) }
        default:
            break
        }
        for session in sessionOrder {
            petsBySession[session]?.handle(command)
        }
    }

    // MARK: - Control server

    private func startControlServer() {
        let port = UInt16(ProcessInfo.processInfo.environment["RPETS_PORT"] ?? "") ?? ControlServer.defaultPort
        do {
            let server = try ControlServer(port: port) { [weak self] command in
                self?.handle(command)
            }
            server.start()
            controlServer = server
        } catch {
            FileHandle.standardError.write(Data("RPets: control server failed to start on port \(port): \(error)\n".utf8))
        }
    }

    private func resolvePetDirectory() -> URL {
        let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : Self.defaultPetPath
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🦦"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit RPets", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("RPets: \(message)\n".utf8))
    }
}
