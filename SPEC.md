# RPets — Specification

A native macOS desktop-companion app: small always-on-top "pets," **one per coding-agent
session**, that react to and narrate what each session is doing. Inspired by
[OpenPets](https://github.com/alvinunreal/openpets) but rebuilt native, leaner, and with a
cleaner control protocol.

> Status: design spec / not yet implemented.

---

## 1. Goals & non-goals

### Goals
- **Native macOS app** (AppKit window shell + SwiftUI content). No Electron/Chromium.
- **One pet per agent session.** Multiple pets shown simultaneously, one per live session.
- **Tray-first.** Lives in the menu bar; no Dock icon, no main window required.
- **A clean control channel** so an external agent (Claude Code, etc.) can tell a pet what to
  display / how to change state.
- **A new animation model** built on a persistent-`state` vs one-shot-`react` split.

### Non-goals (explicitly dropped vs OpenPets)
- No plugin system / plugin SDK / plugin catalog.
- No bundled "abilities" (reminders, break nudges, focus timers, walks).
- No pet-install/catalog flow (`pets.install`, downloadable pet packs).
- No lease / heartbeat / TTL machinery (replaced by connection lifecycle — see §4).
- No cross-platform target. macOS only.

---

## 2. Technology

| Concern | Choice | Native API |
|---|---|---|
| Window shell | borderless transparent floating panel | `NSPanel` `[.borderless, .nonactivatingPanel]` |
| Always-on-top | float above normal windows | `window.level = .floating` (`.statusBar`/`.screenSaver` to go higher) |
| Transparency | clear background, no shadow | `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false` |
| All Spaces + fullscreen | follow the user everywhere | `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` |
| No Dock icon | menu-bar only | `NSApp.setActivationPolicy(.accessory)` (LSUIElement) |
| Click-through | transparent areas pass clicks; pet/bubble are hittable | `ignoresMouseEvents` toggling / custom `hitTest` |
| Tray icon | menu-bar item | `NSStatusItem` |
| Content / animation | pet rendering | SwiftUI (`PhaseAnimator`, `KeyframeAnimator`, `TimelineView`); optionally Lottie |
| Multi-monitor | reposition on display changes | `NSScreen.screens` + `didChangeScreenParametersNotification` |
| Transport server | loopback control channel | `Network.framework` `NWListener` (TCP/WebSocket) |

### Window-flag recipe (mapped from OpenPets' Electron flags)

| OpenPets (Electron) | RPets (AppKit) |
|---|---|
| `transparent` + `backgroundColor:#00000000` | `isOpaque = false; backgroundColor = .clear` |
| `frame: false` | `NSPanel`, `styleMask: [.borderless, .nonactivatingPanel]` |
| `alwaysOnTop "floating"` | `window.level = .floating` |
| `setVisibleOnAllWorkspaces({visibleOnFullScreen})` | `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` |
| `skipTaskbar: true` | `NSApp.setActivationPolicy(.accessory)` |
| `setIgnoreMouseEvents(true, {forward})` | `window.ignoresMouseEvents` / `hitTest` |
| sprite-sheet CSS `steps()` | SwiftUI `PhaseAnimator` / `TimelineView` |

---

## 3. Topology

```
Claude Code session ──spawns──▶ rpets-mcp (stdio, 1 process per session)
                                     │
                                     └── holds ONE open connection ──▶ RPets menu-bar app
                                          (WebSocket / held-open socket)        │
   connection open  = spawn this session's pet                                  ├─ NSPanel #1  (session A)
   messages         = change its state / say                                    ├─ NSPanel #2  (session B)
   connection close = remove this session's pet  (kernel signals it)            └─ NSPanel #3  (session C)
```

- The **RPets app** is the always-running server (menu-bar item + the pet windows).
- **`rpets-mcp`** is a small stdio MCP server, spawned by the agent **once per session**. It is the
  session-scoped process that holds one persistent connection to the app for its whole life.
- One persistent connection ⇄ one pet. The agent never addresses pets by id for the common case —
  the connection *is* the addressing.

---

## 4. The core idea: connection lifecycle = pet lifecycle

OpenPets uses **ephemeral** connections (one short-lived socket per `pet.say` call). Because a
connection can't represent "the session is alive," it bolts on a **lease** system:
`lease.acquire` → `lease.heartbeat` every ~5s (TTL 15s) → on session death, heartbeats stop, a 5s
reaper expires the lease and hides the pet. Leases are reference-counted per pet id.

RPets makes the connection **persistent** and lets its lifetime *be* the pet's lifetime. This
deletes the entire lease subsystem.

| Event | OpenPets (leases) | RPets (connection lifecycle) |
|---|---|---|
| Session starts | `lease.acquire` + spawn | connection opens → spawn pet |
| Keep-alive | `heartbeat` every 5s + TTL + reaper timer | **nothing** — socket stays open |
| Session ends / crashes | heartbeat stops → reaped ~15s later | connection drops → pet removed immediately, by the OS |
| Multiple sessions | ref-count per pet id (shared window) | **one connection = one pet**, naturally |

Benefits: no zombie window after a crash, no missed-heartbeat edge cases, no reaper timer, and
"one pet per session, many shown at once" falls out for free.

---

## 5. Transport & discovery

> **Implemented today:** loopback TCP on port `51789`, fire-and-forget, no token/discovery yet —
> see [§13](#13-implementation-status-current-build). The persistent-connection design below is the target.

- **Transport:** persistent loopback connection. Recommended: **WebSocket over loopback TCP**
  (easy to speak from any language; a hook can even use `websocat`). A raw held-open framed-JSON
  TCP socket is an acceptable simpler alternative.
  - Swift side: `NWListener` over TCP is a few lines; AF_UNIX would need raw POSIX, so prefer TCP.
- **Discovery file:** the app writes
  `~/Library/Application Support/RPets/runtime/ipc.json` (mode `0600`, dir `0700`) containing:
  ```json
  { "protocolVersion": 1, "endpoint": "ws://127.0.0.1:<port>", "token": "<random>", "pid": 1234, "appVersion": "x.y.z" }
  ```
  The `rpets-mcp` shim reads this to find the endpoint and authenticate.
- **Auth:** a random per-launch token in the discovery file. Every connection authenticates with it
  on open. (Loopback alone is insufficient on a multi-user Mac.)

---

## 6. Message protocol

> **Implemented today:** a simpler flat `{ "action", "state", "message" }` command over
> fire-and-forget loopback TCP — see [§13](#13-implementation-status-current-build). The
> `type`-tagged envelope below is the target design.

JSON messages over the open connection (NDJSON lines, or WebSocket text frames). Small, fixed set.

### Client → app

| Message | Effect | Notes |
|---|---|---|
| `{ "type":"session.start", "label": "...", "appearance"?: "...", "position"?: {x,y} }` | spawn a pet bound to this connection | `label` = project / cwd basename, shown by the pet so sessions are distinguishable |
| `{ "type":"state", "value":"working" }` | set the **persistent looping** animation | the pet's resting state until changed again |
| `{ "type":"react", "value":"celebrating" }` | play a **one-shot** overlay, then return to current `state` | success burst, error shake, wave |
| `{ "type":"say", "text":"...", "ttlMs"?: 4000 }` | transient speech bubble | text passes through the sanitizer (§7) |
| `{ "type":"session.end" }` *(optional)* | graceful goodbye animation, then remove | otherwise removal is implicit on disconnect |
| *(disconnect)* | remove the pet | the primary, crash-safe teardown signal |

### App → client (optional acks)

| Message | Meaning |
|---|---|
| `{ "type":"hello.ok", "petId":"..." }` | connection authenticated, pet spawned |
| `{ "type":"error", "code":"...", "message":"..." }` | rejected request |

### Reaction / state vocabulary (reused from OpenPets)

```
idle, thinking, working, editing, running, testing, waiting, waving, success, error, celebrating
```

`state` values are the looping ones (idle/thinking/working/editing/running/testing/waiting).
`react` values are the one-shot ones (waving/success/error/celebrating). The split is enforced by
the animation model (§8).

---

## 7. Message sanitization (kept from OpenPets)

`say` text is privacy-filtered before display. Reject when the message:
- contains newlines / is multi-line, or exceeds ~140 chars;
- looks like code (``` ``` ``, `<script`, `=>`, `function …`, `class/import/export/const/let/var`);
- contains a URL or filesystem path;
- looks secret-like (`api_key`, `secret`, `token`, `password`, `BEGIN … PRIVATE KEY`).

Bubbles are for short status/personality only — never code, logs, paths, secrets.

---

## 8. Animation model

> See **[MOTION.md](./MOTION.md)** for the full motion spec: sprite-sheet contract, state→row map,
> precedence, and per-state looping behavior.

The protocol's **`state` vs `react`** split *is* the animation model:

- **`state`** → the looping resting animation. Native fit: `PhaseAnimator` (define phases like
  idle / working / running; SwiftUI tweens transitions), or sprite-sheet rows driven by
  `TimelineView`.
- **`react`** → a one-shot animation played *over* the current state, resolving back to it when
  done. Native fit: `KeyframeAnimator` triggered on the event, or a transient sprite overlay.

Changing the look = redefine the phase set and per-phase animations; the protocol is untouched.
For smooth vector animation instead of pixel sprite sheets, Lottie (`lottie-ios`) slots in here —
one Lottie file per `state`, one per `react`.

---

## 9. Two control channels

Separate *who* drives the pet:

1. **Model-driven personality** — MCP tools the agent chooses to call:
   - `rpet_state(value)` → send `state`
   - `rpet_react(value)` → send `react`
   - `rpet_say(text)` → send `say`
   - `rpet_status()` → is the app running / is my pet alive
   Held on the persistent connection by `rpets-mcp`.

2. **Automatic activity (optional)** — Claude Code **hooks** that set `state` from *real* tool
   activity, so the pet reflects what's happening without the model remembering to call anything:
   - `PreToolUse(Bash)` → `running`; `PostToolUse` → back to `working`
   - `PreToolUse(Edit/Write)` → `editing`
   - test command detected → `testing`
   - `Stop` → `waiting` / `success`
   - `Notification` (needs input) → `waiting` + a bubble

### The one fiddly detail
Hooks are stateless one-shot processes; they can't hold the persistent connection. So pets are
**keyed by a session id** that both `rpets-mcp` and the hooks share (Claude Code passes
`session_id` to hooks on stdin). The persistent connection still owns **cleanup** (its close
removes the pet); the session id is how any stateless hook addresses the right pet. Everything else
is connection-scoped.

---

## 10. Multi-pet layout (app responsibility)

- Each connection → one `NSPanel`. The app owns a layout manager that positions new pets to avoid
  overlap (e.g. along a screen edge, offset per index), and reflows on display changes.
- Each pet shows its session `label` (project / cwd basename) so the user can tell sessions apart.
- Pets are draggable; persisted position is best-effort per session label.

---

## 11. What we keep / drop vs OpenPets

**Keep:** discovery-file + token handshake · reaction/state vocabulary · say-sanitizer · MCP as the
agent-facing surface · the window-flag recipe (mapped to AppKit) · tray-first architecture ·
sprite/animation-state concept.

**Drop:** leases / heartbeats / TTL / reaper timer (→ connection lifecycle) · `pets.install` /
plugin catalog / plugin SDK · bundled abilities (reminders etc.) · per-pet-id reference counting
(→ per-session) · Electron/Chromium runtime · cross-platform code.

---

## 12. Open questions / TODO

- [x] Transport for v0: **loopback raw framed-JSON TCP** (port 51789). WebSocket / persistent
      connection deferred — see [§13](#13-implementation-status-current-build).
- [ ] Revisit transport: WebSocket vs raw framed-JSON TCP for the persistent-connection model.
- [ ] Pet appearance source: bundled sprite sets vs Lottie vs both. Decide authoring format.
- [ ] Session-id sharing for the hooks channel (exact mechanism for `rpets-mcp` ↔ hooks).
- [ ] Layout policy for many simultaneous pets (edge-dock? grid? user-arrangeable?).
- [ ] Persistence: per-session position memory keyed by label.
- [ ] Packaging / signing / launch-at-login for the menu-bar app.

---

## 13. Implementation status (current build)

What is actually wired today (SPM package, two executable targets). Tracks the build against the
design above; expect it to evolve.

### Targets
- **`RPets`** — the pet app (menu-bar `.accessory`, 🦦 status item). `swift run RPets`.
- **`RPetsTester`** — a small windowed button panel that fires hardcoded commands for manual
  testing. `swift run RPetsTester` (regular activation policy → Dock icon while running). For a
  persistent, double-clickable Dock app named "RPets Tester", run `./Scripts/build-tester-app.sh`,
  which wraps the binary in `.build/RPetsTester.app` (Info.plist + bundle).

### Control transport — implemented
- **Loopback TCP** via `Network.framework` `NWListener`, bound to **127.0.0.1 only**, port **51789**
  (override with `RPETS_PORT`). Newline-delimited JSON, one command per line.
- **Fire-and-forget**, *not yet* the persistent-connection lifecycle of §4: each command opens a
  connection, sends one line, and closes. Pet lifetime is therefore **not** tied to a connection
  yet (no auto-cleanup on disconnect).
- **No token, no discovery file yet** (§5). Loopback-only binding is the current safeguard.

### Command shape — implemented
Flat object (not the `type`-tagged envelope of §6):
```json
{ "session": "my-session", "state": "working", "message": "Refactoring…" }
```
- `session`: targets a specific pet. **Any command with a session auto-creates that pet** if it
  does not exist; `action:"close"` with a session removes just that one. Pets are keyed by session id.
- `action`: `"create"` (spawn) / `"close"` (remove). With a `session` they target that pet; without
  one, `create` spawns an anonymous pet and `close` removes the most-recently-created (LIFO).
- `state`: one of `idle, working, reviewing, completed, failure, permission, wave`, plus synonyms
  (`editing`/`running`→working, `thinking`/`review`→reviewing, `success`/`done`/`celebrating`→completed,
  `failed`/`error`→failure, `approval`/`waiting`/`blocked`/`testing`→permission, `waving`/`hello`/`hi`→wave).
  Maps to the MOTION.md §2 sprite rows; `idle` clears to the default.
- `message`: non-empty → show bubble; `""` → hide; key omitted → leave unchanged. Body and bubble
  are independent layers (§3 / MOTION.md §3).

### Multi-pet — implemented (session-keyed)
- **No pet on launch.** Pets are created on demand: the first command carrying a new `session`
  spawns a pet for it (staggered so they don't overlap), held in a `[session: controller]` registry.
- `state`/`message`/`close` with a `session` target **only that pet**.
- A command with **no** `session` falls back to legacy: `state`/`message` broadcast to all pets,
  `action:"create"` spawns an anonymous pet, `action:"close"` removes the most-recent (LIFO).
- Tester: a session-id text field + **Create** spawns a pet; a **picker** chooses which session the
  state/bubble/close buttons target.

### Bubble — implemented
- `BubbleView`: a self-sizing rounded speech bubble in its own child `NSPanel` above the pet;
  follows the pet when dragged, flips below the pet near the screen's top edge, click-through.
- A **message-only** command (`{ "message": "…" }`, no `state`) shows a bubble without changing the
  pet's animation — body and bubble are independent.

### Bubble interaction (planned)
How the user interacts with a bubble (design — not yet built):
- **Click-through by default.** Bubbles never capture clicks, so they can't block dragging the pet
  (today they're `ignoresMouseEvents = true`).
- **Dismissal:**
  - *Transient* bubbles (`say` / plain `message`) auto-dismiss after a TTL (e.g. 4 s, configurable).
  - *Sticky* bubbles (`permission`) persist until the state clears.
  - *Manual:* a single click on the **pet** (not a drag) dismisses its current bubble.
- **Actionable bubbles** (later): a `permission` bubble may carry Approve/Deny buttons; that is the
  one case where the bubble itself captures clicks and sends a response back on the connection.
- **Settings surface** (menu-bar submenu / small Settings window) for global knobs: bubbles on/off,
  auto-dismiss seconds, side (above/below), max width. This is where the "setting" idea fits —
  global behavior, not per-bubble wiring.

### Not yet implemented (vs the design above)
Persistent connection = pet lifecycle (§4) · token auth + discovery file (§5) · `type`-tagged
`session.start`/`state`/`react`/`say` envelope (§6) · say-sanitizer (§7) ·
`working` 7/8 randomization (currently row 7 only; `reviewing` = row 8) · hooks channel + MCP shim
(§9) · position persistence (§10).
