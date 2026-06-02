import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Default pet asset for the skeleton. Override by passing a pet directory as the first argument.
    private static let defaultPetPath = "/Users/rikyfocil/.codex/pets/pebble-otter"

    private var petWindowController: PetWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let petDirectory = resolvePetDirectory()
        do {
            let controller = try PetWindowController(petDirectory: petDirectory)
            controller.show()
            petWindowController = controller
        } catch {
            let message = "RPets: failed to load pet at \(petDirectory.path): \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            NSApp.terminate(nil)
            return
        }
        setupStatusItem()
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
