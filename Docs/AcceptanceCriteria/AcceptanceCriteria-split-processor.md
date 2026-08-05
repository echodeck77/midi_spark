# SPEC → Code — THE SPLIT (chain processor): set-membership semantics
# (2026-08-05 — answers Paul's behind-the-arp question)
_The returning chord-split/velocity-window, as a chain stage. The
law that makes it coherent at any chain position:_

## THE MEMBERSHIP LAW
SPLIT computes its subset from its INPUT SET at that chain position —
the literal simultaneous set upstream of the driver, **the driver's
source pool when downstream** — and passes/blocks each note by
MEMBERSHIP in that subset. Never per-singleton (TOP 1 of a chord of
one is degenerate); always set-relative. Derive-pure: the set is
already known at every beat.

## PARAMS
- SPLIT: ALL · TOP n · BOTTOM n · RANGE lo/hi (TOP/BOTTOM are
  POOL-RELATIVE; RANGE is absolute).
- VEL: floor / ceiling (per-note, position-independent).

## THE TWO PLACEMENTS (document as the teaching pair)
- **[SPLIT → ARP]** — RE-POOL: the driver walks only the subset
  (TOP 1 = pedal ticks · BOTTOM 2 = the low pair). Rhythm compresses
  to the smaller pool.
- **[ARP → SPLIT]** — PUNCH HOLES: the driver walks everything; only
  subset visits sound, filtered visits become RESTS — the pattern
  keeps its shape with gaps. Same notes, different music.
Factory pair when it ships: "PEAKS" [ARP up 1/16 → SPLIT TOP 1] ·
"LOW WALK" [SPLIT BOTTOM 2 → ARP up 1/8].

## Notes
- Generalises the standing downstream-fold law (harmonize blooms,
  chance dices, SPLIT filters — all per emitted note, set-informed).
- Replaces the door-side splits removed from the edit page; the
  door's RANGE (cog) remains the upstream window and is unrelated.
— design-side Claude

## CHORD CHANGES (Paul's question, pinned)
- TOP/BOTTOM RE-RANK against the live pool EVERY BEAT: the subset
  follows the harmony (Am's peak is E; F's peak is C — the split
  remembers "the highest," not the note). Kin to FOLLOW-echo.
- **Membership is evaluated AT ADMISSION** — sounding notes never
  lurch when the chord moves; new visits obey the new ranking.
- Hold-class chains ([PASS → SPLIT TOP n]) re-derive per beat and
  RECONCILE at chord change — shared notes continue, departed
  release, arrivals speak (the LEGATO reconcile machinery, reused).
- RANGE stays absolute (chord-agnostic on purpose — the not-following
  option); under KEY± notes may enter/leave an absolute window —
  correct and documented, not a bug.
- Uniqueness note for the record: upstream-style chord extraction has
  niche cousins; the DOWNSTREAM membership filter (rank-aware holes
  in a driver's walk) requires set-based derivation and is this
  instrument's own.
