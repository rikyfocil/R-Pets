import Foundation

/// An external control command (newline-delimited JSON over the ControlServer). See SPEC.md §6.
///
/// Both fields are optional and independent:
/// - `state`   sets the pet's session state (e.g. "working", "completed", "idle").
/// - `message` shows the speech bubble; an empty string hides it; omitting it leaves it unchanged.
struct PetCommand: Decodable {
    let action: String?   // "create" spawns a new pet (handled by AppDelegate)
    let state: String?
    let message: String?
}
