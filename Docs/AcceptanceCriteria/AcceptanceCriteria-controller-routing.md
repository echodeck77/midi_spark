# AcceptanceCriteria — CONTROLLER ROUTING v1 (captured 2026-08-06)

**STATUS: ✅ BUILT + DEVICE-VERIFIED (2026-09-01 doc reconcile — controller routing shipped; see CLAUDE.md status).** Design-side ruling of record (ferry `REPLY-audit-rulings-controllers.md`, §1②/⑦
+ CC123/120). Building it is render-input-path engine work + a device pass — deferred, not done blind. Paul can
veto any of this.

## THE MODEL — per-door "CONTROLLERS → [A·B·C·D]"
- Each receiver door gets a cog mask **CONTROLLERS → [A · B · C · D]**, **default ALL-LIVE** (all four selected).
- Matching controllers arriving at that door — **CC · PB (pitch-bend) · AT (aftertouch) · PC (program change)** —
  are **FORWARDED to each selected emitter, RE-STAMPED to that emitter's stamp channel**. So the synth on emitter
  C finally receives the door's pitch-bend on C's channel.
- **Sustain / CC64 forwards like any CC** (no special-case).
- This SUPERSEDES today's hardwired passthrough (CC/PB/AT + stopped-note soundcheck on ALL + Emit A, per
  `Derivations.passthroughCableMask`): the destination becomes the per-door CONTROLLERS mask, re-stamped per emitter.

## BEND OWNERSHIP (the ruled pin)
- When the FUTURE per-emitter BEND stage is ACTIVE on an emitter, it **OWNS that channel's bend** — a forwarded
  external bend is suppressed on that emitter while the stage drives it.
- When the BEND stage is IDLE, the forwarded external bend passes. Co-writers on one channel = **last-writer + a
  tell** (a UI note that two sources are fighting for the bend).

## CC123 / CC120 (ALL-NOTES-OFF / ALL-SOUND-OFF) — RATIFIED
- Interpret as **pool/latch FLUSH _and_ forward**: an incoming CC123/120 must actually RELEASE our held/latched
  notes (flush the receiver's live pool + its frozen latch) AND be forwarded downstream. A controller's
  all-notes-off must actually silence us, not just pass through while our pool keeps feeding the grid.

## ⑦ UMP — legacy-first
- Patch the UMP (MIDI-2.0 eventList) path to **legacy parity where cheap** — the system / SysEx message pass that
  `umpToLegacy` doesn't yet cover. Full MIDI-2.0 semantics are NOT a launch target; this is just "don't drop
  messages we could trivially translate."

## FEASIBILITY / SEAMS
- New model: `Receiver.controllerMask: UInt8?` (nil ⇒ 0b1111 all-live, additive-Optional like the rack masks) →
  box field → the input handler forwards matching controllers per the mask, re-stamped per emitter (`busChannels`).
- Emission stays the only place that knows cables (seam rule 3): the forward re-stamps to each selected emitter's
  cable + channel.
- CC123/120 flush touches the Kernel/input handling (pool + `latchedPools`); testable via the RouterTests
  emitter-double for the forward, but the pool/latch flush is Kernel-side (needs a device ear-check).
- Test surface: `passthroughCableMask`'s successor is pure/testable; the per-emitter re-stamp forward is
  assertable through the recording MIDIEmitter; CC123 flush is the Kernel path (device).

## SCOPE NOTE
v1 = the CONTROLLERS mask + per-emitter re-stamp forward + CC123/120 flush + the cheap UMP parity. The BEND
STAGE itself (per-emitter pitch generation) is a LATER stage — this spec only reserves its ownership rule.
