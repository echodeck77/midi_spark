# AcceptanceCriteria — THE RACK (emitter treatment matrix)

Spec of record for the emitter-treatment rework. **Supersedes the tabbed emitter page**
(`AcceptanceCriteria-emitter-page-pass1.md`, `EmitterPage.swift` — both retired). Source: design ferry
`DESIGN-the-rack.md` (2026-08-04). The metaphor: each output has a RACK — pedals on the board (the matrix's
toggles) vs the loop switcher (the strip's enable button).

## BUILD STATUS
**ALL EIGHT PRIMARY TREATMENTS LIVE (2026-08-05, off-device: iOS builds + 424 macOS tests green; DEVICE pass owed).**
Pass 1 (2026-08-04) shipped the shell + two-tier gate + OWNS/KEY/TURNS. 2026-08-05 un-dimmed the rest —
CURVE · FENCE · MONO · POCKET · CONVERSATION. Only ECHO/CHOKE/GOVERNOR + secondary detail params remain dimmed.

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
- **THIS VOICE** (shapes the emitter's OWN notes): **MONO** · **FENCE** · **CURVE** · **POCKET**. *(all LIVE 2026-08-05)*
- **OVER OTHERS** (this emitter changes what OTHERS may do): **OWNS** (claim) · **KEY** (duck). *(LIVE)*
- **TOGETHER** (mutual arrangements): **TURNS** (alt) · **LEAD/STANCE** (conversation). *(all LIVE)*
A lit toggle always means "THIS COLUMN does the verb" — owns, keys, turns — never "is affected by it."

## §6 — THE TREATMENTS (toggle · chip · detail · readout). PASS-1 engine status in brackets.
- **OWNS (claim)** — owns its sounding pitch classes; others withheld or admitted as shadows per LEAK. Toggle OWNS ·
  chip **LEAK %** · detail SCOPE (CLASS | RANGE lo/hi) · RELEASE LAG · readout "OWNS 3 classes · leaks 20%".
  **[LIVE: toggle+LEAK backed by claimMask/claimLeak; detail = coming.]**
- **KEY (duck)** — while this emitter sounds, others' NEW notes arrive velocity-scaled down (admission-time; 100% =
  gate). Toggle KEY · chip **AMOUNT %** · detail DUCKS→B·C·D targets · ATTACK · RELEASE · MATCH-CLASS · readout
  "KEY: ducks B·C by 40%". **[LIVE: toggle+AMOUNT backed by flattenMask/flattenAmount; detail = coming.]**
- **TURNS (alt)** — the lit emitters **take turns IN TIME playing the INCOMING notes from ANY cell**. The turn
  advances once per articulation MOMENT (a new onset time); every note at that moment routes to the one turn-holder,
  then the next moment hands off to the next member. So two independent cells firing at the SAME instant both sound
  on ONE emitter and alternate over successive moments (A then B, not both at once); a single fan-out cell whose
  notes land at distinct times still ping-pongs per note. Non-group emitters in a fan-out are untouched. Toggle
  TURNS · chip **COUNT** = moments of DWELL before the turn passes (1 = hand off every moment) · **HAND-OFF mode**
  (global, in the TURNS detail): **PER MOMENT** (default) vs **PER NOTE**. **[LIVE: toggle+COUNT backed by altMask/
  altCount; mode = `turnsPerNote`. REVISED 2026-08-04: per-fan-out → whole-group; per-NOTE pointer → per-MOMENT
  hand-off. 2026-08-05: the PER-NOTE mode returns as an explicit EXCLUSIVE option (user) — the group's emitters
  never sound together; a note at the same onset as an already-played group note is DROPPED (leftmost wins), never
  delayed. Per-moment sends simultaneous notes to the one holder (both sound).]**
- **MONO** — forces monophony at this output; a new note STEALS per PRIORITY. Toggle MONO · chip **PRIORITY**
  (cycle LAST→LOW→HIGH). **[LIVE 2026-08-05: `monoMask`/`monoPriority`, rack-gated. `Router.emitOneBus` reads the
  emitter's current holder from the voice table; if the new note wins (LAST always / LOW keeps the lower / HIGH the
  higher) it closes the holder (own + All) at the new onset and opens the new (RETRIG). readout "MONO LAST".
  RE-STRIKE RETRIG|LEGATO detail = coming; chords churn re-strikes at onset (accepted v1).]**
