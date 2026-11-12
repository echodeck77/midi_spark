# Lane strip bands — amendment 1: findings (§B10)

Committed before any code (the ferry's build step 1). Mapped against the real code, not a paraphrase. All line numbers are the `Fourfold/` tree, branched off `main` (post the LANE STRIP BANDS ferry: commits `ceb2b03`→`e42195e`, `8d4621a`).

**Prerequisite:** the "LANE STRIP BANDS ferry" **has landed**. Paul's ferry dated it 2026-11-11; the code and status log (line 11363) say **2026-11-12** — same ferry (PLAY RIFF→header, PLAY STACK→footer, bands, chips, rank outlines, joined plates). Minor date discrepancy, reported.

## §B10.1 — the findings, with file:line

### The slot bug (chips one step early) — the §B1 target
- **Cause:** `laneStripSounding` (`LaneStripBands.swift:287-296`) places the footer stack chips **and** the stack rank outlines at `s = stepOf(note.onBeat)`. The UI supplies `stepOf = { b in euclideousStripPlayheadStep(raw: cometRawAt(b), n: n, dir: dir) ?? -1 }` (`EuclidLaneUI.swift:503`), i.e. **the floor of the comet sweep position at the note's onset beat** (`Int(euclidCometPos(raw, n, dir).rounded(.down))`, `LaneStripBands.swift:210-214`). A note emitted at the leading edge of its step reconstructs to a sweep position at/just below the step boundary, and `.rounded(.down)` yields the **previous** step — one early — and wraps at step 0.
- **The other three are correct:** the cells (`let isHit = i < d.hits.count && d.hits[i].kind != .rhythmRest`, `LaneStripBandPainter.swift:116`), the header riff chips (`guard let chip = d.hits[i].chip`, `:157-160`), and the riff rank marks (ANDed with `d.hits[i].chip`, `:139-144`) all index the **authored hit array** `d.hits[i]` (= `strip.legs[stripLeg].hits`, `EuclidLaneUI.swift:513`) directly — no onset round-trip. Only the stack path re-derives its step from the onset.
- **Why the test missed it:** `LaneStripBandsTests` passes the identity stub `stepOf = { Int($0) }` (`:110`), never exercising the floored-comet mapping.
- **Fix (§B1):** one shared position function indexed by the hit's own step (the step whose cell lights). Map a played stack note to its authored hit step, not a floored sweep position; the header/cells/footer/rank-marks all read the same index.

### Lane 2's empty header (riff off) — the §B6 target
- **Cause:** the header loop is gated solely by `guard let chip = d.hits[i].chip else { continue }` (`LaneStripBandPainter.swift:157-158`). The off-part grey-outline look is only reachable *after* that guard (via `fill: d.riffShown ? .map(..) : nil`, `:160`). With the riff OFF the hits carry a nil `chip`, so the guard fires on every step and the header draws nothing.
- **The footer is correct** (`:168-177`): it has `else if isHit { laneStripDrawChip(fill: nil, label: "") }` keyed on `d.hits[i].kind != .rhythmRest`, independent of a chip.
- **Fix (§B6):** mirror the footer — `riffShown ? (guard chip; filled) : (isHit ? outline)`.

### The joined shape reads as separate pieces — the §B5 target
- **Cause:** `drawLaneStripBands` draws ONLY the header/footer **track plates** (`LaneStripBandPainter.swift:100-109`) — each its own closed `laneStripTrackPath` with its own `ctx.fill` + 1 pt `ctx.stroke`. The PLAY RIFF/PLAY STACK **button tiles** are drawn separately by `EuclideousPartPlayButton` (`PartPlayButton.swift:27`) in the HStack, and the **bridge** over the g=4 gap isn't drawn at all (status log 11389: the literal bridge + the seamless joined outline were deferred, "needs an HStack→ZStack restructure"). So tile + bridge + track are three separate strokes → a doubled border at the joint.
- **Fix (§B5):** wire the already-built-but-unused `laneTopRowFrames` (`LaneStripBands.swift:103`, returns leadTile/trailTile/headerBridge/footerBridge/strip/header/cells/footer in content-local coords) and draw each `tile ∪ bridge ∪ track` as ONE path in a Canvas spanning the full top row; the button text/lamp + tap target become overlays (tap = tile only, §B5.4).

## §B10.2 — T, hH, hC, slot, w, g, and the button type at every layout

**T = 44 at every layout** (`EuclideousStripMetrics.stripH = trackH 27 + rowGap 3 + keyRowH 14 = 44 = cometRowH`, `Derivations.swift:9133` / `:4637`; pinned `PlayButtonsAmendmentTests` → `[44]`). T/w/g are fixed at every layout; only the strip width varies. The page scales uniformly with `scaleEffect` below the reference size (`EuclideousScaleToFit`, `Derivations.swift:4987`), so **portrait-AUM renders ~41 but lays out at 44** — the amendment's "41" is that scaled value, the same screenshot-vs-point slip the ferry already resolved (78→44). **The bands are not half-size.**

| quantity | current code | §B amendment | **at T=44** | §B's "T 41" |
|---|---|---|---|---|
| hH | round(T·0.23) | max(8, round(T·0.22)) | **10** | 9 |
| band gap | rowGap 2 | 1 | **1** | 1 |
| hC | T−2hH−2·gap = 20 | T−2hH−2 | **22** | 21 |
| rank slot | (hC−9)/8 = 1.375 | (hC−5)/8 | **2.125** | 2 |
| rank bar h | fallbackBarH 1 | max(1, slot−0.5) | **1.625** | 1.5 |
| button name | half(clamp(T·0.22,9,18)) | §A3 h=T | **9.5** | 9 |
| button PLAY / line gap | §A3 | §A3 | **6 / 3** | 6 / 3 |
| w | fixed 44 (`playButtonW`) | ceil("STACK"@name+8) | **44 (kept, Paul)** | ~37 |
| g (item gap) | columnGap 4 | as built | **4** | 4 |

Fallbacks tripped at T=44: `hC 22 ≥ 18` (ok); `slot 2.125 < 4` ⇒ **filled bars on every lane, every layout** (§B4.4's 1 pt outline fires only at slot ≥ 4, i.e. at the spec's T=78, never at 44). The full `euclideousPartPlayType(height:44)` result: name 9.5, PLAY 6, lineGap 3, lampH 6.5, lampW 6, lampGap 3.5, stroke 1, glow 4.

## §B10.3 — contradictions (spec vs code; source wins)
- **T**: amendment 41 → real **44**. Every "At T 41: …" example is off by the delta (hC 22 not 21, slot 2.125 not 2, bar 1.625 not 1.5, button name 9.5 not 9; hH stays 10).
- **`w` (§B3.2)**: amendment derives w from the name size; shipped code uses a fixed 44 (`playButtonW`; the prior ferry's writeup claimed the measured-w change but left `laneTopRowFrames` unwired — it has no production caller). **Decision (Paul, 2026-11-12): keep 44**; derived-w offered as a follow-up.
- **§B4 insets**: amendment riff 2 / stack 4 (narrow-cell 1 / 3) vs current `riffInset 3` / `stackInset 6`.
- **§B4.4 fallback inverted**: amendment = filled bars default, 1 pt outline only at slot ≥ 4; current = outline default, bar at slot < `slotFallback 3`.
- **§B2.2 30-cap**: `chipMaxW 30` caps the chip width; §B2.2 says no 30 cap.
- **chip height / label**: current chip is `slot.height − chipShrink(4)` = 6 pt with a 10 pt label (`chipLabel`); §B2.2/§B2.3 = full band height, 7 pt label inside — this (not the band size) is the "slivers with spilling labels".
- **band gap**: amendment 1 vs current `rowGap 2`.
- **ANSWER line (§B2.6)**: amendment 1.5 pt inside the footer track bottom edge; current `answerLineH 2` as a separate `.overlay(.bottom)` (`EuclidLaneUI.swift:206`).
- **sounding ring (§B2.4)**: current = an OUTSIDE ring grown `ringGap + ringWidth/2 = 2.25` pt beyond the chip (`laneStripDrawRing`, `LaneStripBandPainter.swift:59-63`) → spills the band; amendment = a 1 pt #F2F4F7 stroke **inside** the chip, chip 100% (resting 78%), no outside ring.
