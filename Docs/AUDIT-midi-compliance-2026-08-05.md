# MIDI compliance & side-effect audit — 2026-08-05

Four read-only investigations across the MIDI surface: output/emission, input/passthrough, note lifecycle, and
render-thread real-time safety. Verdict: **no hard MIDI-spec VIOLATIONs in the core emission or render path.** The
material items are (1) a handful of fixable bugs/gaps and (2) design-level questions about controllers/MPE/multi-out
that need a MIDI-domain ruling (handed to design-side Claude). File:line anchors are to `AUExtension/`.

## Where the audit found the code (for future reference)
The MIDI parser is in **`Kernel.swift`** (`render` event-walk, `handleIncoming`, `processUMPPacket`), not the AU
file (whose `internalRenderBlock` just forwards to `kernel.render`). The emitter is `LiveMIDIEmitter` (Kernel) →
host `AUMIDIOutputEventBlock`. All sequenced note-ons funnel through `Router.openVoice` (one `0x90` site) and offs
through `Router.closeVoice` (one `0x80` site).

---

## A. CONFIRMED COMPLIANT (no action)
- **Note-on velocity 0 is impossible on output** — the sole note-on site applies `max(1, velocity)` and every
  upstream transform floors at 1 (Router.openVoice; ratchet/curve/flatten/leak/bypass). Input `0x90` vel-0 is
  correctly treated as note-off (`NotePool.noteOn`, `PassthroughGate`).
- **Note numbers guaranteed 0..127 at the wire** — `emitOneBus` guards `sn>=0 && sn<=127` after octave+masterKey
  (out-of-range DROPS, never wraps); FENCE always yields in-range; no `UInt8` truncation path.
- **Channel encoding 1..16 (model) → 0..15 (wire) correct** — `(busChannels[bus] &- 1) & 15`, busChannels clamped
  1..16 in the builder; no off-by-one.
- **PANIC / transport-stop / scene-switch / latch / emitter-disable emit INDIVIDUAL note-offs** (never rely on
  CC123). Note-off is `0x80 | chan` release-vel 0, one form, one site.
- **Refcount pairing** — every note-on eventually paired with exactly one off via the per-(cable,ch,note) refcount;
  no overflow (bounded by the 128-voice table), no underflow (guarded decrement, balanced silent-voice path);
  `distinctSounding` exact; `quiescent` invariant pinned by FuzzTests.
- **Real-time safety** — render path is allocation-free, lock-free, no Date/random; `process()` is a pure function
  of (SnapshotBox, transport, input); the `_swift_release_dealloc` poll crash class is fully fenced (every render→
  main drain returns a fresh array or a scalar); SnapshotBox is immutable, acquire is one atomic load; the macro
  layer folds at BUILD time (nothing macro-related runs at render).
- **Input**: UMP multi-packet event-lists walked correctly; UMP MIDI-2.0 pitch-bend downscaled 32→14-bit properly;
  OMNI(0)/1-16 note-channel filter correct; passthrough note-offs balanced against their ons (no stranded echoes).

---

## B. FIXABLE BUGS / GAPS (no domain ruling needed — we can do these)
- **B1 · THRU channel filter drops channel-less System messages.** `thruAudible`→`receiverHears` (Derivations)
  passes a System status's low nibble as a "channel", so a THRU receiver set to any non-OMNI channel silently
  drops MIDI clock/start/stop/SysEx/active-sensing (their sub-type nibble ≠ filter−1). Fix: exempt `0xF0..0xFF`
  from the channel filter.
- **B2 · Legato drone strands on key-release under a single-column (k=1) lap.** `emitColumnHolds` (the only path
  that closes a legato drone for an emptied pool) runs only when `effColumn` changes; a 1-column lap pins
  `effColumn`, so releasing the chord leaves the immortal drone hung ~1s until the Kernel self-heal net closes it
  (and bumps `diag.panics` spuriously). Fix: drive the drone reconcile off `absoluteStep` (which advances during a
  lap) or re-run it when the pool empties. **Coverage gap** — no test releases a chord mid-k=1-lap; add one.
- **B3 · Host `fullState` restore doesn't flush voices** — the one load path missing `kernel.flushVoices()` (scene
  switch, factory/preset load, currentPreset setter all flush). Mid-play session restore briefly overlaps old+new.
