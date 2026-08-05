# AcceptanceCriteria — THE TAIL ERA: the tail class → DELAY → ECHO (captured 2026-08-05)

**STATUS: CAPTURED, NOT BUILT (Paul's "go", but large).** From `BUILD-tail-era-delay-echo`, riding
`ANALYSIS-tails-beyond-the-column`. Processors that extend BEYOND the cell/column. Build order: the engine class →
DELAY (proving citizen) → ECHO (virtuoso).

## 0. THE ENGINE INCREMENT (once, for both + every future tail)
- **TAIL emissions**: scheduled beyond their activation window. Deriving beat B gathers activations in
  `(B − maxTail, B]` and emits their due tails. `maxTail` per stage (DELAY: TIME · ECHO: TIME×REPEATS), doc-capped at
  **2 passes** total span.
- **Discontinuity handlers LOOK BACK maxTail** (tests: seek-with-tails · loop-jump-with-tails · block-size invariance).
- **Scene-mortal + transport-stop KILLS tails** (v1).
- Tails are ADMITTED at the wire like fresh notes — **the roles eat echoes** (claimed/ducked/dealt) — and COUNT as
  the cell's sounding (the seal's spark rings with them).
- Budget: per-cell concurrent-tail cap; overflow drops oldest-quietest; decay floor kills (lossy-by-law).
- CPU: lookback re-derivation bounded by the 2-pass cap; profile on device before raising.

## 1. DELAY — the time-shift (one copy, displaced)
- **TIME**: musical divisions 1/32 … 2 bars (+ optional fine ms).
- The stage's input emits displaced by TIME (the whole voice late). Downstream stages fold onto the delayed notes
  normally (pure time math, any chain position).
- **The dry is slot-BLEND (PREV)**: PREV 0 = pure displacement (twins, one delayed = hocket-by-time) · PREV 100 =
  classic SLAPBACK · between = the mix.

## 2. ECHO — repeats with a soul
- **TIME** (divisions) · **REPEATS** (1–8) · **DECAY** (per-repeat velocity ×; floor kills) · **MODE: FOLLOW | KEEP**
  (pool-index re-resolved at the repeat's beat vs the struck pitch; oversize indices WRAP).
- Inherently dry+wet (original always passes; repeats add) — PREV blend n/a on ECHO.
- **SPREAD: MAIN | PING** — repeats ALTERNATE between MAIN and the ALT destination set (ping-pong across synths,
  wire-native; roles still eat every bounce).
- Factory pair: **"CANYON CALL"** [ARP → ECHO ×3 FOLLOW] · **"DUB TABLE"** [ECHO ×5 KEEP, DUCK on the lead].

## §4 TAIL ROUTE: CHAIN | DIRECT (per tail-producing stage; the pass-through always continues in-chain)
- **CHAIN (default)** — tails feed the NEXT stage (downstream folds them: gated/diced/bloomed tails).
- **DIRECT** — tails jump past remaining stages straight to the cell's OUTPUT stage (dest/chop/emitters/roles still
  apply; PING picks the destination, ROUTE picks the path). Covers the MIDDLE: `[ARP → ECHO(direct) → HARM]` =
  harmonized line, pure echoes — unreachable by reordering. DELAY DIRECT: downstream folds only the PREV blend.
- Manual line: "CHAIN feeds the tails to the next pedal; DIRECT sends them straight to the wire."

## ORDER
Class + tests → DELAY (validates crossing/seek/budget with ONE copy) → ECHO (repeats/modes/PING).
