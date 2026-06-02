# RPets — Motion Spec

How a pet animates. Companion to [SPEC.md](./SPEC.md) §8 (Animation model). This document is
authoritative for sprite layout, state→row mapping, precedence, and per-state behavior.

> **Core invariant — always looping, never stops.** At every instant exactly one sprite row is
> playing, as an infinite loop. The pet never freezes on a static frame. State changes swap *which*
> row loops; they never stop the loop.

---

## 1. Sprite-sheet contract (OpenPets / ChatGPT compatible)

Same grid format as OpenPets' `default-pet-spritesheet.webp`, so sheets are drop-in reusable.

| Property | Value |
|---|---|
| Layout | grid, **8 columns × 9 rows** |
| Frame size | **192 × 208 px** |
| Full sheet | 1536 × 1872 px (`192·8 × 208·9`) |
| Row order | top → bottom |
| Frame order | left → right within a row, columns `0 … frameCount-1` |
| Populated frames per row | ≤ 8 (a row may use fewer than 8 columns — see metadata) |
| Image format | webp or png with alpha |

**Frame indexing (continuous loop):**
```
elapsed   = now - rowStartTime           // ms, resets when the row changes
frame     = floor(elapsed / durationMs * frameCount) % frameCount   // 0-indexed column
srcX      = frame    * 192
srcY      = row0     * 208                // row0 = 0-indexed row
cropRect  = (srcX, srcY, 192, 208)
```

**Rendering (native).** Two good options:
- **`CALayer.contentsRect`** driven by a `CAKeyframeAnimation` with `calculationMode = .discrete`
  and `repeatCount = .infinity` — GPU-side, no per-frame SwiftUI work. Preferred for many
  simultaneous pets.
- **SwiftUI `TimelineView(.animation)`** computing `frame` each tick and cropping an `Image`.
  Simpler, fine for a few pets.

### Canonical row metadata

These are the per-row frame counts / durations inherited from the OpenPets default sheet. **Frame
count is a property of the sheet row** (how many columns are drawn), so it holds for any sheet in
this format. Durations are inherited defaults and should be **retuned** for RPets' semantics
(below), since RPets reassigns row meanings.

> Rows shown **1-indexed** (matching the requirements). `row0` is the 0-indexed value used in the
> crop math above.

| Row (1-idx) | row0 | Frames | Inherited duration (ms) | OpenPets' original content |
|---|---|---|---|---|
| 1 | 0 | 6 | 5500 | idle |
| 2 | 1 | 8 | 1060 | running-right |
| 3 | 2 | 8 | 1060 | running-left |
| 4 | 3 | 4 | 700  | waving |
| 5 | 4 | 5 | 840  | jumping |
| 6 | 5 | 8 | 1220 | failed |
| 7 | 6 | 6 | 1010 | waiting |
| 8 | 7 | 6 | 820  | running |
| 9 | 8 | 6 | 1030 | review |

---

## 2. Motion states & row map

RPets motion states fall in two groups. **Interaction** states are driven by the app/UI;
**session** states are driven by the control protocol (SPEC.md §6).

| Motion state | Source | Row (1-idx) | Loops | Extra |
|---|---|---|---|---|
| `idle` | default | **0** | ∞ | resting state when nothing else applies |
| `drag-right` | interaction | **1** | ∞ | while dragging, horizontal motion → right |
| `drag-left` | interaction | **2** | ∞ | while dragging, horizontal motion → left |
| `hover` | interaction | **3** | ∞ | pointer over pet, not dragging |
| `completed` | session | **4** | ∞ | agent stopped / done; sticky |
| `failure` | session | **5** | ∞ | agent failed; sticky |
| `permission` | session | **6** | ∞ | approval needed; **+ bubble** (§4.6) |
| `working` | session | **7 / 8** | ∞ | randomized between rows 7 and 8 (§4.7) |
| `reviewing` | session | **8** | ∞ | distinct review state |

---

## 3. Precedence (which state wins)

The pet has two independent layers:

- **Body layer** — the looping sprite row. Exactly one motion state at a time, by precedence below.
- **Bubble layer** — speech / approval bubbles. **Independent** of the body row.

**Body precedence (highest wins):**

```
1. drag-right / drag-left        (actively dragging — direct manipulation)
2. hover                         (pointer over pet, not dragging)
3. session state                 (permission | failure | completed | working | reviewing)
4. idle                          (default)
```

Session states (line 3) are **mutually exclusive** — a session is in exactly one at a time, so
there is no contest among them; the active one simply occupies that slot.

**Bubble layer is separate:** the `permission` approval bubble stays visible even while the body is
overridden by `hover` (or briefly by `drag`), so an approval prompt is never hidden by the user
mousing over the pet. See §4.6.

> Design note: precedence puts interaction above session status (dragging/hovering temporarily
> overrides the work animation). If you'd rather have `permission`/`failure` body motion survive a
> hover, swap lines 2 and 3 for those two states — the bubble already survives either way.

---

## 4. Per-state behavior

### 4.1 `idle` (row 1)
Default resting loop. Active whenever no interaction is happening and the session has no active
status (or no session is bound). Loops row 1 forever.

### 4.2 Drag (row 1 right / row 2 left, keep-last otherwise)
While the pet is being dragged, pick the body row from **horizontal** motion only:

