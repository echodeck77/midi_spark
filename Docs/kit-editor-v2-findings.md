# KIT EDITOR V2 ferry — findings (mapped before any edit, 2026-11-24)

Amends KIT source + DRUM mode + INPUTS MODE (all landed on main). This text wins where they disagree.

## (a) Fixed gate + gate dims (INPUTS MODE 2.4 / 5.3) — BUILT, to be REMOVED by §1
- Engine fixed half-step: `Router.swift:6383` `let euclideousFixedGate = isEuclideousRow && L.euclideousFixedLane`, applied at the `runEuclidLine` call — `gate:` (`:6385`), `missGate:` and `notesGate:`. ALT gate guards `!kitLane` at `Router.swift:4082 / 4086 / 6011`.
- UI gate dims: MIX GATE tile `MixPanelV2Views.swift:201-203` (`fixedLane` on `dimmed:` + `.opacity/.allowsHitTesting`); ALT GATE pill + slider `EuclideousPage.swift` (`dimFixed(...)` on the GATE pill/slider). MIX **OCT** dim (`:205`) and ALT **OCT** pill dim are §5.2 (PITCH) and STAY. STACK VOICES/SPREAD/BASS dims are §5.4 and STAY.
- Other per-lane gate: `missGate` (pattern-miss) is the only other; it was also forced — restore it.

## (b) Kit editor + drum picker as built
`KitEditorViews.swift` `EuclideousKitEditorView` + `euclideousKitEditorLayout(box:lowC:showsRanksAndName:)` (`Derivations.swift:13295`). Header `:57` (title · RESET GM · DRUM · close); ranks `:96`; NAME·VEL `:119`; octave ‹/› + range readout `:150`; keyboard `:180`. The picker passes `showsRanksAndName:false` (no ranks/NAME, taller keyboard).

## (c) Rank names — the mismatch cause
`euclideousGMDrumName` (`Derivations.swift:13194`) is CORRECT (36 KICK … 49 CRASH). `euclideousKitNamesResolved(nil, notes)` (`:~13225`) maps rank i → `GMname(notes[i])` — correct on a fresh kit. **The mismatch comes from the NAME field's auto-commit:** `KitEditorViews.swift:123` has `.onChange(of: nameDraft) { onSetName($0) }`, and the page reseeds `kitEditorNameDraft` programmatically on open / rank-select (`EuclideousPage.swift` openKitEditor + onSelectRank). Selecting a rank changes `nameDraft`, which fires `onChange` → `onSetName` on the STALE view's captured `rank` → the newly-selected rank's name is written onto the previously-selected rank. Clicking through ranks shifts names relative to notes (exactly 0.1(c)'s pattern). **Fix (§2.1):** commit the name only on Return (`onCommit`), on rank-switch (the OLD rank), and on close — never on every change.

## (d) Range label "C2–C3" for 36–59
`KitEditorViews.swift:169` prints `"C\(lowC/12-1)–C\(hi/12-1)"` — it labels the HIGH end "C<octave-of-hi>" (59 → C3) instead of the last note's real name. §2.4 fix: use `euclideousNoteViewName(hi)` ⇒ "B3".

## (e) Title outside the overlay
`KitEditorViews.swift:70` the title is `"KIT \(lane + 1)"` ("KIT 3"), drawn in a ZStack frame positioned at the header rect. Paul's "T 3" at the screen's left edge is the title clipped/escaping. §2.2/§2.3 rebuild the header with "KIT" (no lane number) inside the overlay at the leading edge.

## (f) MODE row
`EuclideousPage.swift modeRow` — three equal segments in a #17191E well (MELODIC·DRUM·KIT), lit #EDEFF3 + lane dot, unlit #8A909A no-fill, tappable. Matches INPUTS MODE 3.1 / §2.9. (Device-owed whether the unlit segments read as buttons.)

## (g) "▲ KEYS"
**NOT in the Fourfold codebase** (grepped UI/Shared/App). It is the HOST's on-screen-keyboard toggle — AUM shows a "KEYS ▲" button at the bottom of a plugin window. §2.10: not ours, nothing to remove.

## Saved sessions
A kit edited in the shipped build by clicking through ranks holds SCRAMBLED `kitNames`. §2.1: report, do not migrate. A fresh kit (names nil) is correct.
