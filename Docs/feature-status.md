# 8x8 State — feature status (snapshot 2026-07-24)

A point-in-time survey. **CLAUDE.md is the live truth**; when they disagree,
this file is stale — regenerate, don't trust. Legend: ✅ shipped &
device-verified · 🔧 built, confirm status · 📋 specced & queued · 📐 specced,
unqueued · 🧭 decided posture · 💭 sketched (parked, design on record) ·
❓ awaiting the user's call · 🚫 rejected on record.

## ✅ Shipped and device-verified
- AUv3 `aumi` core: five cables (All + Emit A–D), fullState = host Preset,
  35-param tree (stable addresses), passthrough (All + Emit A, `e4bfa30`)
- Snapshot architecture: atomic publish/acquire; render thread pure;
  derived-never-accumulated; zero stuck notes (emitted-tuple refcount)
- v3.0 GRAPH ROUTING: receiver-picked references (any row), fan-out,
  cycles legal-and-silent, muted-parent reroute, backward taps
- Channels: filter-in (per-cell, OMNI default) / stamp-out (busChannels)
- ALL SIX processors: ARP (5 patterns) · RATCHET · PASSGATE · STRUM ·
  CHANCE · HARMONIZE; PHASE = RETRIG / LEGATO / FREE; swing; morph A/B per
  Colour + morphMaster (current model)
- GUI reconcile: four-row cells, FROM/OUT popovers (as built), PROCESSOR
  box, three-box responsive desk, v57 column keys, SIXTEEN-slot scene
  strip, master arrow + mutation-line playheads, watermarks
- PERFORM v1: EDIT·PERFORM toggle; tap = ALT flip (MUTE/BYP + selector +
  column-tap-mute REMOVED at `3e816ee` pending TOUCH; engine fields kept)
- AUDITION, all six types (chord-hold reconciles to live keys)
- §5b COLUMN-SUBSET LAP: engine (`f30b006`) + multi-touch UI (`6f28e88`);
  k∤8 polymeter + k=1 sustain confirmed by ear
- §6a EMITTER TOGGLES (`a3227fa`): busEnabled[4], emission-boundary gate,
  All = enabled sum (CH editing currently caption-popover — superseded on
  paper by a7)
- §6b COLOUR-chip activity playheads (`b3d2445`); (a4) velocity METERING
  (`43c6cf5`): panel glow + peak-hold bars, post-transform, event-driven
- Identity: "8x8 State" display name applied everywhere; AppIcon; 111-test
  off-device suite; T1–T17 + DEV LOADER; deduped 4 Hz poll

## 🔧 Built — confirm status on repo side
- SceneFactory sixteen scenes vs the REVISED factory-scenes.md (scenes 9/11
  grid changes; standing-rig ear-verify) — reconcile item left old NEXT
- UI-size checkpoint gate (test-procedures) — formal run not seen in status
- `v0.7-gui` tag — candidate, pending the above

## 📋 Specced and queued (CLAUDE.md NEXT)
- (a5) THE CELL EDITOR — delta §5 rev 2: one tap-anywhere pop-up (palette ·
  input/IN CH · emitters · clear/copy/split-paste); inspector retargeting;
  SESSION TEMPLATE (=clipboard, one stamp object, commit-on-first-
  interaction); STAMP MODE ("COPY TO CELLS…", banner, overwrite tint);
  invalid-⇐ROW dimmed display; retires tap-paint + FROM/OUT popovers +
  hold menu; audition RETURNS to EDIT+stopped; drag = accelerator
- (a6) UNDO/REDO — document-value stack, coalescing, (scope: ❓ below);
  future RECORD layer-undo unifies
- (a7) EMITTER PANEL v2 — PERFORM face: four channel strips (toggle+flash ·
  momentary-ABSOLUTE velocity slider + green LED ladder, spring-back,
  ephemeral · CLAIM radio, persisted, suppress-never-defer); EDIT face:
  dedicated per-emitter CH selectors; VISUAL KINSHIP with cell letters
- (b) MORPH desk (16 faders) — parked-tagged, model-dependent (see ❓)
- (c) MULTI-SCENE — the flagship gap (scenes[] length-1 today)

