# INPUTS MODE ferry — findings (mapped before any edit, 2026-11-24)

Built on the KIT source + DRUM mode ferries, both landed on `feature/kit-source` (NOT main). This ferry replaces `kitOn`/`fixedMode` with `laneMode`.

## (a) How far kit + drum landed
Both complete on `feature/kit-source`. `EuclidLine.kitOn` `Models.swift:853`, `fixedMode` `:863`, `drumNote/Low/High/Ramp` `:864-867`. The KIT | DRUM switch `kitDrumSwitch` `EuclideousPage.swift:7961`; the SOURCES chips `MIDI IN`/`KEY` at `:7952/:7955` — **the DRUM ferry narrowed them to ≈36 pt (`sideW = plainW − 24`) to widen the switch, which is why Paul's screenshot shows them truncated ("M…"/"K…")**. Removing the switch from SOURCES (this ferry) returns them to full width. Kit editor `KitEditorViews.swift`; drum picker = the same in its `isDrumPicker` variant.

## (b) INPUTS row stack + heights
`poolTabContent` `EuclideousPage.swift:7783`; rows POOL · SOURCES · (MIDI|DRUM) · APPLY-ALL · (CANON|VEL). Layout `euclideousInputsTabLayout` `Derivations.swift:13385`, metrics `:13371` (`gap 14`, `minGap 8`, `rowIdeal 44`, `rowFloor 30`, `sourcesH 30`, `midiH 30`). Today it lays out 4 rows + the 30 pt APPLY button; MELODIC's seven-rows-under-strip concern is §3.2 (report if the gap must shrink).

## (c) Pitch-only per-lane controls
- MIX: **OCT** only — `EuclideousOctaveBoxes` (`MixPanelV2Views.swift:219/577`). **TRANS was REMOVED 2026-11-07** and the **PITCH pad is RETIRED** (card backs hidden) — §5.2 names them but they are not in the live UI, so there is nothing to dim there. (Contradiction, reported.)
- ALT: the **OCT override pill** per band — `EuclideousAltPill(label: "OCT", …)` `EuclideousPage.swift:4026`.
- Out-transpose is retired (SnapshotBuilder hands nil). No other live pitch-only control.

## (d) Gate / note-length + RATCH
- Riff gate `gate` (= `gateResolved`, default 0.9) and notes `notesGate` (`Models.swift:1223/1302`), used at the riff/notes `addPitch` (`:4749/:4857`).
- **RATCH strike SPACING is step-based**, not note-length: `emitterRatchetStrikes` `Router.swift:5392` uses `spacing = emitterStrikeSpanBeats(length:stepBeats:) / n` (step `subAtHit`), and the per-strike GATE is `spacing * pitchGate[j]`. So §2.4's conditional ("if RATCH derives spacing from note length") is FALSE — spacing is already independent of gate; only each ratchet note's LENGTH follows the gate. Halving the gate leaves ratchet onsets unchanged.

## (e) STACK VOICES / SPREAD / BASS
PLAY AS ROWS on the NOTES/STACK tab: VOICES/SPREAD rows via `euclideousRowsActiveChip` (`EuclideousPage.swift:6687-6695`), BASS row `:6639-6643` (`notesBassOn`). Reads `notesVoicesChainResolved` / `notesSpreadChainResolved` / `notesBassOnResolved`.

## (f) HARMONY grid lane groups + header status
- HARMONY draws a grid's lane group from `lines[$0].poolChordsOn && euclideousLaneChordGrid(poolSrcMaskResolved) == set` (`HarmonyPage.swift:246`), rendered by `laneSquare` `:293`. §5.5: exclude a DRUM/KIT lane.
- The old `euclideousSourceStatusAcrossLanes` is RETIRED (`Derivations.swift:13458`); the header now shows per-grid chord tokens + a MIDI lamp (lit while any lane has MIDI IN on). §5.5: a DRUM/KIT lane must not count toward the lamp.

## (g) The 42 % dim + inert
`.opacity(0.42)` + `.allowsHitTesting(false)` (the pattern the kit ferry's dimmed SOURCES chips already use). VoiceOver adds the value "inactive".

## Design (why the engine barely changes)
`laneMode` (MELODIC|DRUM|KIT) resolves to the engine's existing `kitSnap`: KIT/DRUM ⇒ `kit.on[lane] = true` and the fill chosen by the mode; MELODIC ⇒ off. The Router's `kitLane = euclideousKit.kitOn(lane)` is unchanged. `SnapshotBuilder` keys the fill off `laneMode` instead of `kitOnResolved`/`fixedModeResolved`. The only new engine behaviour is §2.4's half-step gate on DRUM/KIT lanes.

## Migration / deletions
`laneMode` nil → §1.2 maps from `kitOn`/`fixedMode` (kept decodable, no longer written). No session migration. Nothing deleted (the KIT|DRUM switch, drumRow/VEL stay but are re-homed under the MODE row).
