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

## Future (captured, not built)
- **CHORD variant** — "this same pop-up will later show as chord selected." The
  pop-up shell is generic; a CHORD door would swap the per-slot editor (a chord
  picker) and the pool derivation. Shape TBD with Paul.

## Device-owed / judgment calls
- The SCALE button's amber "engaged" visual still reads off the MANUAL latch mask —
  a self-arming SCALE door may look un-engaged though it is feeding (pre-existing).
- The strip label stays "SCALE" (doesn't yet show which slot is live).
- Editing a slot requires making it active first (radio model).
- Pop-up sizing / legibility.
