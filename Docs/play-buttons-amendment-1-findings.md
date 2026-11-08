# PLAY RIFF / PLAY STACK — amendment 1 — findings (§0 map, before any change)

Ratified Paul 2026-11-08. Fourfold only, layout and drawing only. Base: the PLAY RIFF / PLAY STACK ferry (2026-11-07), landed (`9246144` … `7ed2f01`; map in `Docs/play-riff-stack-findings.md`). Audited against the raw amendment text.
Where the amendment disagrees with the code the code wins and the difference is listed under "Differences" at the end.

## §0.1(a) the card's content insets and the top row's frames

- **Insets:** `laneCard` pads its VStack by `cardInset` = `EuclideousLaneCardMetrics.inset` = **10 on all four sides** (`EuclideousPage.swift:2476`, the constant at `Derivations.swift:4636`). The top inset is already equal to the side inset; the bottom inset is the same 10 (`chromeH = bodyTop + inset`). The content box is the card less 10 each way: **360.67 × 281** (landscape card 380.67 × 301), **367 × 281.67** (portrait card 387 × 301.67).
- **Top row:** one `EuclidLaneBox` (`EuclidLaneUI.swift:166`), an HStack with `spacing: 6` (compact), width = content width, height `cometRowH` = **44** (`Derivations.swift:4636`; `EuclideousPage.swift:1713`). Order: PLAY RIFF (`leadTile`, 44 × 44) · comet strip · [lock badge 34 × 34, height 44] · PLAY STACK (`soloButton`, 44 × 44; `stepCountBadgeTotalWidth` = 44, `EuclideousPage.swift:2692`). PLAY RIFF's leading edge is the content box's leading edge and PLAY STACK's trailing edge its trailing edge today.
- **Strip width** (`EuclidLaneUI.swift:183-185`): `width − 50 − (6 + 44 + lockReserve)`, `lockReserve = 6 + 34 − 2·(6 − 4)` = 36 with a badge → landscape **260.67 / 224.67**, portrait **267 / 231** (pinned by `PartPlayButtonTests`, `LaneLockTests`; `EuclideousLockBadge.cometStripWidth`, `EuclideousLock.swift:491`).
- **Frames in card coordinates** (row y 10, h 44): landscape — PLAY RIFF x 10, strip x 60 w 260.67, badge x 288.67 y 15, PLAY STACK x 326.67; portrait — strip w 267, badge x 295, PLAY STACK x 333. The row is a function of the card's size only, so these hold in every page layout.
- **Gap below the row:** `bodyGap` = **8** (`Derivations.swift:4638`) → the tab body starts at card y **62** (`bodyTop`), `chromeH` 72, `contentAreaH = card height − 72` = **229 / 229.67**.
- **The size of "portrait-in-AUM":** the card is 387 × 301.67 at the portrait reference whatever the host window is; a window narrower than 814 is rendered at the reference and scaled down, never up (`euclideousScaleToFit`, `Derivations.swift:4962`). The button is therefore **44 pt tall in every layout**. The screenshot isn't shared, so its size is unknown; a 44 pt button on a page scaled to 0.887 (a ≈ 722 pt wide portrait window) measures 78 px in a 2× screenshot — a likely source of the "h 78" figure.

## §0.1(b) the strip's bands

