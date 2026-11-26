# COMPACT LAYOUT + LANE STRIP STYLE — findings (§9 report-back)

Ferry 2026-11-26 (Fourfold only). Landed in slices on `main`: strip style (slice 2) → size-class + Compact layout fn (slice 3) → Compact views (slice 4) → dev toggle (slice 5) → VoiceOver + this doc (slice 6). The full narrative is in `Docs/euclideous-status-log.md`; this is the structured §9 report.

## 1 · The map (file:line)

- **Layout fn** `euclideousPageLayout` `Derivations.swift:5685` / `EuclideousPageLayout` `:5661`; header kind `euclideousHeaderKind` `:4999` (A ≥ 929.88 containerW, else B ≥ 607.88, else C; top A→64 B/C→111); floors `euclideousPageFloors` `:5630` (a flag, never a clamp). Scale-to-fit `euclideousScaleToFit` `:5748` + the references `:5739-5741`. Consumers: `pageGeometry` / `pageBody` `EuclideousPage.swift:1985/1991`; the `body` size-class branch `:1798-1800`.
- **Tab strip** `EuclideousPageTab` `LaneViewStrip.swift:14` (release 8 tabs, dice/padlock DEV-only `:125`); **strip height 28** `:76`.
- **2×2 cards** `laneCard` `EuclideousPage.swift:2972` = `VStack { laneCometRow; tabContent }`; metrics `EuclideousLaneCardMetrics` `Derivations.swift:5106`. The RESETS ALL row `EuclideousAllRowView` `RestartEditorViews.swift:541`, reserved by `allRowRect` `Derivations.swift:5709`.
- **Overlays covering the 2×2 as one**: MIX `EuclideousMixV2Panel` `MixPanelV2Views.swift:75`; HARMONY `EuclideousHarmonyPage` `HarmonyPage.swift:27`; KIT `kitEditorView` `EuclideousPage.swift:8094` — all size to the passed lane-block union.
- **Right panels**: grid `riffGridView` `EuclideousPage.swift:8660` → mono/poly/stack grid views (each reserves a tab row via `riffTopRow`/`riffModeRow`); emitter `sequencerPanel` `:9901` (MUTE=`.lanes`·RATCH·VEL(dev)·CC). Layout `euclideousRiffPanelLayout` `Derivations.swift:5391`, body size `euclideousSeqTabBodySize` `:5608`.
- **Lane strip = the BANDS painter** `drawLaneStripBands` (`LaneStripBands.swift` / `LaneStripBandPainter.swift`); PLAY buttons `EuclideousPartPlayButton` `PartPlayButton.swift:28`; built in `EuclidCometBar` `EuclidLaneUI.swift:571`, drawn at the card header, MIX back, random/lock cards.
- **View state** (all `@State`, never persisted): `pageTab` `:1088`, `riffPanelTab` `:1641`, `gridLane` `:1095`, `sequencerTab` `:1069`; new Compact state `compactLane` / `compactRightGrid` `:1642-…`.
- **Dev settings** `EuclideousSettingsSheet.swift` CLOCK tab (`#if DEBUG block{ segmented }` + `@AppStorage("fourfold.*")`).

## 2 · Design minimum · column widths · scale

- **Compact design minimum = 730 × 594** (`EuclideousScaleToFit.compactRef`), from the floor sweep (`CompactLayoutTests.testCompactMinimumSweep`): width-bound by the right riff grid's 18 pt cell floor, height-bound by the card's 192 pt floor. ≤ 900×600 as §1.2 requires. At/above it Compact renders 1×; below (either dim) it scales to fit via `euclideousScaleToFit(ref: compactRef)`.
- **Left column = max(476, round(0.54 · (width − 16)))**; right = (width − 16) − left − 8. Representative Compact sizes (landscape, 1× since all ≥ 730×594):

  | view size | header | left | right | scale |
  |---|---|---|---|---|
  | 900 × 600 | B | **477** | 399 | 1 |
  | 1024 × 768 | B | 544 | 456 | 1 |
  | 1133 × 744 (mini) | B | 603 | 506 | 1 |
  | 1189 × 725 (1 under the FULL ref) | B | 634 | 475 | 1 |

  Below 730×594 the whole Compact page scales: scale = min(w/730, h/594), centred, never above 1 (e.g. 700×560 → 0.94; 640×520 → 0.876).
