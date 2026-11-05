# RIFF tab regrouped — §0 findings (before any change)

Ferry "RIFF · v2" (ratified Paul 2026-11-05). Layout + drawing only; no model field, engine path,
range, default or undo change. All file:line against `Fourfold/` at `b5aedad` (origin/main).

The RIFF tab is the lane-CARD content when the page tab strip is on RIFF (TAB STRIP ferry 2026-10-29).

## §0.1(a) Every control the RIFF tab draws, top→bottom
Entry `riffTabContent` — **EuclideousPage.swift:5319** (4211 is only the call site). Pure layout
`euclideousRiffTabLayout` — **Derivations.swift:6765** (struct 6746, floors `EuclideousRiffTabFloors`
6743). Body frame: `EuclideousLaneCardMetrics` (Derivations.swift:4883) `bodyTop 62`, `chrome 72`.

Landscape reference lane card 380.67×301 → body **x10–370.67, y62–291, 360.67×229**.
Portrait 387×301.67 → body **x10–377, y62–291.67, 367×229.67**. (Both match the ferry §0.1(c) exactly.)

The ZStack rows (`euclideousRiffTabLayout`, 6pt? no — current gaps are `sp4`=4):
1. `riffTopRow` — rowAHeight **103**: `riffCard` 90×103 (x0) + WALK strip 266.67×38 (x94, y0) + direction row 266.67×61 (x94, y42).
2. `riffAdvanceRow` — 38: "ADVANCE"/"EVERY" label col 60 + EVERY stepper 76 + HIT 106.33 + STEP 106.33.
3. `melodyValuesRow` (4870) — 38: LEN · SHIFT · STRIDE · TRANS, each 87.17.
4. `riffOutputOctaveRow` (4930) — 38: A–D discs (outW 196.17) + OCT slider (160.5).

