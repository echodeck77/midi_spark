# LANE STRIP CLARITY — findings map (2026-11-17, before any code)

Spec: Paul's raw ferry text (2026-11-17, from his iPad/AUM screen recording; the text is the whole spec). Base
ferries verified landed: LANE STRIP BANDS (e42195e + amendment 1 5e7d0f3), STACK RANKS GREY (3f6cc9),
PLAY BUTTONS RAIL+NOTE (ab048b3 + fixes 1b5fea6/8fe8216). Display only.

## The metrics as built
- `laneStripBandHeights` LaneStripBands.swift:79–84: hH = max(8, round(T × 0.2)) (`headerRatio` :21), reserve =
  rail 1.5 + gap 1 + hH + gap 1 (:69). **T = 44** (:8; the file-top comment's "hH 10 / hC 20" is STALE — the real
  values are hH 9, reserve 12.5, both-on hC 19, one-on 31.5, both-off 44, per :77–78). Chips: frame = the full
  cell slot (:177), radius 2, label 7 pt heavy (:30), rest 78 % (:32), label-fit rule :181–183.
- Strip columns: `euclidEvenBoxGeometry` Derivations.swift:10252 — gap = `EuclideousStripMetrics.columnGap` = 2;
  cellW = (W − 2(n−1))/n. Strip width (EuclideousLock.swift:526, `cometStripWidth`): landscape card 380.67 →
  **264.67** (226.67 with the lock badge); portrait 387 → 271 (233).
- **Cell widths (laid out)**: landscape no-badge 8→31.33 · 12→20.22 · 16→14.67; with badge 8→26.58 · 12→17.06 ·
  16→12.29; portrait 8→32.13 · 12→20.75 · 16→15.06 (badge: 25.38/16.58/12.69).
- **THE SCALE FINDING (resolved by Paul):** below the reference the page lays out AT the reference and
  `scaleEffect`s down (`euclideousScaleToFit` Derivations.swift:5460, mounted EuclideousPage.swift:1707/:1845) —
  so laid-out cellW is never under 12 and §1.1 as written would never fire; the recording's ≈7 pt is screen
  points (≈0.5 scale in AUM). **Paul 2026-11-17: slim = laid-out cellW × the page's fit scale < 12** (on-screen
  width; the scale threads to the strip as a display-only input). At scale 1 nothing is slim; in the recording's
  AUM window every step count ≥ 8 with badge (26.58 × 0.5 ≈ 13.3 — not slim) and 12/16 steps (≈8.5/6.1) are slim.

## The chip draw (the strike-through answer)
- One shared pair: `laneStripDrawChip` LaneStripBandPainter.swift:205–230 (header + riff tile) and
  `laneStripDrawFooterChip` :177–192 (footer + stack tile). Draw order in BOTH: fill → the sounding double
  stroke (`laneStripDrawSoundStroke` :196–200, called :222/:191) → **the label LAST** (:227–228/:187–188).
- **What crosses the digit:** NOT paint over the glyph (the label is last) — it is STACK GREY 2.4's INK stroke
  (#0D0F14, inset 1.5, :199): in a 9 pt chip its horizontal runs sit at y 1–2 and 7–8, exactly the 7 pt digit's
  cap/baseline band, so the dark line continues either side of (and optically through) the number. §2.2's
  single-white-stroke fix (inset 0.5 → y 0–1 / 8–9) clears the cap (≈ y 1.9–6.9) — §2.4's check passes at hH 9.
- The PLAY tiles' note chips: PartPlayButton.swift:89–101 — frame maxWidth × hH (the ONE `bandH` formula, :90)
  and they CALL the shared functions (:94/:96) → §2's fix reaches them with no extra work.

## Rank bars, cells, playhead
- Rank slots/marks: `rankSlotRect` LaneStripBands.swift:243–256 (slot = (hC−5)/8; filled-bar fallback under 4 —
  always active at T 44, slot = 1.75 both-on); drawn at LaneStripBandPainter.swift:64–69, currently ONLY while
  sounding (:125–138) — §4 adds the resting state. Riff rank source = the hit's header-chip prediction
  (`EuclideousStripHit.chip`, used :128); stack = `sounding.stackOutline` (played) and
  `hits[i].predictedStackRanks` (`euclideousStripStackRanks` LaneStripBands.swift:480–495).
  **PLAY AS settings with no prediction: none** — every ORDER/VOICES/SPREAD chain is closed-form through
  `euclideousNotesHitPitches`; prediction is empty only for a POLY lane (:482 `poly == nil` guard), a hit
  predicted silent, cfg/lapStartTick nil, or an empty pool. (Global-pool limit stands.)
- Cell looks: `stripCellLook` LaneStripBands.swift:264–268 — rest #2A2C33 (**not** §5.3's "as built" #22242A —
  source wins, reported; §5.3's VALUES are the ferry's new ones anyway), playhead rest #3A3D44 ✓, hit lane100 @
  30 %/45 % + 3 pt bottom bar; drawn LaneStripBandPainter.swift:85–99. Sounding cell stroke (to be removed, §6.3):
  :105–110. ALT outline :112–118. Playhead mover: `euclideousStripPlayheadStep(raw: cometRaw)` from the walk
  clock, EuclidLaneUI.swift:532; bands assembled :526–551.
