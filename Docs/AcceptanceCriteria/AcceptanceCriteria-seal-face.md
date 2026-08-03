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

## B — HASH → SEAL (the generation — THIS is canon)
Via a **mulberry32 step PRNG** seeded by the hash (`SealRNG`) — every decision is a successive draw, so
the seal is reproducible from the hash. (The original `seal-glyph-mockup.html` never travelled and its
geometry was superseded by the device amendments below; per the design side it is HISTORICAL — the shipped
mulberry32 + amended geometry here ARE the frozen identity. The requirement was only ever INTERNAL
determinism: same config = same seal within the app, every device, forever.)
**B1. START — edge-biased (USER CHANGE, deviates from the mockup's `x=rnd()%3`).** Start on a LEFT/RIGHT
edge column (`x ∈ {0,2}`), `y = rnd()%3`. Then a FORCED first move horizontally inward. This guarantees the
route spans across the lattice so the seal uses the full LENGTH instead of hugging one side.
**B2. ROUTE.** Then ≤3 further orthogonal moves (≤5 nodes total). Per move draw `dir = rnd()%4` (0/1 = ±x,
2/3 = ±y); REJECT immediate backtrack (`dir == last^1`) and out-of-bounds, ≤8 rejection tries each; a
boxed-in move stops the route early.
**B3. CORNER BITS.** One hash word `round`; at interior node `i` the turn is a QUARTER-ARC iff
`(round>>i)&1` (arcTo, radius = 0.45 × pitch), else a sharp MITRE.
**B4. COIL.** Iff `hash%4==0` (and there are interior nodes): ONE open 300° circle (start angle 0.6 rad,
span 1.66π) of radius 2.1 × stroke, centred astride a mid-route node (index 1…len-2, from the next draw).
At most one, ever.
**B5. TERMINALS.** FILLED start dot (r = 1.15 × stroke) · ARROWHEAD at the end (length 2.5 × stroke,
±2.5-rad wings, filled), oriented by the last segment.
**B6. Pure geometry.** `sealGeometry(hash) -> SealGeometry {nodes, arcAtNode, coilNode}` in lattice space;
the SwiftUI layer (`sealLayout`/`drawSeal`) FITS the route's bounding box to the padded rect (independent
x/y scale) — so the seal fills the full length + height wherever the route sits (USER CHANGE — replaces the
fixed 0…2 lattice mapping; the visible-lattice option of §E is dropped as a consequence). Twins share one path.

## C — THE BADGE (cell face)
**C1.** Occupied cell face = **hue block (whose) · THE SEAL (which) · bus dots (where)**.
**C2. The plate (USER CHANGE — CENTRED + rectangular, was left-set square).** A rounded-square-cornered
engraved plate, CENTRED, filling the cell above the dots so it reads LANDSCAPE (wider than tall); corner
radius 8pt, fill ≈ 14% black + a 1pt inner hairline 10% black. The type emblem AND digest text RETIRE.
**C3. The seal inside** the plate: padding 16% of the shorter side; the route's bbox fits the plate (§B6),
so it fills the length. Stroke 2.4pt, round caps/joins, ink `rgba(12,12,16,0.8)`. NO lattice at cell size.
**C4. Bus dots** sit CENTRED at the foot (USER CHANGE — was bottom-right).

## D — THE COMET (motion = MIDI only; invisible = frozen)
**D1. Silent cell:** the seal renders STATIC at rest ink. No timers.
**D2. Note event.** ONE spark runs the wire. Its POSITION FREE-RUNS on a continuous clock (loops the path at
~0.9 lengths/sec), so a new note does NOT reset it to the start (USER FIX — it used to snap back each note).
Its LIFE is GATED by the per-cell note-on/off feed (`snapshotCellSounding` → `cellSoundingMask` →
`pollCellSounding`; a bit per cell with ≥1 active non-silent voice): while the note is HELD the spark is fully
alive — travelling for EXACTLY the sounding duration — then fades ~0.45 s from release. A pluck too short for
the 4 Hz gate still completes a ~1.1 s tail off its STRIKE feed (`cellStrike[64]` → `pollCellStrikes`), so
plucks aren't lost. Each strike RE-GLOWS the wire (+0.35α, ~450 ms) + sets the TRAIL length ∝ velocity. ONE
traveller per cell (budget law). **The coil-node slowdown** stays deferred polish (constant speed for now).
**D3. Death:** the spark fades (seal back to rest ink, frozen) ~1.1 s after the last event; backgrounded = frozen.

## E — THE EDIT PAGE (the large seal)
**E1. (USER CHANGE — MATCH THE CELLS.)** IDENTITY hosts the seal on the chosen-colour box, drawn to MATCH
the grid cells: a LANDSCAPE engraved plate with the SAME BLACK ink `rgba(12,12,16,0.8)` (was light
`rgba(236,234,223,0.9)`), stroke 2.8pt, NO visible lattice (was on). Same dimensions/aspect as a cell seal —
the selected-colour indicator and the cells now read identically.
**E2. Change:** on ANY config change, re-hash → re-route. Design target = arc-length resample old+new to
64 points and lerp ~400 ms. _CURRENT build: a simple ~250ms opacity CROSSFADE stands in; the per-point lerp
is deferred polish._
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
Built + off-device green (380 tests, iOS builds); DEVICE pass owed. Pure core `Derivations.sealHash` /
`sealGeometry` + `SealRNG`. Renderer `GridUI.sealLayout` / `drawSeal` (bbox-fit) + the cell BADGE (§C) + the
edit-page seal matching the cells (§E1). Comet `sealComet` (§D): free-run position + the note-on/off SOUNDING
GATE (`Router.snapshotCellSounding`/`cellSoundingMask` → `Kernel`/`AU.pollCellSounding` → VC edge-detect →
GridView), so the spark travels for exactly the held duration. Tests: 6 seal (Derivations) + 2 comet feed
(RouterTests: strike + sounding-gate). DEFERRED: the coil-node slowdown (D2), the 64-point re-route glide
(E2), and the edit-page audition comet (E3). (Mockup reconciliation is CLOSED — this build is canon.)
