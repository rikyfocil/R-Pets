import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Default pet asset for the skeleton. Override by passing a pet directory as the first argument.
    private static let defaultPetPath = "/Users/rikyfocil/.codex/pets/pebble-otter"

    private var pets: [PetWindowController] = []
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
        createPet()
        setupStatusItem()
        startControlServer()
    }

    // MARK: - Pets

    /// Spawns a new pet window using the already-loaded sprites.
    private func createPet() {
        let controller = PetWindowController(sprites: sprites, index: pets.count)
        controller.show()
        pets.append(controller)
        FileHandle.standardError.write(Data("RPets: created pet #\(pets.count - 1) (total \(pets.count))\n".utf8))
    }

    /// Applies an external command: `action: "create"` spawns a pet; state/message broadcast to all pets.
    private func handle(_ command: PetCommand) {
        switch command.action?.lowercased() {
        case "create": createPet()
        case "close":  closeLastPet()
        default:       break
        }
        for pet in pets {
            pet.handle(command)
        }
    }

    /// Closes the most recently created pet (LIFO). No per-pet addressing yet — see SPEC.md §13.
    private func closeLastPet() {
        guard let pet = pets.popLast() else {
            FileHandle.standardError.write(Data("RPets: close ignored — no pets\n".utf8))
            return
        }
        pet.close()
        FileHandle.standardError.write(Data("RPets: closed a pet (total \(pets.count))\n".utf8))
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
}