- Fixed, in `EuclideousStripMetrics` (`Derivations.swift:8665-8666`) and `euclideousStripLayout` (`:8720`): the **cells** (the track columns, with the riff chips drawn INSIDE them — a 9 pt chip at (8 − rank) × 2 from the column's top) y 0 h **27**; a **3** pt gap; the **key row** (the note keys, drawn only for a hit column while NOTES is enabled) y 30 h **14**. Total **44** = the card's `cometRowH` = the bar's frame (`EuclidLaneUI.swift:204`).
- Nothing in it depends on a setting, a lane, a tab or the playback: every lane's strip, on every tab, has the same three rectangles whether or not anything is drawn in them. There is **no separate "hit-count chip band above the cells"** (the riff chips sit inside the cells) and **no progress line** in the strip (the playhead is a band over the cells, y 0–27). The only thing that ever made one lane's strip look taller was the SHADOW partner-colour band (§0.1(d)).
- What is not constant is what is DRAWN: an empty key row (NOTES off, no hit, a SHADOWing lane) leaves the bottom 17 pt of the strip blank, so the visible cells are 27 pt tall against 44 pt buttons.

## §0.1(c) the PLAY button

- `EuclideousPartPlayButton` (`Fourfold/UI/PartPlayButton.swift:22`): tile 44 × 44 default, `#202226` fill + 1 pt `#2B2D33` border, radius 9; one VStack (spacing **3**): line 1 = lamp then "PLAY" (HStack spacing **4**), line 2 = the part name. Type: PLAY **6 pt** heavy mono, tracking 0.16 em; name **9 pt** heavy mono, tracking 0.08 em, `lineLimit(1)`, `fixedSize` (it never truncates, it overflows), frame height 10. Lamp: **5.5 × 6** (`EuclideousPartPlayLamp.size`), stroke 1 pt, glow blur 4 pt.
- Looks (`euclideousPartPlayLook`, `Derivations.swift:5079`): on — "PLAY" #AAB0BA, name #F2F4F7, lamp lane100 filled + lane stroke; **off — "PLAY" #4E525A, name #5A5E66, lamp outline #4A4E57** on a #202226 tile (all three greys sit close to the tile's own fill, which is why it reads as disabled).
- **Nothing fades the tile when it is off**: no opacity or dim on the button, and the lead tile is exempt from the solo dim (`EuclidLaneUI.swift:167-168`, PLAY ferry §4.2). The only dim near it is `stripDim` (42 %) on the comet strip.

## §0.1(d) the solid bar

- **What:** the SHADOW partner-colour band — `EuclidLaneUI.swift:206`, `.overlay(alignment: .bottom) { if let t = listenShadowTint { Rectangle().fill(t).frame(height: 14) … } }` on the comet bar: the bar's full width, **14 pt tall** (= the key row's height), flush with the strip's bottom, opaque, no radius, dimmed with the strip. Tint = `laneAccents[line.listenSourceResolved(ownLane: idx)]` when `phaseLines[idx].listenPitchResolved == .shadow` (`EuclideousPage.swift:2363`, passed at `:2422`).
- **Which ferry / state:** the LISTEN tab's SHADOW "partner-colour band" (LANE STRIP ferry, 2026-10-21, "SHADOW keeps its footer-height partner-colour band"); today the trigger is the ANSWER PITCH row on with mode SHADOW (the default mode). It is an ANSWER state (a lane answering another lane's pitch), so amendment §A5.1 applies. A SHADOWing lane also draws no chips and no key row (`LaneStripPainter.swift:209`), so the band stands in for the key row; it draws nothing else.

## §0.1(e) the tab body's column grid

- The body's box is the content box (`fullWidth = cardW − 20`); it starts at card x 10, y 62. **g = 4** (`sp4`, `EuclideousRhythmGeometry.gap`) on RHYTHM, RIFF and NOTES alike.
- **RHYTHM:** columns edge to edge (x 0 … W): two halves of (W − 4)/2, the left split into two columns of (half − 4)/2; the lower block is rate half · 17 pt divider footprint · out half. Zones: `patternBlockH` 80, `upperH = contentAreaH − 80 − 4` = **145 / 145.67**; the 192 pt `rhythmZonesFloor` is not an upper-zone floor — it gates the STEPS picker (`contentAreaH ≥ 192`), margin 37 pt.
- **RIFF:** the MOVE and NOTES bands span x 0 … W; **row A and the output row sit inset 4** (content x 4 … W − 4, toggle column 124, gap 8). Row A = H − 18 − 142 = 69 / 69.67.
- **NOTES:** the strip x 0 … 35, gap 3, then columns to x = W (edge to edge); `upperH` as RHYTHM's.
- So the body fills the content box on RHYTHM and NOTES; **RIFF's controls sit 4 pt inside it** (its bands do not). The buttons align with the content box.

## §0.2 what is hidden / what stays

Nothing is deleted. The 14 pt band becomes a 2 pt line (§A5); `EuclideousLockBadge.rowGap` / `EuclideousLaneCardMetrics.rowGap` (6) stop being used; the old off colours are replaced, not kept.

## Differences between the amendment and the code (source wins, reported)

1. **T is 44 pt in every layout**, not 78: the buttons are not bigger than 44 × 44 anywhere (§0.1(a)). The type function takes h, and the ratified sizes at h 78 / 70 are pinned as pure-function outputs, but at runtime h = T = 44 — the sizes at every layout are the h 44 ones (name 9.5, PLAY 6). "About twice their old size" in portrait AUM is therefore not produced by this change; if T is meant to grow with the layout, that is a different (unspecified) change.
2. **The strip has two bands, not three**: cells with the riff chips inside, and the key row; no hit-count band above, no progress line. All four lanes already reserve identical bands (A2 holds already; the test pins it).
3. **A1.5 is already true numerically** (the buttons equal the strip's full frame, 44); what Paul sees is that the cells occupy 27 of those 44 pt and the note band is blank when empty.
4. **The padding is already equal** (10 on all four sides, A1.1); what changes is the gap (6 → g = 4 beside the strip, 8 → 4 under the row).
5. **The tab body's outer edges sit inside the content box on the RIFF tab** (4 pt, controls only) — reported, the buttons align with the content box.
6. The bar is the 14 pt SHADOW band, an ANSWER state: §A5.1 applies.
