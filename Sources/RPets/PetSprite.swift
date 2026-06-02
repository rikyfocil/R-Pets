import AppKit
import ImageIO

/// Optional manifest for a pet asset directory (OpenPets / ChatGPT / Codex pet format).
/// Only the spritesheet is required; the manifest is honored if present but never required.
struct PetManifest: Decodable {
    let id: String?
    let displayName: String?
    let description: String?
    let spritesheetPath: String?

    static func load(from directory: URL) throws -> PetManifest {
        let url = directory.appendingPathComponent("pet.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PetManifest.self, from: data)
    }
}

/// Locates a pet's spritesheet. Only the image matters — webp and png are interchangeable.
enum PetAsset {
    /// Image formats ImageIO can decode for sheets, in preference order.
    static let imageExtensions = ["webp", "png", "gif", "jpeg", "jpg", "tiff", "heic"]

    /// Resolves a spritesheet from a path that may be either the sheet file itself or a pet directory.
    static func resolveSpritesheet(at path: URL) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        // A spritesheet file was passed directly.
        if fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            return path
        }

        // Honor pet.json's spritesheetPath if present and the referenced file exists.
        if let manifest = try? PetManifest.load(from: path),
           let spritesheetPath = manifest.spritesheetPath {
            let url = path.appendingPathComponent(spritesheetPath)
            if fileManager.fileExists(atPath: url.path) { return url }
        }

        // Fall back to a `spritesheet.<imageExt>` file in the directory.
        for ext in imageExtensions {
            let url = path.appendingPathComponent("spritesheet").appendingPathExtension(ext)
            if fileManager.fileExists(atPath: url.path) { return url }
        }

        // Last resort: the first image file in the directory.
        if let contents = try? fileManager.contentsOfDirectory(at: path, includingPropertiesForKeys: nil),
           let firstImage = contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
               .first(where: { imageExtensions.contains($0.pathExtension.lowercased()) }) {
            return firstImage
        }

        throw SpriteLoaderError.noSpritesheet(path)
    }
}

/// Universal sprite-sheet contract — see MOTION.md §1.
/// 8 columns × 9 rows of 192×208 frames (full sheet 1536×1872).
enum SpriteSheet {
    static let frameWidth = 192
    static let frameHeight = 208
    static let columns = 8
    static let rows = 9
}

/// One animation state: a row of the sheet looped at a fixed cadence.
struct SpriteState {
    let row: Int         // 0-indexed row in the sheet
    let frames: Int      // populated frames (columns) in that row
    let durationMs: Int  // full-cycle duration

    /// MOTION.md §2 — idle loops row 1 (1-indexed) == row 0 (0-indexed), 6 frames.
    static let idle = SpriteState(row: 0, frames: 6, durationMs: 5500)
}

enum SpriteLoaderError: Error {
    case noSpritesheet(URL)
    case cannotDecodeSheet(URL)
    case cannotCropFrame(column: Int, row: Int)
}

enum SpriteLoader {
    /// Crops the frames of `state` out of the sheet, left → right, top-left origin.
    static func loadFrames(sheetURL: URL, state: SpriteState) throws -> [CGImage] {
        guard
            let source = CGImageSourceCreateWithURL(sheetURL as CFURL, nil),
            let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw SpriteLoaderError.cannotDecodeSheet(sheetURL) }

        var frames: [CGImage] = []
        frames.reserveCapacity(state.frames)
        for column in 0..<state.frames {
            let rect = CGRect(
                x: column * SpriteSheet.frameWidth,
                y: state.row * SpriteSheet.frameHeight,
                width: SpriteSheet.frameWidth,
                height: SpriteSheet.frameHeight
            )
            guard let frame = sheet.cropping(to: rect) else {
                throw SpriteLoaderError.cannotCropFrame(column: column, row: state.row)
            }
            frames.append(frame)
        }
        return frames
    }
}
