# REEL V3 — the paged looper (2026-11-16)

Plan of record for the reel from this ferry on; supersedes the phase-3 screen's three-panel/selection
model (`Docs/reel-redesign-plan.md` stays as the history of phases 0–4 and the tape/anchored-replay
engine, which this ferry builds ON, not over). Brief (Paul, 2026-11-16, decisions ratified by Q&A):

> Open the page and see the current page drawing what's playing — live. When it gets to the end of
> the pass the GUI makes it clear the engine is now replaying rather than generating. Navigate back
> and forth with a page width that can be halved or doubled. The selection boxes are not nice to
> use. No play and loop buttons — that's its natural state.

Ratified: opening the reel ALWAYS ends in a loop (even if you only came to export) · paging switches
the sound INSTANTLY, phase-matched · default page width 4 bars (the old 16-beat pass), ×½/×2 over
1…32 bars · closing hands back to live for now — the two-option close ("back to your session as it
was" / "continue from this point in the playback", with undo restoring the pre-reel state) is the
NEXT phase (§7): for a generative engine "continue from here" means relocating the engine's musical
clock, which touches every derived-from-beat system and is its own piece of work.

## §0 Vocabulary + the model

- **The page grid** tiles the SESSION TAPE's timeline (tape beat 0 = the first play; the session
  clock runs only while the transport plays, so stops/seeks never shear it) into **pages** of
  `pageBars × beatsPerBar` beats. Page N = tape beats `[N·W, (N+1)·W)`.
- **The live page** is the one containing the tape's write head — still being generated.
- **A tape page** is any earlier page — finished, replayable.
- The screen shows exactly ONE page as a full-size roll. There is no selection: **the page is the
  selection** (KEEP and EXPORT act on the shown page).

## §1 Behaviour

1. **Open** → the live page, drawing itself: the sweep line at the live write head, notes appearing
   behind it. The open page is ARMED: at the page boundary the engine flips to looping the page just
   completed. No button does this; it is the reel's natural state.
2. **The flip** (generating → replaying) is unmistakable: while LIVE, notes APPEAR at the sweep; at
   the boundary the page frame lights, the pill flips LIVE → TAPE, and from then on the notes are
   already there and LIGHT UP as the replay head re-strikes them (velocity-scaled, the page's PULSE
   convention). Spoken via VoiceOver announcement.
3. **Navigate**: ‹ › (and horizontal swipe) move one page at a time. The sound switches INSTANTLY,
   phase-matched — the new page picks up at the same position within the page, so the groove holds.
   Paging forward onto the live page = the hand-back: you are live again (pill LIVE), and the page
   draws itself; at its end it loops (same rule as open — armed is the only state).
   While you loop, the live engine keeps generating SILENTLY into the tape (phase 1c), so pages that
   "would have played" are all there when you page forward.
4. **Width**: ×½ / ×2 re-tile the grid (1…32 bars). Doubling keeps the shown page's START; halving
   keeps the half the playhead is in. While looping, the loop re-stages to the new page bounds,
   phase preserved (position within the page maps proportionally from the old page start).
5. **Minimap** (locator only, NO handles): a thin strip of the whole session, page-width cells, the
   shown page outlined, faint per-lane density; tap a cell to jump there (instant, phase-matched).
6. **KEEP** stars the shown page (the existing `ReelKeep` model + chips); **EXPORT** exports it (the
   existing phase-4 SMF path). Loading a keep chip = jump to its page(s).
7. **Close** (×) = back to live, as the session would have been (hand-back + the existing
   `reelStopReplay`/browsing-off path). §7 adds the second option later.
8. **Transport stop** while looping: today's rule holds — ringing notes closed once, replay pauses
   (host beat frozen) and resumes on restart. Stop while armed-not-yet-flipped: stay armed; the
   boundary is on the tape timeline, so a stop/start cannot shear it.
9. **Empty tape**: the existing drawn empty state ("Play to start the tape.").
10. Free-run (host stopped, KEEP PLAYING) does not record to the tape today; the reel page keeps
    that scope — it pages over what the tape holds.

## §2 Engine (all on the phase-2 anchored path; legacy pass browser stays compiled, dual-path)

