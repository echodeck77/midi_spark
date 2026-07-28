# Design — SPATIAL ROUTING (the patch-bay projection), items 10/11c–11f (2026-07-28)
_Preserved from the ferry inbox. Refines item 10 (design-verb-rebuild-2026-07-27.md). Status: DIRECTIVE = build.
The engine/document already pay for it (per-source refcount, cycle-safe T11). Schema is a SET-capable ref already._

## The interface (10 + 11c UNIFICATION)
Wiring happens by POINTING AT THE WORLD, live whenever a **wiring-capable context** exists — a **PLACE hold** OR an
**active SELECTION** (one routing interface everywhere, not PLACE-only; the panel remains the escape hatch/display).
- **ROUTE IN** (the cell's source): the four RECEIVERS light (large) + candidate SOURCE cells light where they sit.
  **Single-select radio** — one input per cell; a new tap releases the old. The CURRENT source renders SOLID.
- **ROUTE OUT** (what the cell feeds): the EMITTERS light (multi-toggle, geographic) + candidate GRAFT targets below.
- The bands wear a SESSION FACE (large labelled in-hue targets) for the duration; revert on DONE; engine never pauses.

## 11f — HEADS LIGHT, BODIES DON'T (the precise offer rule)
- **No cell has a null input**: every input is a RECEIVER (a door A–D) or a ROW (⇐n, a chain member).
- **CHAIN HEAD** = a cell whose `inputRow == nil` (a root, hearing a door; a tree of one counts). **BODY** = `inputRow != nil`.
- **ROUTE OUT invites CHAIN HEADS below** (same column). Tapping a lit head **GRAFTS it and its ENTIRE SUBTREE under
  your cell** — set the head's `inputRow` to your row; its children (which reference the head's row) follow unchanged.
  Two chains become one: **chain composition as a one-tap power move**. Residue: a grafted head that was DELIBERATELY
  door-assigned drops that assignment (now row-fed) — the released door dims; undo behind it.
- **BODIES (row-fed) don't light** — mid-spine re-pointing ripples remotely; that surgery = SELECT the body (owner rule).

## 11e — THEFT IS UNOFFERABLE (curate the offer, don't announce the crime)
Only receiver-fed HEADS below are invitations (grafting a head steals nothing — its old source was the ambient door).
**Cross-chain re-pointing = SELECT the child and change ITS input** — the PROPERTY-OWNER PRINCIPLE as law: to change
X's wiring, select X. A released source dims briefly on any re-point (gentle feedback, not load-bearing).

## 11d — the frame + display law
- **DISPLAY ⊇ OFFER**: current wiring ALWAYS renders solid wherever it physically is (a climbing source below still
  shows lit when its cell is selected), even where the interface wouldn't OFFER it. Truth is never filtered; only
  invitations are curated.
- Three classes: IMPOSSIBLE (cross-column, empty sources — unofferable) · DISCOURAGED (climbs — panel hatch only) ·
  PERMITTED-WITH-TOOLS (spaghetti — answered by tints/map/FLOW). The interface STEERS, not stops.

## ROUTE IN sources (10 + 11f)
Candidate sources for cell X = the four RECEIVERS (always) + **OCCUPIED cells in rows ABOVE X** (same column; empties
don't light — nothing to hear). Single-select: tapping a receiver sets `inputRow=nil, inputReceiver=r`; tapping a cell
above sets `inputRow=thatRow`.

## v1 scope + testable model core (Code)
- MODEL (unit-tested, this increment): `isChainHead`, `graftHeadBelow(head, under:)`, `routeInReceiver`,
  `routeInRow`, `toggleEmitter`, and the candidate lists (`routeInSourcesAbove`, `graftHeadsBelow`).
- UI PROJECTION (next increment, device-iterated): the bands' session faces + the grid lighting (heads-below,
  sources-above, current-solid), the graft/route taps, the emitter multi-toggle. Big surface; needs device feel.
- Multi-input (10c): schema is already ref-capable; UI SINGLE-SELECT v1 (radio); multi = a later UI flip.