- **B4 · Boundary onset can be emitted at sample == frameCount** (one past the buffer) — `sampleOf` clamps only the
  lower bound; the arp/ratchet tick path doesn't clamp to `windowEnd` (STRUM already guards). Fix: clamp `< windowEnd`.
- **B5 · `rebuildAltSequence` mutates a heap array on the render path** — steady-state no-alloc, but the first window
  that grows the sequence reallocates on the audio thread. Fix: preallocate `altSequence` to 32 in init/reset.
- **B6 · Stale doc comment** at `Router.openVoice` capacity guard — says "the on still sounded; we can't track its
  off" but the code returns −1 *before* emitting (correct). Correct the comment.
- **B7 · No CC120/123 (All-Sound-Off/All-Notes-Off) interpretation on input** — a controller that releases via CC123
  instead of note-offs leaves the grid pool holding notes → stuck grid voices. (Interpreting it as a pool flush is a
  small fix, but the exact semantics may want a design nod — see C7.)
- **B8 · Legacy `.MIDI` path truncates >3-byte messages** (`min(length,3)`) — corrupts a multi-byte SysEx delivered
  as a `.MIDI` event (rare; usually arrives via eventList). Low priority.

---

## C. NEEDS DOMAIN RULING (handed to design-side Claude)
These can't be settled by code inspection — they need a MIDI-domain / product ruling on *intended* behaviour or a
real-hardware/host test.
- **C1 · MPE is inert.** `Receiver.mpeMerge` is a stored toggle with "engine semantics deferred" and ZERO render-side
  consumers; the UI advertises MPE-merge + auto-detect. Per-note-channel pitch/pressure are neither merged onto a
  note nor preserved — flattened into the raw passthrough, and the note pool is channel-blind. **Is MPE a target, and
  with what semantics?** Either build it or retire the toggle so the UI stops promising it.
- **C2 · Controller passthrough is notes-blind and single-out.** CC/PB/AT/ProgramChange pass through only on All +
  Emit A (never B/C/D) and keep their SOURCE channel, while grid notes are re-stamped to bus channels. A synth on
  Emit C gets notes but no pitch-bend/CC, and controllers don't channel-align with the notes they shape. **What
  should a multi-out MIDI effect do** — per-emitter controller routing? re-stamp controllers to match? This is the
  biggest usability question.
- **C3 · The "double-on" collision policy** (re-articulating an already-sounding pitch emits a 2nd `0x90` with no
  intervening off) is synth-dependent — safe on retriggering synths, a hung note on instance-counting synths. This
  is exactly the **WIRE ARTICULATION ASK already in flight** (RESTRIKE | MERGE) — the audit confirms the current wire
  is on-only. Needs Paul's word + a hardware pass.
- **C4 · Equal-timestamp off-before-on ordering** relies on the host preserving emission order for events at the same
  `AUEventSampleTime`. Program order is correct; needs confirmation of the AUv3 host-scheduler guarantee (else a
  re-struck same pitch at a column boundary could drop).
- **C5 · TURNS/ALT turn-phase is history- and block-size-dependent** → offline bounce may differ from live (resets
  only on transport-start, not loop-jump; cells processed sequentially so onSample is non-monotonic). **Is
  bounce-reproducibility a requirement?**
- **C6 · own + All double-emit** — every note goes out its own cable AND the All cable (0). These are separate MIDI
  OUTPUT PORTS (not channels), so no double-trigger normally — but a user connecting a synth to BOTH All and an Emit
  port gets the note twice. Confirm AUM maps each cable index to a separate destination; decide the product stance.
- **C7 · UMP vs legacy inconsistency** — the UMP path drops SysEx (MT 0x3/0x5), UMP poly-aftertouch, and all
  system/realtime, which the legacy path passes. Is MIDI-2.0/UMP a support target?

---

## Coverage gaps to add (tests)
- B2: a `k=1` lap that releases the chord mid-lap → `assertNothingLeftSounding` + `quiescent` (currently untested).
- CC123/All-Notes-Off on input (B7). · fullState-restore-mid-play flush (B3). · boundary-onset at frameCount (B4).