- **`ReelDeck` — the staged handoff gains v3 fields** (same single atomic protocol): `stagedStartTapeBeat`
  (the page start on the tape timeline — events stay range-relative `[0, span)`), `stagedEndTapeBeat`
  (= start + span), `stagedArmEndTapeBeat` (non-nil ⇒ ARMED: flip to `.replaying` when the live tape
  clock reaches it), `stagedKeepAnchor` (top-up/page-switch: adopt events WITHOUT re-latching the
  anchor or re-arming), `stagedFlushOnAdopt` (page switch ⇒ blanket-off the old loop's ringing
  notes; top-up of the SAME page ⇒ no flush — the new buffer is a superset, offs match).
- **Emission rewritten on the host timeline** (same maths, scheduled-start-capable): an occurrence
  is `occHost = anchorHostBeat + k·span + ev.beat`; emit those in `[max(beatPos, anchorHostBeat),
  beatPos + windowBeats)` at `windowStart + (occHost − beatPos)/beatsPerSample`. An anchor mid-window
  therefore starts sample-exact. `.toLive` unchanged.
- **The ARMED flip** (Kernel, per playing window): the live tape beat is the recorder's own clock —
  `TapeRecorder.tick(forBeat: beatPos)/ppq` (a small public accessor; the segment mapping already
  exists and is stop/seek-proof). `remain = armEndTapeBeat − liveTapeBeat`; when `remain <
  windowBeats` the flip happens THIS window: `anchorHostBeat = beatPos + remain` (exact, possibly
  mid-window), state `.replaying`, `router.externalFlush` through `reelFlushTap` exactly as the
  legacy armed flip does. Tape and host beats advance 1:1 inside a segment, so this is derived, not
  accumulated (invariant 2).
- **Top-up staging** (the narrowed phase-2b): the page is staged INCOMPLETE (the drain runs ~0.25–0.5 s
  behind; at arm time the page may not even be fully generated yet). The UI's existing 0.25 s poll
  re-stages `events(pageStart, min(tapeEnd, pageEnd))` with `keepAnchor` until coverage reaches the
  page end. The missing events sit at the page's END, a full page-length from the flip, so the first
  loop iteration is already heard complete for any page ≥ ~2 s; `tape.drain()` at stage time keeps
  the gap to ~one render window.
- **Page switch / jump / width change** (instant, phase-matched): stage the new page's events with
  `keepAnchor` + `flushOnAdopt`; same span ⇒ `(beatPos − anchor) mod span` lands at the same
  position in the new page with no other work. A width change re-stages with the NEW span and an
  anchor adjustment staged alongside (`stagedAnchorShift`) so the playhead's bar-within-page maps
  proportionally.
