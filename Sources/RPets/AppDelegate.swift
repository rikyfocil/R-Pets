import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let excludedPetsKey = "RPets.excludedPets"

    private var allPets: [URL] = []
    private var roster: PetRoster!
    private var spriteCache: [URL: [MotionState: LoadedSprite]] = [:]
    private var settingsController: SettingsWindowController?

    private var petsBySession: [String: PetWindowController] = [:]
    private var sessionOrder: [String] = []
    private var anonymousCounter = 0
    private var statusItem: NSStatusItem?
    private var controlServer: ControlServer?

    // Frames saved just before sleep so pets can be restored to their original screen on wake.
    private var savedFrames: [String: NSRect] = [:]
    private var pendingRecovery: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let fallback = Bundle.module.resourceURL?.appendingPathComponent("Pets/pebble-otter") else {
            log("bundled fallback pet not found — cannot start")
            NSApp.terminate(nil)
            return
        }

        allPets = PetRoster.discover(fallback: fallback).shuffled()

        let excludedNames = Set(UserDefaults.standard.stringArray(forKey: Self.excludedPetsKey) ?? [])
        let excluded = Set(allPets.filter { excludedNames.contains($0.lastPathComponent) })

        roster = PetRoster(pets: allPets)
        roster.excluded = excluded

        log("discovered \(allPets.count) pet(s): \(allPets.map { $0.lastPathComponent }.joined(separator: ", "))")
        setupStatusItem()
        startControlServer()
        setupScreenRecovery()
    }

    // MARK: - Sprites

    private func loadSprites(for petDirectory: URL) -> [MotionState: LoadedSprite]? {
        if let cached = spriteCache[petDirectory] { return cached }
        do {
            let sheetURL = try PetAsset.resolveSpritesheet(at: petDirectory)
            let sprites = try SpriteLoader.loadSprites(sheetURL: sheetURL, motions: MotionState.allCases)
            spriteCache[petDirectory] = sprites
            return sprites
        } catch {
            log("failed to load pet at \(petDirectory.path): \(error)")
            return nil
        }
    }

    // MARK: - Pets (keyed by session id)

    @discardableResult
    private func ensurePet(for session: String) -> PetWindowController? {
        if let existing = petsBySession[session] { return existing }
        let petDirectory = roster.assign(to: session)
        guard let sprites = loadSprites(for: petDirectory) else {
            roster.release(session: session)
            return nil
        }
        let controller = PetWindowController(sprites: sprites, index: sessionOrder.count,
                                             petName: petDirectory.lastPathComponent, sessionId: session)
        controller.onClose = { [weak self] in self?.closePet(for: session) }
        controller.show()
        petsBySession[session] = controller
        sessionOrder.append(session)
        log("created pet '\(petDirectory.lastPathComponent)' for session '\(session)' (total \(petsBySession.count))")
        return controller
    }

    private func closePet(for session: String) {
        guard let controller = petsBySession.removeValue(forKey: session) else {
            log("close ignored — no pet for session '\(session)'")
            return
        }
        controller.close()
        sessionOrder.removeAll { $0 == session }
        roster.release(session: session)
        log("closed pet for session '\(session)' (total \(petsBySession.count))")
    }

    /// Routes a command. With a session it targets (and auto-creates) that pet; without one it
    /// falls back to the legacy broadcast + LIFO create/close.
    private func handle(_ command: PetCommand) {
        if let session = command.session?.trimmingCharacters(in: .whitespacesAndNewlines), !session.isEmpty {
            if command.action?.lowercased() == "close" {
                closePet(for: session)
            } else {
                ensurePet(for: session)?.handle(command)
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

    // MARK: - Settings

    @objc private func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(allPets: allPets, excluded: roster.excluded)
            settingsController?.onExclusionChange = { [weak self] excluded in
                guard let self else { return }
                self.roster.excluded = excluded
                UserDefaults.standard.set(
                    excluded.map { $0.lastPathComponent },
                    forKey: Self.excludedPetsKey
                )
            }
        }
        settingsController?.show()
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
            log("control server failed to start on port \(port): \(error)")
        }
    }

    @objc private func refreshPets() {
        guard let fallback = Bundle.module.resourceURL?.appendingPathComponent("Pets/pebble-otter") else { return }
        allPets = PetRoster.discover(fallback: fallback).shuffled()
        let newRoster = PetRoster(pets: allPets)
        newRoster.excluded = roster.excluded
        roster = newRoster
        settingsController = nil   // discard; next open rebuilds with fresh pet list
        log("refreshed: \(allPets.count) pet(s) discovered")
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🦦"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Refresh Pets", action: #selector(refreshPets), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit RPets", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    // MARK: - Screen recovery

    private func setupScreenRecovery() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(self, selector: #selector(systemWillSleep),
                             name: NSWorkspace.willSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(systemDidWake),
                             name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensDidChange),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
    }

    @objc private func systemWillSleep() {
        savedFrames = petsBySession.mapValues { $0.currentFrame }
        log("sleep — saved frames for \(savedFrames.count) pet(s)")
    }

    @objc private func systemDidWake() {
        // Wait briefly for monitors to reconnect before attempting recovery.
        scheduleRecovery(after: 5)
    }

    @objc private func screensDidChange() {
        guard !savedFrames.isEmpty else { return }
        scheduleRecovery(after: 0.3)
    }

    private func scheduleRecovery(after delay: TimeInterval) {
        pendingRecovery?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recoverAllPets() }
        pendingRecovery = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func recoverAllPets() {
        guard !savedFrames.isEmpty else { return }
        var restoredCount = 0
        for (session, controller) in petsBySession {
            let saved = savedFrames[session] ?? controller.currentFrame
            controller.recoverAfterScreenChange(savedFrame: saved)
            // Once the saved screen is back, drop the entry so future screen events don't
            // forcibly reposition a pet the user may have deliberately moved.
            if NSScreen.screens.contains(where: { $0.frame.intersects(saved) }) {
                savedFrames.removeValue(forKey: session)
                restoredCount += 1
            }
        }
        if restoredCount > 0 {
            log("restored \(restoredCount) pet(s) to their pre-sleep screen")
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("RPets: \(message)\n".utf8))
    }
}
