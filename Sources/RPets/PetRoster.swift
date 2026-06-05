import Foundation

/// Discovers pet directories and manages round-robin assignment to sessions.
///
/// Each new session advances the rotation index, so consecutive sessions always get
/// different pets (when more than one is available). Closed sessions simply free their
/// slot; the rotation keeps advancing rather than reusing the same pet immediately.
/// Excluded pets are skipped throughout; duplicates are allowed once all are in use.
final class PetRoster {
    private let allPets: [URL]
    private var nextIndex: Int = 0
    private var active: [String: URL] = [:]

    var excluded: Set<URL> = []

    init(pets: [URL]) {
        precondition(!pets.isEmpty, "PetRoster requires at least one pet directory")
        self.allPets = pets
    }

    /// Returns the pet directory assigned to `session`, creating an assignment if none exists.
    func assign(to session: String) -> URL {
        if let existing = active[session] { return existing }

        let pool = allPets.filter { !excluded.contains($0) }
        let source = pool.isEmpty ? allPets : pool   // never block if everything is excluded
        let petDir = source[nextIndex % source.count]
        nextIndex += 1
        active[session] = petDir
        return petDir
    }

    /// Frees the slot for `session`. The rotation index keeps advancing, so the next
    /// assignment will not immediately reuse this pet.
    func release(session: String) {
        active.removeValue(forKey: session)
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