- **§9.2 spec discrepancy**: the spec states "476 at 900 wide"; the 54%-of-body formula with 8 pt padding gives **477** at 900 — a 1 pt difference, reported (the formula is the general rule the spec also states).

## 3 · Tab content heights at 900×600 · overlays

- At 900×600 the card content area = **198 pt** (header B, top 111; card 218 − 20 inset). **EUCLID clears the 192 floor** (6 pt spare) — the §9.3 EUCLID-fit risk does **not** bite at 900×600; the whole layout is clean there bar the inherent `.compactLaneChip` floor. INPUTS/MODE and every other tab lay out at the card's own size via their existing layout functions.
- **§2.6 overlays**: MIX / HARMONY / KIT are laid out at their designed block (`euclideousPageLayout(landscapeRef)`'s lane-block union, ~769×610) and `scaleEffect`-ed to the left region (strips panel + card) — per Paul's decision #2. Fit/legibility-at-scale is DEVICE-OWED.

## 4 · The lane strip (§4)

- Drawn everywhere the BANDS strip is: the 2×2 lane card header (`laneCard` → `laneCometRow`), the MIX card back (`laneCardBack`), random/lock-mode cards, and now the Compact chip-led strips (`compactStripRow` reuses the same `laneCometRow`).
- **Mid tone: DERIVED** (`stripHitMidColour` `Derivations.swift`) = lane100 (`euclideousLaneTokens`) mixed 50 % with the dark tone (= the built hit fill `stripHitColour`), in OKLCH — source has no mid/dark token.
- **§4.8 (nothing removed / harder to see)**: everything the strip showed is kept. The two deliberate departures: §4.4's fixed stack ink drops the mid-dark ranks' contrast (rank 3 ≈ 3.25:1, rank 4 ≈ 2.52:1) below the old 4.5:1 — a reported legibility note; §4.5's rank line was KEPT as-built (per-voice colour) rather than flattened to white@60 % (a DECISION).

## 5 · Findings by count

**Fixed / implemented:** the size class + scaling (§1), the Compact left + right columns + scaled overlays (§2/§3), the lane strip restyle everywhere (§4), the dev toggle (§1.5), the VoiceOver groups (§5), the floor sweep + design-minimum (§1.2/§6).

**DECISIONS (each a one-line question for Paul):**
- §4.4 — keep the fixed stack-chip ink split even though ranks 3–4 fall under 4.5:1, or revert those ranks to the WCAG pick?
- §4.5 — keep the rank line showing per-voice colour (as built), or flatten it to the spec's "2 pt white @ 60 %"?
- §2.6 — MIX/HARMONY/KIT scaled into the ~476-wide Compact left region read small; accept scaled, or give them the full body width in Compact?
- The right-column body-only panels keep their layout's reserved tab-row height as a small slack at the panel foot — tighten it (more surgery) or leave for v1?

**FLOORS (reported, not failures):** `.compactLaneChip` — the lane chip's hit area (leading edge → PLAY RIFF) is inherently under 44 pt wide on every Compact layout (§2.3).

**Known v1 gaps (device-owed / refinement):** random & lock modes and the grid-chance editor overlay are not wired in Compact (dice/padlock are DEV-only; grid-chance is a §3.4 follow-up).

## 6 · Spec-vs-source contradictions (source wins, reported)

- Tab strips are **28 tall** (source), not the **32** the spec gives for both tab rows.
- The dice/padlock and the **VEL** emitter tab are **DEV-only** → release has no random/lock buttons and a 5-tab (not 6) right column.
- PLAY buttons are **`EuclideousPartPlayButton`** (not `EuclidCompactPlayButton`); the live strip is the **bands** painter (not the comet painter); `euclideousStripCurrentStep`/`euclideousStripPlayhead` are the retired comet painter's (the band strip uses `euclideousStripPlayheadStep`); there is **no mid/dark lane token** (derived); the riff-grid label column is **48** wide (not 30); the left column is **477** at 900 (not the stated 476).
- The dependency ferry **LAYOUT AT EVERY SIZE 1 never landed**; its scale-to-fit already existed as `euclideousScaleToFit` + a reference size, reused here per Paul's decisions.
