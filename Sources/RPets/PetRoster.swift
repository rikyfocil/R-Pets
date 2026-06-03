import Foundation

/// Discovers pet directories and manages round-robin assignment to sessions.
///
/// Assignment order: freed slots (from recently closed sessions) are exhausted first,
/// then the rotation advances to the next directory. Once all directories are in use
/// the rotation wraps and duplicates are allowed. Excluded pets are skipped throughout.
final class PetRoster {
    private let allPets: [URL]
    private var nextIndex: Int = 0
    private var freed: [URL] = []
    private var active: [String: URL] = [:]

    var excluded: Set<URL> = [] {
        didSet { freed.removeAll { excluded.contains($0) } }
    }

    init(pets: [URL]) {
        precondition(!pets.isEmpty, "PetRoster requires at least one pet directory")
        self.allPets = pets
    }

    /// Returns the pet directory assigned to `session`, creating an assignment if none exists.
    func assign(to session: String) -> URL {
        if let existing = active[session] { return existing }

        // Prefer a freed slot, skipping excluded entries.
        if let index = freed.indices.first(where: { !excluded.contains(freed[$0]) }) {
            let petDir = freed.remove(at: index)
            active[session] = petDir
            return petDir
        }

        // Advance the rotation, skipping excluded entries.
        let pool = allPets.filter { !excluded.contains($0) }
        let source = pool.isEmpty ? allPets : pool   // never block if everything is excluded
        let petDir = source[nextIndex % source.count]
        nextIndex += 1
        active[session] = petDir
        return petDir
    }

    /// Returns the pet directory for `session` to the freed pool so it can be reused.
    func release(session: String) {
        guard let petDir = active.removeValue(forKey: session) else { return }
        if !excluded.contains(petDir) {
            freed.append(petDir)
        }
    }
}

extension PetRoster {
    /// Discovers pet directories from `~/rpets/`, falling back to `fallback` if empty or absent.
    static func discover(fallback: URL) -> [URL] {
        let rpetsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("rpets")
        let pets = subdirectories(of: rpetsDir)
        return pets.isEmpty ? [fallback] : pets
    }

    private static func subdirectories(of url: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return contents
            .filter { url in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
