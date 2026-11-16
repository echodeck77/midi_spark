# PLAY buttons, rail and note — §0 FINDINGS (committed before any code, per the ferry's build step 1)

Ratified by Paul 2026-11-16 (boards A·RAIL + C·NOTE combined). Display-only; no model/engine/saved-data/undo change; golden byte-identical. Source wins where it disagrees with an existing value — every difference is reported below. The §5 fork was put to Paul and resolved (REAL PREDICTED CHIPS).

Full plan: `~/.claude/plans/zesty-zooming-whisper.md` (top section).

## Prerequisite ferries — all LANDED (confirmed)
Status log has: PLAY RIFF / PLAY STACK + amendment 1 (:11020, :11077); LANE STRIP BANDS ferry + amendment 1 (2026-11-12, :11363, :11395); STACK RANKS GREY (2026-11-15, :11837). No prerequisite is missing — proceed.

## The play tile as built — `EuclideousPartPlayButton` (Fourfold/UI/PartPlayButton.swift)
- Frame **44×44** (`EuclideousLaneCardMetrics.playButtonW`=44, `cometRowH`=44 = **T**; Derivations.swift:4856/4860). T is also `EuclideousStripMetrics.stripH` = trackH 27 + rowGap 3 + keyRowH 14 = 44 (Derivations.swift:9627).
- Fill **#202226** + **1 pt #2B2D33** border, radius **9** (`EuclideousPartPlayLook.tileFill/tileBorder/tileRadius`, Derivations.swift:5438); tile identical ON and OFF (`.opacity(tileOpacity=1)`).
- Triangle (lamp): path `M1 1 L7 4.5 L1 8 Z`, drawn ~5.5×6 (Derivations.swift:5468); `lampW/lampH/lampGap` from `euclideousPartPlayType(height:)` (:5458). Laid out as `HStack(spacing: lampGap){ lamp; PLAY }` with the name below (VStack spacing `lineGap`), PartPlayButton.swift:51-63.
- **How the triangle lights today:** `look.lampFilled` = the part's **on-state** (ON → filled lane accent, `lampUsesLane:true`; OFF → outline, `lampStrokeHex #6E737C`; Derivations.swift:5441-5442). PLUS a SEPARATE 150 ms `flash` glow (blurred overlay) fed by the NoteRoll feed `rollLive.model.parts[part]` via `euclideousPartPlayFlash` (Derivations.swift:5484, supplied at EuclideousPage.swift:3047). The triangle has NO 55%/silent dim today — it's full-on while the part is on, with a per-strike flash on top.
- Type: PLAY **6 pt** heavy monospaced (h×0.13 clamp 6…11); name "RIFF"/"STACK" **9.5 pt** (h×0.22 clamp 9…18), `lineLimit(1)` tail-truncate (amendment 1 B3).
- Colours: **OFF** → PLAY #6E737C, name #8A909A, lamp-stroke #6E737C. **ON** → PLAY #AAB0BA, name #F2F4F7, lamp filled lane accent.
- **No pressed/touch-down state** exists (bare `.onTapGesture`, `.transaction{ animation = nil }`, PartPlayButton.swift:41). Tap target `contentShape(Rectangle())` 44 wide; action `cardBackToggle(idx, .riff/.notes)` (EuclideousPage.swift:3050, one undo step); **no haptic** anywhere.

## Layout — T, hH, hC, w, g (Fourfold/Engine/LaneStripBands.swift, Derivations.swift)
- **T=44, w=44, g=`columnGap`=4** — all FIXED at every layout incl. portrait-AUM (no narrow variant; Derivations.swift:4856/4858/4860). The "78"/"41" in screenshots are device pixels resolving to 44 (status log :11367/:11397).
- Band heights already named hH/hC: `laneStripBandHeights(T:)` LaneStripBands.swift:62-67 → `hH = max(8, round(T·headerRatio))`, `gap = rowGap`, `hC = max(0, T−2hH−2gap)`. **Current (amendment 1 B2.1): headerRatio = 0.22, rowGap = 1** ⇒ T44 hH=10, hC=22.
- `euclideousLaneCardFrames(card:withBadge:)` Derivations.swift:4883 → content (card inset 10)/topRow/lead(PLAY RIFF)/trail(PLAY STACK)/strip/body; unused `headerBridge`/`footerBridge` rects exist in the frames.

