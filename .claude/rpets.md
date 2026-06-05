## RPets desktop companion

An RPets MCP server for this session controls the desktop pet the user sees.
Most visual state transitions are driven automatically by hook scripts — use
the MCP tools only for communication that hooks cannot capture.

Call `rpets_status` at session start if you want to confirm the app is reachable
before deciding whether to narrate activity.

---

### `rpets_say` — speech bubbles

Use for brief, user-facing status. Show it when the user genuinely benefits from
knowing what is happening right now:

| Good | Bad |
|---|---|
| "Refactoring the auth module" | Stack traces or debug output |
| "Tests green — ready to merge" | File paths or URLs |
| "Waiting for your approval" | Code snippets or imports |
| "Reverting to last good commit" | Anything longer than 140 chars |

**Dismissing a bubble:** re-send `rpets_state` with the current state — resetting
state clears any stale message. Do this when the status is no longer relevant
(e.g. after the user replies, after the task it described is done).

Constraints: ≤ 140 characters · single line · no code, paths, URLs, or secrets.

---

### `rpets_react` — one-shot reactions

Plays a brief animation then returns to the current looping state. Use once per
meaningful event:

- `celebrating` / `success` — task completed well
- `error` — something went wrong and the user should know
- `waving` — greeting or farewell at session edges

Do not chain reacts. Do not react for every tool call.

---

### `rpets_state` — override looping state

Hooks drive state automatically for common activities (`editing`, `running`,
`testing`, `idle`). Override only when hooks cannot capture the situation:

- `waiting` — blocked on the user for something beyond a normal permission prompt
- `thinking` — extended reasoning with no tool use occurring
- `working` — reset to a neutral active state after a non-hook activity

---

### Mandatory checkpoints

These two calls are required on every non-trivial task — do not skip them:

1. **Before your first tool call:** `rpets_say` with a one-line description of what you are about to do (e.g. "Refactoring the auth module", "Fixing crash on symbol switch").
2. **After final cleanup (commit merged, worktree removed):** `rpets_react` with `celebrating` on success or `error` on failure — exactly once.

---

### When to stay silent

The hook system already handles: file editing · bash execution · test runs ·
session open/close · permission and elicitation prompts · idle after a turn ends.
Do not duplicate these with extra MCP calls — let the hooks speak for themselves.
