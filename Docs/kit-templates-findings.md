# KIT TEMPLATES ferry — findings (2026-11-25; ratified with §0 proposed answers)

Built on KIT source + DRUM mode + INPUTS MODE + KIT EDITOR V2 (all landed).

## (a) RESET GM as built
- Kit editor HEADER: `KitEditorViews.swift:71` `headerBtn(L.resetBtn, "RESET GM", "Reset to GM kit", action: onResetGM)`; frame `L.resetBtn` (86 wide, header height 40). Action `EuclideousPage.swift:8033` `onResetGM` → `edit(lane){ kitNotes = euclideousKitDefaultNotes; kitNames = euclideousKitNamesResolved(nil, …); kitVel = euclideousKitDefaultVel }` + reseed range/prev/draft. ONE undo step. → §3.1 this button becomes the TEMPLATE button.
- KIT ROW (INPUTS card) RESET GM: `EuclideousPage.swift:8115` → `resetKitGM(lane)` `:7994`. NOT named by this ferry — stays (resets to GM). Reported.

## (b) Rank names (after KIT EDITOR V2 §2.1)
- A key tap (`onAssignNote`, `EuclideousPage.swift:8015`) sets the PITCH only (never the name). The NAME commits on Return / rank-switch / close (`commitOpenKitName` `:7984`). Decode: `Models.swift` custom decoder reads `kitNames`. Default names derive from notes via `euclideousKitNamesResolved(nil, notes)`.

## (c) GM short-name table + readers
- `euclideousGMDrumName` `Derivations.swift:13340` (35–81, else note-view name). Readers: `euclideousKitNamesResolved` `:13375`, `euclideousKitNameClean` `:13358`; `drumRow`/`drumPoolChips` (`EuclideousPage.swift:8152/7935`); the kit editor keys `KitEditorViews.swift:230` (`gmName`); the DRUM picker reuses the editor view. The STACK grid / POOL show the NOTE NUMBER (not the name) for a fixed lane.

## (d) APPLY TO ALL
- `euclideousApplyInputsToAll` `Derivations.swift:13504`: copies `poolSrcMask`, `midiMode`, the four kit fields (`kitOn`/`kitNotes`/`kitNames`/`kitVel`), the drum fields, `laneMode`. → §1.3 add `kitTemplate`.

## (e) Dev-build flags
- `#if DEBUG` in `EuclideousSettingsSheet.swift` (FX COUNTS, CHORD CANON ENTRY, CLASHES) + `clashPolicyResolved` forcing release behaviour. Pattern: the control is `#if DEBUG`, the data carried unconditionally. → §3.5/§0.4 COMMUNITY rows show only `#if DEBUG`.

## Contradiction to report
- §5 lists EIGHT HARDWARE templates (Circuit Rhythm, Drumlogue, MPC, RD-6, RD-8, RD-9, TR-8S, Volca Beats) but the release line says "HARDWARE shows all seven." None are COMMUNITY, so all 8 show in release; the "seven" is a miscount. COMMUNITY (dev-only) = Gadget, Koala, DigiStix (APPS). Ruismaker is "SECONDARY notes / COMMUNITY names" but the release list includes it ⇒ treated as shows-in-release (confidence secondary).
