# FILL TAB V2 — §0 findings map (2026-11-17, before any code)

Spec: Paul's raw ferry text (2026-11-16, "FILL tab v4" artboard; the text is the whole spec). Amends FILL,
FILL TAB and FILL TAB AMEND 1. **AMEND 1 was never built** — no commit, and source still has the old defaults
(`fillSpeed ?? 3` = ×2, `fillHits ?? .keep`, Models.swift:859/835) — so this ferry carries its defaults in
(×1, HITS ALL), reported as the one place the spec assumed code that does not exist.

## The FILL tab as built
- Mount: EuclideousPage.swift:3539/3546 `fillTabContent` → `fillBlock(box: fullWidth × contentAreaH)`.
- Layout: FillBlock.swift:44–78 `euclideousFillBlockLayout` — 28 pt bar row (bars 2.5 apart) + 34 pt LOOP chip,
  preview 50 pt (36 under a 200 pt card, 0 under 180), then 3 control rows × 4 equal columns (row gap 4.5, col gap 3).
- Bar tiles: EuclideousPage.swift:4467–4484 `fillBarTile` — the rate grid's looks (lane20 fill + lane100 1 pt border
  lit; #2A2D34 unlit; #363A42 current-unlit), number 8 pt, progress line 1.5 pt (width − 5) × progress.
- Preview: EuclideousPage.swift:4415–4465 `fillPreviewStrip` over `euclideousFillPreviewNotes` — spans the LOOP, draws
  only fill notes (riff lane-colour / stack #9AA0AA / LAND white / BREAK dashed), **recomputed EVERY FRAME** (the
  60 fps TimelineView at :4350 rebuilds the notes array each tick — the §3.7 cache is a real improvement).
