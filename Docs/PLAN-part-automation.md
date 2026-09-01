# PLAN — Part Automation (the AUTO lanes), full implementation

The part-page band is the AUTO flow: per colour, **five lanes** (`AUTO 1–5`) + **NONE**. A lane targets a
processor param (pre-mapped useful default), you **tap cells to toggle them into an extent**, and the param
**ramps across the extent** (the range). Selecting a lane **enables** it → it must **play immediately**.

## What's built (UI, `BuildPage.swift`)
- `AutoLane { slot, param, cells: Set<Int> }` (per colourID, 5 lanes, in `buildAutoLanes` @State).
- Header: `NONE · AUTO 1–5 (span) · CLEAR (separate)`; `buildAutoSel` = −1 NONE / 0–4 active lane.
- Selectors: MACHINE chips (the chain) · PARAM chips (`autoPrimaryKey` leads: ARP→GATE etc.).
- Main-grid PUNCH: `roomsPartCell` — when a lane is selected, THIS colour's cells tap-toggle in/out of the
  extent; toggled cells show a bottom-up ramp fill (`buildAutoRampFrac`) = the range swept across them.
- **NOT audible yet, not persisted** — the values are display-only.

## The remaining work — make it PLAY + persist

### The value it applies (per cell)
A cell in an active lane's extent gets the param set to a **ramped value**: `frac = rank/(count−1)` over the
extent (column→row order), `value = lo + frac·(hi−lo)` over the param's range. So an ARP-GATE lane over
columns 1–4 plays those columns with a low→high gate sweep. (No per-cell stored value — it's derived from
extent + range, so it stays cheap + editable.)

### P1 — Model + persistence
- Make `AutoLane` **Codable + Equatable**; add a per-colour **`activeLane: Int`** (−1 NONE) so each colour's
  automation is independent and the SELECTED tab is the enabled one (today `buildAutoSel` is one global value —
  it should read/write the focused colour's `activeLane`).
- `PluginState.partAuto: [String: PartAutoColour]?` (additive-Optional, keyed by colourID) where
  `PartAutoColour { activeLane: Int, lanes: [AutoLane] }`. Byte-identical when nil.
- Rooms @State ↔ document sync (mirror `BuildPlayGridData`: capture in `buildPersistTick`, restore on load).
  ⚠ **ephemeral colours** (`b<n>`, session-only) — their auto data travels only if the build's ephemeral
  colours persist (they already ride `buildUnassigned`/scenes); confirm the colourID is stable across save/load.

### P2 — The engine bake (audible) — the load-bearing bit
- The automation is per-colour, applied to CELLS of that colour in the extent. The part cells are built in
  **`BuildSceneLogic.composeScene`** (the rooms scene) — inject there:
  - Thread the per-colour auto data into `composeScene`'s `Input` (activeLane + its slot/param/extent/range).
  - When composing a part cell `(cid, col, row)`: if `cid`'s active lane's extent includes `(col,row)`, compute
    the ramped value and apply it to the cell's resolved chain slot via **`applyProcessorValues`** (MacroAuthoring).
  - Byte-identical when no colour has an active lane (the map is empty) → the whole suite stays green.
- **Render unchanged** (invariant 1): the value bakes into the published box's resolved `procs` at build time,
  exactly like the macro fold / M2. No render-thread change, no new hot-path state.
- **+tests** (BuildSceneLogic, off-device): a cell in an active lane's extent gets the ramped param value; a
  cell outside the extent / a NONE colour stays at base; the ramp endpoints are correct across the extent.

### P3 — Plays immediately (live)
- Selecting a lane, toggling a cell, or changing the machine/param → **republish** (`buildPublishScene`) so the
  composed scene carries the new auto values and plays on the next boundary. Wire the AUTO taps + `buildAutoToggle`
  to trigger a republish (they already mutate @State; add the publish call).

### P4 — Range + shape (only if wanted beyond the default)
- Default range = the param's **full low→high** swept once across the extent. If a configurable **BEFORE/AFTER**
  or a **RATE** (repeat/curve within the extent) is wanted, add them to `AutoLane` + the ramp math + the band.
  Kept OUT of the MVP for the "fewest steps" goal.

## Open decisions (need Paul)
1. **Range default** — is a **full low→high sweep** across the extent the right default, or should the ramp span a
   musical sub-range (e.g. gate 0.3→1.0, not 0.05→1.0)? Per-param sensible ranges are easy to curate.
2. **One active lane per colour** (the selected tab), others dormant until selected — correct? (vs. all lanes with
   extents playing at once.)
3. **Ramp direction/shape** — low→high in column order, single sweep. Reverse / centre / RATE-repeat later?
4. **Extent = the colour's own cells only** (today's restriction) — keep, or allow punching any cell?

## Sequence
P1 (model + persist) → P2 (composeScene bake + tests) → P3 (live republish) → device ear-check → P4 if wanted.
P2 is the load-bearing, off-device-testable increment; do it with tests. The whole thing is byte-identical until a
colour has an active lane, so the suite + fuzz stay green throughout.
