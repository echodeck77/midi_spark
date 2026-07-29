# MidiSpark — PENDING TASKS (forward checklist)

_The canonical "what's left" list. CLAUDE.md's "Current status" is the backward log (what LANDED, with commit
refs); THIS file is forward-looking (what's open). Keep them from overlapping: when a task lands, tick it here
AND add its commit line to CLAUDE.md status. Terse by design — detail lives in the spec (`midispark-spec-v3.0-
delta.md`, esp. §10) and the `Docs/design-*.md` ferries. Last synced: 2026-07-29._

## A. Blocked on the user (need a decision before building)
- [ ] **/btw ④** — mid-PLACE colour switch: retro-repaint cells placed *this hold*, or only *subsequent* placements?
- [ ] **/btw ⑤** — SELECT scope: do **columns** act as selectors too, or rows only?
- [ ] **/btw ⑥** — "one placement per column": per-**stroke** / per-**hold** / **absolute**? (and is drag-to-place built? — seems to fight vertical chains)
- [ ] **HOLD latch re-home** — §5c latch UI slot is vacant; CONTROLS-corner restoration recommended, awaiting the nod.
- [ ] **SCOPE ops home** — chips-during-SELECT-hold vs deferred (design device-nod).

## B. Device-verify owed (this thread's work — none seen or heard on device)
- [ ] **Adoption ear-check** — drones glide across boundaries, no clicks; claim/ALT/emitter-octave edges (`8d5f1b3`).
- [ ] **Strips** — session faces (ROUTE IN/OUT) · LATCH arm · DUCK · **SPACE-FILL at small sizes** · receiver velocity marks · taller emitter buttons · verbs-as-pills.
- [ ] **COPY·PASTE flow** · **preset enlarge + UNDO/REDO** · **selected-visual white ring** (does ROUTE-IN still read as a selection?).

## C. Buildable now (next increments)
- [ ] **④ strip polish-laws** — device-tuning pass (v1 `ffef361` was conservative guesses).
- [ ] **Emitter hold-while-sounding marks** — needs a per-emitter sounding-note **engine feed** (render-path; receiver has its feed).
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
