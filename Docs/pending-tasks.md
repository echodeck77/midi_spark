# MidiSpark — PENDING TASKS (forward checklist)

_The canonical "what's left" list. CLAUDE.md's "Current status" is the backward log (what LANDED, with commit
refs); THIS file is forward-looking (what's open). Keep them from overlapping: when a task lands, tick it here
AND add its commit line to CLAUDE.md status. Terse by design — detail lives in the spec (`midispark-spec-v3.0-
delta.md`, esp. §10) and the `Docs/design-*.md` ferries. Last synced: 2026-07-29._

## ★ CURRENT PRIORITY (user, 2026-07-29) — finish the /btw authoring UX
See **`Docs/implementation-plan-btw-authoring.md`** for the firm ordered plan. All tail decisions RATIFIED:
- [ ] **/btw ⑥** — one-per-column, scope = **PER-HOLD** (block a 2nd cell in a column already placed this hold).
- [ ] **/btw ④** — mid-PLACE brush switch = **RETRO-REPAINT** (chevrons + all cells placed this hold recolour).
- [ ] **/btw ⑤** — SELECT selectors = **per-cell + ROW chevrons** (columns do NOT select; likely mostly built).
- [ ] **STROKES** — drag = batch (place/delete/select), one undo per swathe.
- [ ] **MIXED-SET law** — processor panels dim to "MIXED" for multi-colour selections; cell-level edits still apply.
- [ ] palette-live-during-holds — delivered by ④; confirm on device.

## A. Blocked on the user (need a decision before building)
- [ ] **HOLD latch re-home** — §5c latch UI slot is vacant; CONTROLS-corner restoration recommended, awaiting the nod.
- [ ] **SCOPE ops home** — chips-during-SELECT-hold vs deferred (design device-nod).

## B. Device-verify owed (this thread's work — none seen or heard on device)
- [ ] **Adoption ear-check** — drones glide across boundaries, no clicks; claim/ALT/emitter-octave edges (`8d5f1b3`).
- [ ] **Strips** — session faces (ROUTE IN/OUT) · LATCH arm · DUCK · **SPACE-FILL at small sizes** · receiver velocity marks · taller emitter buttons · verbs-as-pills.
- [ ] **COPY·PASTE flow** · **preset enlarge + UNDO/REDO** · **selected-visual white ring** (does ROUTE-IN still read as a selection?).

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
- [ ] **Touch completions** — palette LIVE during holds (brush-switch) · **STROKES** (drag-paint, one undo/swathe) · **MIXED-SET law** (processor panels dim to "MIXED" for mixed selections).
- [ ] **Live preset previews** · **SCROLL+TEACH** (both deferred-flagged).
- [ ] **Tag `v0.7-gui`** (user tags manually).

## D. Parked futures — log only, NO build (re-explain from `design-ferry-completions-phase-cc-2026-07-28.md`)
- [ ] FEEDBACK EDGES (unit-delay) · THE PIN · MASTER+TEXTURE multi-playhead · **THE CC RAIL** · **THE TWO-LANE INSTRUMENT** (+ cross-lane valves) · MORPH desk (16 faders) · EXTERNAL processor type + standalone-app milestone.

## E. Architecture debt (opportunistic, all accepted)
- [ ] §6a CLAIM L3 residual (short-note All `on,off,on,off`) · `TODO(spec §7)` param route (writes doc then rebuilds) · `Cell.stack`/`srcMix` kept load-bearing for the v2→v3 migration.

---
_Done this thread (moved off the list): /btw ①②③ · adoption · strips session-faces/LATCH/DUCK/SPACE-FILL/receiver-marks · verbs reverted to pills · CONTROLS single-face · §10 spec fold. See CLAUDE.md status for commit refs._
