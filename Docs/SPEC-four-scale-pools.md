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

## THE CHORD DOOR (Paul 2026-09-04) — BUILT (sibling of the scale door)
A new `DoorMode.chord`: like SCALE, FOUR instances radio-switched from a strip
pop-up (the strip CHORD button + a door-sheet launcher). Its pool is a DIATONIC
CHORD generated from the CHORDS-processor primitives:
- **Per-instance config:** KEY FROM (a referenced SCALE door ▸/A–D that supplies
  root+scale; ▸/non-scale ⇒ C major) · DEGREE (I…VII, quality-aware Roman labels) ·
  VOICING (TRIAD/7TH/ADD9) · SPREAD (CLOSE/OPEN) · base octave.
- **Engine:** the door's frozen pool = `chordDoorNotes(...)` = `diatonicChord`
  anchored at the base octave, fed through the KEYS pipeline (self-arms, honours
  EXCLUDE, plays along) exactly like SCALE. Byte-identical machinery; only the note
  SOURCE differs (a chord set vs a scale set). `latchPianoResolved` true for `.chord`.
- **Model:** `ChordPool {source·degree·voicing·spread·baseOct}` +
  `Receiver.chordPools`/`activeChord` (additive-Optional; nil ⇒ four defaults). The
  strip/tab/chip name themselves ("A · V7").
- **Standing set, switched by hand** = the progression (no PATTERN/FOLLOW/WALK modes;
  the four instances + the radio ARE the way you move between chords).
- Built end-to-end; iOS builds, macOS 1057 green (+5 tests). DEVICE eye/ear owed.

### CHORD-door judgment calls (device-owed)
- Each instance is ONE standing chord (degree-selected). If you want a door to WALK a
  progression or FOLLOW played input over time, that's a separate mode (not built).
- KEY FROM references a SCALE door; a non-scale/absent source silently falls back to
  C major (a small "using C major" hint shows in the editor).
- Same self-arm visual caveat as SCALE (the strip amber reads off the manual latch).

## Device-owed / judgment calls
- The SCALE button's amber "engaged" visual still reads off the MANUAL latch mask —
  a self-arming SCALE door may look un-engaged though it is feeding (pre-existing).
- The strip label stays "SCALE" (doesn't yet show which slot is live).
- Editing a slot requires making it active first (radio model).
- Pop-up sizing / legibility.
