# I/O principles — the spine, amended to code truth

> Commissioned 2026-08-25 (design-side `REQUEST-io-principles.md`). Symptom: input/notes flowing without lighting
> the receiver/emitter strips. This doc is the honest map: the six principles as they ACTUALLY hold in the code,
> the DECLARED exceptions (not every off-spine path is a bug), and what the audit changed. Verified against Router /
> Kernel / Emission / SnapshotBuilder by a three-way read-only audit (emission · input · auditions).

## THE SPINE (the only intended road)

```
  MIDI in ──▶ RECEIVER DOOR ──▶ POOL ──▶ CHAIN ──▶ EMITTER WIRE ──▶ MIDI out
             (THRU·LATCH·HOLD    (live or   (processors,   (A–D + ALL,
              KEYS·REPLAY·FILE)   frozen)    step clock)     stamped ch)
```

- **Enters** only through a door: `Kernel.handleIncoming` is the ONLY site that calls `pool.noteOn`. Every door mode
  (THRU · LATCH · HOLD · KEYS/PIANO · REPLAY/Last-N · FILE/.mid) feeds the grid through `latchedPools`/`effectivePool`.
- **Leaves** only through an emitter: the metered choke is `emitOneBus` (reached only via `emitArtic`), which stamps the
  wire's cable + channel and accumulates the emitter meter.
- **Passage requires a chain**: a cell is a step-sequenced hold; an *empty* chain is a **wire** (see the declared
  exception below). Stopped transport ⇒ the scene sweep never runs ⇒ no scene emission.

## The six principles — as they hold in code

1. **ONE ENTRANCE.** ✅ True. `pool.noteOn` exists only in `handleIncoming`; there is no synthetic/injected pool (the old
   reference-chord fallback was removed). REPLAY/FILE are cables into a door, not side-doors.
2. **ONE EXIT.** ✅ For notes: all engine note-ons flow `emitArtic → emitOneBus`. ROW 8's announced acts and control
   messages leave via the Kernel (see exceptions).
3. **THE GATE.** ✅ A playing chain speaks; a stopped transport emits nothing from the scene. The **no-machine live wire**
   is the ONE sanctioned realtime side-path (Paul's ruling): an empty-chain cell passes its door's input straight through
   in realtime via `reconcileBypass`, not the step clock.
4. **★ METER-TRUTH.** ▲ **Amended** (see below). Every note-on that goes through the ENGINE lights the emitter strip —
   now including GLIDE. But "*all* emission must meter" is too absolute: **reel replay** and **control messages** are
   declared exceptions, not bugs.
5. **ONE AUDITION.** ✅ For BUILD: "PLAY THIS MIDI CHAIN" and the grid-selector audition are literally one path
   (`ddSolo` + `buildPublishScene` → the normal scene render — same voice, same playhead, same meters). Three off-spine
   audition renderers still exist in code (one for EDIT's "play this cell only"; two dead-from-UI) — see Deferred.
6. **ONE SPINE.** ✅ door → pool → chain → wire is the only road; REPLAY/FILE feed the door; auditions ride the spine
   with a scope, never beside it.

## DECLARED EXCEPTIONS (off-spine by design — do not "fix" by forcing metering)

- **REEL replay** — the reel is a *tape of prior output*. Replaying it plays the tape (`ReelDeck.replay` → the emitter
  directly), with `Router.process` deliberately skipped. It is off-spine and unmetered **by design**. (Paul: "reel replay
  is a major exception to this rule.")
- **CONTROL MESSAGES** — CC/PB/PC/AT (MOD CC, GLIDE pitch-bend/portamento, ROW 8 CC-punch/PC-send, controller-forward)
  are not note-ons, so they cannot light a note-velocity meter. Emitted correctly; just not on the note-meter seam.
- **NO-MACHINE LIVE WIRE** — the sanctioned realtime side-path of principle 3 (empty chain = wire). Injects via
  `reconcileBypass`; currently unmetered (a wanted feature; metering it would follow the same seam question if ever wanted).
- **PANIC / all-notes-off / flush** — note-offs + CC120/123; unmetered by design (a note-on meter must not fire on offs).

## What the audit changed (2026-08-25)

- **GLIDE made honest.** GLIDE emits its mono voice via a direct `openVoice`, so it sounded without lighting the strip —
  the tell that GLIDE is *terminal* (a mono voice + continuous bend; nothing downstream is fed). Ruling: keep it terminal,
  make it honest → `openVoice` gained an opt-in `meter` flag (bumps the §6a accumulators, no double-count on the normal
  path), set at GLIDE's note-on sites; the editor now says "TERMINAL — a processor placed after it is not fed."
  Proven off-device by `testGlideLightsTheEmitterMeter`.
- **Door-level BYPASS toggle retired.** `reconcileBypass` served two features on one mechanism: the door BYPASS toggle
  (unused) and the no-machine live wire (wanted). The door-toggle half (`receiverBypassMask`/`receiverBypassDest`,
  `Receiver.bypass`/`bypassDest`, the AU/VC API) was removed; the wire (`passEmitterMask`) and the immortal-voice
  machinery (`bypassRecv`) stay. The door-bypass RouterTests were re-pointed to exercise the surviving wire path.

## Deferred (flagged, not done)

- **Dead audition/preview renderers** (`auditionRender`, `previewStopped/previewPlaying`) — dead-from-UI, but `previewMode`
  threads through ~15 guards in the hottest function (`emitOneBus`); removing it is a render-hot-path refactor for zero
  functional gain. Left in place.
- **Receiver strip coarseness** — live input lights the 30 fps attack flash, but armed-playback modes
  (LATCH-after-release · KEYS · REPLAY · FILE) reach the strip only through the 4 Hz held bar, so a note that starts and
  ends between two polls plays invisibly. A real (small) follow-up if the dark input strip bugs on device: drive the flash
  off pool onsets. The range-aware live signal `recvLiveHeldMask` is computed but currently has no UI consumer.

## The invariant (the proof, not the assurance)

`testGlideLightsTheEmitterMeter` locks the meter-truth law for the path that was violating it. The general fuzz-checked
form ("no engine note-on without an emitter-meter event", with reel + controls as declared exceptions) is the natural next
guard if the class recurs — but with the two biggest offenders now either metered (glide) or declared (reel), the bug Paul
was hearing is addressed at the source, not asserted around.
