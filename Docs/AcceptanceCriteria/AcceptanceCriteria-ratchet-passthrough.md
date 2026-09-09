# AC — RATCHET PATTERN standalone = PASS-THROUGH + unselect-to-mute (Paul 2026-09-08)

STATUS: BUILT (2026-09-09, branch `fix/ratchet-passthrough`; both decisions confirmed — OFF=mute required, sustained =
sweep-lens). Engine + RouterTest green off-device; matrix OFF option added; DEVICE EAR OWED (I can't hear it). v1 scope:
SINGLE-SLOT standalone cells (a [RATCHET PATTERN → X] chain keeps the old self-clocked generator — flagged follow-up).

## The bug
A lone RATCHET PATTERN fed a short chord stab "plays for each step." Root cause: standalone `.pattern`
(`Router.emitRatchetModal`, :4374) is a SELF-CLOCKED GENERATOR — it window-scans its RATE grid and STRIKES the pool on
every column-tick (`count 1 = single hit`), independent of the input's rhythm. So it manufactures a note per column even
from one short stab. This contradicts the v6 spec: "Ratchet pattern is NOT a driver. It receives MIDI, passes it
through, unless the current column is active in which case it ratchets it."

## The fix — standalone RATCHET PATTERN is a PROCESSOR of the input, not a generator
Reconciles "has its OWN clock" with "passes through": **the clock decides WHICH treatment applies; the INPUT decides
WHETHER anything sounds.** No input → silence (kills the phantom per-step notes).
- The ratchet's own clock (RATE · STEPS · SPAN) sweeps the STEPS columns — its OWN playhead, as today.
- A note is heard ONLY while it is actually sounding at the input (a held chord, or a stab for its short duration). While
  it sounds, its treatment = the column the ratchet's playhead is on at that moment:
  - **count 1** — PASS THROUGH: the note sounds at its natural onset + length; no re-strike.
  - **count 2…8** — RATCHET: while the playhead is on that active column, the sounding note is re-struck N times over the
    column's RATE slot (spacing slot ÷ N), as today.
  - **UNSELECTED (new OFF/rest state)** — MUTE: the note is silenced while the playhead is on that column.
- A short stab therefore: plays once if it lands on a count-1 column · ratchets if it lands on an active column · is
  muted if it lands on an unselected column — and NEVER re-fires on columns where no input is sounding.
- Downstream of a real driver ([ARP→RATCHET PATTERN]) is UNCHANGED (the v6 per-note fold — each arp note reads its
  column). Only the STANDALONE (no upstream driver) path changes.

## Two decisions I need from you (flagged mismatches)
1. **UNSELECT = MUTE reverses an earlier ruling.** CLAUDE.md records you rejected "rest-as-silence" on the ratchet
   TWICE (every column must sound). Unselect-to-mute is that same idea returning — an unselected column now SILENCES the
   pass-through. Confirm you want the OFF state back (matrix states become: OFF/mute · 1/pass · 2…8/ratchet).
2. **Sustained-input behaviour.** For a HELD chord (not a stab), a count-1 column = sustain (one continuous note), a
   ratchet column = re-strikes, an OFF column = a gap in the sustain. So a held chord through a mixed pattern becomes
   sustain-punctuated-by-ratchets-with-gaps. Confirm that's the intent (vs. "only re-trigger at the note's onset, ignore
   the playhead after" — a simpler onset-only reading).

## Test (RouterTest, off-device — the confidence anchor)
- A lone RATCHET PATTERN, all columns count 1, fed a short stab → emits the stab ONCE (pass-through), not once per step.
- All columns count 3 → the stab ratchets 3× on its column; still no per-step generation on silent columns.
- One column OFF → a stab landing on it is silent; neighbours unaffected.
- No input → total silence (no self-generated notes).
- [ARP→RATCHET PATTERN] regression: unchanged from v6.

## IMPLEMENTATION FINDING — this is a GLIDE-scale subsystem, not a patch (2026-09-09, both decisions confirmed)
Decision 2 (a count-1 column SUSTAINS continuously and RELEASES on key-up) means the standalone ratchet needs the
legato-hold reconcile machinery (adopt / close-on-release), but driven by the ratchet's OWN clock — and the normal hold
reconcile (`emitColumnHolds`) only runs at GRID-column transitions, not per window. So a per-window subsystem is
required, modelled EXACTLY on GLIDE (which already does this): immortal voices, tagged so the grid hold-reconcile skips
them, managed by a dedicated per-window emitter + a flush on every transport/scene edge.

### Approach (the GLIDE template)
1. **A `Voice` tag** (`rtcHold`, parallel to `glideAnchor`/`bypassRecv`) so `emitColumnHolds`' candidate/close loop
   (Router:1691) SKIPS these voices — the grid boundary must not close the ratchet's own-clock sustain.
2. **`emitColumnRatchetPattern(cell,…)`** — called EVERY window (sibling to `emitColumnMod`/`emitColumnGlide`, Router:2554).
   Resolve the ratchet column at `mNow` (own clock: rtcRate·STEPS·SPAN·rotate). Per this cell, reconcile its `rtcHold`
   voices via the proven `adoptLegatoBus`/`openVoice`(immortal)/`closeVoice` calls:
   - **count 1 (PASS)** → adopt the sustaining wires; open immortal voices for new held notes; close released ones.
   - **OFF** → close the cell's `rtcHold` voices (a gap).
   - **count 2…8 (RATCHET)** → close the sustain + window-scan N staccato sub-strikes over the column's rate slot (the
     existing `ratchetStrikeAt`, short offs — NOT immortal).
   - **input released (pool empty, no latch)** → close all the cell's `rtcHold` voices. (Release-safety, like GLIDE.)
3. **`flushRatchetPattern`** on every transport/scene/panic/latch edge (mirror `flushGlide`) → no stuck notes.
4. **Dispatch:** route a STANDALONE `.ratchet .pattern` cell to the new subsystem; SKIP it in the tick-loop generator
   (`emitRatchetRow`/`emitRatchetModal .pattern`). The `[ARP→RATCHET PATTERN]` per-note FOLD (v6) is UNCHANGED.
5. **Matrix OFF state:** `rtcSlices` gains 0 = OFF/mute (editor + decode); today's clamp `max(1,…)` becomes `max(0,…)`.

### Effort / risk
A focused engine build in the most invariant-sensitive code (voice table + adoption). LOW conceptual risk (GLIDE proves
the exact pattern), but it's ~a subsystem, not a line. Guarded by the RouterTest cases above + the fuzz harness
(no-stuck-notes / determinism), then a device ear-pass (I can't hear it). This is also the first concrete instance of
the stream-unification model — a standalone processor as a stream transform, not a self-driver.

### Alternative (interim, if you want the stab bug gone TODAY without the subsystem)
Input-gate the current generator + make count-1 hold to the ratchet-column end (re-articulated per ratchet column, a
soft repeat — NOT a seamless sustain). Kills the "plays for each step" on a stab immediately; the seamless count-1
sustain (decision 2) then lands as the subsystem follow-up. Smaller, shippable now, but count-1 isn't yet continuous.
