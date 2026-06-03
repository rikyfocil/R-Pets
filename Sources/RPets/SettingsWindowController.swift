import AppKit
import SwiftUI

// MARK: - Helpers

private func displayName(for url: URL) -> String {
    if let manifest = try? PetManifest.load(from: url), let name = manifest.displayName {
        return name
    }
    return url.lastPathComponent
        .split(separator: "-")
        .map { $0.capitalized }
        .joined(separator: " ")
}

// MARK: - View model

final class SettingsModel: ObservableObject {
    @Published var excluded: Set<URL>
    let allPets: [URL]
    let sortedPets: [URL]
    var onExclusionChange: ((Set<URL>) -> Void)?

    init(allPets: [URL], excluded: Set<URL>) {
        self.allPets = allPets
        self.sortedPets = allPets.sorted {
            displayName(for: $0).uppercased() < displayName(for: $1).uppercased()
        }
        self.excluded = excluded
    }

    func toggle(_ pet: URL) {
        if excluded.contains(pet) { excluded.remove(pet) } else { excluded.insert(pet) }
        onExclusionChange?(excluded)
    }

    func isIncluded(_ pet: URL) -> Bool { !excluded.contains(pet) }
}

// MARK: - SwiftUI view

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        List(model.sortedPets, id: \.self) { pet in
            Toggle(isOn: Binding(
                get: { model.isIncluded(pet) },
                set: { _ in model.toggle(pet) }
            )) {
                Text(displayName(for: pet))
            }
        }
        .frame(width: 280, height: min(CGFloat(model.allPets.count) * 32 + 16, 420))
    }
}

// MARK: - Window controller

final class SettingsWindowController: NSObject {
    private var window: NSWindow?
    private let model: SettingsModel

    var excluded: Set<URL> { model.excluded }

    var onExclusionChange: ((Set<URL>) -> Void)? {
        get { model.onExclusionChange }
        set { model.onExclusionChange = newValue }
    }

    init(allPets: [URL], excluded: Set<URL>) {
        model = SettingsModel(allPets: allPets, excluded: excluded)
    }

    func show() {
        if window == nil { window = makeWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let win = NSWindow(contentViewController: hostingController)
        win.title = "RPets Settings"
        win.isReleasedWhenClosed = false
        win.styleMask = [.titled, .closable]
        win.center()
        return win
    }
}
