# AC — MOD finishing for launch (design-cc-stage; Paul 2026-09-09)

STATUS: BUILT (branch `feature/mod-finishing`; iOS builds, macOS green incl. fuzz; the CC feel is DEVICE-owed). MOD
already functioned (all 5 sources + MIN/MAX + SPAN + CC/CHAIN targets, tested); Paul's launch pick = **FREE/LFO cell +
refinements** (not the tactile fader or the ownership pin).

## Built
- **FREE / THE LFO CELL (§16):** `modFree` — a MOD slot speaks EVERY window regardless of the playhead (the grid becomes
  a mod-matrix: place a modulation-only cell beside music cells). Engine: `emitFreeMod` (scans all cells once per window,
  beat-derived so replay-safe/block-invariant; active-column FREE slots skipped in `emitColumnMod` → no double-emit; no
  leave-disposition — a flush stops it). CC targets only (a FREE chain-target has no active column to fold into — v1).
  UI: SPEAK = ON PLAYHEAD | FREE (LFO). +RouterTest (a FREE MOD in column 3 speaks while column 0 is active; a scheduled
  one is silent).
- **QUANTIZE (§14①):** `modQuantize` — snap the output to N evenly-spaced levels (bit-crush for control / stepped
  sweeps). Pure `modQuantizeValue` + test; applied in both emit paths. UI: QUANTIZE ◀OFF/N LVL▶.
- **PHASE (§14②):** `modPhase` — a 0–360° offset on the SHAPE wave (two cells' sines in quadrature → rotary panning).
  Applied at the SHAPE + EXTERN-SCALE call sites. UI: PHASE slider (SHAPE only).
- **EXTERN SCALE (§6):** `modExternMode` RE-EMIT | SCALE — SCALE makes the incoming CC scale the cell's SHAPE depth
  ("rhythm from us, amount from the wheel"). UI: MODE seg on the EXTERN source. (Device-owed — needs live incoming CC.)

## DEFERRED — with reason
- **FOLLOW averaging WINDOW (§1):** a true time-average of the sounding material (event-rate density over 1/4…2 bars)
  requires POOL/EVENT HISTORY accumulated across renders — which violates architecture invariant 2 (derived, never
  accumulated). It needs a sanctioned mutable-state exception (like the note tracker), a design decision, not a quick
  refinement. v1 FOLLOW stays instantaneous (pool fullness). Flagged for Paul: sanction the state exception, or leave it.
- The tactile curve-as-fader (§2①) and the ownership/strip pin (§5/§8) — not in this launch pick.

## Device-owed
The CC feel (does the LFO cell modulate the synth as expected, EXTERN SCALE with a real wheel, QUANTIZE steppiness) is
device-only — the engine paths are beat-derived + tested, the audition is Paul's.
