# INSTRUCTIONS → Code — THE CC STAGE + THE TACTILE STACK + ROUTING
# (2026-08-09 · captured for the shelf; sequencing at the end)

## 1. THE CC STAGE (a chain processor; emits control, not notes)
- **Header**: type name + **TARGET chip** — the named dozen (1 MOD ·
  2 BREATH · 5 PORTA-TIME · 7 VOL · 10 PAN · 11 EXPR · 64 SUSTAIN ·
  65 PORTA · 71 RESO · 72 REL · 73 ATK · 74 BRIGHT · 91 REVERB ·
  93 CHORUS) + CUSTOM 0–127. The blend strip DIMS (no notes flow).
- **SOURCE radio (always visible)**: **SHAPE · FOLLOW · STEPS ·
  STRIKE** — the stage's spine; row 2 reshapes to it:
  - SHAPE: WAVE (sine·tri·square·ramp·S&H) · RATE (×8…÷8, musical)
    · **the standing phase law** (RETRIG | LEGATO | FREE at column
    entry — as arps).
  - FOLLOW: WHAT (DENSITY · REGISTER · COUNT · VEL) · WINDOW
    (averaging span, 1/4…2 bars).
  - STEPS: the 8-bar mini-row (drag to draw) · RATE · SMOOTH|STEP.
  - STRIKE: ATTACK · RELEASE chips (per-note AR on the CC) ·
    vel-scales-depth toggle.
- **Row 3, universal**: **MIN / MAX chips (0–127)** — range IS
  depth and polarity (MIN 90 / MAX 20 = inversion; no invert chip
  ever) · **DEST: MAIN | ALT**.
- **The face**: an S-size WINDOW in the header drawing the LIVE
  curve against the beat (the component exists; a CC stage's truth
  is its curve).
- Inherited laws: the expression scheduler · ~150Hz only-on-change
  decimation · per-emitter ownership while active (external CC
  passes when idle; last-writer + tell).

## 2. THE TACTILE STACK (punch-in/out; the performance chapter)
- **① THE CURVE IS THE FADER**: the stage's window is TOUCHABLE —
  finger position OVERRIDES the source while touching; the machine's
  curve ghost-draws underneath; release SPRINGS back. (The macro
  touch-law verbatim: the hand outranks the machine while touching.)
- **② CC PUNCH (trigger action)**: HOLD roster gains CC PUNCH
  [target · value] — hold the cell, the CC slams to value; release
  returns. One finger punches notes AND tone.
- **③ BUTTON STABS, free**: MIN/MAX are macro-able params —
  BUTTON+spring macro = the filter stab / trance pump, no new
  machinery.
- **④ RETURN (one new chip, shared by all punches)**: glide-back
  time on release (0 = snap · else the value closes over a musical
  division). The difference between a punch and a phrase.
- **⑤ DEFERRED, on record**: the XY popup (two CCs, one thumb,
  touch-in spring-out). Real; waits until ①–④ prove what hands
  reach for.

## 3. ROUTING GUIDANCE (Paul's channel question, ruled)
- **Synth-native CCs (the dozen): SAME CHANNEL AS NOTES — the
  default, zero setup** (CC interleaves with notes; synths expect
  it). Doc lines: CC is CHANNEL-WIDE (one cell's CC stage
  modulates every note on that emitter — inherent, usually
  wanted); two authorities on one CC fight last-writer (our
  ownership pin covers our side).
- **Host-parameter control (AUM faders · FX · any AU param): THE
  DEDICATED CONTROL WIRE** — recommend one emitter (e.g. D) → AUM
  MIDI Control; bindings stay singular, synth channels stay clean,
  the monitor gets a separate lane. Manual caution: prefer CC11
  for phrase dynamics at the synth; drive MIX levels via AUM
  faders through Control (CC7 at the synth = two volume
  authorities).

## 4. SEQUENCING
The expression scheduler builds ONCE → **CC stage first** (the
simplest citizen: SHAPE/FOLLOW/STEPS need no per-note scheduling)
→ BEND → GLIDE. STRIKE mode lands with the per-note machinery
BEND brings. Shelf status: captured, not urgent; jumps when Paul
sequences the expression era.
— design-side Claude

