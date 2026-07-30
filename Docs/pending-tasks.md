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

## B. Device-verify owed (this thread's work — none seen or heard on device)
- [ ] **Adoption ear-check** — drones glide across boundaries, no clicks; claim/ALT/emitter-octave edges (`8d5f1b3`).
- [ ] **Strips** — session faces (ROUTE IN/OUT) · LATCH arm · DUCK · **SPACE-FILL at small sizes** · receiver velocity marks · taller emitter buttons · verbs-as-pills.
- [ ] **COPY·PASTE flow** · **preset enlarge + UNDO/REDO** · **selected-visual white ring** (does ROUTE-IN still read as a selection?).
- [ ] **AcceptanceCriteria wave (2026-07-29)** — /btw ④⑥ · STROKES · MIXED-SET · **DELETE-sever** (no orphaned children / stuck notes) · multi-cell routing feel · candidate BODY pulse + WHITE selected ring · sticky routing · desk re-point. All off-device only.
- [ ] **Routing view + visualisation (2026-07-30)** — IN/OUT labels (candidates + strips) · candidate hides content · chosen-candidate-returns-to-standard · the **routing overlay** (curved flows + comets · cell→cell solid line + downward arrow · large band dots · clip-over-uncrossed · lane separation · lit-through-selected). Anchor positions computed — verify endpoints land right on device; tune lane/dot/arrow sizes.
- [ ] **Cells & colour desk overhaul (2026-07-30)** — cell face (emblem · digest · bus dots · compass tint · trigger glyph · white selection) · desk title-as-picker + type popover · Colour NAMES (desk editor) · SPARSE palette (defined chips + "+" slots, birth via picker) · census delete-protection. Placeholder SF-Symbol emblems/glyphs (real artwork pending); check emblem contrast on pale/dark hues; confirm the desk points at a defined chip after delete.
- [ ] **Fresh-cell + naming fixes (2026-07-30)** — new cells are FULLY NULL (no input row, no receiver, no emitter — never auto-wired) · processor names shown in FULL · grid numbers → down chevrons (watermark + column keys) · row-select rail on BOTH sides (left points right, right points left). Verify: a placed cell shows no source-from-above/no receiver ring/no emitter until wired (red dashed "no-dest" ring is expected on a null cell); the full name (`HARMONIZE`, 9ch) fits the desk title/picker without clipping; the new left rail aligns with the grid rows and applies the held verb identically to the right rail; chevrons read clearly in empty cells + column keys.

## C. Buildable now (next increments)
- [ ] **THE "STRIPS DONE" WAVE** (design-ACCEPTED 2026-07-29, one wave = strips finished): **emitter
  sounding-feed → emitter hold-while-sounding marks → ④ polish-laws device tuning.**
  - Emitter feed: per-emitter currently-sounding notes = the **refcount/voice table sliced by bus** (should
    fall out nearly free), and **carry the source CELL/`colourIndex` with each note** so the cargo-tint law
    (marks in the source Colour) rides the same feed. `Voice` already has `colourIndex` (adoption). Mirror the
    receiver's `recvHeld` pattern: accumulate render-side, drain to the VC, render hold-while-sounding +
    fade-on-release in `OutputsView` (like the receiver's `releaseMarks`).
  - ④ polish-laws: v1 `ffef361` was conservative guesses — tune on device.
- [ ] **Full strip EDIT-face sweep** — retire OutputsView.channelStepper / ReceiversView.editFeatures *after* re-homing channel/cable/latch config to the **cog** ("single-face forever").
- [ ] **Trigger-glyph cell face** (§3, ratified) — Colour block · emblem · trigger glyph · digest dim · dots · compass tint; naming demoted.
- [x] **Touch completions** — palette LIVE during holds · **STROKES** · **MIXED-SET law** — ALL DONE (2026-07-29; see the DONE block above).
- [ ] **Live preset previews** · **SCROLL+TEACH** (both deferred-flagged).
- [ ] **Tag `v0.7-gui`** (user tags manually).

## D. Parked futures — log only, NO build (re-explain from `design-ferry-completions-phase-cc-2026-07-28.md`)
- [ ] FEEDBACK EDGES (unit-delay) · THE PIN · MASTER+TEXTURE multi-playhead · **THE CC RAIL** · **THE TWO-LANE INSTRUMENT** (+ cross-lane valves) · MORPH desk (16 faders) · EXTERNAL processor type + standalone-app milestone.

## E. Architecture debt (opportunistic, all accepted)
- [ ] §6a CLAIM L3 residual (short-note All `on,off,on,off`) · `TODO(spec §7)` param route (writes doc then rebuilds) · `Cell.stack`/`srcMix` kept load-bearing for the v2→v3 migration.

---
_Done this thread (moved off the list): /btw ①②③ · adoption · strips session-faces/LATCH/DUCK/SPACE-FILL/receiver-marks · verbs reverted to pills · CONTROLS single-face · §10 spec fold. **2026-07-29 wave:** /btw ④⑤⑥ · STROKES · MIXED-SET · DELETE-sever · multi-cell routing + SRC/DEST look · desk re-point · sticky routing · verbs-no-latch · routing refactor+tests. See CLAUDE.md status for commit refs._
