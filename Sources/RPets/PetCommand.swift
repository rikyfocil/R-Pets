import Foundation

/// An external control command (newline-delimited JSON over the ControlServer). See SPEC.md §6/§13.
///
/// - `session`: targets a specific pet. Any command with a session auto-creates that pet if needed;
///   `action:"close"` with a session removes it. A command with no session falls back to the legacy
///   broadcast behavior (all pets) + LIFO create/close.
/// - `action`:  `"create"` / `"close"`.
/// - `state`:   sets the pet's session state.
/// - `message`: non-empty shows the bubble; empty hides it; omitted leaves it unchanged.
/// - `source`:  where the command originated — `"mcp"` for an `rpets_*` MCP tool call, `"hook"`
///   for a Claude Code lifecycle hook. Affects bubble priority for `message` — see
///   `MessageSource`.
struct PetCommand: Decodable {
    let session: String?
    let action: String?
    let state: String?
    let message: String?
    let source: String?
}
