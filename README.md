# RPets

RPets is a native macOS desktop companion for multi-agent development workflows. It shows one small animated pet per agent session, so you can see whether a session is thinking, editing, running tests, waiting for approval, or finished without switching context.

The project is inspired by ChatGPT Pets, Codex Pets, and OpenPets, but is designed for environments where several agent sessions may be active at the same time.

## What It Does

- Shows one draggable desktop pet per session.
- Uses native AppKit `NSPanel` windows instead of Electron.
- Receives session updates from both MCP tools and Claude Code hooks.
- Listens on a local TCP port for newline-delimited JSON commands.
- Supports short speech bubbles alongside body animation.
- Reuses the Codex/OpenPets-style pet spritesheet format.
- Includes a tester app for manually creating sessions and sending states.

## Architecture

RPets has three main parts:

- `RPets`: the menu-bar macOS app that owns pet windows, bubbles, animation, and session routing.
- `RPetsMCP`: a stdio MCP server exposing tools like `rpets_state`, `rpets_react`, `rpets_say`, and `rpets_status`.
- Claude Code hooks: lifecycle events that automatically update the pet based on real session activity.

Both MCP and hooks send the same command shape to the app over loopback TCP:

```json
{ "session": "repo-a", "state": "working", "message": "Refactoring the parser" }
```

Commands are scoped by `session`, so multiple agent sessions can be represented independently.

For a deeper walkthrough, see [docs/ARTICLE.md](docs/ARTICLE.md).

## Running Locally

Run the pet app:

```bash
swift run RPets
```

Run the manual tester:

```bash
swift run RPetsTester
```

Send a command manually:

```bash
printf '{"session":"demo","state":"working","message":"Reading the diff"}\n' | nc 127.0.0.1 51789
```

Use a custom port for testing:

```bash
RPETS_PORT=51800 swift run RPets
```

## Claude Integration

Install the MCP server, hook script, and Claude instructions:

```bash
make install
```

Remove them:

```bash
make remove
```

The installer is designed to be reversible. It copies the RPets MCP binary and hook script into the user Claude configuration, registers the MCP server, adds hook entries, and can remove only the entries it owns.

## Pet Assets

RPets uses the Codex/OpenPets-style sprite atlas:

- 8 columns x 9 rows
- 192 x 208 px frames
- up to 8 frames per row
- optional `pet.json`
- `spritesheet.webp`, `spritesheet.png`, or another supported image format

Rows map to motion states:

1. idle
2. drag/run right
3. drag/run left
4. hover/wave
5. completed
6. failure
7. permission/waiting for approval
8. working
9. reviewing/thinking

Put pet directories in:

```text
~/rpets/
```

The app autodiscovers available pets and rotates/randomizes assignments across sessions to keep parallel work visually distinct.

See [docs/MOTION.md](docs/MOTION.md) for the sprite and motion contract.

## Documentation

- [docs/ARTICLE.md](docs/ARTICLE.md): project article and architecture narrative.
- [docs/SPEC.md](docs/SPEC.md): design specification and protocol notes.
- [docs/MOTION.md](docs/MOTION.md): sprite-sheet contract and motion-state behavior.

## License

MIT. See [LICENSE](LICENSE).
