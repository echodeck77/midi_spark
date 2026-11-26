# DRUM CARD V2 — findings (§0.1 a–g, §10), before any change

Ferry: the MODE tab's DRUM card redesigned — the drum chosen on the card by a number+note scrub (no
pop-up, no drum name), POOL gone, the ranks shown as the VEL section's bars, a headphone rank preview.
All references are file:line on `feature/drum-card-v2` (off main `9e042cf`). Read-only mapping.

## (a) DRUM rows as built + heights
`poolTabContent` (EuclideousPage.swift:8163-8188) builds, in a `VStack(spacing: layout.gap)`:
`modeRow`(modeH 30) · `poolNowRow`(nowH) **shared, every mode, :8170** · per-mode (DRUM: `drumRow`
(sourcesH) :8177 + `drumVelRow`(midiH) :8178) · `Spacer` · `inputsApplyAllButton`(buttonH 30) :8183.
Heights from `euclideousInputsTabLayout(contentAreaH)` (Derivations.swift:13521 metrics / :13534):
ideals `[rowIdeal 44, sourcesH 30, midiH 30, rowIdeal 44]`, gap 14→8, floor 30; `contentAreaH =
cardContent − buttonH − modeH − 28` (:8166).
- **Landscape ref (card ~363×287):** MODE 30 · POOL 44 · DRUM 30 · VEL 30 · APPLY 30, gap 14.
- **Portrait ref (taller card):** same ideals (rows don't shrink), larger gap slack absorbed by the Spacer.
- **Ferry target:** MODE 36 · DRUM 54 · VEL 96 · APPLY (built), **no POOL**, slack above APPLY. DRUM gets
  its own fixed heights (not the shared layout); exact portrait-ref numbers reported when slice 4 lands.

## (b) TO KIT — `toKitFromDrum` (EuclideousPage.swift ~:8540)
`let k = euclideousKitFromDrum(line, lane)` → `edit(lane) { kitNotes=k.notes; kitNames=k.names;
kitVel=k.vel; laneMode = .kit; kitTemplate = nil }`. ONE undo step (one `edit`). The drum fields
(`drumNote/drumLow/drumHigh/drumRamp`) are untouched, so switching the mode back to DRUM restores the
drum. Ferry §3.3 relabels the button "CONVERT DRUM TO KIT" (two lines); behaviour unchanged.

## (c) The drum picker + every open path (to remove, §5)
`openDrumPicker(lane:)` (EuclideousPage.swift:8578): `closeAllOtherOverlays()`; seeds
`kitEditorRangeLow`/`kitEditorPrevNote`; sets `kitEditorIsDrumPicker = true`; `kitEditor =
KitEditorTarget(lane, rank: 0)` → the kit-editor overlay draws the piano keyboard in its `isDrumPicker`
(`picker`) branch (`kitEditorView`). **Callers:** (1) the DRUM POOL cell tap, :8268; (2) the drum-button
tap in `drumRow`, :8518. Both go away. To delete: `openDrumPicker`, its 2 callers, the `isDrumPicker`
branch of `kitEditorView` + the `kitEditorIsDrumPicker` @State. The kit editor's OWN "DRUM" button (kit
ferry §4.5 — sends the editor's selected rank to a drum) is a DIFFERENT path and stays.

## (d) How the engine reads drumNote per hit + immediacy (§2.2)
`euclideousDrumNote(line, lane)` (Derivations.swift:13438) → baked, once per snapshot build on the main
thread, into `EuclideousKitSnap` (Snapshot.swift:334) at `SnapshotBuilder.swift:538` (all 8 ranks = the
one drum note). The Router reads `p.kitSnap` once per window (`Router.swift:6281`) and fills the pool via
`fillKitPool` (Router.swift:3498). **There is no live-word for drumNote.** A UI edit reaches the render
thread on the NEXT snapshot/window (editDocument → rebuild → publish → acquire). ≤ one window ≈ "at once".
The existing VEL two-thumb slider already live-writes per drag move via `editStep` (burst undo) — the
scrub reuses exactly that: write `drumNote` live each move, coalesce the drag to one undo step.

## (e) Note-off integrity (§2.3) — ALREADY SAFE, no path changed
ONE refcounted tracker per (cable, channel, note): `openVoice` (Router.swift:1635) stores the struck
pitch on the voice — `voices[slot].note = note` (:1706); `closeVoice` (:1842) reads it — `let … note =
voices[i].note` (:1845) — and emits the note-off on that STORED pitch in both exits (:1873 group, :1881
refcount→0). `EchoTail` stores its own `note` (:1402, set :1461; drained pitch `e.note + k*e.pitch`
:2336). Every emission path forms its off from the stored voice: riff/stack (`strikeChord` :3095 →
`emitArtic`→`emitOneOutput`→`openVoice`/`closeVoice`), mask RATCHET/FILL/ALT (same), emitter-ratchet &
echo-tail spill (EchoTail), kit audition (:2272), pool audition (:2247). **No path recomputes a note-off
pitch from `drumNote` or re-resolves rank→pitch at release.** A live drum-note change only affects future
note-ONs. → §2.3 needs NO engine change; slice 2 adds tests only. **Report: zero note-off paths changed.**

## (f) The audition path (§2.4) + the DRUM headphone as built
Kit one-shot: `euclideousKitAudition` live word (Kernel.swift:73) → `euclideousPlayKitAudition`
(Router.swift:2257): one note, 120 ms gate (:2261), velocity passed through unscaled, across the lane's
`riff|notes` output mask (:2259); fires BEFORE the `!playing` early-out (block at :2660) so it sounds
while STOPPED; sets `euclideousKitAuditionOffSample` (:2269) so the stopped-silence invariant allows the
ring (Kernel.swift:604). It does NOT explicitly cut a prior preview today (overlap covered by the
exemption). §2.4 wants a new audition to first CLOSE the lane's previous audition note → a small engine
add (track the lane's last-audition voice; close via `closeVoice`). Pool audition `euclideousRunAudition`
(Router.swift:2223) runs only when the clock runs (after the :2790 early-out). The DRUM POOL cells'
"headphone" today just opens the picker (:8268) — there is no separate DRUM headphone; §4 adds one.

## (g) The lane step clock while the transport is STOPPED
`Router.process` early-outs `if !playing { … return }` (Router.swift:2790) BEFORE the step/column
derivation (:2797+) — so the lane step clock is frozen while stopped, UNLESS free-run substitutes
`rPlaying`/`rBeat` in the Kernel (`if freeRunEnabled && !playing { rPlaying = true; rBeat = freeRunBeat }`
Kernel.swift:522). Free-run = host-stop behaviour KEEP PLAYING (the DEFAULT; `EuclideousHostStopBehavior`
Models.swift:246, resolved `.keepPlaying` Models.swift:~4292; `setFreeRunEnabled` FourfoldRootView.swift:
728). So the normal step clock advances while stopped only under KEEP PLAYING.
**§4.3 rank preview clocking:** it rides the lane step clock → runs while stopped under KEEP PLAYING (the
default) and while playing; under host-stop = STOP the clock is frozen and the preview needs the transport.
This is reported per §4.3's own "if it doesn't run while stopped, report how you clocked it".

## §10.6 — spec vs code contradictions found
- Ferry §3.1 lists DRUM's built rows as "POOL, DRUM, VEL" — consistent: POOL is the shared `poolNowRow`
  drawn in every mode (:8170), DRUM = `drumRow`, VEL = `drumVelRow`. No contradiction.
- §2.1 note-name convention (36=C2, 48=C3, 56=G#3, 60=C4, 0=C-1, 127=G9) **matches the existing
  `euclideousNoteViewName`** (and the kit-editor keyboard) — reuse it; no new function, no octave-naming
  divergence to report.
- §2.3 (note-off integrity) is already satisfied by the architecture (finding (e)) — the ferry's "track it
  per sounding note, fixed storage, no allocation" is exactly the existing `voices[]` tracker.
