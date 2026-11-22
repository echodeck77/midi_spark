# Grid CHANCE ferry — findings (mapped before any edit, 2026-11-22)

Ratified by Paul 2026-11-22 from the "Fourfold grid · CHANCE" canvas. Audited against the raw ferry
text. Fourfold only; `AUExtension/` frozen. Spec build order step 1: these findings, before any change.
Source-vs-spec differences are flagged (source wins).

## 1. Corner spaces + the ribbon-settings button
- **Ribbon-settings button is BUILT but UNMOUNTED** (Paul removed it 2026-11-17). `EuclideousRibbonSettingsButton`
  (`Fourfold/UI/RibbonSettingsViews.swift:13`), layout `euclideousRibbonSettingsLayout` (`Derivations.swift:5331`),
  wrapper `ribbonSettingsButton(box:)` (`EuclideousPage.swift:7912`) all compile but are never invoked;
  `@State ribbonSettingsOpen` (`EuclideousPage.swift:1076`) is never set true (doc note at `:7903`). So the **riff
  grid's bottom-left space is EMPTY** — the `%` toggle reuses exactly its rect: `x=8, y=railsTop (≈270 land /
  ≈270.67 port), free 48×41, drawn 36×41` (`Derivations.swift:5335`). The button does NOT occupy the space, so §3 proceeds.
- **STACK grid top-left free space** = the `Color.clear.frame(width: labelW, height: headerH)` blank at
  `EuclideousPage.swift:8541`: `x=8, y=34, 48×16` drawn, 48×20 down to the first rank row (`rowsTop=54`).
  **DIFFERENCE vs §3.1 (~40×22):** actual 48×16–20, under the 22×22 floor. Reported; **Paul chose 48×20, accept <22 tall** (no layout change).
- **DIFFERENCE vs §3.1 (riff "26×44"):** actual free/drawn is 48×41 / 36×41. Source wins.
- Riff ladders: y = rank-chip column `riffNoteLabelColumn` (`EuclideousPage.swift:7975`); x = four 8pt lane rails
  (`:8023`), `railsH=41/railH=8/railGap=3` (`Derivations.swift:5233`). The riff grid has **no column-number row** — rails are the x axis.
- STACK ladders: y = rank chips `stackAxisChip` (`:8558`); x = lane headers `EuclideousStackHeaderView` (`:8543`).
  **TOP / TOP−1 / TOP−2 rows were REMOVED 2026-11-09** — the stack is exactly 8 rank rows (ranks 8→1),
  `euclideousStackGridRows` (`StackGrid.swift:29`). So `stackRankChance` has 8 entries.
- **Portrait-AUM size** = portrait reference `814×1102` (`Derivations.swift:5623`; AUM window confirmed
  `PlayButtonsAmendmentTests.swift:24`). Panel box: land `380.67×319`, port `387×319.67` (`RiffPanelTests.swift:13`).
  Below reference the whole page scales uniformly. The "782 portrait" is a stale MIX measurement, not this panel.

## 2. Where chance sits in each hit path (`Router.swift`)
- **Riff:** gate at `:4592`, after scrub-hold/LOOP/TUTTI substitution (`euclideousRiffHitSource`, `Derivations.swift:5397`,
  called `:4585`) where `rawRank`/`leapStep` are known, BEFORE octave/transpose in `strikeRiffRawRank` (`:4603`). Fail ⇒
  `restEnd = 1` (SKIP, `:4627`) so the walk advances, no pitch added. Rest column has no rank; column chance applies only
  if a hold/TUTTI gives a note.
- **Stack by rank:** per-voice in `strikeRowsRank` (`:4749`, before `addPitch` `:4774`) + gap `strikeGap` (`:5935`, before
  `strikeChord` `:5937`). Key (lane, kept-step ordinal, rank).
- **Stack by lane:** one roll gating the hit/gap block (`:4739`/`:5913`), before `euclideousRowsResolve`.
- **Order:** rhythm isHit → mask CHANCE/PAUSE → LANES mute/solo/part-solo (`lanesSeqMuted` `:3918`) → scrub/LOOP/TUTTI →
  INVERT/TRANSPOSE/octave → ON-REST/STACK WHEN → AVOID/HOCKET → `emitOneOutput` flood gate. **Grid CHANCE = last gate
  before emitters at the LAYER decision point (4592/4774/5935)** — NOT at `emitOneBus`/`emitOneOutput` (shared by
  ratchet/echo/hocket re-strikes + feed the counters).
- **Counters that see note-ons (§2.5):** `NoteRollRing`/`rollNoteStruck` (`:1998` from `emitOneBus:2057`), flood
  `euclideousOnsThisBeat` (`:2076`), NOTE VIEW/PULSE `pushNoteViewEvent` (`:995`) — all downstream of the layer gate, so
  a skip never reaches them (correct by construction). Counters that MUST keep counting (walk `advOrd` `:4140`, REPEAT
  lookback `:4653`, PLAY-AS k `:4737`, mask ordinal, TUTTI table, ALT/SWITCH/RESETS) run BEFORE the strike. **Caution:**
  `euclideousLastSounded*` caches (`:616`) are written at strike time + read by mask-REPEAT replay — a chance-silence
  leaves the prior value; acceptable (mask inert in production), noted.

## 3. Modes that hold across hits (§2.7)
Euclideous legato GATE=100 (`reconcileEuclidLegato` `:3078`) — a silenced would-be-legato strike runs reconcile with
that pitch ABSENT (the layer gate achieves this: the pitch is never added, exactly like a rest). FX TIE carry
(`restEnd==2`, `heldRiffPitch` `:4719`) — chance-fail is SKIP (`restEnd=1`), not TIE. RING (`:4420`) / POLY-RIFF ring
(`:4521`) — per-pitch, a silenced start is omitted; ringing notes clear at the boundary. DRONE (PLAY AS) — §2.7
explicit: a silenced voice counts as not played for its held note (layer gate handles it).

## 4. Salts
Chosen: `riffGridChanceSalt = 0x5249_4646_4752_4944` ("RIFFGRID"), `stackGridChanceSalt = 0x5354_414B_4752_4944`
("STAKGRID"). Verified distinct from all in use: `0x4E4F5445_5343_4841` ("NOTESCHA", legacy notes/stack chance —
reserved, dead), `0xA24BAED4963EE407` (mask chance), `0x2545F4914F6CDD1D` (mask ratchet), `0x454D4954_5254_4348`
("EMITRTCH"), `0x5241_5443_4852_4E47` ("RATCHRNG"), `0x4341_4E4F_4E53_4C50` ("CANONSLP"), `0xD1B54A32D192ED03`
(FILL chance). `splitmix64Mix` at `Derivations.swift:367`.

## 5. Settings save + undo
Page-level additive-Optional Codable on `PluginState` → auto-saved to AU fullState + presets (same codec,
`PresetStore.swift:24`). Undo = canon-unit / ribbon-settings template: `EuclideousUndoSnapshot` (`Models.swift:4738`)
+ `euclideousSnapshot()` (`FourfoldRootView.swift:828`) + `euclideousApply()` (`:875`, live mirror AND
`au?.editDocument`) + an `onSet…` funnel: `euclideousRecordUndo(coalesceKey: nil)` then one `editDocument` + `publish()`
(template `onSetCanonUnit` `:614`). Slider drag coalesces on `gestureKey("euclideousGridChance")`; a CLR / toggle is
`coalesceKey: nil` = one step.

## 6. Contradictions with the ferry text
(a) riff toggle "26×44" → actual 48×41/36×41. (b) STACK corner "~40×22" → actual 48×16–20 (Paul: 48×20). (c) the STACK
**bottom**-left has no room (ribbon-findings §13); the feature uses the STACK **top**-left header-band gap, which exists.
(d) stack CHANCE was "removed" by the 2026-11-22 STACK WHEN ferry — this ferry re-adds probability on the GRID, not the
STACK tab; the legacy "NOTESCHA" salt stays reserved.

## Build-on status (all BUILT)
Riff scrub (`1827c02`; `euclideousRiffHitSource`/`euclideousStackHitRanks`, `Derivations.swift:5397/5404`). STACK grid
+ live + riff arrow (`StackGrid.swift`, `StackGridViews.swift`). Stack ranks grey (`LaneStripBands.swift:155`). Riff map
(`Derivations.swift // MARK: - RIFF MAP`, `RiffMapPalette.swift`). Riff grid stack dots. PLAY AS rows + amendments.
Style pass 1 (`StyleTokens.swift`).
