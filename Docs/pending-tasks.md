# MidiSpark — PENDING TASKS (forward checklist)

_The canonical "what's left" list. CLAUDE.md's "Current status" is the backward log (what LANDED, with commit
refs); THIS file is forward-looking (what's open). Keep them from overlapping: when a task lands, tick it here
AND add its commit line to CLAUDE.md status. Terse by design — detail lives in the spec (`midispark-spec-v3.0-
delta.md`, esp. §10) and the `Docs/design-*.md` ferries. Last synced: 2026-07-29._

## ★ DONE (user, 2026-07-29) — /btw authoring UX + AcceptanceCriteria wave
Spec of record: **`Docs/AcceptanceCriteria/verbs-behaviour.md`**. All LANDED off-device (device pass owed) —
commit refs in CLAUDE.md "Current status":
- [x] **/btw ⑥** one-per-column per-hold · **④** retro-repaint · **⑤** per-cell + row selectors (already built) ·
  **STROKES** · **MIXED-SET law** · palette-live-during-holds (via ④).
- [x] **AcceptanceCriteria additions**: SELECT empty-tap no-op · **DELETE = SEVER** (children cut to MIDI-IN) ·
  **DESK RE-POINT** hard rule · **multi-cell routing (per-column)** + **SRC/DEST pulsing candidate look** ·
  placed/selected cells always WHITE · PLACE nearest-above nudge · **sticky routing** · **verbs do NOT latch**.
- [x] Refactor + tests: routing logic → pure `Derivations` helpers (`routeFociByColumn`, `placedCellRouting`) +
  `deleteCell` dedup (`181bf7c`).

## A. Blocked on the user (need a decision before building)
- [ ] **HOLD latch re-home** — §5c latch UI slot is vacant; CONTROLS-corner restoration recommended, awaiting the nod.
- [ ] **SCOPE ops home** — chips-during-SELECT-hold vs deferred (design device-nod).
- [x] **DELETE-sever fallback in the null era** (user ruled NULL, 2026-07-30) — severed children now fall to NULL
  input (inputRow nil AND inputReceiver nil, own emitters kept) instead of a phantom R1 re-point. Done in
  `deleteCellSever`; test updated. Reply to design-side owed (bundle with the file-read ack).

## B. ✅ DEVICE-VERIFIED (user device pass, 2026-07-30 — "happy with things as they stand")
The whole accumulated GUI + engine stack was run on device and ACCEPTED. Cleared from the owed list:
- [x] **Adoption ear-check** · **Strips** (session faces · LATCH · DUCK · SPACE-FILL · receiver marks · emitter buttons · verbs-as-pills) · **COPY·PASTE** · **preset enlarge + UNDO/REDO** · **white selected ring**.
- [x] **AcceptanceCriteria wave (2026-07-29)** — /btw ④⑥ · STROKES · MIXED-SET · DELETE-sever · multi-cell routing · candidate body-pulse · desk re-point.
- [x] **Routing view + visualisation (2026-07-30)** — IN/OUT labels · candidate-hides-content · the routing overlay (curved flows + comets · cell→cell arrow · band dots · clip-over-uncrossed · lane separation · lit-through-selected).
- [x] **Cells & colour desk overhaul (2026-07-30)** — cell face (emblem · digest · dots · compass tint · trigger glyph · white selection) · desk title-as-picker + popover · Colour NAMES · SPARSE palette · census protection. _(Placeholder SF-Symbol emblems still stand in for real artwork — the drawing job is a separate asset task, not a bug.)_
- [x] **Fresh-cell + naming + furniture (2026-07-30)** — fully-null new cells · full processor names · grid down-chevrons (watermark + column keys) · dual-side row rails · DELETE-sever→NULL.

## C. Buildable now (next increments)
- [x] **THE "STRIPS DONE" WAVE** — emitter hold-while-sounding feed built + **device-verified 2026-07-30**
  (steady cargo-tinted `SoundMark` ticks + fade-on-release; `Router.snapshotEmitterSounding`; test
  `testEmitterSoundingReportsHeldNoteOnItsBusThenClearsOnRelease`). ④ polish-laws accepted at current values on
  the device pass. _(Latent: the release-fade keys on (vel, colour) not the wire note — same-vel chords could
  mis-pair a fade; not seen on device, revisit only if it surfaces.)_
- [x] **Full strip EDIT-face sweep** — DONE (off-device): the strips' EDIT faces were dead in the live path
  (nothing passed `editing:true`) and their config already lives on the cog (`CogPage.swift`). Retired
  `OutputsView.channelStepper` + `ReceiversView.editFeatures` and the `editing` param on both, plus the orphaned
  callbacks/helpers. Strips are single-face forever. _(Separate future: `GridView.editing` — the grid's own
  cell-editor mode — is untouched.)_ Device-verify: the strips look/behave unchanged (perform face only).
- [~] **CELL EDIT** (spec `Docs/AcceptanceCriteria/AcceptanceCriteria-cell-edit.md`; user-chosen phased build).
  Decisions locked: start with the station skeleton; **triggers stay Colour-side** (no per-cell schema change).
  **LAYOUT (evolving): design-side revised B to a full-page takeover (2026-07-31); the USER then overrode that —
  the page REPLACES THE GRID in its slot (via `gridBlock`, like FLOW) while receivers/emitters/strips/desk/arr-bar
  stay visible + reachable. Spec B on file still says full-takeover — ferry the user's grid-slot override to
  design-side.** Content/model/engine/tests unaffected by all this layout churn.
  **OPEN BUG: crash on tapping the TRIGGERS section (device, first Cell-Edit device run). No logic error on that
  path (collapsed rows are plain text) → suspect a SwiftUI transition/nesting crash; the grid-slot move may have
  cleared it. Awaiting device retest + a crash log to confirm/pinpoint.**
  - [x] **Phase 1 — station skeleton + full-page rework** (off-device): EDIT = a 6th TOGGLE (out of the `Verb`
    enum); tap re-points + suppresses the trigger fire. **Re-architected to the full-page takeover**: `cellEditPage`
    replaces the whole grid layout when a cell is pointed; pinned breadcrumb (scene · column · 8-dot minimap ·
    DONE); persistent LOOP+TEST strip (placeholders; test pad shows the glyph, H6); ONE vertical accordion
    (IDENTITY · INPUT · TRIGGERS · OUTPUT · sound-desk, B4). Retired the `primarySlot`/`deskSwapBar`/`deskShowsColour`
    in-place swap. Device-verify: takeover push/return (DONE + re-tap EDIT), breadcrumb minimap, one-open accordion.
  - [x] **Phase 2a — triggers accordion** (Colour-side, off-device): the 5 ON rows (TAP/HOLD/ARRIVE/LEAVE/SCENE)
    as a one-open accordion, collapsed summaries + expanded action/facet pickers, editing `Colour.on` via
    `editOn`→`editBrushColour` (undoable). Reused `OnConfig` wholesale — no schema change. Device-verify the
    accordion + that edits ride through to the cell-face glyph.
  - [ ] **Phase 2b — REDIRECT + retrigger style** (NET-NEW model+engine): the REDIRECT TAP/HOLD action + ALT-DEST
    A–D toggles (new `OnConfig` field + admission-time engine effect); the TAP CUT|LAYER retrigger field.
  - [~] **Utilities §I**: [x] Apply-input-to-scope (twins / all-colour, reuse `applyToScope` + live counts) +
    Reset-input (off-device). [ ] Copy/Paste CONFIG (a cell input+triggers clipboard, `ProcClip` pattern) — deferred.
  - [x] **Phase 3 — input editing** (COMPLETE, off-device): source · octave/transpose · chord-split · velocity window.
    - [x] **3a source picker** (off-device): NONE · MIDI-IN R1–R4 · FROM ROW n value-chip, editing the existing
      `inputRow`/`inputReceiver` (reuse `routeInReceiver`/`routeInRow`/`routeInSourcesAbove`). No schema change.
    - [x] **3b chord-split** (NET-NEW, off-device): ALL · TOP n · BOTTOM n · KEY RANGE. `Cell.chordSplit?`
      (migration-safe) → `SnapCell`; pure `chordSplitWindow` applied inside the `srcCount(for:)`/`srcAscending(for:)`
      readers (contiguous window, ALL fast-path); station INPUT SPLIT control (per-cell). Tests: window (all
      modes+edges) · readers apply it · Codable/migration. _(Follow-up: preview/audition STRUM use a raw filter,
      so the split doesn't reach those two paths yet.)_
    - [x] **3c velocity window** (NET-NEW, off-device): `Cell.velWindow?` (migration-safe) → `SnapCell`;
      velocity-aware base readers composed as velocity-admit THEN chord-split (full-range fast-path); station
      VEL ≥ / VEL ≤ steppers. Tests: gating + composition + Codable/migration.
    - [x] **3d input octave + transpose** (off-device, REUSE not net-new): per spec "existing steppers,
      unchanged" — surfaces the per-Colour `transpose` (−24…+24 st, already engine-wide) as a SHIFT row (octave
      ±12 + semitone ±1) via `setBrushTranspose`. Colour-side like triggers; no schema/engine change. _(If a true
      per-CELL input transpose is wanted later, that's the net-new ~5-site version — deferred.)_
  - [~] **Phase 4 — output/chop** (spec F REVISED 2026-07-31):
    - [x] **UI + model** (off-device): MAIN dest A–D (LIVE, edits cell.buses) · the 8×2 chop grid (MAIN+redirect
      dot / MUTE) · shared ALT A–D. New `Cell.chop` (Chop = 8 slots + alt set, migration-safe; Codable test).
      Grid/alt edits persist but are labelled "routing engine pending".
    - [ ] **chop routing ENGINE** (NET-NEW, the real work): per pass-column, a SUSTAINED cell's output re-routes
      MAIN/REDIRECT(+alt)/MUTE across column boundaries — touches the boundary reconcile. Confirm the temporal
      semantic (8 slots = pass columns; applies to notes crossing boundaries) on device before wiring.
    - Open call F (emitter-picker vs spatial ROUTE-OUT) — both surfaced now (two doors); leave as-is unless the
      user rules to collapse them.
  - [ ] **Phase 5 — LOOP**: single-column loop ≈ one-bit `laneMask` via existing `lapColumn` (very low engine
    risk); UI toggle + wiring. Resolve open call G3 (LOOP-starts-playback-when-stopped).
  - [ ] **Phase 6 — test pad**: real-path stopped-time trigger fire (self-driven clock + silence-invariant
    exemption + scope). Hardest engine piece.
- [x] **Trigger-glyph cell face** (§3) — built in the cells-and-colour-desk overhaul (emblem · trigger glyph · digest · dots · compass tint) and device-verified 2026-07-30.
- [x] **Touch completions** — palette LIVE during holds · **STROKES** · **MIXED-SET law** — ALL DONE (2026-07-29; see the DONE block above).
- [ ] **Live preset previews** · **SCROLL+TEACH** (both deferred-flagged).
- [ ] **Tag `v0.7-gui`** (user tags manually).

## D. Parked futures — log only, NO build (re-explain from `design-ferry-completions-phase-cc-2026-07-28.md`)
- [ ] FEEDBACK EDGES (unit-delay) · THE PIN · MASTER+TEXTURE multi-playhead · **THE CC RAIL** · **THE TWO-LANE INSTRUMENT** (+ cross-lane valves) · MORPH desk (16 faders) · EXTERNAL processor type + standalone-app milestone.
- [ ] **MULTI-INPUT / fan-in — THE G1 RULING** (design-Claude, 2026-07-30; captured here because the ferry note is
  transient). Shipping subset = **multi-RECEIVER-in** only (merge the four doors); keep the single row-parent so
  chains stay trees (no DAG, cycles impossible). At a union point: the pool is a **refcounted SET** (a note lives
  while ANY source holds it; entry dies at count 0; dedup by wire note-number after per-source transforms).
  **Velocity** = the latest strike UPDATES the pool entry but NEVER re-strikes a sounding hold-voice (applies to
  the next articulation). **Voice identity stays source-blind**: note + emitter + Colour-and-face, refcounted at
  the union. Full multi-row-parent remains the parked birthstone (schema-as-set already insures it).

## E. Architecture debt (opportunistic, all accepted)
- [ ] §6a CLAIM L3 residual (short-note All `on,off,on,off`) · `TODO(spec §7)` param route (writes doc then rebuilds) · `Cell.stack`/`srcMix` kept load-bearing for the v2→v3 migration.
- [ ] **HARMONIZER hung-note ROOT CAUSE** (user-reported device bug, 2026-07-31) — the §a8b playing-time net now
  auto-clears it within ~1 s (safety net, committed), but the underlying leak is NOT fixed. HARMONIZE emits
  root + up to 3 interval voices per source note with column-boundary offs (Router `emitHarmony`); a missed/late
  off leaves a stuck wire note. Suspect the close-vs-reemit ordering at a column boundary or a refcount imbalance
  amplified by harmonize's fan-out (4× voices vs identity's 1×). Repro on device, then trace `emitHarmony` →
  `emitArtic`/`openVoice` refcount across a column transition + a live interval change while a chord sustains.

---
_Done this thread (moved off the list): /btw ①②③ · adoption · strips session-faces/LATCH/DUCK/SPACE-FILL/receiver-marks · verbs reverted to pills · CONTROLS single-face · §10 spec fold. **2026-07-29 wave:** /btw ④⑤⑥ · STROKES · MIXED-SET · DELETE-sever · multi-cell routing + SRC/DEST look · desk re-point · sticky routing · verbs-no-latch · routing refactor+tests. See CLAUDE.md status for commit refs._
