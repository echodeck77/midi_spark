# SPEC → Code — MOD · SPAN + INTERNAL TARGETS (Paul, 2026-08-20:
# per-cell CC values + per-cell chain params — NOT a new
# processor; MOD grows two axes)

## §1 — STEPS gains SPAN
**SPAN: PERIOD (today) | ROW | ROW×2 | ROW×4** — the drawn steps
lock to the row's columns instead of the mod RATE's period:
- ROW = 8 values, one per cell/column (cell 1 holds its value or
  ramps toward cell 2's — GLIDE SMOOTH|STEP as today).
- ×2 / ×4 = 16 / 32 breakpoints ACROSS PASSES (the value
  sequence longer than the row; stepIndex = floor(beat×rate)%N —
  the polymeter law, replay-safe). The lap indicator marks which
  half/quarter is live.
- "Cycle from and to a value per cell" = adjacent breakpoints +
  SMOOTH — already the STEPS grammar; SPAN just re-anchors it to
  cell geography.

## §2 — TARGET gains THIS CHAIN
**SEND: CC# (today) | THIS CHAIN → [param picker]** — the picker
lists the chain's automatable params (the macro-authoring list,
reused: gate · rate · spread · …).
- Internal mode EMITS NO CC — it writes the param's OFFSET LANE
  (the macro offset engine: base ⊕ Σ; MEAN/last-writer laws
  apply; macros and MOD compose on one lane).
- MIN/MAX re-range as today (inversion free); ON EXIT
  (RESET|HOLD) applies to the offset.
- Boundary-deferred application per config-never-stops; the
  window shows the value curve against the row.

## §3 — Lineage notes (no double-builds)
- This partially lands the CC-RAIL birthstone's "mapped values →
  param addresses" half — note it in that roster.
- The parked AUTOMATION SWEEP (A→B over 8 passes, the OPEN file)
  is the SIBLING, not the same: the sweep = a one-way transition;
  this = a repeating per-cell texture. Both stand; neither
  absorbs the other.
— design-side Claude
