# AcceptanceCriteria — RECORDER (the looper-in-a-chain)

Provenance: Paul 2026-09-18 (design conversation, ratified in chat). This is the CONTRACT — build to it; behaviour
changes need a spec revision first. Not yet built.

## THE CONCEPT
A RECORDER is a **looper that lives inside a machine's chain**. It has two phases:

1. **RECORDING** — note-transparent: it passes the upstream stream straight through downstream while it CAPTURES the
   timed note events reaching it (the output of every stage BEFORE it — `composeChainSet(upto: recorderSlot−1)`).
2. **PLAYING BACK** — it becomes a DRIVER: it emits the captured buffer on the following steps/passes, folded through
   the stages AFTER it in the chain.

So `[ARP → RECORDER]` records the arp's line then replays it; `[RECORDER → GATE]` gates the replay; `[CHANCE → RECORDER]`
photographs a one-off random result and loops the frozen version.

**The family line** (from the RIFF spec): ARP computes the walk · RIFF authors it · **RECORDER photographs it**. The
"CLIP / catch" the RIFF spec gestured at, realised as a chain stage. Records the OUTPUT, not a stencil — literal notes.

## THE PANEL (controls)
- **GRAIN** — `STEPS | PASSES`. The loop's unit: a short step-window (uses the part's step rate) or a phrase-window
  (uses the part's loop length). Both supported.
- **LENGTH — N** — how many steps / passes the window spans (bounded; see Engine).
- **ARM** — `ON PLAY | AFTER N`. When capture begins: from the first downbeat, or after N steps/passes have elapsed
  (let the phrase develop, then grab the next N).
- **MODE** — `LOOP | FREEZE | CANON` (v1):
  - **LOOP** — the captured window replays rhythmically, re-triggered every N. A tape loop.
  - **FREEZE** — capture once, then SUSTAIN the captured notes as a held layer (input-independent) — freeze a moment
    into a pad/texture. Distinct SOUND from LOOP (held, not re-struck). ⚠ SEE OPEN Q1.
  - **CANON** — capture continuously and replay offset by N while recording continues — the phrase chases itself a
    window later (an instant round / self-delay). Inherently rolling.
- **MIX** — `REPLACE | LAYER`. During playback: downstream hears ONLY the recording (REPLACE), or the recording PLUS
  the live upstream on top (LAYER). Both options.
- **CAPTURE** — the re-arm control (#6): `ONCE | REFRESH EVERY M | HOLD`:
  - **ONCE** — record the first window, then LOCK the loop forever (the "freeze a happy accident" case).
  - **REFRESH EVERY M** — re-capture a fresh window every M cycles (a rolling looper that periodically renews).
  - **HOLD** — a momentary button: re-arm/grab a new take on demand. (v1-optional — could drop for a clean two-state
    ONCE|REFRESH; see OPEN Q2.)
- **CLEAR** — empty the buffer + disarm.

## WHAT IT RECORDS
The timed note stream from upstream: per event `{ beat-offset within the window · pitch · velocity · on/off }`. v1
records **RAW timing** (as it arrived) — GRID-quantize is a deferred nicety (RIFF-capture's quantiser is the model).
Routing (emitter/channel) is decided DOWNSTREAM at emission, so it is NOT captured. LITERAL pitches (record what came,
play what came) — chord-FOLLOW re-voicing (like RIFF) is a deferred fast-follow.

## PLACEMENT (examples)
- `[ARP → RECORDER(LOOP, PASSES, N=1)]` — loops the arp's phrase.
- `[ARP → RECORDER(CANON, PASSES, N=1)]` — the arp chases itself a pass later: an instant round.
- `[CHANCE/RANDOM/EUCLID → RECORDER(FREEZE or LOOP, CAPTURE=ONCE)]` — capture a one-off generative result you like and
  loop the FROZEN version deterministically (the headline use — turns a happy accident into a repeatable part).
- `[RECORDER → RATCHET]` — ratchet the replayed loop.
Manual line: *"A recorder here is a loop pedal in the chain: it tapes what comes before it, then plays it back."*

## ENGINE (reuse, don't rebuild)
- **Transparent while recording · driver while playing back.** Recording adds the upstream events to a buffer; the
  stream still passes through (so recording is audible). On playback the RECORDER is the note source, folded downstream
  through `emitDriverNote` like any driver.
- **The capture buffer is a SANCTIONED accumulated-state exception** (the class of the echo ring / ReelDeck / TURNS
  counters — the "derived, never accumulated" rule's blessed exceptions). Fixed-size, bounded by N × the max grain, no
  render-path allocation.
- **Playback reuses the ECHO activation ring** (emit stored events at future beats, column-independent, FLUSHED on
  every transport/scene/panic edge) and the **ReelDeck on/off pairing** (a note left open at the window edge closes at
  the boundary). No stuck notes by construction — every emitted on has a paired off; all playing voices close on a
  flush edge.
- **Clock:** STEPS grain runs on the part's step rate; PASSES grain on the part loop length. Rides the per-part
  multi-clock path.

## PERSISTENCE (Paul: PERSISTED)
- The captured buffer is **saved with the session**: a Codable events array on the machine's `MachineParams`, ADDITIVE-
  Optional + decode-tolerant (the CR-8 `init(from:)` class — a missing key must not throw), BOUNDED in size.
- **Buffer lives ON THE MACHINE** (like RIFF's stencil), so a machine placed in several cells shares one recording
  (coherent — the machine's chain is identical everywhere; only routing differs per cell). Per-cell buffers are a
  flagged alternative, not v1.
- On load, a persisted buffer restores as an already-captured loop (it plays back immediately without re-recording,
  unless CAPTURE=REFRESH).

## REPLAY-EXACTNESS (the #5 nuance)
- A **captured/frozen/looped buffer plays back deterministically** — it's just "emit these stored events at these beat
  offsets," a pure function of beat, so it IS replay-exact (survives host loop/seek).
- The parts that are NOT seek-exact are (a) the LIVE CAPTURE WINDOW itself and (b) CANON's rolling record — their
  record/playback PHASE can't be rebuilt from the beat number alone. On straight top-to-bottom playback everything is
  correct; only transport SCRUBBING/LOOPING *across the capture point* is fuzzy. Same accepted class as TURNS/DEAL. v1
  limit, flagged.

## ACCEPTANCE (Given / When / Then — the testable contract)
1. **Records + loops.** GIVEN `[ARP → RECORDER(LOOP, PASSES, N=1, ARM=ON PLAY, MIX=REPLACE)]` and a held chord, WHEN
   the first pass completes and the transport continues, THEN pass 2+ emit the SAME note sequence pass 1 produced
   (the recording), and no upstream-live notes leak (REPLACE).
2. **LAYER mixes.** As (1) but MIX=LAYER: pass 2 emits the recording AND the live arp on top.
3. **ARM AFTER N.** GIVEN ARM=AFTER N (N=1), THEN pass 1 records nothing/plays nothing, pass 2 captures, pass 3 replays.
4. **CANON offsets.** GIVEN MODE=CANON, N=1 pass, THEN the buffer replays one pass later while the live input keeps
   playing — the two overlap as a round.
5. **CAPTURE=ONCE locks.** After the first capture, changing the upstream input does NOT change the loop.
6. **CAPTURE=REFRESH EVERY M.** The loop content updates every M cycles to the newly-played input.
7. **Persistence round-trips.** A captured buffer survives encode→decode; an old doc missing the key decodes without
   throwing (default: empty buffer).
8. **No stuck notes.** Across transport stop/start, scene switch, and panic — during record AND playback, in every
   mode — nothing is left sounding (fuzz-covered, like DEAL).
9. **Frozen buffer is seek-exact.** A locked (CAPTURE=ONCE) loop plays identically whether reached by straight
   playback or by a host loop back to its start.

## v1 SCOPE / DEFERRED (flagged)
- **v1:** GRAIN both · LENGTH · ARM (ON PLAY | AFTER N) · MODE (LOOP · FREEZE · CANON) · MIX (REPLACE | LAYER) ·
  CAPTURE (ONCE | REFRESH | HOLD) · CLEAR · persisted buffer · literal pitches · RAW timing.
- **Deferred:** OVERDUB (layer new input onto the loop each pass) · REVERSE / half-double-speed · GRID-quantize on
  capture · chord-FOLLOW re-voicing (RIFF-style) · per-cell buffers · multiple RECORDERs interacting in one chain.

## OPEN QUESTIONS (confirm before build)
- **Q1 — FREEZE semantics:** is FREEZE a SUSTAINED held capture (notes ring, a pad — my lean, distinct from LOOP), or
  simply LOOP locked + input-independent (rhythmic repeat that never refreshes)? These sound different; pick one (or
  ship both as a sub-option).
- **Q2 — CAPTURE=HOLD:** keep the momentary "grab a new take" button, or trim CAPTURE to a clean ONCE | REFRESH?
- **Q3 — LENGTH bound:** max N for STEPS (e.g. 16/32) and for PASSES (e.g. 4/8) — sets the buffer's fixed size.
