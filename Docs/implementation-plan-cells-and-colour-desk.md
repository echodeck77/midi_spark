# IMPLEMENTATION PLAN — cells & colour desk (the visual overhaul)

_Builds `Docs/AcceptanceCriteria/AcceptanceCriteria-cells-and-colour-desk.md` (design-side, 2026-07-29). Parts
A–B are ratified; C–D are the user's direction — **build in order, and STOP to confirm sequencing with the user
at the B→C boundary** (per the doc). Per-increment discipline (as the /btw plan): confirm the current code
first, build, unit-test off-device FIRST, iOS-build-check, commit atomically, tick + add a CLAUDE.md line. UI
isn't in the unit target, so device-verify is the user's; state exactly what to check. Placeholder-quality
emblem/trigger glyphs are acceptable this wave (the artwork is a separate asset job)._

## Current homes (confirmed)
- **Cell face** — `GridUI.cellView` (four-row cell) via `inputHeader` (`:396`, R2–R4 band / "FROM ROW n"),
  `bodyText` (`:417`, `typeLabel` + `paramText`), `emitterStrip` (`:432`, A·B·C·D lit chips).
- **Desk** — `GridUI.ProcessorBox`: `titleRow` (`:1353`, "PROCESSOR A/B" + COPY/PASTE) and `typeSelector`
  (`:1364`, a `seg(...)` segment control). A/B faces, `onSetTypeA`/`typeB` edits.
- **Palette** — `GridUI.PaletteView` (`:1476`) iterates ALL 16 `colourIDs` as chips; `onPick(id)`.
- **Colour model** — `Models.Colour` (`:64`): `colourID`, `type`, params, `on` (trigger config). NO `name`, NO
  "defined" flag; `PluginState.colours` is always the 16.
- **Text input to reuse** — `PresetBrowser` `TextField` (`:38`) + `savePreset` — the app's first text input.

## Prerequisite — EMBLEMS (shared by A + B; build first)
Add `func emblem(for: ProcessorType) -> Image` (+ a B-less/OFF mark) — ONE static glyph per type (ARP climb ·
RTC burst · PASS gate · STRM fan · CHNC die · HARM bloom). **Placeholder SF Symbols** this wave; the drawn
artwork follows. Pure/stateless, drawn STATIC (invisible-when-frozen law: no timers). Used by the cell face and
the desk title.
- **Test:** a tiny mapping test (every `ProcessorType.allCases` returns a non-nil emblem).

## PART A — THE CELL FACE

### A1. Resting occupied cell  ✦
Rework the cell's inner content to the ratified grammar: **Colour block · EMBLEM leading · params DIGEST (small,
dim, deviations-only — the shipped v59 field set: rate · oct · ∞ · transpose) · up to four small BUS DOTS at the
foot (lit = emitter enabled).** The A·B·C·D chip strip (`emitterStrip`) is REPLACED by bus dots.
- **Where:** `bodyText` (emblem + digest), `emitterStrip` → `busDots`. Keep `paramText` as the digest source
  (it already renders deviations); wire the emblem in front.
- **Acceptance (device):** an ARP cell shows its emblem + only-diverging params + lit-bus dots at the foot; a
  default cell shows minimal digest.

### A2. Input attribution — the compass tint  ✦
- **Given** a cell fed by a ROW, **then** a slim whisper-weight tint in the PARENT's hue sits on the
  parent-facing edge (parent above → top edge; below → bottom edge). **Given** a receiver-fed cell, **then** NO
  edge tint (default recedes). Replaces/absorbs today's `inputHeader` band treatment.
- **Where:** `cellView` overlay (a thin edge bar), driven by `cell.inputRow` (above/below) + the parent's colour.
- **Acceptance:** a downhill chain shows the parent's-hue sliver on each child's top edge; a MIDI-IN cell is clean.

### A3. Trigger glyph (deviation-shown)  ✦
- **Given** a non-default TAP action, **then** a small glyph in the bottom-right (↻ replay · ⇄ flip · ↑/↓ octave
  · ❄ freeze). **Given** a non-default HOLD action, **then** the same position wears a RING modifier. Default =
  NOTHING. Never more than two marks.
- **Where:** `cellView` overlay bottom-right; read the Colour's `onResolved` (tap/hold). Pure `triggerGlyph(_:)`
  mapping (testable).
- **Acceptance:** default cells are unmarked; a cell whose Colour has a REPLAY tap shows ↻; a HOLD action rings it.

