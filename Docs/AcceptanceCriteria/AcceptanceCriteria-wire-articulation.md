# AcceptanceCriteria — WIRE ARTICULATION: same-note overlap on one emitter (captured 2026-08-05)

**STATUS: CURRENT BEHAVIOUR VERIFIED; the proposed re-articulation law awaits Paul's word.** From
`ASK-wire-articulation-law`. Scenario: a sustained E4 (drone) + a gated E4 strike on the same emitter/channel — MIDI
has no note instances, so what does the wire do?

## VERIFIED CURRENT BEHAVIOUR (test: `RouterTests.testSameNoteOverlapOnOneEmitterEmitsBothNoteOns`)
The ASK's premise ("refcount ⇒ wire CONSOLIDATION ⇒ the overlap strike is INAUDIBLE") is **STALE**. Reality
(`Router.openVoice`, §7 clause 1 — "note-ons ALWAYS emit"):
- **Every note-on emits to the wire** — two holders of note 60 on emitter A produce **two note-ons** in one window.
  The same-note strike is **AUDIBLE**, its velocity heard.
- The collision **refcount** governs only the note-**off**: the shared note ends at refcount→0 (the drone survives
  the gate's release; the off fires when the LAST holder lets go). No stuck note (verified across a full run).

So the wire already does the *audible-restrike + survive-to-last-release* half of the proposal — WITHOUT a paired
note-off before the second on.

## PROPOSED (design) — THE RE-ARTICULATION LAW, if Paul wants the clean off/on
On a strike for an already-sounding (note, chan): emit **note-off THEN note-on, same timestamp, off first**, velocity
= the striker's. Count stays consolidated; note ends only at refcount→0. Gains: clean re-attack, correct off-pairing,
mono synths retrigger properly. Ordering: off-before-on in-frame (the tested sample-offset discipline).
- **Option chip if contested:** `WIRE ARTICULATE: RESTRIKE | MERGE` (MERGE = today's on-only overlap; the pad case).
  Design leans RESTRIKE default. **This is Paul's ONE word to give** before building — not built on an implication.

## TEST MATRIX (for when the law is built — add to RouterTests)
drone+gate same note (strike audible; drone survives gate end) ✓ current · gate+gate overlap · three holders
staggered release (off only at last) · re-articulation velocity = striker's · off-before-on ordering in-frame ·
MONO-treatment interplay · scene-switch mid-overlap (quiescent holds).

## MANUAL LINE (once ruled)
"Two machines holding one note on one wire: the synth hears one note, re-struck at each new attack, released when
the last hand lets go."