- **riff card** `riffCard` (5041): 90×`rowAHeight`(103); tap toggles `riffOn`; fill `lane100` on / #2A2D34 off; border #0D0F14 on / #5C626C off; **radius 10**; label "RIFF" 10pt heavy mono kerning 2; never dims.
- **`riffMiniGrid`** (4981) at size 55.3: `cellW=(size-(n-1))/n`, `cellH=(size-7)/8`, VStack/HStack spacing **1** → **~6.04pt cells, 1pt gaps**; radius `poly ? 0.75 : 1.5`; **32% dim** per out-of-window / never-played column (opacity 0.32). (The riffCard doc comment "5.6pt / 1.5 apart" is **stale** vs the code.)
- **WALK strip** `riffWalkStrip` (5071): display-only, 266.67×38; header "WALK" 8pt + `euclideousWalkReadoutText`; 16 cells `riffWalkStripCell` (5127), current-step ring lane20 fill + lane100 1pt border radius 3; container #131519 radius 8 border #262930. Folds riff-off into its own per-cell 0.42 (never wrapped in `.opacity`).
- **direction row** `riffDirectionRow` (**5230**, NOT `directionRow`@4226 which is RHYTHM's): `let dirs: [(RiffDir,String)] = [(.reverse,"<"),(.pingpong,"><"),(.forward,">")]` + an **INV** `melodyButton`. All `melodyButton` fontSize **13**, radius **7**. Tapping the lit direction sets `riffOn=false`; another sets `riffOn=true; riffDir=d`. Uses `HStack(spacing:3)` + `maxWidth:.infinity` (NOT `layout.directionButtonWidth`, which only drives the floor check).
- **INV** (5253): label literally **"INV"**, toggles `riffInvert` (rank mirror 9−r), `melodyButton` fontSize 13 radius 7.
- **ADVANCE row** `riffAdvanceRow` (5264): `riffRowLabel("ADVANCE","EVERY")` col 60; EVERY `melodyStepper` (`riffAdvanceEvery`, **range 1…8**, no wrap, showLabel:false, w76); **two separate** `melodyButton`s HIT/STEP (fontSize 11) writing `riffAdvanceStep` (false=HIT, true=STEP); `plural = every>=2` → "HIT"/"STEP" at 1, "HITS"/"STEPS" at 2–8.
- **`melodyValuesRow`** (4870): LEN `euclideousSetRiffLength`(`riffLength` 1…cols) · SHIFT `euclideousSetRiffShift`(`riffRotate` 0…cols−1, wraps) · STRIDE(`riffStride` 1…7) · TRANS(`melodyTranspose` −7…7), each `melodyStepper` 87.17.
- **A–D + OCT** `riffOutputOctaveRow` (4930): `partOutputToggles`→four `partOutputDisc` (5531) `Circle` **28×28**, HStack spacing 4 + trailing Spacer (`riffOutMask`); OCT `partOctaveControl` (5541) = a **sliding thumb over 5 positions −2…+2** (track 6pt, thumb 40 wide "OCT n"), **NOT five boxes**; writes `riffOctave`.
- **Not present:** no ON REST row (removed 2026-10-29; `onRestButtonWidth` still computed, unused), no velocity control, no extra label column.

## §0.1(b) Direction cases
Exactly **3** direction buttons + INV. `<`→`.reverse`, `><`→**`.pingpong` (PING)**, `>`→`.forward`.
**`><` is PING, not PEND** — PENDULUM was removed from the row (still a live `RiffDir` case). Per the
ferry "the icon mapping follows the glyph, not the name": the middle (`><`) button gets the ping-pong
icon and keeps setting `.pingpong` — no behaviour change.

## §0.1(c) Tab body frame — matches the ferry exactly
Landscape 360.67×229 at x10 y62; portrait 367×229.67. Pinned by `PageLayoutTests.swift:203/212`.

## §0.1(d) Components
- `melodyButton` (4789): selected = `lane20(accent)` fill + `lane100(accent)` 1pt border + #F2F4F7 text; unselected = #2A2D34 fill, no border, #AAB0BA. Default height 40, fontSize 10, radius 6 (directions/INV use 13/7; HIT/STEP use 11/7).
- `melodyStepper` (4810): key-line 10pt heavy mono #8A909A, value 14pt heavy mono #F2F4F7, arrowZone 18, radius 6, height 34, `showLabel` drops the key line.
- RHYTHM **FLIP HITS** `flipHitsButton` (4246): two lines `["FLIP","HITS"]` (`EuclideousFlipHits`, Derivations.swift:4896) **8pt heavy mono, tracking 0.64, 1pt apart, centred, radius 7**, same lane20/lane100 selected look, VoiceOver "Flip hits".

## §0.1(e) A–D circles + OCT
A–D: four 28×28 `Circle` discs. OCT: a single sliding thumb (5 discrete positions −2…+2), not five boxes.

## §6 VoiceOver order today
riff card ("Riff, on/off[, now on step n]") → WALK ("Walk" + value) → `<`/`><`/`>` (`riffDirHelpPhrase`
+ "selected/not selected") → INV ("Invert the riff", .isSelected) → ADVANCE EVERY ("Advance every", value
"n hits/steps") → HIT ("Advance by hits") → STEP ("Advance by steps") → LEN/SHIFT/STRIDE/TRANS → A–D
("Riff output A…D") → OCT ("Riff octave"). The "ADVANCE"/"EVERY" `riffRowLabel` has no a11y element.

## Tests touching the RIFF tab
`PageLayoutTests.swift:201` (`testLaneCardZonesAtBothReferences`), `:224` (walk-strip floor), `:349`
(mini-card floors); `EuclideousFlipHits` in `RhythmPolishTests.swift:483`. No test exercises the riff
card/mini-grid/walk/stepper/button *visuals* — only the pure layout + `EuclideousFlipHits`.

## Discrepancies (ferry vs code) — §11.5
1. `riffTabContent` is **5319** not 4211; the RIFF direction row is **`riffDirectionRow` (5230)**, not `directionRow`.
2. **`><` = PING (`.pingpong`), not PEND**; exactly 3 directions + INV (icon follows glyph → no behaviour change).
3. **OCT is a slider (−2…+2), not five boxes** — kept "as today" per §1.7.
4. **riffMiniGrid** today is ~6.04pt cells / 1pt gaps / radius 1.5 → §2.2 asks 5.4 square / 1.4 apart / radius 1 (53 square). Build §2.2's values.
5. **FLIP NOTES type:** §5.2 gives 11pt / 0.1em / 13pt line / leading-aligned AND says "matches FLIP HITS" — but FLIP HITS is 8pt / 0.08em / centred. They can't both hold. **Decision: follow §5.2's explicit numbers (11pt, leading, beside the icon); report the mismatch.** Reversible.
6. **"layout 5.3"** (the full iPad/orientation card-size set) is not a doc in this tree; card+body sizes are reported for every reference `PageLayoutTests` enumerates (landscape 380.67×301, portrait 387×301.67, iPad-mini, Stage-Manager min).

## §0.2 Hide-don't-delete plan
The retired pieces keep their code: the `riffRowLabel("ADVANCE","EVERY")` column, the two-button HIT/STEP
(replaced by one segmented control), the `< >< >` text glyphs (replaced by drawn icons), and the unused
`onRestButtonWidth`. No stored field is touched — every RIFF value stays decodable.
