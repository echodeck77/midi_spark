# AcceptanceCriteria — THE SEAL (the derived cell face)
_From the design side (INSTRUCTIONS-implement-the-seal, 2026-08-02 — SUPERSEDES the ORBIT, which retires:
the lissajous + ratio table are gone). THE SEAL is a maze/route glyph DERIVED from a cell's behavioural
config, drawn on the cell. It REPLACES the type emblem + digest text on occupied faces (single-type faces
stopped being true once chains shipped). "The seal cannot be dressed." Pure derivation, document-visible
truth: same config ⇒ same seal on every device, forever. Twins share one cached seal path._

## A — THE GENERATING HASH (unchanged contract)
**A1. Behavioural config hash.** The seal derives from the SAME equality that defines TWINS:
- INCLUDED: chain (slots + params + per-slot bypass) · input source (receiver) · output (emitters +
  ALT set + the three CHOP masks) · triggers (when they re-host).
- EXCLUDED: colour, name, MUTE (chrome — a muted twin still twins), grid position.
**A2. Stable 32-bit hash.** Serialize the included config stably (JSONEncoder `.sortedKeys`) → 32-bit
FNV-1a (offset 2166136261, prime 16777619). Twins share one hash ⇒ share one seal. (`Derivations.sealHash`.)

## B — HASH → SEAL (the generation; reference = seal-glyph-mockup.html)
Via a **mulberry32 step PRNG** seeded by the hash (`SealRNG`) — every decision is a successive draw, so
the seal is reproducible from the hash. (The mockup HTML wasn't shipped to Code; the generation is ported
from the prose below. If the mockup's exact PRNG/proportions differ, reconcile — the GRAMMAR is fixed.)
**B1. START.** `x = rnd()%3, y = rnd()%3` on a 3×3 lattice.
**B2. ROUTE.** ≤4 orthogonal moves (≤5 nodes). Per move draw `dir = rnd()%4` (0/1 = ±x, 2/3 = ±y);
REJECT immediate backtrack (`dir == last^1`) and out-of-bounds, ≤8 rejection tries each; a boxed-in move
stops the route early.
**B3. CORNER BITS.** One hash word `round`; at interior node `i` the turn is a QUARTER-ARC iff
`(round>>i)&1` (arcTo, radius = 0.45 × pitch), else a sharp MITRE.
**B4. COIL.** Iff `hash%4==0` (and there are interior nodes): ONE open 300° circle (start angle 0.6 rad,
span 1.66π) of radius 2.1 × stroke, centred astride a mid-route node (index 1…len-2, from the next draw).
At most one, ever.
**B5. TERMINALS.** FILLED start dot (r = 1.15 × stroke) · ARROWHEAD at the end (length 2.5 × stroke,
±2.5-rad wings, filled), oriented by the last segment.
**B6. Pure geometry.** `sealGeometry(hash) -> SealGeometry {nodes, arcAtNode, coilNode}` in lattice space;
the SwiftUI layer (`drawSeal`) maps nodes → the rect (pitch = half the drawable span) and draws it. Cache
one path per unique hash — twins share it (×64 grid stays cheap by construction).

## C — THE BADGE (cell face)
**C1.** Occupied cell face = **hue block (whose) · THE SEAL (which) · bus dots (where)**.
**C2. The plate.** A rounded-square inset plate, LEFT-set: inset 6pt (top/left/bottom), width = height
(square by construction), corner radius 8pt, fill ≈ 14% black + a 1pt inner hairline 10% black — an
engraved plate on the hue. The type emblem AND the digest text RETIRE from the face.
**C3. The seal inside** the plate: padding 18% of badge width; pitch = (W − 2·pad)/2. Stroke 2.4pt, round
caps/joins, ink `rgba(12,12,16,0.8)`. NO lattice dots at cell size.
**C4. Bus dots** move to the bottom-RIGHT; the face's right region stays clear (future name/space).

## D — THE COMET (motion = MIDI only; invisible = frozen)
**D1. Silent cell:** the seal renders STATIC at rest ink. No timers.
**D2. Note event** (per-cell strike feed, `cellStrike[64]` → `pollCellStrikes`): ONE spark runs the wire
START→ARROW at ~0.9 lengths/sec; TRAIL length ∝ velocity; the seal ink BRIGHTENS by up to +0.35α on
strike, decaying ~450 ms. Re-strikes re-glow, never spawn a second spark (ONE traveller per cell; budget
law). **The spark slows to ~0.6× while crossing the coil node** (the one charm) — _deferred §5 polish;
current build runs a constant-speed spark._
**D3. Death:** the spark dies (seal back to rest ink, frozen) ~1 s after the last event; backgrounded = frozen.

## E — THE EDIT PAGE (the large seal)
**E1.** IDENTITY hosts the seal LARGE (a big plate beside the 4×4 hue picker): stroke 3.4pt, ink
`rgba(236,234,223,0.9)` on the panel plate, LATTICE VISIBLE (nine 1.6pt dots at ~20% alpha).
**E2. Change:** on ANY config change, re-hash → re-route. Design target = arc-length resample old+new to
64 points and lerp ~400 ms (terminals + coil crossfade the same window). _CURRENT build: a simple ~250ms
opacity CROSSFADE stands in; the per-point lerp is deferred polish. Cells: a 250ms crossfade suffices._
**E3.** While the audition loop runs, the big seal carries the comet too (same D rules). _Not yet built —
only the grid comet + the edit-page crossfade are live._

## F — TWINS + LIBRARY
**F1.** Twin-advertise (the whole-cell cyan pulse) is unchanged and now doubly legible: pulsing cells
VISIBLY share one seal. Border (selection dash) · fill (pulse) · ink (seal) never conflict — three layers.
**F2. Library:** NO seal in the library (machine-minus-routing has no full hash) — the library keeps its
text row; the seal appears the moment a library chain lands in a real cell.

## G — TUNING (pre-agreed)
If it under-reads on device: stroke weight, plate alpha, badge inset may be tuned. Freeze the §B constants
once device-approved. NEVER tune: hue tint, autonomous motion, user editing.

## Implementation status (2026-08-02)
Built + off-device green (379 tests, iOS builds); DEVICE pass owed. Pure core `Derivations.sealHash` /
`sealGeometry` + `SealRNG` (6 tests). Renderer `GridUI.drawSeal` / `sealNodePoints` + the cell BADGE (§C)
+ the edit-page large seal (§E1) + the `sealComet` (§D, constant-speed). DEFERRED: the coil-node slowdown
(D2), the 64-point re-route glide (E2), the edit-page audition comet (E3), and reconciliation with the
mockup's exact PRNG/proportions once the HTML is shipped.
