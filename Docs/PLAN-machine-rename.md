# PLAN — rename the concept: Colour → Machine

**Status:** DONE 2026-09-09 on branch `feature/machine-rename` — macOS 1085 tests
green, iOS build green. AWAITING MERGE (held until the other instance's
`feature/grid-rebuild` lands on `main`, to avoid a whole-repo conflict). Nothing
shipped → on-disk keys moved with the field names; pre-rename sessions factory-reset
by design (no migration).

## Why

The `Colour` object is no longer "a colour the user picks for a sound." It is a
**MIDI treatment/machine**: a processor `type` + its `ColourParams` (or a
`templateChain`) + identity + an inert `OnConfig`. It carries **zero routing**
(buses/receiver/input all live on `Cell`; out-channel was deleted) and **zero
visual-colour data** (the hue is derived from the id in the UI layer). The code
already drifts to the right word — `buildMachine*`, RackMatrix "the treatments" —
so today there are TWO words for one thing, which is worse than either. This
rename resolves that and makes the name match the concept.

## Core insight — split the two meanings

"Colour" does two jobs. The rename separates them:

- **The object/treatment → `Machine`.**
- **The display appearance → `hue`** (a *derived* property of a machine's id).

The id bridges them: a machine's identity is `machineID`; its display hue is
derived via `machineHue(machineID)`. So the word "colour" the-appearance mostly
retires in favour of "hue"; "colour" the-object becomes "machine."

## Naming map (before → after)

### The object family
| before | after |
|---|---|
| `struct Colour` | `struct Machine` |
| `SnapColour` | `SnapMachine` |
| `ColourParams` | `MachineParams` |
| `Colour.colourID`, `Cell.colourID` | `machineID` (on-disk key moves too) |
| `PluginState.colours` | `machines` (on-disk key `"machines"`) |
| `colourIDs` (16 canonical) | `machineIDs` |
| `colourIndexByID` | `machineIndexByID` |
| `docColours` | `docMachines` |
| `buildColourReg` | `buildMachineReg` |
| `withChainColour` | `withChainMachine` |
| `colourHasStoredChain` | `machineHasStoredChain` |
| `buildColourTranspose` | `buildMachineTranspose` |
| `setBuildEphemeralColours` | `setBuildEphemeralMachines` |
| `ExcludeRef .allColour` (Models.swift:1917) | `.allMachine` |
| `ColourTypeSwitchTests.swift` (file) | `MachineTypeSwitchTests.swift` (optional; needs xcodegen) |

### The display/hue family (these currently say "colour" but mean HUE)
| before | after |
|---|---|
| `colourColor(_ id:) -> Color?` (GridUI:129) | `machineHue(_ id:) -> Color?` |
| `colourHexes` (GridUI:77) | `machineHexes` |
| `colourHueOverride` (GridUI:128) | `machineHueOverride` |
| `SnapColour.hue` | `SnapMachine.hue` (field name `hue` stays; type renamed) |

## What does NOT change

- **Palette id string VALUES** — `"gold" … "slate"`, ephemeral `"b<n>"`, transient
  `"gsAud"`. These are DATA tokens (a `Cell.machineID` is `"gold"`; `partAuto` is
  keyed by them). They anchor the default hue palette (id `"gold"` → gold hue).
  **DECIDED (Paul 2026-09-09): KEEP the string values as-is.**
- **AU parameter addresses** — numeric, indexed by machine *index*, never named
  (invariant 5). No change: `100+i` transpose, `200+i` morph, etc. stay.
- **Host-facing identity** — `CFBundleDisplayName` "8x8 State", AudioComponents
  name, aumi codes (type `aumi`/subtype `MSpk`/manufacturer `MSPK`). None contain
  "colour". Verified clean — nothing here to touch.
- **Position/role palettes** — `playHexes`, `partRowHexes`, `emitterHexes`,
  `receiverHues`/`receiverGreys`. Not machine-related; leave as-is.
- **`Cell`** — stays `Cell` (the patch point). It references a machine by
  `machineID`.

## Scope

~1,914 "colour" mentions in `AUExtension/*.swift`, ~2,390 in `Tests/*.swift`.
Almost entirely mechanical (word-boundary symbol renames). Heaviest source files:
BuildPage (617), Router (298), Models (187), MidiSparkAudioUnit (175),
SnapshotBuilder (70), GridUI (62). Heaviest tests: RouterTests (1,555),
MigrationTests (318), SnapshotBuilderTests (190).

## Execution order

1. **Branch** off `main` (`git checkout -b feature/machine-rename`). Confirm the
   other instance is idle / use a git worktree — this sweep touches nearly every
   file and is a merge-conflict bomb otherwise (the two-instance hazard).
2. **Models.swift first** — rename the `Colour`/`SnapColour`/`ColourParams` types,
   `machineID`, `PluginState.machines`, `machineIDs`, the `.allMachine` enum case,
   decode-tolerant inits. Synthesized Codable moves the on-disk keys automatically.
3. **Engine + builder** — Snapshot, SnapshotBuilder, Router, Kernel, Emission,
   Derivations, Dice.
4. **AU + UI** — MidiSparkAudioUnit, BuildPage, GridUI (incl. the hue-family
   renames), BuildSceneLogic, BuildModel, DragDropPage, EditPage, ArrangementBar,
   SceneFactory, TestSessions, BuildSelfTest, ChaosDriver, PresetStore.
5. **Tests** — sweep `Tests/*.swift`; rename `ColourTypeSwitchTests.swift` if
   desired (then `xcodegen generate`).
6. **Docs + comments** — CLAUDE.md §1 vocabulary (term-of-record becomes
   "Machine = the treatment; its display hue is derived from its id"), source
   comments, spec files, UI strings the user reads.
7. **machine vs treatment — DECIDED (Paul 2026-09-09): "machine" everywhere**,
   user-facing AND internal (incl. the rack code's "the treatments" → "machines").

## Verification gates

- macOS unit suite green (the pinned-derivedData command in CLAUDE.md).
- iOS build green (the `DEVELOPER_DIR=…` xcodebuild command).
- Codable round-trip tests reflect the NEW shape (they test the current model
  round-trips — still valuable; no migration test needed since sessions may die).
- No device behaviour change expected — this is a pure rename. Device pass only to
  confirm UI strings read right.

## Git

Own branch → commit only my own files (two-instance rule) → merge to `main` →
push. One atomic feature.
