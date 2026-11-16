# REEL redesign — Phase 2 (replay from anywhere, onward): design + findings

Plan of record: `Docs/reel-redesign-plan.md` (phase 2). Brief: replay any MIDI **from any point onward**, not
just a phase-locked loop of one pass. Decided defaults adopted (plan §Decisions): replay **replaces** live
(today's behaviour); position is **derived** (host beat − anchor), nothing accumulated.

## The map (current replay, before the change)
- **`ReelDeck`** (`Fourfold/Engine/Emission.swift:40`) holds a single playback `loop` (`[Ev]`, pass-relative
  beats, ≤ `cap` 16384) of length `loopCycle`. `stageLoop`/`adoptStagedLoop` hand one pass across the audio
  boundary lock-free (an atomic 0/1/2/3 state). `closeOpenLoopNotes` appends synthetic offs so a loop never
  strands a note (invariant 4).
- **`reel.replay(beatPos:windowBeats:cycleBeats:beatsPerSample:windowStart:out:)`** (`Emission.swift:295`) is
  the per-window emission: `passStart = floor(beatPos/cycleBeats)·cycleBeats`, then every `loop[i]` is emitted
  at `passStart + loop[i].beat`, wrapped to the next cycle if already passed. ⇒ **phase-locked to the global
  cycle** (the root-cause the plan flagged: a tap replays "70 % into the bar").
- **Kernel** (`Kernel.swift:434-524`): `adoptStagedLoop` → `.replaying`; while `.replaying && playing` it calls
  `reel.replay(… out: liveEmitter)` and routes the live engine to `reelSilentTap` (the tape keeps recording; the
  host hears the loop). Hand-back = `.off` + `reelExitFlush` (blanket-off the loop's ringing notes). The live
  engine **never stops** (phase 1c), so hand-back just re-routes + flushes replay's notes.
- The tape (`SessionTape`) is **main-thread only**; the render thread sees only what was staged into the deck.

## The new model — an ANCHORED tape playhead (replaces phase-locking)
When replay starts, capture (set on the main thread, adopted by the render thread at a window edge):
- `startTapeBeat` — the tape beat of the selection start (0 = from the start of the session),
- `endTapeBeat` — the selection end (loop) or the recorded end at press (from-here→live),
- `mode` — `.loop` or `.toLive`,
- and on the first replay window, the render thread latches `anchorHostBeat = beatPos`.

Each playing window (`beatsPerSample > 0`): `elapsed = beatPos − anchorHostBeat` (≥ 0).
- **`.loop`**: `span = endTapeBeat − startTapeBeat`; `tapeBeat = startTapeBeat + (elapsed mod span)`; emit staged
  events whose tape-beat ∈ `[tapeBeat, tapeBeat + windowBeats)`, wrapping across the loop seam (emit the loop's
  tail then its head when a window straddles the seam — the derived, accumulation-free analogue of today's
  per-event wrap). Aligned to **when you pressed**, not the global grid.
- **`.toLive`**: `tapeBeat = startTapeBeat + elapsed`; emit in `[tapeBeat, tapeBeat + windowBeats)` with no wrap.
  When `tapeBeat ≥ endTapeBeat` → **hand back to live** (state `.off` + flush). ⚠ semantics flagged below.
- **live now** = not a state; it is the hand-back (`.off`).

Position is a pure function of `beatPos` (host beat) and the latched anchor — **nothing accumulates across
windows** (invariant 2). Transport stop freezes `beatPos`, so replay pauses and resumes on restart, exactly as
today.

## Render-thread safety / the staged buffer
The render thread cannot read the tape, so the main thread stages the range's events (tape-**absolute** beats
now, not pass-relative) into the deck via an extended handoff `stageRange(events, startTapeBeat, endTapeBeat,
mode)` (same lock-free atomic as `stageLoop`). `closeOpenLoopNotes` still appends the seam/edge offs.
- **Slice 2a (this slice):** one staged buffer, ≤ `cap` 16384 events. At the plan's mean density (~4.8k
  events / 128 beats, both cables) that is ~110 bars / ~3.5 min — enough for any **loop selection** and most
  **from-here** spans. If a `.toLive` span exceeds the buffer, 2a plays to the staged end then hands to live
  (documented limit).