- **UI feeds** (two atomics, written once per render window, read on the UI poll — the
  `emitterIndexLive` pattern): `reelLiveTapeBeat` (the recorder's write head — the LIVE sweep) and
  `reelReplayTapeBeat` (`startTapeBeat + phase` while replaying — the TAPE sweep). No allocation,
  no locks (invariant 3).
- **`FourfoldAudioUnit` API** (main thread): `reelArmPage(startBeat:endBeat:)` (stage + arm),
  `reelShowPage(startBeat:endBeat:)` (instant switch), `reelTopUpPage(...)` (poll-driven),
  `reelLivePositions() -> (live: Double, replay: Double, replaying: Bool)`. `reelPlayRange`,
  the keeps and the export API stay as they are.

## §3 UI (rewrite of `FourfoldReelBrowser`; pure layer first)

- **Pure** (`ReelScreen.swift`, extended; `ReelV3Tests`/`ReelScreenTests`): `reelPageLayout(size:)`
  (minimap · page roll · control bar — one shape, scales; the AUM small window just gets a shorter
  roll), the page-grid maths (`reelPageIndex/Start/End(beat:width:)`, ×½/×2 re-tiling incl. the
  keep-the-start / keep-the-playhead-half rules, 1…32 bar clamp), phase mapping for a width change,
  minimap cell maths, and every VoiceOver string. The existing selection/zoom/snap functions stay
  compiled for the old tests but nothing mounts them.
- **Views**: one Canvas page roll (lane-coloured notes, the LIVE pen sweep vs the TAPE replay head,
  frame lit while replaying, strike flashes from the poll feed), the minimap strip, and ONE control
  row: `‹ · › · ×½ · [4 BARS] · ×2 · KEEP ★ · EXPORT · pill · ×`. Keeps chips stay. START/PLAY/LOOP
  buttons, the drag-handle selection, and the overview/tape/close-up stack are DELETED from the
  mount (views kept compiled where cheap, the project's retire pattern).
- 4/4 stays assumed for bar maths (the phase-3 flag), noted device-owed.
- Reduce Motion: page slide → crossfade; the flip keeps its colour change, drops the pulse.

## §4 Proofs

- `run.sh --golden` + `--octaves-keep` byte-identical (no golden path opens the reel).
- `CONFIG=Release … run.sh --alloc` 0 (replay scenario included).
- New `ReelV3Tests` (engine): the armed flip lands sample-exact across buffer sizes 64–4096 and
  window-straddling boundaries; top-up re-stage ⇒ iteration 2 == the full page == iteration 1 + the
  late tail, no doubled/lost events; instant page switch phase-matched with no stuck notes (old
  loop blanket-off) and no doubled notes; width halve/double keeps the playhead's musical position;
  forward-onto-live hand-back closes every open note; stop/restart while armed and while looping.
- `ReelPhase2Tests`, `ReelDeckTests`, `ReelTapeAdapterTests` stay green (legacy path untouched).
- The reel screenshot/tap UI tests updated to the new screen (run on the mini, device-owed). A soak
  that DRIVES the reel (random open/switch/width/close) does not exist yet — the monkey suite taps
  it blindly; a scripted reel soak is a worthwhile follow-up, not a landed gate.

## §5 Slices (each green → land)

1. Engine: deck v3 staging + host-timeline emission + armed flip + feeds + `ReelV3Tests`. **DONE**
   (with a fifth adopt kind the build surfaced: `livePhase` — paging back from the live, not-yet-flipped
   page starts replay at the live clock's position in the page grid; a pre-flip top-up is instead a
   RE-ARM, so a keep-adopt can never clear a pending arm).
2. Engine: top-up protocol + page-switch/width re-stage + the AU API (`reelArmPage` / `reelShowPage` /
   `reelTopUpPage` / `reelRetilePage` / `reelLivePositions`); soak owed at landing. **DONE**
3. UI pure layer (`reelV3*` in ReelScreen.swift) + tests. **DONE**
4. UI views (page roll, minimap, control row, flip look) + VoiceOver; UI tests updated; docs. **DONE —
   look + feel device-owed.**

## §6 Known limits (declared)

- The tail of a very short page (1 bar at fast tempi) can be thin on the FIRST loop iteration only
  (top-up races the playhead; converges by iteration 2).
- Notes appear on the LIVE page up to one poll (~0.25 s) after they sound; the sweep itself is exact.
- At the armed flip the LIVE engine is silenced for the whole flip window, so live notes end up to
  one render buffer (≤ ~12 ms typical) before the boundary; the loop itself starts sample-exact AT
  the boundary (the same window-granularity class as the legacy pass flip and random-roll landing).
- 4/4 bar maths until the host time signature is polled; free-run output is not on the tape.
- A keep wider than the current page still loads (the page jumps to its start; EXPORT uses the
  keep's own range).
- Release-WMO note (2026-11-16): the SIL ownership verifier crashed twice optimizing
  `FourfoldAudioUnit`'s reel staging helpers — fixed by a loop-based, `@inline(never)`
  `reelRangeEvents`/`reelStageV3` with locals hoisted. Touch those shapes carefully.

## §7 Next phase (parked, Paul 2026-11-16): the two-option close

Close offers "back to your session **as it was**" (this ferry's behaviour) or "**continue from this
point in the playback**": the live engine relocates so its musical now = the tape point you are
hearing — for this engine that is an engine-clock offset at the ONE place the Router reads the
musical beat, so every derived system (passes, restart chains, canon clock, chance rolls — splitmix
by position, so replay-exact) lands where it was at that tape beat. A simple UNDO then restores the
pre-reel state (enter-reel records a checkpoint; choosing "continue" commits one undo step). Design
owed before build; AU-under-host-transport needs the offset to persist; standalone app can also move
its own `FourfoldTransportClock`.