### A4. States (verify + close gaps)
Empty = watermark row number (exists). Selected / placed-this-hold = WHITE outline (already canon — confirm NO
amber survives on the face). Hidden-pending ring = existing behaviour. Likely verify-only.

## PART B — THE DESK (ProcessorBox)

### B1. Title-as-picker + the TYPE PICKER popover  ✦ the big one
- Title row becomes **[EMBLEM] TYPE ▾ · COPY · PASTE** — current type always visible, emblem beside it, tinted
  in the Colour's hue. Tapping the type name opens a **PICKER POPOVER**: one row per type — emblem · NAME ·
  one-line description — selecting retypes the panel (params reset per the standing retype rules; A uses
  `onSetTypeA`, B uses `typeB`). **Panel B's picker leads with OFF; panel A's has none.**
- **Then the `seg(...)` type rows are DELETED** everywhere (`typeSelector` gone).
- **Where:** `ProcessorBox.titleRow` + a new `typePicker` popover (a self-contained view — reused by D2). Keep the
  popover a plain overlay/`.popover` sized for 6–7 rows.
- **Acceptance:** the title shows emblem + type; tap → popover of all types (B also OFF) with descriptions; pick
  → the panel retypes; no segment row remains.

### B2. Emblems on cells + titles
Draw the emblem (prereq) statically in the cell face (A1) and the desk title (B1). No new work if A1/B1 wired it;
this increment is the consistency check + the placeholder-glyph set finalised.

## ⛔ CONFIRM WITH THE USER (B→C boundary) — proceed to C/D only on the nod.

## PART C — NAMES (optional Colour ownership)

### C1. Optional Colour name  ✦
- Add `Colour.name: String?` (Optional → old docs decode nil; `nameResolved = name ?? typeName`). Editable in the
  desk title area (reuse the `PresetBrowser` `TextField` keyboard handling). Shows in the palette chip, the desk
  title, and INSPECT cards. No custom name → the type name shows (today's labels). **Names never replace the
  emblem** (glyph = mechanism-truth; name = the user's word).
- **Tests:** Codable round-trip + `nameResolved` fallback (nil → type name).
- **Acceptance:** name a Colour → its chip/title update; clearing → reverts to the type name.

## PART D — THE SPARSE PALETTE

### D1. Defined vs "+" slots (model)  ✦
- Add `Colour.defined: Bool` (Optional/`= true` → old docs = all defined = today's behaviour). Palette shows only
  DEFINED Colours as chips + "+" slots for the undefined remainder (16 max). The DEFAULT preset ships only the
  arc's 3–4 Colours defined; the rest undefined.
- **Where:** `PaletteView` (render defined chips + "+" slots), `PluginState.factory`/`defaultArc` (seed `defined`).
- **Tests:** migration (old doc → all defined), factory has 3–4 defined.

### D2. Creation via the type picker  ✦
- Tapping a "+" slot opens the **B1 type-picker popover** (reused) — choosing a type BIRTHS the Colour (hue = the
  slot's default from the standard 16-wheel; name = the type; `defined = true`). **During a PLACE hold**, tapping
  "+" opens the same picker and the new Colour becomes the brush — creation never exits the hold.
- **Acceptance:** tap "+" → picker → a new chip appears (correct hue); in a PLACE hold, the new Colour is the brush.

### D3. Protection — scenes-are-precious sibling  ✦
- **Census** = cells painted with a Colour (cheap derived count across scenes). Census > 0 ⇒ cannot delete; the
  desk shows the census. Census = 0 ⇒ a small delete control on the desk; deletion is UNDOABLE (`defined = false`).
- **Where:** pure `colourCensus(_ doc:) -> [colourID: Int]` (testable); desk delete control gated on it.
- **Tests:** census count; a painted Colour is protected; an unpainted one deletes (undo restores).

## Verification & housekeeping
- Off-device FIRST: the `MidiSparkTests` macOS suite (emblem map, trigger-glyph, `nameResolved`, `defined`
  migration, census). iOS build each increment. Tick `pending-tasks.md` + add a CLAUDE.md status line per commit.

## Judgment calls flagged for ratify
1. **Emblem glyphs** = placeholder SF Symbols this wave (doc permits). OK to pick reasonable stand-ins?
2. **`defined` model** = a `Colour.defined` bool (vs. a separate defined-set). Proposed the bool (Codable-simple).
3. **Emblem/white contrast on pale hues** (design note) — I'll add a dark keyline behind the emblem/glyph on
   pale Colours; confirm that treatment on device.