## 📐 Specced, unqueued (promotable on your word)
- CYCLES {∞,1,2,3,4} — one-shot/N-cycle gestures; pure tick comparison,
  needs no tail rule; STRUM ×N; RECORD LOOP/ONE-SHOT collapses into it
- SPILL — finite gestures complete past the boundary (tail customer 6;
  waits on the tail amendment)
- §6b/metering follow-mentions: per-cell-per-event emitter-letter flash
  (needs a per-cell feed — deferred by a4 as built)

## 🧭 Decided postures (design settled, work deferred)
- MIDI 2.0: UMP/eventList transport verification SOON (delegable spike);
  semantics not-now · MPE: input MERGE toggle = near-term insurance; full
  MPE = pitch-continuity wave 3 (foreclosure check passed)
- EXTERNAL processors: standalone-only; hosting-policy PHASE modes;
  instance-per-RUN; edit-time instantiation
- STANDALONE app: second-host model; three seam rules enforced (done)
- HARDWARE surfaces: CoreMIDI-in-extension SPIKE gates (delegable);
  Launchpad X first (SysEx RGB = the real hexes); PERFORM-only v1; Push =
  pads-only later
- TOUCH v1 ships live-replay only; per-cell capture = TOUCH v2 direction

## 💭 Sketched — parked with full design on record (delta §9)
1. TOUCH system: 3 slots (TAP·HOLD·COL-HOLD) × 3-axis grammar
   (WHAT×WHEN×HOW-LONG); ~10-behaviour menu; inherit/QUANT-blink laws
2. Recorded-input capture: consolidated into RECORD's infra (two lifecycles)
3. Row solo (undesigned)
4. Emitter layer remainder: persistent scale-fader (automatable), HOCKET,
   velocity-SPLIT, emitter SWAP, TOUCH slots on pads
5. COLOUR-PAIR MORPH model (❓ unratified): ALT box, capability tiers
   (FULL/SWAP now, PARTIAL by ear), rescues (200+i addresses, 16-strip
   desk); p-lock per-cell overrides = sanctioned later layer
6. Future processors: STEP-MASK (confirmed; drawable bars) · PICK (FROM+N;
   voice splitting) · NOTE-CHANCE · roster (★TRANSPOSE-SEQ, ★ROTATE/
   INVERT, BURST, DRONE, CASCADE, RAMP, HUMANIZE, MIRROR, SHIFT,
   VELOCITY-MAP; EUCLID/ACCENT as STEP-MASK modes) · TAIL RULE brief (6
   customers; slide is the headline) · PITCH BEND (wheel→morph = cheapest
   win; BEND processor; PICK→GLIDE) · MONO (only impure idea)
7. MPE/MIDI 2.0 posture (above)  8. Hardware surfaces (above)
9. RECORD processor: grid-as-record-button, LENGTH 1–8, ONE-SHOT/OVERDUB,
   overlapping fan-out windows, ABS v1 (+ROOT/DEGREE later), resampling
   (⇐Rn), scene riffs, takes, true-timeline rule
10. PARAMETRIC GLYPHS: settings-drawn cell glyphs, derived live highlight,
    disclosure ladder, user Colour names (picked glyphs rejected)

## ❓ Outstanding calls — yours
- Colour-pair morph RATIFICATION (needs the v61 mockup sitting)
- SCALE adjudication (corrective-post-HARMONIZE vs constitution)
- Undo SCOPE (lean: EDIT-only) · TOUCH behaviour shortlist (+COL-HOLD
  reading, portrait fit) · CYCLES promotion timing
- By ear at their passes: PICK STRICT-vs-CLAMP · tail referenceability
  fork · NOTE-CHANCE form (lean TILT) · PARTIAL-morph pairs · RECORD
  re-arm/clear UX + undo depth
- Scheduling: multi-scene slot; the two delegable spikes (UMP verify,
  CoreMIDI-in-extension)

## 🚫 Rejected on record (with reasons in the delta)
Double-tap TOUCH slot · pure per-cell ALT/TOUCH (legibility contract) ·
invalid-ref field mutation · dual-threshold holds · shared CH selector
row · hand-picked glyphs · tap-to-paint (retired by the editor) ·
two-finger loop brace (subsumed by the lap) · order-of-press lap sets ·
PASS-MASK (incidental) · engine-linked standalone · morphing opaque
external plugins · SCALE-as-input-override (pending the ❓ above)
