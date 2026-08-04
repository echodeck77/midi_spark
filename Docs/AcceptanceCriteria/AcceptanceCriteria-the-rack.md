# AcceptanceCriteria — THE RACK (emitter treatment matrix)

Spec of record for the emitter-treatment rework. **Supersedes the tabbed emitter page**
(`AcceptanceCriteria-emitter-page-pass1.md`, `EmitterPage.swift` — both retired). Source: design ferry
`DESIGN-the-rack.md` (2026-08-04). The metaphor: each output has a RACK — pedals on the board (the matrix's
toggles) vs the loop switcher (the strip's enable button).

## BUILD STATUS
**PASS 1 BUILT (2026-08-04, off-device: iOS builds + 415 macOS tests green; DEVICE pass owed).** The full RACK
shell + the two-tier gate + the three engine-backed treatments' PRIMARY controls. Everything else is a dimmed
"coming" seat (its engine is a later pass). User-confirmed scope.

## 1. THE STRIP GOES CLEAN
Per-emitter strip tenants, final: **OCT± · velocity bar · LIVE · SOLO · RACK**. Nothing else. RACK is one button:
**tap = toggle the board in/out of the signal path** (lit cyan = rack in path; outlined = raw wire), **long-press =
open the matrix (SETUP)**. Fallback if the tap/long-press combo tests poorly on device: two small buttons SETUP·ON
(noted, not built). The CLAIM/DUCK/ALT role buttons are RETIRED from the strip (they move into the matrix).

## 2. SETUP = THE RACK MATRIX (a grid overlay, per the overlay rule)
- Drawn **INSIDE the grid's cell area** (user instruction 2026-08-04): the chevron column-key row and the L/R row
  rails STAY framing it; only the 8×8 cell body is replaced. (Impl: `GridView.cellAreaOverride`.) The strips + master
  stay live around it. DONE returns; scene-switch closes; EDIT-toggle closes; one overlay at a time.
- **Four COLUMNS = the emitters A–D** (header: hue dot · A–D · ch · mini-meter; a rack-off column reads **RAW**).
  **ROWS = the treatments**, grouped by three families (§5).
- Each row×column = an **on/off toggle** with the treatment's **PRIMARY PARAM as a rotary knob directly beneath**
  (270° gauge + pointer; vertical drag turns it — user 2026-08-04, rotary over a slider for legibility),
  column-aligned, no row-selection step (the flat law). TAP a column header → its social-sentence readout.
- **Row labels are DESCRIPTIVE** (user 2026-08-04, space traded for legibility — wide label column, narrow emitter
  columns): OWNS reads **"Claims this note from others"**, KEY reads **"Ducks others' velocity"**, TURNS reads
  **"Takes turns with others"** (TURNS wording is Code's pick — confirm/rename). The canonical short names
  (OWNS/KEY/TURNS) remain the identity in the readout + spec.
- **DETAIL STRIP below the matrix** follows the last-touched row (four columns). PASS 1: the live rows' secondary
  params are named but dimmed ("coming").

## 3. THE TWO-TIER LAW (the language, stated for the manual)
- Matrix toggles = **which pedals are on the board** (armed).
- Strip RACK = **is the board in the signal path**. RACK off ⇒ the wire is raw regardless of the matrix; RACK on ⇒
  exactly the armed treatments apply.
- LIVE/SOLO unchanged and senior (the kill-switch law: LIVE off silences everything, rack or raw).
- **Engine**: `PluginState.rackEnabledMask: UInt8?` (nil ⇒ 0b1111, all in path — old-doc/clean-instrument safe). The
  builder **pre-ANDs** it into `claimMask`/`flattenMask`/`altMask` before they reach the render box (`rackMask` also
  carried in the box for future self-affecting treatments). Router unchanged. AU: `uiRackMask()`/`setRack()`.
  Tests: `RouterTests.testRackOffMakesClaimantARawWire`, `testRackOnKeepsClaimSuppression`,
  `testRackGatePreAndsTreatmentMasksIntoTheBox`.
- **DEVICE VERIFY (open reading):** RACK-off on an emitter is treated as a FULL-COLUMN bypass — it suspends BOTH the
  treatments that shape that emitter's own notes AND the treatments it imposes on others (its OWNS suppression, its
  KEY duck), since those are *its* pedals. Confirm this is the intended feel; the alternative (RACK gates only
  self-affecting treatments, leaving OWNS/KEY acting on others) is a one-line builder change if wanted.

## 4. Superseded / retained
- SUPERSEDED: the A–D tabs · the per-emitter page scroll · roles living on the strip (moved to the matrix).
- RETAINED: the relationship READOUT (one line, on a column-header tap) · live-and-undoable, no transaction ·
  chrome-quiet (off rows recede).

## §5 — THE THREE FAMILIES (matrix row grouping)
- **THIS VOICE** (shapes the emitter's OWN notes): MONO · FENCE · CURVE · POCKET. *(all dimmed, pass 1)*
- **OVER OTHERS** (this emitter changes what OTHERS may do): **OWNS** (claim) · **KEY** (duck). *(LIVE)*
- **TOGETHER** (mutual arrangements): **TURNS** (alt) · LEAD/STANCE (conversation). *(TURNS live; LEAD dimmed)*
A lit toggle always means "THIS COLUMN does the verb" — owns, keys, turns — never "is affected by it."

## §6 — THE TREATMENTS (toggle · chip · detail · readout). PASS-1 engine status in brackets.
- **OWNS (claim)** — owns its sounding pitch classes; others withheld or admitted as shadows per LEAK. Toggle OWNS ·
  chip **LEAK %** · detail SCOPE (CLASS | RANGE lo/hi) · RELEASE LAG · readout "OWNS 3 classes · leaks 20%".
  **[LIVE: toggle+LEAK backed by claimMask/claimLeak; detail = coming.]**
- **KEY (duck)** — while this emitter sounds, others' NEW notes arrive velocity-scaled down (admission-time; 100% =
  gate). Toggle KEY · chip **AMOUNT %** · detail DUCKS→B·C·D targets · ATTACK · RELEASE · MATCH-CLASS · readout
  "KEY: ducks B·C by 40%". **[LIVE: toggle+AMOUNT backed by flattenMask/flattenAmount; detail = coming.]**
- **TURNS (alt)** — the lit emitters form a ring and **take turns playing the INCOMING notes from ANY cell**: any
  note destined for a group member is routed to the current turn-holder (the whole-group rotation), then the turn
  advances — so two independent cells (one → A, one → B, both in TURNS) POOL and interleave across A and B, and a
  single cell targeting only A still spreads across the group. Non-group emitters in a fan-out are untouched. Toggle
  TURNS · chip **COUNT** (notes-per-turn) · detail RING · RESET-at-pass · readout "TURNS (count 2)".
  **[LIVE: toggle+COUNT backed by altMask/altCount. REVISED 2026-08-04 — was per-fan-out only (dealt only among the
  members present in one cell's fan-out), which left single-target cells stuck on their own emitter; now the whole
  group shares the incoming stream. detail = coming.]**
- **MONO** — forces monophony; priority LAST|LOW|HIGH; RE-STRIKE RETRIG|LEGATO. **[NO ENGINE — dimmed seat.]**
- **FENCE** — out-of-range notes DROP|CLAMP|FOLD; lo/hi. **[NO ENGINE — dimmed seat.]**
- **CURVE** — per-output velocity re-map (soft↔hard, bipolar); floor/ceiling. **[NO ENGINE — dimmed seat.]**
- **POCKET** — per-output timing feel (±ms push/lag) + humanize. **[NO ENGINE — dimmed seat.]**
- **LEAD / STANCE (conversation)** — one LEAD (radio); others FREE|WITH|AGAINST. **[NO ENGINE — dimmed seat.]**
- **Dimmed future seats**: ECHO · CHOKE · GOVERNOR — labels reserved so the matrix never reflows.

## OUT OF SCOPE (later passes — un-dim a seat as each lands)
MONO · FENCE · CURVE · POCKET · CONVERSATION engines; all secondary detail params (claim scope/range/release-lag,
duck targeting/attack/release/match-class, alt rotate|deal/ring/reset). Each = new model + box + builder + Router +
AU setter + tests.
