# SPEC — FOUR SCALE POOLS per SCALE door (Paul, 2026-09-04)

> STATUS: RATIFIED by Paul (decisions below) + BUILT (model/AU/UI; iOS builds,
> macOS 1046 green). DEVICE eye/ear owed. Commit pending.

## The ask
A SCALE-mode receiver door configures **four** scale pools instead of one, and
the user switches between them live from the **strip SCALE button** — a pop-up
appears with the four options as toggles. The **same pop-up** will later carry a
CHORD variant (to be defined).

## Ratified decisions (AskUserQuestion, 2026-09-04)
1. **Toggle semantics = RADIO.** Exactly ONE scale is active at a time; tapping a
   slot switches the active pool to it. (Not a union of scales.)
2. **Config lives in the pop-up itself.** Each of the four slots carries its own
   root/scale/range editor in the pop-up — no separate sheet is the source of
   truth. (The MIDI-IN door sheet keeps a launcher into the same pop-up.)

## Model (byte-identical for old docs)
- `struct ScalePool { root; type; baseOct; octaves }` — one pool, the exact shape
  of the legacy single scale; defaults match the legacy defaults (C major, C3, ×2).
- `Receiver.scalePools: [ScalePool]?` (four) + `Receiver.activeScale: Int?` — both
  additive-Optional.
- The four existing resolvers (`scaleRootResolved` / `scaleTypeResolved` /
  `scaleBaseOctResolved` / `scaleOctavesResolved`) read the **active pool**, so the
  whole render pipeline (builder → box → kernel → CHORDS) is untouched. Switching
  the radio republishes the box with the newly-active scale.
- **Migration:** `scalePools == nil` ⇒ pool 0 = the legacy single scale, pools 1–3
  default, active = 0 → identical resolved values as before. A stray `activeScale`
  with no `scalePools` is ignored.

## UI
- **Strip SCALE button** → opens the pop-up (a SCALE door self-arms via its derived
  pool, so there is nothing to toggle on the button itself). Other door modes keep
  their arm behaviour.
- **MIDI-IN door sheet** (SCALE row) → a launcher: active-scale summary + "EDIT 4
  SCALE POOLS ▸" opens the same pop-up.
- **Pop-up** = a top-aligned card wrapping the shared editor: a 4-slot RADIO row
  (each names its scale; tap = switch active, LIVE) over the ROOT/SCALE/RANGE +
  EXCLUDE editor for the active slot.

## THE CHORD DOOR = a chord SEQUENCER (Paul 2026-09-05) — BUILT
A new `DoorMode.chord`: like SCALE, FOUR instances radio-switched from a strip
pop-up. Each instance is the **full CHORDS PROCESSOR**, reused wholesale so future
processor work reflects on the door for free. The door AUTONOMOUSLY plays its
progression on the transport clock — its pool is TIME-VARYING.

**The three shared surfaces (the "future dev reflects" contract):**
- **Config = `ColourParams`.** `Receiver.chordSeqs: [ColourParams]?` (4) — only the
  `chords*` fields matter; a future `chords*` field appears on the door automatically.
  (`activeChord` = the radio. nil ⇒ four interesting default progressions,
  `Receiver.defaultChordSeqs`, all referencing KEY-FROM door D.)
- **Editor = the processor's `ProcessorBox`.** The pop-up mounts the real CHORDS
  editor (slotMode, chrome hidden) bound to the active instance — LITERALLY identical
  controls (MODE · SCALE-FROM · degree MATRIX · VOICING · SPREAD · RATE · STEPS · WALK).
- **Engine = one pure `chordSeqNotes(beat, params, keyRoot, keyTones, followNote)`**
  (Derivations). The Router's CHORDS stage calls it (behaviour-identical refactor) AND
  the Kernel's door pool-fill calls it — one derivation.

**Time-varying pool:** the builder puts each chord door's active config into the box
(`receiverChordsParams[4]`); the Kernel walks the progression per render on
`renderBeatPos` (host or free-run beat), keyed by the SCALE-FROM door
(`chordsScaleRef`), and fills the door's latch pool (beat-derived, replay-safe). The
builder bakes NO static pool for a chord door (`receiverPianoNotes` empty; the piano
bit still set so the Kernel fills it live). The `SnapshotBuilder.applyChords` copy is
also shared between the cell build and the door build.

**Default rig (makeInit):** D → SCALE door (A mixolydian, existing); C → CHORD door;
C's four instances = AXIS (I–V–vi–IV) · 50s (I–vi–IV–V) · JAZZ ii7–V7–I7–vi7 ·
PACHELBEL (I–V–vi–iii–IV–I–IV–V), all KEY FROM D.

Built end-to-end; iOS builds, macOS 1057 green (+5 tests). DEVICE eye/ear owed.

### CHORD-door judgment calls (device-owed)
- **FOLLOW** on a door has no grid trigger; the pool-fill passes `followNote: nil`, so
  FOLLOW sits on the tonic without play-along input (v1 — wiring the door's live input
  to name the degree is a follow-up).
- **Free-run**: when the transport is stopped, the progression only advances if the
  free-run clock is driving `renderBeatPos`; otherwise the door holds one chord.
- The strip label is "A · CHRD" (the live chord changes on the beat, so it names the
  door, not a frozen chord). No matrix playhead in the door editor yet (liveStep = -1).
- Same self-arm visual caveat as SCALE (the strip amber reads off the manual latch).
- Each instance carries a full `ColourParams` (only `chords*` used) — the price of reuse.

## Device-owed / judgment calls
- The SCALE button's amber "engaged" visual still reads off the MANUAL latch mask —
  a self-arming SCALE door may look un-engaged though it is feeding (pre-existing).
- The strip label stays "SCALE" (doesn't yet show which slot is live).
- Editing a slot requires making it active first (radio model).
- Pop-up sizing / legibility.