- **Slice 2b (follow-up):** the main thread RE-STAGES a forward window as the playhead advances (it reads the
  deck's live `tapeBeat` off the existing 0.5 s poll and stages the next chunk before the playhead reaches the
  buffer end) → arbitrarily long "from the start onward". The deck emits only within the staged coverage
  `[bufLo, bufHi]`; a playhead that outruns the buffer (main thread behind) emits nothing for the gap and counts
  it (like the recorder's drop). No render-thread allocation either way.

## Modes & hand-back (clean, no stuck notes — invariant 4)
Hand-back (`.loop`→off, `.toLive` reaching the end, transport stop's explicit exits, browser close, a new
`stageRange`) flushes the replay loop's open notes (`reelBlanketOff` on `liveEmitter`, the existing path) and
re-routes the live engine (already running on `reelSilentTap`) back to `liveEmitter`. A `.toLive` end and a
`.loop` seam both go through `closeOpenLoopNotes` so no note hangs across the seam/end.

## What stays / what changes
- `reel.replay` (phase-locked) is **replaced** by `reel.replayAnchored(...)`; the old signature is kept compiled
  for the diff but no longer called (or deleted once the UI no longer needs it). The current browser's
  "tap a pass → loop it" becomes an anchored single-pass `.loop` (strictly better — no phase lock).
- `stageLoop`/`adoptStagedLoop` → generalised to `stageRange`/`adoptStagedRange` carrying start/end/mode/anchor.
- `FourfoldAudioUnit` gains `reelPlayRange(fromTapeBeat:toTapeBeat:mode:)` + `reelMode`; the browser (interim)
  and phase-3 UI call it. `uiReelState` keeps 0/1/2; a new `reelModeValue()` reports loop/toLive for the
  LIVE/TAPE pill.

## ⚠ Decisions flagged (adopting a default, confirm if wrong)
1. **`.toLive` end semantics.** Replay advances at 1× and the live tape also grows at 1×, so a replay that
   starts in the past never literally "catches up" to live. Adopted: **`.toLive` plays `startTapeBeat` →
   `endTapeBeat` (the recorded end captured at press), then hands back to live.** I.e. "play from here to the
   end of what's recorded, then you're live again." If you meant something else (e.g. speed-up catch-up, or
   chase a moving end), say so.
2. **Anchor on a tempo change mid-replay.** Position is `host beat − anchor` in BEATS, so a tempo change keeps
   musical position (a beat stays a beat); wall-clock speed follows the host. Adopted as correct (the tape is
   beat-indexed). The sample-accuracy test covers a tempo change.

## Proof gates (plan §2)
- `run.sh --golden` **byte-identical** (the golden harness has no reel/transport-edge path — replay rides unit
  tests), and `--octaves-keep`.
- `CONFIG=Release … run.sh --alloc` **0**, including the existing record-while-replaying scenario (render side
  allocates nothing; staging is main-thread).
- New `ReelPhase2Tests` (sample-accuracy: replayed sample offsets == recorded, across buffers 64–4096, stop/
  start, tempo change; loop-seam no-stuck-note; `.toLive` hand-back closes every open note; derived position has
  no drift over long runs).
- `soak.sh` with random replay start/stop/mode (no stuck note); the `ReelDeckTests`/`ReelTapeAdapterTests`
  differential still green.

## Slice order (each green → land)
1. **2a engine — DONE (`692825d`):** `replayAnchored` + `stageRange`/`adoptStagedLoop` + `.loop`/`.toLive` +
   hand-back in `ReelDeck`/`Kernel`; `FourfoldAudioUnit.reelPlayRange` + `reelModeValue`; `ReelPhase2Tests` (30
   reel tests green). **Dual-path:** the current browser keeps its legacy phase-locked replay unchanged
   (`usesAnchoredReplay` false), so no interim regression — the anchored engine is new + tested + driven only by
   the new API (phase 3's UI). golden byte-identical; alloc 0 (PASS, Release, 61 docs).
2. **2b engine:** the re-stage/stream for long `.toLive` spans + a `bufLo/bufHi` coverage guard + the main-thread
   poll hook; soak with random replay start/stop/mode.
3. Docs + land. (Phase 3 — the new screen — then drives `reelPlayRange` with real selections + the LIVE/TAPE
   pill; Phase 4 — keep + multi-export — adds the model, a new stable AU parameter and session persistence.)