- **FENCE** — a per-emitter note-RANGE policy on the OUTPUT pitch: notes outside [lo, hi] are DROPped (suppressed),
  CLAMPed (to the nearest bound), or octave-FOLDed back in. Primary = a **POLICY cycle chip** (DROP→CLAMP→FOLD);
  LO/HI note-steppers live in the DETAIL strip (live — the window is what makes FENCE act); the active range shows
  INLINE on the row ("C2–C6", user 2026-08-05 — the LO/HI were undiscoverable). **[LIVE 2026-08-05: backed by
  `fenceMask`/`fencePolicy`/`fenceLo`/`fenceHi`, rack-gated, applied in `Router.emitOneBus` on the fenced pitch.
  On ENABLE, a still-full window seeds a SENSIBLE default — policy CLAMP + C2…C6 — so FENCE audibly acts (user:
  "the defaults should be something more sensible"). readout "FENCE CLAMP C2–C6".]**
- **CURVE** — per-output velocity re-map (soft↔hard). Toggle CURVE · chip **AMOUNT** (−100…+100 bipolar knob; 0 =
  linear, + boosts low velocities = harder, − softens; `u' = u^(2^(−amt/100))`). **[LIVE 2026-08-05: toggle+AMOUNT
  backed by `curveMask`/`curveAmount`, rack-gated, applied in `Router.emitOneBus` before the master fader; readout
  "CURVE +30". FLOOR/CEILING detail = coming.]**
- **POCKET** — per-output timing feel: shift this output's notes a few ms ahead (push) or behind (lay-back). Toggle
  POCKET · chip **PUSH/LAG** (−50…+50 ms bipolar knob; − ahead, + behind). **[LIVE 2026-08-05: `pocketMask`/
  `pocketMs`, rack-gated. `Router.emitOneBus` shifts the note's on/off equally (duration preserved), clamped into
  the render window (push can't precede the window start; small offsets are exact — near a buffer edge it clamps).
  readout "POCKET −6ms". HUMANIZE detail = coming.]**
- **LEAD / STANCE (conversation)** — one emitter LEADs (radio, tap to set/clear); each other emitter's STANCE admits
  its NEW notes only WITH the lead's sound or AGAINST its silences (or FREE). Row 1: **LEAD** radio · Row 2:
  **STANCE** chip per non-lead column (FREE→WITH→AGAINST). **[LIVE 2026-08-05: `convLead`/`convStance` (stance
  rack-gated to FREE). `Router.emitOneBus` gates a follower's note-on on `emitterSounding(lead)` (WITH admits when
  the lead sounds, AGAINST when it's silent) — a live query like KEY; order-dependent at co-onset (the claim L1
  caveat). readout "AGAINST A" / "LEADS".]**
- **Dimmed future seats**: ECHO · CHOKE · GOVERNOR — labels reserved so the matrix never reflows.

## OUT OF SCOPE (later passes — un-dim a seat as each lands)
ECHO · CHOKE · GOVERNOR engines (still dimmed seats); all secondary detail params (claim scope/range/release-lag,
duck targeting/attack/release/match-class, curve floor/ceiling, mono re-strike RETRIG|LEGATO, pocket humanize).
**All eight primary treatments now LIVE** (OWNS · KEY · TURNS · MONO · FENCE · CURVE · POCKET · CONVERSATION —
CURVE/FENCE/MONO/POCKET/CONVERSATION landed 2026-08-05).