```
dx = pointerX(now) - pointerX(prevSample)      // screen-space, per move event
if      dx >  DEADZONE   →  drag-right (row 1)
else if dx < -DEADZONE   →  drag-left  (row 2)
else                     →  keep the current drag row   // stationary or purely vertical
DEADZONE ≈ 2–3 px
```

- **Keep-last rule.** No clear horizontal direction (not moving, or moving only vertically) ⇒ the
  last committed drag row keeps looping. This is the requirement's "keep doing last one."
- **At drag start**, before any horizontal movement, retain the row that was playing pre-drag until
  a direction is detected (then commit to row 1 / row 2).
- **DEADZONE** provides hysteresis so tiny jitter doesn't flicker between rows.
- **On release**, drag precedence drops; the body reverts to whatever is next-highest (hover if the
  pointer is still over the pet, else the session state, else idle).

### 4.3 `hover` (row 3)
Pointer enters the pet's hittable region and is not dragging → loop row 3. Pointer leaves → revert
to next-highest (session state or idle). Has no effect while dragging.

### 4.4 `completed` (row 4) — sticky
Set when the agent stops / completes. Loops row 4 **indefinitely** ("always") until the session
state changes again or the session ends. Not auto-cleared.

### 4.5 `failure` (row 5) — sticky
Set on agent failure. Loops row 5 indefinitely until the state changes or the session ends.

### 4.6 `permission` (row 6 + bubble) — sticky until resolved
Set when the agent is blocked awaiting approval.
- **Body:** loop row 6.
- **Bubble:** show a **persistent** approval bubble (no auto-dismiss TTL — unlike `say` bubbles).
  Short, sanitized text (≤140 chars, single line), e.g. *"Waiting for your approval."*
- The bubble persists through `hover` (and is restored immediately after a `drag`), per §3.
- When permission resolves (state changes), the bubble hides and the body follows the new state.

### 4.7 `working` (rows 7 & 8, randomized)
General active work. **Randomize between row 7 and row 8**:
- At each **loop-cycle boundary** (when the current row finishes a full cycle), pick the next row
  uniformly at random from `{7, 8}` (default 50/50; weight is tunable).
- Repeats are allowed (it's a draw, not a strict alternation) — this yields a lively, non-periodic
  "busy" motion.
- Switching only at cycle boundaries means each row always plays a complete loop (no mid-cycle
  cuts).

### 4.8 `reviewing` (row 8)
Distinct review state → loop row 8 only, **no** randomization. (Row 8 thus appears both standalone
here and inside `working`'s random pool — intentional.)

---

## 5. Transitions

- **Interaction changes** (drag start/stop, hover enter/leave) apply **immediately** — they're
  direct user input and must feel responsive.
- **Session-state changes** (`working`→`completed`, etc.) apply at the **next loop-cycle boundary**
  of the current row, so the outgoing animation finishes cleanly. `permission` is the exception:
  it may cut in **immediately** (it's important and time-sensitive).
- `rowStartTime` resets to "now" whenever the active row changes, so the new row starts at frame 0.
- All of the above are tunable; defaults chosen for smooth-but-responsive feel.

---

## 6. Timing

Inherited durations (§1 table) are the starting point. Because RPets reassigns row meanings,
retune per RPets state. Suggested starting durations:

| State | Row | Suggested durationMs | Notes |
|---|---|---|---|
| idle | 1 | 5500 | slow, calm breathing-style loop |
| drag-right | 1 | ~1000 | faster than idle while moving (may want a separate quick sheet row) |
| drag-left | 2 | 1060 | |
| hover | 3 | 1060 | lively attention loop |
| completed | 4 | 900 | |
| failure | 5 | 1100 | |
| permission | 6 | 1100 | |
| working | 7 / 8 | 820–1010 | keep 7 and 8 close so random swaps don't jump in tempo |
| reviewing | 8 | 1030 | |

---

## 7. Mapping from the control protocol → motion state

SPEC.md §6 sends `state` / `react` messages. They resolve to motion states as:

| Protocol value | Motion state |
|---|---|
| `idle` | `idle` |
| `working`, `editing`, `running` | `working` |
| `thinking`, *(reviewing)* | `reviewing` |
| `testing`, `waiting` | `working` *(or `permission` if it specifically means "blocked on approval")* |
| `waving` | `hover`-style wave — or fold into `idle` (no dedicated row in this map) |
| `success` | `completed` |
| `error` | `failure` |
| *(permission/approval)* | `permission` |
| `celebrating` | `completed` |

> The motion-state set here (idle / working / reviewing / completed / failure / permission +
> interaction states) is the **refined, authoritative** set and supersedes the looser reaction
> vocabulary in SPEC.md §6. Recommend updating SPEC.md §6 to this set, or keeping §6 as the wire
> vocabulary and this table as the resolver.

---

## 8. Open questions / to confirm

- [ ] **Row 1 collision:** `idle` and `drag-right` both map to row 1. Keep shared, or give
      `drag-right` its own row (e.g. row 9)? (§2)
- [ ] Bootstrap with OpenPets' real default sheet (placeholder, mismatched content) vs author a
      custom RPets sheet to this map first? (§1 caveat)
- [ ] Retune per-row durations for RPets semantics (§6 are guesses).
- [ ] `working` 7/8 randomization weight (default 50/50) and whether to bias against immediate
      repeats.
- [ ] Exact `permission` bubble copy.
- [ ] Should `permission`/`failure` body motion survive a `hover` (precedence swap, §3)?
- [ ] Reconcile SPEC.md §6 vocabulary with the motion-state set (§7).
