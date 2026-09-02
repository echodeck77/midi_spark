# PLAN — the part-page PIANO ROLL (true + accurate)

The strip under the part grid must show, as a piano roll, **exactly what the part will play on one pass**.
Today it's a static mock (`roomsPartPianoRoll`). This plan replaces it with the REAL engine output.

## Paul's rules (the contract)
1. **TRUE + ACCURATE** — not a mock. It must be the actual engine output.
2. **8-view AND 16-view** — the roll spans the part's active width (`buildPartCols`, 8 or 16) at the part's rate.
3. **The selected column's MIDI output, or nothing if no output** — a column with no selected rung is silent; a
   cell routed to no emitter (no output) contributes nothing. (Both fall out of rendering the real scene — see below.)
4. **Truly what the user hears on this pass** — rendered against a FIXED reference chord, deterministically,
   **NOT** re-shaped by live MIDI input. (A fixed reference is better: deterministic, always shows something, and
   doesn't flicker as you play. Chosen.)

## The insight — render the real scene offline
The part audition scene (`BuildSceneLogic.composeScene`, `stagingPlaying`) IS what plays. It already encodes rule 2
(per-row rate/length → the pass width), rule 3 (only selected rungs are placed; a cell with no emitter emits nothing),
and the AUTO automation bake. So the roll = **run the real Router over that scene for ONE pass against a reference
chord and record every emitted note**. Same discipline as `Dice.runRecorder` / `Accept.onsA` / `gridSelRollBars` —
the recording `MIDIEmitter` double + the real engine, so it can NEVER drift from what actually plays.

## Increment 1 — the offline renderer (pure, testable) — the load-bearing bit
- New pure fn (Foundation-only, in a testable file — e.g. `Derivations`/`BuildSceneLogic` or a new `PartRoll.swift`):
  `partRollBars(scene: SceneState, chord: [Int:UInt8], cycleBeats: Double, stepBeats: Double) -> [RollBar]`
  where `RollBar { startBeat, endBeat, pitch: Int, vel: UInt8, cable: Int }`.
- It builds a one-scene `PluginState`, runs `SnapshotBuilder` → `Router.process` across ONE pass (0…cycleBeats) with
  the reference `chord` held on the doors the cells read, capturing events into a `RecordingEmitter`, then PAIRS each
  note-on with its note-off (a note open at pass end closes at `cycleBeats`) → bars. Captures ALL five cables (not
  just A, unlike `Dice.signature`) so per-emitter colour is available.
- **Reference chord**: a fixed canonical voicing (start with the Dice reference / a C-major triad or a 4-note spread —
  a `staticReferenceChord`, Paul-tunable). Note: chord-derived processors (arp/chords/harmonize/euclid) render their
  derivation OF the reference — accurate for that reference.
- Sweeps the pass (transport advancing), NOT `forceColumn` — so it captures the whole sequence, honoring per-column
  selected rungs + the part rate. (The Acceptance harness already sweeps; model on it.)
- **+tests**: a known 2-column part (arp on col 0, drone on col 1) → the expected bars (counts, pitches, the
  col-1 bar starts at 1 step); a deselected column → no bars in its span; a cell with no emitter → no bars.

## Increment 2 — wire it + draw the real roll (replaces the mock)
- Recompute the bars when the composed scene changes — off the main thread (the `gridSelRollBars` pattern), keyed by a
  cheap scene signature so it only recomputes on a real change; cache in `@State buildPartRollBars`. (The part audition
  scene is already built in `buildPublishScene`; feed the same scene to the renderer.)
- Rewrite `roomsPartPianoRoll` to draw the bars: **x** = `startBeat / cycleBeats × width` (span = `buildPartCols`
  columns, gridlines aligned to the grid columns — rule 2); **width** = `(endBeat−startBeat)` (real duration);
  **lane (y)** = pitch, auto-fit to the used pitch range (a few semits of headroom); **colour** = the bar's EMITTER
  (`emitterHexes[cable]`) so "the MIDI output" reads as its output cable — rule 3; **opacity** = velocity.
- Empty (no bars) → the strip is blank (rule 3: no output → nothing).

## Increment 3 — polish (optional)
- A playhead on the roll synced to the part playhead (reuse the `roomsPartPlayhead` beat math), so the roll shows
  where the pass is.
- Pitch-range auto-fit with a stable window (avoid the lanes jumping as notes change).
- A per-emitter legend / filter if a part uses several emitters.

## Open decisions (need Paul)
1. **Reference chord** — a plain C-major triad, or a richer 4-note voicing? (Tunable; affects how arps/chords/harmonize
   render.) Should it follow the part's KEY/SCALE door if one is set, or always a fixed C? (Rule 4 says exclude live
   INPUT, but a SCALE door is a setup, not input — could honor it.)
2. **Colour** — by EMITTER (the output, my read of rule 3) or by the cell's COLOUR? Emitter reads as "what plays where".
3. **Recompute cadence** — on every scene change (debounced), or only when the strip is visible / the part is stopped?

## Sequence
Increment 1 (offline renderer + tests) → Increment 2 (wire + draw) → device ear/eye check → Increment 3 polish.
Increment 1 is off-device-testable and is where the accuracy is proven; do it first, with tests.