## §5 — INBOUND CC POLICY (Paul: strip, override, or transform?
## Answer: ALL THREE, scoped — 2026-08-09)
- **PASS (the default)**: idle addresses forward per the
  controller-routing v1 spec (per-door CONTROLLERS→mask, re-stamped
  to emitter channels). Mod wheels just work; never blanket-strip.
- **STRIP = OWNERSHIP-SCOPED** (the standing pin, extended from
  bend to every CC): while our stage is ACTIVE on (emitter, CC#),
  it OWNS that address — incoming CC to the same address DROPS;
  when idle, it passes. Override and strip are one law seen from
  two sides; the tell shows ownership.
- **TRANSFORM — the star, two homes**:
  ① **SOURCE: EXTERN on the CC stage** (the fifth radio value,
  when built): the stage READS an incoming CC and re-emits it
  transformed — re-ranged via MIN/MAX (inversion free), re-TARGETED
  (wheel-in CC1 → brightness-out CC74), re-curved, decimated. The
  hardware wheel becomes material our machinery shapes; the window
  shows in-vs-out.
  ② **CC-IN → THE MACRO BANKS** (the rail's ruled destiny, Macro
  Main tab era): hardware knobs ride the macros — one mapping,
  every bound target, spring semantics from the touch-law.
- CC64/120/123 keep their special rulings (forward · flush+forward)
  unchanged.
One manual line: "Incoming control passes through untouched — until
one of our machines is speaking on that address, or you point a
machine at it and make it raw material."

## §6 — TWO ADDITIONS (Paul, 2026-08-09)
- **EXTERN × RHYTHM (the wheel's marriage)**: EXTERN gains a role
  beyond re-emit — **DEPTH-SCALER over another source**: a SHAPE or
  STEPS pattern supplies the rhythm; the incoming CC (mod wheel)
  scales its depth live. "Gate pattern from us, amount from the
  left hand." One chip on the stage when EXTERN lands: MODE:
  RE-EMIT | SCALE [source].
- **★ MACRO CC COMPANIONS (the A/B inference — buildable as
  heuristics)**: the authoring flow READS the sparse delta's PARAM
  SEMANTICS (duration · density · register · dynamics · sparsity —
  a static tag per param kind) and consults THE COMPANION TABLE →
  offers a one-tap chip ("SUGGESTED: +REVERB" · "+RELEASE" ·
  "+BRIGHT"). Accepting ADDS the CC delta to the SAME binding —
  one fader moves music and tone together. Honesty bounds: we
  infer from param meaning, never sound (we're MIDI); suggestions
  only, never automatic; the table is authored taste (the dice-
  distributions discipline — one table, printable in the manual).
  Seed pairings: gate/length ↑ → +CC91/+CC72 · rate/chance-density
  ↑ → +CC74 · oct/register ↑ → +CC74 · velocity-ish → CC11 ·
  sparsity ↑ → +CC91.

## §7 — THE RAIL ARCHITECTURE (Paul's plumbing question, settled:
## READ AT SOURCE, REAPPLY AT EXIT — never through the pipeline)
**The model**: incoming CC lands in a PER-DOOR VALUE STORE; a SIDE
RAIL forwards door→emitter per the routing mask, re-stamped, with
its own decimation. The note pipeline never carries control.
**Why (the six reasons)**:
1. **The engine stays a pure note function** — no per-stage CC
   forwarding semantics, no ordering swamp across 13 types.
2. **Timing sanity** — the rail runs at wire rate; threading CC
   through column derivation would quantize your wheel to ticks
   (steppy, laggy).
3. **No duplication** — one door feeds many cells feeds many wires;
   through-the-chain = N copies of the wheel per wire. The rail =
   one re-stamp per (door, emitter) pair, deduped by construction.
4. **Ownership stays one gate** — the active-stage-owns pin sits at
   the EXIT; in-pipeline would need per-stage resolution.
5. **Chains still get CC where wanted — as a TAP, not a thread**:
   EXTERN reads the value store as an input (f(state, pool, beat,
   controls) — derive-safe; the wheel becomes an input like the
   pool). Stages opt in; everything else never sees control.
6. **Nothing is lost** — channel CC is per-wire by protocol anyway;
   per-note association is MPE's business (the birthstone).
**Replay honesty**: external CC = an input stream; determinism =
same inputs, same output. Capturing/replaying that stream is the
bounce era's job, cleanly separable because the rail is one place.

## §8 — THE COLLISION MATRIX (incoming CC × generated CC, settled)
- **Different CC#s (Paul's case): both flow, no interaction.** The
  rail forwards the wheel's CC1; our stage emits its CC74; the wire
  interleaves them like any MIDI stream (per-address decimation).
  They only ever MEET if the user opts in (EXTERN scaling — §6's
  marriage), which is a feature, not a fight.
- **Same CC#, same emitter: the OWNERSHIP pin** — while our stage
  is ACTIVE on (emitter, CC#), incoming to that address DROPS at
  that exit; when it idles, incoming resumes. **ACTIVE defined**:
  the stage exists un-bypassed and its cell is reachable (the
  liveness function) — a ÷8 sine owns BETWEEN its emissions too;
  ownership is presence, not per-message. The tell shows it.
- **THE HANDBACK (new, small, kind)**: on ownership RELEASE, the
  exit re-emits the CURRENT incoming value once — the wire syncs
  to the wheel's truth instead of jumping from our last value at
  the synth. (Acquire needs nothing: our first emission supersedes
  naturally.)
- **Same CC#, different emitters**: no collision — different
  wires/channels; per-emitter scoping does all the work.
- **Door vs door** (two doors forwarding one CC# to one wire): the
  routing masks are the tool; unmasked overlap = last-writer at
  the rail, documented.

## §9 — CHAINING CC STAGES: THE INTERNAL BUSSES (Paul, 2026-08-09)
**The one addition**: TARGET gains **BUS A–H** (virtual addresses,
never on the wire) and EXTERN's source chip speaks them too.
Generated control becomes readable like incoming — CC stages patch
through the store, and the modular idioms arrive free:
- **DEPTH MODULATION**: stage 1 (sine ÷4) → BUS A; stage 2's EXTERN
  SCALE mode rides its square's depth from A — the wobble that
  swells on the slow wave.
- **★ STRIKE-SAMPLING**: stage 1 (continuous sine) → BUS A; stage 2
  in STRIKE mode sampling A per note-on → **the sweep quantized to
  the melody** — arpeggiated filter steps, rhythm-locked, the S&H
  patch every modular owner knows, from two chips.
- **SLEW**: a stage whose only job is EXTERN-in → glide → out
  (RETURN's math reused) — the lag processor; put it after a
  square and the gate becomes a breath.
- **MIX on shared targets** (same cell, same target driven twice):
  the later stage gains MIX: REPLACE | ADD | SCALE — sine + S&H
  jitter = the organic wobble; clamped at the rails as ever.
- **The reverse direction already exists**: CC→notes runs through
  the macro rail (CC-in rides macros rides any param) — so the
  full loop is closed: notes→CC (FOLLOW) · CC→CC (busses) ·
  CC→notes (macros).
- **The one law**: the bus graph is ACYCLIC v1 (binding that would
  cycle is refused with a tell) — patching, not feedback; the
  screaming-modulator era can apply for a birthstone later.

## §10 — SCOPE CORRECTION (Paul's catch, 2026-08-09: machines don't
## interact with machines — §9's busses were scope-creep)
- **BUSSES ARE PER-CELL.** A chain may hold multiple CC stages;
  BUS A–H patch AMONG THEM, inside the one machine. Every §9 idiom
  survives unchanged (depth-mod · strike-sampling · slew · mix are
  all two-stages-one-chain). No cell ever reads another cell's
  bus — the cell-machine law holds at the control layer too.
- Cross-cell coupling remains where it always was: shared INPUTS
  (all cells may read the same door's wheel — shared source, not
  interaction) and the wire's roles (admission-time, at the exit).
- **If cross-machine control is ever wanted: it becomes A DOOR**
  (the tails-door precedent — a CONTROL DOOR cells may listen to).
  Birthstone, not v1, and never busses.
- For the record: this was my scope-creep, caught by Paul — the
  architecture's owner outranking the architect's enthusiasm, as
  designed.

## §11 — THE REST OF THE WIRE (taxonomy handling + two gems)
**Rail handling table**: Channel Pressure = forward like CC (the
controller family) · Poly Pressure = parked with MPE · PC/Bank =
pass on THRU (+ the gem below) · CC121 Reset All Controllers =
forward AND reset our value stores · Clock/Start/Stop/MTC/SPP =
the host's, ignore · Active Sensing = drop · SysEx = THRU-pass
only.
**★ GEM 1 — SCENE → PROGRAM CHANGE**: per-emitter optional PC
(+Bank) per SCENE — scene switches change the SYNTHS' PATCHES:
the arrangement re-voices the whole rig on the lap. Three chips
per emitter per scene (bank·PC·on/off), enormous payoff, pure
config. Shelf candidate.
**★ GEM 2 — THE RPN HANDSHAKE**: emit RPN 0 (pitch-bend range) to
SET the synth's range to match GLIDE/BEND's RANGE param — the
"must match the synth" doc caveat becomes a button ("SET SYNTH
RANGE") or an automatic on-activate courtesy. Kills the
mis-tuned-slide failure class for every synth that honours RPN
(most do). Rides with the expression era.

## §12 — THE KILL MESSAGES AS INSTRUMENTS (Paul, 2026-08-09:
## creative 123/120)
- **As CC-STAGE TARGETS**: the target chip gains **KILL·SOFT (123,
  voices release naturally)** and **KILL·HARD (120, immediate
  silence)**. STEPS pattern of hard-kills = rhythmic voice-chopping
  on the wire — the transform-gate for synths with NO gate input;
  SHAPE square at 1/8 = tremolo-by-execution; euclid-masked kills =
  syncopated cuts. Value semantics: any emission fires the message
  (MIN/MAX dim — kills have no amount).
- **THE CHOKE PUNCH**: a trigger/HOLD action + BUTTON-macro action
  **KILL [wire · soft|hard]** — the DJ cut, per emitter: harder
  than MUTE (mute stops admissions; KILL silences what's SOUNDING).
  This also gives the rack's future CHOKE-GROUP seat its cheap
  implementation (choking B = one 120 to B's channel).
- **THE BOOKKEEPING LAW**: emitting 120/123 on a wire clears OUR
  refcounts for that channel at the same timestamp (forced-off
  reconciliation) — the engine's books and the synth's silence
  never disagree.
- **The exception, named**: KILL deliberately violates sounding-
  notes-never-lurch — that is its entire point. Documented as the
  ESCAPE class: user-invoked violence, never engine-invoked.
  Manual line: "MUTE stops the future; KILL stops the present."

## §13 — PAIRING LORE · THE MULTI-WRITER LAW · THE AUTO MASK
## (Paul's three, 2026-08-09)
- **Pairings for the companion table (with / AGAINST)**: 74+71
  together = the squelch · BRIGHT with register = natural, AGAINST
  = the eerie inversion · EXPR with density = swells, against =
  fade-under-the-fill · **REVERB AGAINST DENSITY** (the king:
  space blooms in the gaps, dries in the thick — the mix law,
  automatable because density is measured) · PAN alternating with
  TURNS (the stereo follows the dealing) · RELEASE with
  gate/length (wash ↔ tight).
- **GENERATED×GENERATED, same (emitter, CC#): MEAN of active
  writers** at the exit per block — commutative, deterministic,
  never saturates; multi-writer tell on the stages. (SUM-CLAMP =
  the noted alternative if mean feels weak on device. Last-writer
  refused: order-dependent churn.)
- **THE AUTO MASK (the decoupling healed)**: the per-door
  CONTROLLERS→ mask gains **AUTO (default): forward to the
  emitters this door's cells CURRENTLY FEED** (live-derived) —
  control travels WITH its music by construction. The manual mask
  remains as the override (the dedicated control-wire rig).
  Receivers and emitters stay decoupled for NOTES (cells are the
  coupling, as designed); AUTO makes control honour that same
  coupling instead of bypassing it.

## §14 — THE MOZAIC SURVEY ABSORB LIST (Paul, 2026-08-09; from ~40
## patchstorage scripts — 85% already inside this file's design,
## which is the market validating the stage+rail. The six worth
## absorbing, all chip-sized:)
① **QUANTIZE chip** (from "Joc CC quantiser"): output snaps to N
levels — bit-crush for control; stepped filter sweeps from any
source. ② **PHASE chip on SHAPE** (from "PhaseCCMaker"): 0–360°
offset — two cells' sines in quadrature = rotary panning, phased
wobbles. ③ **RELATIVE decode, per door** (from "RelativeCC"):
endless-encoder ±increments handled at the value store — hardware
knobs with no absolute position just work. ④ **EXTERN sources gain
AT + PB** (from the aftertouch/PB converters): pressure and bend as
raw material for re-targeting — press harder, open the filter, via
our curves. ⑤ **EXTERN CURVE option** (from "CurveMaker"): a drawn
transfer function (the STEPS mini-row reused as an 8-point curve)
between in and out. ⑥ **STRIKE → ADSR, later** (from "MIDI ADSR"):
decay+sustain chips when per-note depth is wanted; AR ships first.
Meta-note for the record: users currently ASSEMBLE our CC stage
from dozens of scripts and a routing app. We ship it as one
processor on one rail — that's the pitch, validated by its own
prior art.

## §15 — CC CHOP: two curves, the slices decide (Paul, 2026-08-09:
## "two CCs played off against each other — chop comes into its own")
- **MODE: CHOP on the CC stage** — TWO source slots (each the full
  §1 radio: SHAPE · FOLLOW · STEPS · STRIKE · EXTERN) + **the
  8-slice row**, per-slice: **A · B · GLIDE** (crossfade to the
  other across the slice) · **HOLD** (freeze last value — the
  control stutter). Target/MIN/MAX/dest shared; the window draws
  the COMPOSITE curve with slice seams visible.
- **The rotate gesture applies** (CHOP-ROTATE's sibling): the
  control pattern walks the bar by tap — modulation phrasing as a
  performance move.
- **Idioms**: sine ⁄ S&H interleave = ordered chaos · FOLLOW with a
  STEPS stab on beat 4 = tracking-with-punctuation · **EXTERN vs
  SHAPE = the hand and the machine taking turns** (the wheel owns
  slices 1–6, the instrument steals 7–8) — the headline no script
  ecosystem has.
- Composes with per-cell busses (§10): source B may read a bus from
  a sibling stage — chopped depth-modulation, still one machine.
- Noted future, not v1: per-slice combine MATH (MIN/MAX/DIFF/×) —
  the attenuverter-mixer family; A·B·GLIDE·HOLD ships first.

## §16 — CC BEYOND THE CELL + LEGATO (Paul, 2026-08-09)
- **The insight first**: slow curves ALREADY span columns in phase
  (f(absolute beat)); the window only gated their VOICE. The chip
  governs speaking rights — **SPAN: CELL | PHRASE | FREE**:
  - **CELL** (default) — speaks while the column's active (today).
  - **PHRASE** — the CC TAIL: past column exit, the curve COMPLETES
    its current cycle, then silences (SPILL's sibling, riding the
    ring — a sweep that finishes its arc).
  - **★ FREE — THE LFO CELL**: the stage speaks continuously while
    its cell exists un-muted, schedule ignored — place a cell whose
    whole job is modulation, and **the grid becomes a mod-matrix**:
    LFO cells beside music cells, muted like anything, moved like
    anything, rolled by the dice like anything.
- **LEGATO, two layers**: ① the standing phase law (§1) already
  covers re-entries (LEGATO = phase continues). ② **THE ADOPTION
  LAW EXTENDS TO CONTROL**: identical stages in adjacent columns =
  ONE seamless curve across the boundary (free by phase math —
  stated so nobody builds a restart).
- **ENTRY-GLIDE (the acquire mercy, the handback's sibling)**: when
  a stage begins speaking, it RAMPS from the wire's current value
  to its curve over a short time (~30–80ms or a division) — curves
  never click on arrival. With §8's handback on release, every
  ownership edge is now soft both ways.
