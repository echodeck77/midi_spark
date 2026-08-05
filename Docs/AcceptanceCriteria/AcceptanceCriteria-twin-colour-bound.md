# AcceptanceCriteria — TWIN RULING: colour-BOUND twins, colour-blind seals (captured 2026-08-05)

**STATUS: RULING CAPTURED, NOT BUILT.** Design-side ruling (`REPLY-twin-ruling-colour-bound`) resolving the twin
identity question. Spec-of-record for when twin editing / seal caching is next touched.

## THE RULING
- **Twins = behavioural equality AND same `colourID`.** Editing one twin propagates to the group; a different-hue
  cell with identical machinery is NOT a twin (it was separated on purpose — hue = the user's grouping intent).
- **Seals = behavioural only (colour-blind).** The seal says WHICH machine; hue says WHOSE. Two same-machine
  different-hue cells RHYME (same seal) but edit independently. **Rhyme ≠ twinhood** — the seal only promises truth,
  never group-editing.
- **RECOLOUR = DETACH** (name it in the docs): repaint one twin → it leaves the group with machinery intact. The
  cheap un-twin gesture the model lacked.

## IMPLEMENTATION NOTES (design's steer)
- The twin hash: a stable **FNV** over the behavioural serialization, **CACHED per cell** (invalidate on edit), with
  `colourID` as the twin PREFILTER. **No JSONEncoder on the render/UI hot path** (this was my flagged perf blocker).
- Seal geometry stays as-is; if Paul re-sees same-seal-different-output on device, treat as GEOMETRY ALIASING
  (nearby hashes → similar 3×3 mazes) and send a repro for geometry hardening (the ambient/alien-circuitry revisit
  would raise visual entropy).

## RELATED
- The seal hash + twin-contract tests already exist (`testSealHashCoversTheFullTwinContract`,
  `testSealDistinguishesWhichSingleEmitter`). This ruling adds the colourID prefilter + the cached-FNV twin hash.