- FILL tile: EuclideousPage.swift:4488–4500 (PLAY RIFF lamp + "FILL" 7 pt on the value-tile ground).
- LOOP chip: FillBlockViews.swift:161–177 (#22252C + a 45 % lane border — Paul's "looks like a lit bar").
- Value tiles (SPEED/LENGTH/RANKS/SWELL/ROLL/CHANCE): FillBlockViews.swift:16–103 `EuclideousFillFieldTile`
  (OFFSET-look slider; full-strength lane value edge except bipolar-at-0 35 % — Paul's "full lane colour even when
  neutral"); tap halves FillBlock.swift:183–186; drag :189–191; double-tap reset :96.
- STDY/CLB chips: FillBlock.swift:141–149 text + cycle; FillBlockViews.swift:106–122 (13 pt, notched hit area).
- ORDER/HITS tap-to-cycle selectors: FillBlock.swift:152–179; FillBlockViews.swift:126–158.
- BREAK/LAND toggles: EuclideousPage.swift:4502+ `fillBoolTile` (the FLIP HITS look).
- Row-3 empty slot: FillBlock.swift:72 `L.spare = cell(3, 2)`.

## The fill engine as built
- Region/plan: FillRegion.swift:12–77 (`EuclideousFillRegion`, `EuclideousFillPlan`; region(bar:) gates armed + CHANCE).
- CHANCE: FillRegion.swift:80–84 (splitmix of (lane, bar), FILL-CHANCE salt). RUSH: :121–142 (x(y) + exact inverse).
- Forward step list/buffer: Router.swift `iterateTicks` fill branch (j0/N :2377–2379, scalars per slot :2414–2430);
  shuffle scratch Router:701 (`euclideousFillShufBuf`, 128 = `euclideousFillReverseCap`).
- ORDER: FillRegion.swift:148–159 (`euclideousFillSourceStep`; SHUFFLE seed :86–92; `euclideousFillOrderBuffered`
  :145 — ORDER ≠ FWD falls back to FWD above 128 slots).
- HITS: Router.swift:3778 (rawIsHit override by `euclideousFillHitsNow` 0/1/2) + :3950 (`advanceStep: … ||
  euclideousFillHitsNow != 0` — a non-KEEP region advances the walk **once per STEP**, sounding or not).
- Riff ordinal/rank in a region: the body's rank → `riffResolve(rank + euclideousFillRankOffsetNow)` at
  Router:4453/4566 (riff), :4617/:4673 (stack + deferred), :5059 (LISTEN-moved).
- RANKS shapes: FillRegion.swift:162–170 (CLIMB/ARCH/SHIFT). SWELL: :180–185, applied at the one velocity choke
  Router:2989. ROLL: :173–177 → nRep at Router:5198 (the shared ratchet path). BREAK: :188–190 → Router:2401.
- LAND: Router:2426–2430 (vel ×1.3, gate ×2 via :3859, force-hit) ; rejoin = the region's E (iterateTicks segments).

## The rank → pitch resolver
- `riffResolve(rank:oct:n:wrap:.fold:asc:)` Derivations.swift:1646–1660: **rank < 1 or an empty pool → nil → the
  note is silent** (THE empty-rank rule §2.3 adopts); fold wraps over the POOL SIZE n (+12 per lap) — the spec's
  "rank − 8, one octave up" equals it only when the pool has 8 notes; source wins, reported.
- Stack voices: `euclideousNotesHitPitches` Derivations.swift:9321+ — one [Int] of pitches per hit (each voice its
  own entry; `pitchOf(r) = riffResolve(rank: r, oct, pool)` :9333). **Rank 1 of the lane's stack resolves to the
  pool's lowest note + 12 × the stack's OCT** (PEDAL adopts this, at the stack's octave for both parts — judgment).
- The fill rank climb already applies to stack notes (Router:4617) and deferred same-slot notes (:4673).

## §4's look sources
- Rate grid: unselected #2A2D34 fill (`patternUnselectedFill` EuclideousPage:3135) + #AAB0BA text; selected =
  `lane20(accent)` fill + 1 pt `lane100(accent)` inner border + #F2F4F7 (directionRow :3756–3757, fillBarTile).
  (§5.1's NEW segment unselected look #22242A/#8A909A is the spec's own — new controls, not a redraw of these.)
- FLIP HITS: EuclideousPage.swift:3771–3789 (same selected/unselected pair). PLAY RIFF lamp:
  `euclideousPartPlayLook` + `EuclideousPartPlayLampShape` (used by the FILL tile :4488).
- EUCLID direction glyphs: `RiffDirectionIcon(kind: .backward/.pingpong/.forward)` (directionRow :3746–3767,
  stroke 1.75 round) — FWD/REV/BOUNCE reuse these per §4.3.

## Contradictions / discrepancies (spec said, code is)
1. **AMEND 1 doesn't exist** — its defaults land with THIS ferry: `fillSpeed` nil → ×1 (was ×2), `fillHits` nil →
   ALL (was KEEP). Sound-change window: a session with LIT BARS that never stored SPEED/HITS (nil) changes from
   a ×2 KEEP fill to a ×1 ALL fill. Factory presets store no fill → byte-identical.
2. **§2.2's "ordinal advances once per sounding forward step, as ALL and FLIP already do"** — as built, ALL/FLIP
   force the advance once per STEP (Router:3950), sounding or not (under FLIP a silenced hit-step still advances).
   BUILD is built on the SAME mechanism (mechanism parity; landed modes untouched): the region forces per-step
   advance; per slot k < h sounds iff the step is a hit, k ≥ h always sounds. A rest-step that sounds under BUILD
   plays the column the step-ordinal reaches — exactly ALL's rule.
3. The §2.3 wrap "above rank 8: rank − 8" — the engine's rule is fold over the pool size (riffResolve .fold);
   used as the code has it.
4. Three `EuclideousFillModelTests` were already red on main (8-bar-era expectations vs the 16-entry
   `fillBarsResolved`); updated to the current model as part of the model slice, reported.
5. §3.1's widths: 52 + 3 + 259 + 3 + 43 = 360 ✓ and §4.1's heights: 69.5 + 4 + 4×36 + 3×4.5 = 231 ✓ — the spec's
   reference arithmetic is self-consistent at the landscape content area (360 × 231; the real boxes are measured
   in §11.3 at build time).

## Build order (each green → commit; land at the end)
1. This findings doc. 2. Model (+the stale-test fixes). 3. Engine (STUTTER/BUILD/NOTES + scalars + sites) + tests
2–8. 4. The per-bar roll prediction (fill + NORMAL notes + skipped state) + test 9. 5. UI (layout/views/looks/
VoiceOver, hide the old) + test 10. 6. Proofs (golden + octaves-keep + alloc + targeted + iOS build), §11 report,
status log, pending tasks, debt, land.
