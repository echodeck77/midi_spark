# DRUM MODE ferry — findings (mapped before any edit, 2026-11-23)

Built on the KIT source ferry as shipped on `feature/kit-source`. This ferry amends it; where they disagree this wins.

## (a) KIT source as built
- Fields `kitOn/kitNotes/kitNames/kitVel` — `Models.swift:853-860`; custom decoder `Models.swift:1469-1472`.
- Defaults `euclideousKitDefaultNotes = [36,37,38,39,42,44,46,49]`, `euclideousKitDefaultVel` all 100 — `Derivations.swift:13189-13191`; GM names `euclideousGMDrumName` `:13194`.
- Snapshot carrier `EuclideousKitSnap{on,notes,vel}` + `kitOn`/`note(lane:rank:)`/`vel(lane:rank:)` — `Snapshot.swift:334-341`; `SnapParams.kitSnap` `:444`; built from `euclidLinesForEditing()` — `SnapshotBuilder.swift:519-530`.
- KIT chip `EuclideousPage.swift:7931` (PICK's slot, width `plainW`); 42 % dims `:7789-7791,7926-7930`; POOL cells `kitPoolChips`/`kitPoolCell` `:7840-7873`; editor `KitEditorViews.swift` + layout `euclideousKitEditorLayout` `Derivations.swift:13270`.
- Pitch bypass (kit ferry 2.2): `Router.swift:3750-3754` (riff/notes/listen octave→0), `:4080-4084` (ALT octave guards).
- Rank velocity scale (kit ferry 3.1): `Router.swift:2089-2093` in `emitOneOutput`, reading `euclideousKit.vel(lane:rank:)`; 0 ⇒ `return -1` (no note, kit ferry 3.2).

## (b) The card's rows
- `poolTabContent` — `EuclideousPage.swift:7781`; the `VStack(spacing: layout.gap)` stacks POOL · SOURCES · MIDI · APPLY-ALL · CANON — `:7786-7791`. `inputsMidiRow` `:7795`ish, `listenCanonRow` `:7750`.
- Heights from `euclideousInputsTabLayout(contentAreaH:)` — `Derivations.swift:13356`; ideals `nowH 44, sourcesH 30, midiH 30, canonH 44, gap 14`, shrinking to `rowFloor 30` / `minGap 8` when short (`EuclideousPoolTabMetrics` `:13344`).
- SOURCES widths — `poolSourcesRow` `EuclideousPage.swift:7920`: `label · MIDI(plainW) · CHORDS(plainW+chordExtra) · KIT(plainW) · KEY(plainW)`, `gap 5`, `chordExtra = 23·2+2+2`.

## (c) Same-pitch rule (kit ferry 3.4)
- `Router.swift:4443-4449`: on a KIT lane a duplicate pitch+bus keeps the rank with the HIGHER `euclideousKit.vel`.

## (d) Default kit — rank 8
- `euclideousKitDefaultNotes` ends `… 46, 49` ⇒ rank 8 = **49 CRASH**. **No difference** from the kit ferry.

## Design decision (why the engine barely changes)
DRUM = a kit whose 8 notes are all `drumNote` and whose 8 velocities are the ramp. So the Router is UNCHANGED — `SnapshotBuilder` fills `kitSnap.notes/vel` per lane from KIT (`kitNotes/kitVel`) or DRUM (`drumNote×8` / `euclideousDrumRampVel`). The pitch bypass, the 3.1 scale, the 3.4 dedup, `fillKitPool` and the audition all then work for DRUM unchanged. `kitOn` stays the on/off; `fixedMode` picks which fills the snapshot.

## §2.3 → PLAY AS VOICES on a DRUM lane
Every DRUM rank is the same `drumNote`, so VOICES=ALL choosing several ranks collapses (via 3.4) to ONE note at the loudest chosen rank's ramp velocity — a single drum hit at the accent of the highest chosen rank, never a chord. Intended for drums.

## No migration / deletions
`fixedMode` nil ⇒ KIT, so nothing already saved changes. Nothing deleted.