- Lane tokens (EuclideousPage.swift:1655–1658): #F25959 · #59BFF2 · #F2BF40 · #8CD973. OKLCH (computed by the
  standard OKLab inverse of `euclideousRGBFromOKLab` Derivations.swift:8633): hues **23.7° · 233.1° · 85.9° ·
  138.4°** (token L 0.667/0.764/0.829/0.812 — the token LIGHTNESSES differ, which is §5's point).
  `stripHitColour` at L 0.46 C 0.10: **#873F3C · #006086 · #715300 · #39652B** (contrast vs #22242A: 2.07 ·
  2.23 · 2.17 · 2.27 — all ≥ 1.9 ✓); at L 0.56: **#A75B58 · #287EA5 · #8F7023 · #568247** (3.16–3.46).
- Riff map conversion for the table: `euclideousRGBFromOKLab` :8633 + `RiffMapTuning` :8676 (the table-once
  pattern `stackRankTable` LaneStripBands.swift:219–229 is the model).

## GATE 99 % (report only, §12.2)
Yes — the stack's held set EMPTIES between hits at GATE 99: a note's recorded end is gate × the inter-hit gap
(`euclideousPitchGateBeats` path; `euclideousMixNoteSounds` reads the record's end), so 1 % of each gap
(≈2.5 ms at 120 BPM, 1/8) has no sounding note before the next note-on. A 60 fps frame landing in that sliver
(and the chip's newest-note handover at the boundary, `euclideousPartNoteChip` LaneStripBands.swift:456–471)
drops the sounding stroke for a frame — the flicker in the recording. Nothing changed for this (per the spec);
§3.4/§3.6 decouple the LABEL from sounding, which removes the label part of the flicker.

## Spec-vs-code (report-back §12.6)
1. §1.1's threshold measured laid-out width — never under 12 (the scale-to-fit finding above); Paul chose
   on-screen width (laid-out × fit scale).
2. §1.2's "At T 41 … hC 26 (it was 18)": the built T is 44 (LaneStripBands.swift:8; the play-rail ferry reported
   the same) → slim both-on hC = 44 − 2×7.5 = **29**; and the pre-ferry both-on hC is 19, not 18. The T-41
   example is kept as the TEST's formula input (41 → 26 ✓ the formula agrees); the build runs at T 44.
3. §5.3 "Rest cells: #22242A … as built #3A3D44": the as-built rest is #2A2C33 (`stepFill` LaneStripBands.swift:45)
   — #22242A is this ferry's NEW rest value (also §8.8's contrast base); playhead-rest #3A3D44 matches as built ✓.
4. The file-top comment hH 10 / hC 20 (LaneStripBands.swift:8–11) is stale (0.22-era); real hH 9 / hC 19.
5. `laneTopRowFrames` (LaneStripBands.swift:121) has NO production call site — the real strip assembly is
   EuclidLaneUI.swift:526–551 (xs from the comet bar's own geometry); findings-only, nothing to change.

## Build order (per the spec; each green → commit)
findings ✓ → §2 sounding chip (+tests) → §1 slim bands → §3 stack labels → §5 hit colours → §6 playhead tick →
§4 resting rank marks → §7 states → docs + ship.