## DISCREPANCY (source wins) — T: ferry example 41 vs built 44
The ferry's §3.2 worked example ("At T 41: both on hH 8, hC 18; one on 29.5; both off 41") is internally consistent at **T=41**, but the built T is **44**. Per the audit rule, source wins → recompute with the ferry's new §3.1 ratio **0.2** (replacing the current 0.22) and the rail+gap:
- per on-part reserved = rail 1.5 + gap 1 + band hH + gap 1; hH = max(8, round(44·0.2)) = max(8, round(8.8)=9) = **9**.
- **both on: hC = 44 − 2×12.5 = 19** (≥16 ⇒ §3.2 does NOT trip); **one on: hC = 44 − 12.5 = 31.5**; **both off: hC = 44**.
This is the §12.2/§12.5 reported difference. (If a layout with a different T surfaces, recompute and re-check the hC<16 flag.)

## The band draw — `drawLaneStripBands` (Fourfold/UI/LaneStripBandPainter.swift:87)
- Draws **track plates** (band backgrounds #202226 + 1 pt #2B2D33 border, r6 far side, square joint side; :92-105) → **REMOVE** per §2.5 (no track/bridge/band-background/outline). The literal g-gap bridge was already not drawn (deferred); `headerBridge`/`footerBridge` rects unused.
- Cells :110-124: `stripCellLook`, hit fill `d.tint.opacity(0.30/0.45)` + 3 pt lane bottom bar.
- **OFF part draws grey OUTLINE chips** (fill nil, #3A3D44 stroke, label #5A5E66; :175/:187/:242) → **REMOVE** per §3.3 (off part draws nothing, the band is gone, cells extend).

## Lane colour (the rail's colour, §2.1)
`d.tint` in the band painter = `euclideousLaneRGB[lane]` (Derivations.swift:8471; #F25959 / #59BFF2 / #F2BF40 / #8CD973) — the exact constant the hit bottom bar uses. ✓

## The 42% dim — `EuclideousLaneDimStyle.opacity = 0.42` (Derivations.swift:10193)
- Applied as ONE group `.opacity()` on the WHOLE `EuclidCometBar` Canvas: `stripDim = soloDim || partsOffDim` (EuclidLaneUI.swift:212) and `mutedNow` (:640); the two tiles are OUTSIDE this dim.
- **§6.1 cells-only dim: NOT possible via this path.** The dim wraps the whole Canvas; `drawLaneStripBands` draws every element at full strength with no dim arg. To dim the HIT CELLS ALONE (both-parts-off) while leaving tiles/rest-cells/playhead unchanged, add a `cellDim` parameter to `EuclideousStripBandInput`/`drawLaneStripBands`, applied only in the `case .hit` branch (:118) + its bottom bar (:120). **This is clean and small (not a hack) ⇒ not a hard STOP; recommend proceed.** It also means SEPARATING the both-parts-off case (→ new cells-only dim) from the solo-silenced / LANES-mute cases (→ existing whole-strip dim, §6.3).

## The shared chip fns (Fourfold/UI/LaneStripBandPainter.swift — the BANDED strip)
- `laneStripDrawChip(ctx, slot, steps, fill:LaneStripChipFill?, label, hollow, sounding)` :224 — riff header + off/unplayed footer.
- `laneStripDrawFooterChip(ctx, slot, steps, ranks:[Int], sounding)` :196 — live stack footer, SPLIT per voice.
- `laneStripDrawSoundStroke(ctx, frame)` :215 — §2.4 double stroke (1 pt #F2F4F7 inside + 1 pt #0D0F14).
- **Arbitrary frame = YES**: both compute `laneStripChipFrame(slot:)` = identity (LaneStripBands.swift:147) ⇒ pass any rect as `slot`; the §4 note chip can be drawn inside the 44pt tile. ✓
- Riff fill `riffMapColour(column:rank:)` (:173); stack fill `stackRankColour(rank:)` grey ramp (:204, LaneStripBands.swift:189). Sounding `a = sounding ? 1 : chipRestOpacity` (**78%**, :231/:200). Label-hide `laneStripChipLabelFits` (LaneStripBands.swift:151); narrow one-chip fallback `laneStripFooterSegments` minSeg 4 → lowest-rank single segment (:163).
- (NOT the old `euclideousStripChipPaint` in LaneStripPainter.swift — that is the BUILD-page comet path, `strip == nil`; the Fourfold lane card uses `drawLaneStripBands`.)

## Held sets + "most recent note-on hit" (§4)
- Held set = the NoteRoll feed `NoteRollModel.parts[8]` (NoteRollRing.swift:91; riff = 2·lane, stack = 2·lane+1). Sounding gate `euclideousMixNoteSounds(n, at:now)` (MixPanel.swift:305). Per-step mapping `laneStripSounding(riffHeld:stackHeld:…)` (LaneStripBands.swift:334).
- Newest note-on: stack = `euclideousStackSounding(notesPart, rank, nowBeat)` → `{sounding, glowOnset}` (StackGrid.swift:150, per-rank, STACK-ONLY); riff = no twin — use the part's max `onBeat` / `NoteRollModel.lastOnBeat[2·lane]` (NoteRollRing.swift:95).
- Record fields `{onBeat, endBeat?, pitch, velocity, outs, rank}` — **no column**. Recover the chip by onset → hit step → `EuclideousStripHit.column` (the existing `laneStripSnapToHitStep` LaneStripBands.swift:327, as `laneStripSounding`/`euclideousRiffStackDots` already do). So §4's "most recent note-on hit" = newest note-on → its hit step → that step's `d.hits[i].chip` (riff: column+rank) / `stackChipRanks` (stack ranks).

## Prediction (§5) — DECISION: REAL PREDICTED CHIPS (Paul, 2026-11-16)
- Riff header already draws a predicted chip on EVERY hit (`euclideousFooterPass.prediction` → `euclideousStripHits`, Derivations.swift:3104; painter :168).
- Stack footer is PLAYED-ONLY today (chip only where `stackChipRanks[i]` non-empty, painter :185; gate `onBeat<=now` in `laneStripSounding` :346). Upcoming stack prediction was DEFERRED (painter comments :182/:187; status log :11389) — **NOT** a PLAY AS limitation: all orders are closed-form (`euclideousRowsResolve` PlayAsRows.swift:185; SHUFFLE/random replay-exact splitmix), and a deterministic stack predictor `euclideousNotesHitPitches` already exists (Derivations.swift:9178, "pure + deterministic").
- §5.1 "upcoming hit WITH a prediction (lane strip 3.3)" therefore references a chip that was never built — surfaced to Paul (spec↔code contradiction). **Paul chose: wire the real predicted stack chips (riff parity).** Slice 5 wires `euclideousNotesHitPitches`→ranks into the footer; #2B2D33 empty slot only where the predictor says the hit plays nothing. This UI-side engine-mirror MUST be fuzzed against the engine (extend `LaneStripFuzzTests`) — the project's #1 bug class.

## §12 report-back items parked here (quote in the final reply)
1. Tile as built, triangle lit by part on-state + a separate 150 ms NoteRoll flash, NO pressed state, no haptic (above).
2. T=44 (not 41); hH=9, hC both-on 19 / one-on 31.5 / both-off 44; §3.2 flag does NOT trip.
3. Stack chips were played-only because upcoming prediction was deferred (not a PLAY AS limit); every order is predictable.
4. Cells-only dim needed a NEW `cellDim` param (the group-opacity path couldn't do it); built that way.
5. Discrepancies vs source: T 41→44; off text #6E737C/#8A909A → #C9CDD4; on PLAY #AAB0BA → #F2F4F7; triangle on now 100%/55% by held set (was full + flash); tile fill #202226 → none; tile stroke #2B2D33 → #5B606A; headerRatio 0.22 → 0.2; track plates + off-part outline chips removed.
