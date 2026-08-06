# MidiSpark — PENDING TASKS (forward checklist)

_The canonical "what's left" list. CLAUDE.md's "Current status" is the backward log (what LANDED, with commit
refs); THIS file is forward-looking (what's open). Keep them from overlapping: when a task lands, tick it here
AND add its commit line to CLAUDE.md status. Terse by design — detail lives in the spec (`midispark-spec-v3.0-
delta.md`, esp. §10) and the `Docs/design-*.md` ferries. Last synced: 2026-07-29._

## ◐ IN PROGRESS (2026-08-05) — MACROS (phase 2 track, branch `feat/macros`)
Specs: `AcceptanceCriteria-macro-panel.md` · `-macro-ab-authoring.md` · `-overlay-rule-macro-lanes.md`. iOS builds,
438 green; commit refs in CLAUDE.md status; **device pass owed**; NOT on `main`.
- [x] M0 state model · M1 offset term (base ⊕ Σ value×delta, folded at build; seals stable) + tests · M2 the 8
  slider macros as automatable AU params · M3 the MACROS tab panel (BTN|SLD|TML; sliders drive values + padlock) ·
  **M4 A/B authoring** (the [AB] popup on the Edit page's CHAIN header → live B demonstration → bind delta to a
  SLIDER macro; base restored to A on close). **MACROS ARE USABLE END-TO-END.** Device pass owed.
- [x] BUTTON bank completed end-to-end (values via a direct document setter for 8–23; [AB] popup SLD|BTN selector).
- [x] OUTPUT group done end-to-end: the offset extended to the per-emitter role amounts (LEAK/DUCK/CURVE/POCKET,
  MacroEmitterTarget, folded in the builder) + the [AB] popup's CHAIN|OUTPUT selector + OUTPUT authoring.
- [ ] INPUT group — the source shaping. **Underspecified**: the panel spec lists INPUT as a group but doesn't name
  its continuous targets. Candidates: the velocity window (floor/ceil) · the note range (lo/hi). Needs a pick before
  building (SnapCell-field fold + an INPUT group in the popup).
- [ ] Deferred within macros: TIMELINE bank (lane editor + per-column STEP|SMOOTH|BYPASS + the render-time
  TIMELINE bank (lane editor + per-column STEP|SMOOTH|BYPASS + the render-time per-column path, which replaces M1's
  bake-at-build for lanes) · BUTTON/TIMELINE binding + mover-eligibility live-dim · the A↔B morph-audition slider ·
  the CC rail · the perform-surface panel in the GRID top band (part of the phase-2 GRID redesign) · announce/
  ghost-thumb tells.

## ★ DONE (2026-08-05) — LAYOUT v2 tab shell (phase 1)
Spec of record: **`Docs/AcceptanceCriteria/layout-v2-tabs.md`**; plan `~/.claude/plans/resilient-imagining-truffle.md`.
On `main`, iOS builds, 428 green; commit refs in CLAUDE.md status; **device pass owed**.
- [x] Part 0 — retire SELECT · Parts 1-2 — six-tab bar + body switch (`AppTab`) · Part 3 — clock→header ·
  Part 4 — RECEIVERS tab (`ReceiverConfigView`) · Part 5 — EMITTERS tab (rack out of the grid).
- [ ] **Phase 2+ (deferred, captured):** GRID top-band 8 macro sliders+buttons · SINGLE|MULTI toggle · HOLD
  localisation per slider group · the MACROS + AUTOMATION engines/pages · global FREEZE/STUTTER gestures ·
  MIDI-OUT channels moved into the emitters tab. (These are engine/authoring work — needs Paul to prioritise.)

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
- [ ] **Accent-colour dedup (refactor B1)** — the two accent hues are redefined ~35× under ~14 local names
  (`cyan`/`barCyan`/`sceneAmber`/`amber`/`claimAmber`/`soloHue`/…). Canonicalise to `Color.accentCyan`/`accentAmber`
  once (all SwiftUI-only files → import-safe). **BLOCKER:** `FlowView.swift`'s cyan is `Color(red:0.145,g:0.878,
  b:0.941)` — a real ~0.005 near-miss of the canonical `0.15/0.88/0.94`; needs a ruling (unify to canonical, or keep
  FlowView's tuned-for-dark-canvas value). Same open question for FlowView's lighter receiver-hue palette vs
  `receiverHues`.
- [ ] **midiNoteName convention** — the shared `midiNoteName` is 0-based (note 60 = "C5"); `RackMatrix.noteName` is
  `n/12−1` (note 60 = "C4"), so FENCE labels read an octave below the receiver RANGE labels. `midiNoteName`'s doc
  says it exists "so naming can't drift". Pick the canonical convention (C4=60 is the common MIDI one) → unify (a
  visible label shift, hence a ruling).
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
- [ ] **CONTROLLER ROUTING v1** (design ruling 2026-08-06, spec `AcceptanceCriteria-controller-routing.md`) —
  per-door cog mask CONTROLLERS→[A·B·C·D] (default all-live); forward matching CC/PB/AT/PC to each selected emitter
  RE-STAMPED to its channel; supersedes the hardwired `passthroughCableMask`. **CC123/120 = pool/latch FLUSH +
  forward** (all-notes-off must release us). **UMP legacy parity where cheap** (system/SysEx pass). BEND-ownership
  rule reserved for the future per-emitter bend stage. Render-input-path + a DEVICE ear-check — captured, not built
  blind. Model seam: `Receiver.controllerMask: UInt8?` (nil ⇒ 0b1111).
- [x] **MPE toggle + auto-detect RETIRED** (design ruling 2026-08-06, on `main`) — the RECEIVERS-tab MPE toggle
  (`ReceiverConfigView.mpeRow`) + the write-only auto-detect (`mpeSeenAt`) are gone (manual-honesty law: the UI
  stopped promising what nothing reads). `Receiver.mpeMerge` stays Codable + `setReceiverMpeMerge`/`mpeLikely`
  reserved for the two-lane expression era.
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
  - [x] **Phase 2a — triggers accordion** (Colour-side, off-device): a one-open accordion editing `Colour.on`
    via `editOn`→`editBrushColour` (undoable); reused `OnConfig` wholesale — no schema change. **Curated to the
    WIRED actions only** (user, this version): TAP none/alt/mute/solo · HOLD none/alt/oct · ARRIVE none/alt-
    alternate/morph-drift/emitter-rotate; the inert placeholders (fill/replay/freeze/slice-cycle/morph-scrub/dice)
    + the LEAVE & SCENE rows are hidden (enum cases kept for a future TOUCH-box design pass). Device-verify:
    pickers offer only the wired actions, each fires in perform, edits ride to the cell-face glyph.
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
    - [~] **chop routing ENGINE** (SEMANTIC confirmed by user: 8 slices divide the CELL'S OWN column, a per-cell
      output gate — not pass columns):
      - [x] **TICK cells** (off-device): `chopSlice(mBeat, columnBeats:)` → each ARP tick / RATCHET repeat routes
        MAIN/ALT/MUTE by its slice within the column (`chopBusMask`); MUTE-slice = silent. Tests cover both pure
        fns. (Reverted the earlier wrong pass-column indexing.)
      - [ ] **HOLD cells** (identity/passgate/chance/harmonize) — the trance-GATE: sub-articulate the sustained
        chord into 8 slices (note-off at MUTE edges, ALT redirect), interacting with legato/harmonize/adoption.
        The bigger piece.
      - [ ] **STRUM + row-fed MIRROR** chop (thread the onset slice in).
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
