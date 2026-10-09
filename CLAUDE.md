# MidiSpark — project briefing

AUv3 MIDI processor (`aumi`) for iPadOS. One line: **"Don't sequence notes. Sequence what
happens to them."** An 8×8 grid sequences MIDI *processors* (arps, ratchets, gates) over
time; held chords go in, five MIDI outputs come out — ALL + A–D (delta §7b). Primary host: AUM.

## How I respond to Paul (apply to EVERY reply)
- **TL;DR FIRST.** Open every response with a one- or two-sentence TL;DR — the bottom line before any
  detail, so Paul gets the gist without reading the whole thing. (This is a hard rule, not a sometimes.)
- **FLAG POSSIBLE MISMATCHES.** Whenever I make a change, explicitly point out where it might NOT match
  Paul's expectations — device-owed visuals I can't see or hear, judgment calls I made on an ambiguous
  ask, opacity/size/colour values I picked, and interpretations that could differ from his intent. Never
  let a likely mismatch go unstated; naming it up front saves a round-trip.

## Git workflow — AT LEAST TWO INSTANCES, SEPARATE WORKTREES (Paul 2026-09-11, hard rule — supersedes the shared-tree rule)
Paul runs **AT LEAST TWO Claude Code instances at once** (sometimes more), each in its OWN git **worktree** — a
separate working directory backed by the ONE shared `.git`. This is why they can NEVER collide in the working tree
(the old shared-tree "only commit my own files" rule caused 3 collisions and is RETIRED):
- **Worktree A (primary):** `/Users/paulbarrett/src/midi_spark`
- **Worktree B (second instance):** `/Users/paulbarrett/src/midi_spark-b` (branch `wt-b`)
- (Further worktrees may exist — the same rules apply to all.) Every worktree shares the SAME `.git` (one repo, one
  set of refs/remotes) but has its OWN checkout + its OWN branch, so `git status` in one NEVER shows another's edits,
  and `build/`/`DerivedData` are per-worktree (gitignored). The only shared state is the refs/remote — so integration
  is the only coordination point.

**▶ WHEN A PIECE OF WORK IS COMPLETE: commit → merge to `main` → push — ROUTINELY, WITHOUT ASKING (standing
authorization).** Don't leave finished work sitting on a local branch. "Complete" = it builds and its tests are green
(for device-only/visual work, when the off-device checks pass — flag that device verification is still owed, but
still commit+merge+push).

**Rules (standing authorization; don't ask each time):**
1. **Stay in your own worktree.** Never `cd` into another instance's worktree dir. Work, commit, and push from the
   directory you were launched in. `git status` is clean of the other instances, so stage `-A` freely (no
   cross-instance sweep risk — their edits live in their own checkouts).
2. **Branch per task, off `main`** (`git checkout -b <feature>`); commit as you go.
3. **On completion, integrate into `main` via REMOTE fast-forward** (needs no local `main` checkout, so the worktrees
   never fight over who holds `main`): `git fetch origin && git push origin <feature>:main`, then `git fetch` to refresh
   local `main`. If rejected (another instance advanced `main`), `git rebase origin/main` the feature branch, rebuild to
   confirm it still compiles, then push again. (Equivalently: FF a local `main` to `origin/main`, FF it to the feature,
   `git push origin main` — but then return your worktree to its own branch; don't leave `main` checked out, as that
   blocks the other worktrees.)
4. If a shared file genuinely conflicts on integration (two instances changed it), git surfaces it at the rebase/merge
   — resolve it there, don't guess in the working tree.
(A stale worktree can be pruned with `git worktree remove <path>` / `git worktree prune`; `git worktree list` shows both.)

## Claude↔Claude message passing (`_dear_claude_code/` inbox · `_dear_claude/` outbox — gitignored)

An async channel with a PARTNER Claude (design/planning context). Both dirs are gitignored and
NEVER committed. The names read as the letter's salutation: **`_dear_claude_code/`** holds messages
addressed to ME (my INBOX, from the design side); **`_dear_claude/`** is where I write TO the design
Claude (my OUTBOX). Trigger is **MANUAL** — run this when the user asks (e.g. "check incoming"):
1. **CHECK `_dear_claude_code/`** for new files. Each is documentation/instruction from the partner.
   - An UPDATED version of a doc I hold (this CLAUDE.md, a `Docs/*` file) → **MERGE** its changes
     into my copy (reconcile, don't blindly overwrite — we edit in parallel, so watch for reverts).
   - A NEW document → **ADD** it to the right place (`Docs/`, etc.).
   - After processing a file, **DELETE it** from `_dear_claude_code/` (it's consumed), and **RECORD
     which files I read** so my next message can ACKNOWLEDGE them back to the partner (symmetry:
     he applies the same delete-on-acknowledgment rule to his outbox that I apply to mine).
2. **REPLY via `_dear_claude/` — but only when there's something of IMMEDIATE VALUE** (a merge that
   changed something, a real answer, a decision, a blocker). **Do NOT write a ceremonial/empty
   reply.** Silence is a valid response.
   - **DELETE-ON-ACKNOWLEDGMENT (2026-07-25): do NOT pre-empty the outbox.** Outbox files STAY until
     the partner has explicitly acknowledged reading them (he lists which files he read in his
     messages). Only then delete the acknowledged files. This makes the manual, human-relayed channel
     lossless — nothing is cleared before it's confirmed received. **Ask the partner, in each reply,
     to tell me which files he read.**
   - **CONSTRAINTS: keep it FLAT (no subdirectories) and ≤ 20 files total** — Claude's document read
     limit is 20. Bundle source into a SINGLE file (`SOURCE-SNAPSHOT.md`, each `.swift` under an H2
     header) rather than shipping loose files, so FINDINGS + bundle = 2 documents.
3. Keep the tracked side clean: commit only real repo changes (`.gitignore`, docs, code) — the
   inbox/outbox contents are transient and untracked.

## Authoritative documents (read before designing anything)
- `Docs/midispark-spec-v2.8.md` — the base spec (consolidated, self-contained) —
  **read together with `Docs/midispark-spec-v3.0-delta.md`, which supersedes the
  routing model (§2: receiver-picked references — any row, cycles legal-and-
  silent, fan-out; ▾/+SRC/OUT CH/INHERIT removed; channels are filter-in/
  stamp-out; outputs are ALL + A–D cables) and the perform visual language
  (§5: four-row text cells, arrow playhead, one-clock rule) and the desk
  (§6: responsive performance surface).** Where they conflict, the delta wins. Behaviour
  changes still require a spec revision first.
- `Docs/migration-tree-routing.md` — the survey-first plan for the v3.0 graph-routing
  migration. Now HISTORICAL: its engine commits AND the GUI reconciliation are both DONE
  and device-verified. Read it for the rationale behind Router/Snapshot/graph-routing shape,
  not for "what's next" (that's the status section below).
- `Docs/standalone-plan.md` — DEFERRED milestone (standalone app = a second HOST of
  the same AUv3), but its THREE SEAM RULES are enforced NOW: (1) import hygiene —
  only `MidiSparkAudioUnit.swift` / `AudioUnitViewController.swift` / `Kernel.swift`
  may import AudioToolbox/AU frameworks; Router/Derivations/Snapshot*/Models/Emission/
  Diag/TestSessions and ALL of GridUI stay Foundation/SwiftUI-only. (2) one-named beat
  seam. (3) emission is the only place that knows cables. STATUS: seam (3) is realised
  as the `MIDIEmitter` protocol (`Emission.swift`); `Router.swift` was made Foundation-
  only against it (was a violation through v0.6) and now compiles into the unit-test
  target — see `RouterTests.swift`. `Kernel.swift` KEEPS AudioToolbox on purpose (the
  render boundary — host transport/context blocks + render-event types; it hosts the
  `LiveMIDIEmitter` adapter and sheds the import only when the standalone swap replaces
  those host reads per rule 2). GridUI is clean (SwiftUI-only).
- `Docs/router-design.md` — the engine reference (pools/sounding-sets model,
  voice/refcount design, PHASE formulas, per-render flow). Its routing
  derivation and commit plan are marked HISTORICAL (old model, as built);
  use it for what the migration's guard-rail says not to touch.
- `Docs/test-procedures.md` — the device playbook: canned sessions (repo carries
  T1–T17; the doc details T1–T11 + reconciled intents), bridge regression B1–B4,
  the UI-size-checkpoint gate, milestone gates, and the reporting template. When
  asking the human to verify anything, quote the procedure by name.
- `Docs/factory-scenes.md` — the SIXTEEN factory scenes for the scene strip: a
  curriculum disguised as a record (Part I no routing → Part II vertical →
  Part III the graph), with a STANDING RIG (recommended sounds on emitters A–D)
  and PLAY/LISTEN lines per scene. Slot 15's cycle/backward-tap are INTENTIONAL;
  every LISTEN line ships ear-tested with the rig as described. Distinct from
  TestSessions T1–T17 — never merge. **REVISED AFTER SceneFactory landed: the
  doc is authoritative — scenes 9 and 11 changed mechanically (9: the wine toll
  now taps ⇐R1, not ⇐MIDI; 11: gold RETRIG line now ⇐R1 →B, teal moved to
  C5–C8 R2) plus new SOUNDS/PLAY guidance throughout. Reconcile SceneFactory +
  its tests to the doc, then re-ear-verify the changed scenes.**
- `Docs/ui-port-guide.md` — mockup→SwiftUI mapping, design tokens (the 16 Colour
  hexes are canonical), gesture map, and the REVISED order of work (a grid
  slice exists; reconcile, don't rebuild).
- `BRIDGE_NOTES.md` — snapshot bridge design + hear-it tests.
- GUI mockups — **the built plugin is the living reference for SHIPPED features**;
  mockups are the behavioural spec for UNBUILT ones. TWO mockups survive (the earlier
  v26–v59 + v62 lineage were deleted 2026-09-04 as spent history): **`Docs/midispark-
  preview-v60.html` = canonical** (the last full simulator: colour pairs/ALT box/gradient
  morph bodies, cell editor + stamp banner, §6a faces, parametric glyphs, receiver bands,
  the legibility card; also the §6a EMITTER TOGGLES reference) and **`-v61.html` = the
  RATIFICATION BOARD** (a decision surface, not a full sim). NOTE: both PREDATE the rooms
  interface that actually shipped — they're the old tab/perform-era simulators, useful for
  colour/face/glyph reference but NOT the current surface (that's the built plugin + the
  CLAUDE.md status log). The AUTO/WIDE/TALL toggle is a browser preview affordance — never port it.

## Vocabulary (spec §1 — enforced, including in code comments and UI strings)
- **Machine** = the treatment (type + params + its chain). ID-based: the 16 canonical
  palette defaults PLUS unlimited ephemeral machines (`buildMachineReg` registry + `machineHueOverride`
  + GC). The old fixed-16 cap is gone. (A/B states + morph are decode-only zombies — render-dead.) Never "preset".
  (RENAMED 2026-09-09 from "Colour" — the object is a machine, not a user-picked sound colour; its display
  **hue** is *derived* from its `machineID` via `machineHue`/`machineHexes`. On-disk keys moved with the
  rename; pre-rename saved sessions factory-reset by design. Older status-log entries below still say "Colour".)
- **Cell** = one Machine placed at a grid position with its own wiring/state.
- **Preset** = ONLY the host-level fullState document. Nothing inside the app uses this word.
- **Emitter** = a bus A–D as the user-facing concept (its cable + its channel stamp).
- Public/product name: **"8x8 State"** — DECIDED and APPLIED (display-only). It is the
  app `CFBundleDisplayName`, the extension `CFBundleDisplayName`, the AudioComponents
  `name` ("8x8 State: 8x8 State" → AUM shows "8x8 State"), and the in-plugin/app
  logotype ("8×8 STATE"). The AppIcon (App/Assets.xcassets, single 1024 master →
  actool downscales) carries the same mark. EVERYTHING at the code/identity level stays
  `MidiSpark`: target/scheme/module names, `PRODUCT_NAME`/`CFBundleName`, bundle IDs
  (`com.paulbarrett.MidiSpark[.AU]`), and the aumi component codes (type `aumi`,
  subtype `MSpk`, manufacturer `MSPK` — never change these; they are the plugin's
  identity and saved AUM sessions key on them).

## Architecture invariants (violating these = bug, regardless of tests passing)
1. **The render thread reads ONLY `SnapshotBox`** (immutable, atomically published).
   It never touches `PluginState`. UI/document → `SnapshotBuilder` → `SnapshotStore.publish`
   (MAIN THREAD ONLY) → kernel `acquire()` (one atomic load, no locks, no allocation).
2. **Derived, never accumulated:** playhead, arp phase, swing — all pure functions of host
   beat position. No timers, no counters that persist across renders (the note tracker and
   the param-override table are the sanctioned exceptions; see Kernel.swift comments).
3. **No allocation / locks / ObjC dispatch on the render path.** Fixed-size storage only.
4. **No stuck notes, ever:** every transition (transport edge, mute, edit, column change)
   closes sounding notes; note-offs are reference-counted per EMITTED
   (cable, channel, note) — five cables once ALL lands (spec §7 collision
   policy + delta §7b).
5. **Parameter addresses are STABLE forever:** 0 stepRate · 1 swing · 100+i transpose ·
   200+i morph · 300 morphMaster · 400+i macro (the 8-slider automatable bank).
   Add new addresses; never renumber or reuse.
6. Host parameter changes arrive via TWO routes: tree setValue (observer → snapshot) and
   render-side `.parameter/.parameterRamp` events (kernel override table, cleared on each
   new snapshot generation). Keep both paths working.

## Build system gotchas (learned the hard way)
- The `.xcodeproj` is a BUILD ARTEFACT. `xcodegen generate` after ANY file add/remove or
  project.yml change. Editing existing files needs nothing.
- `AUExtension/Info.plist` is HAND-MAINTAINED (declares the `aumi` audio component:
  type `aumi`, subtype `MSpk`, manufacturer `MSPK`). It is excluded from XcodeGen's
  `info:` generation deliberately — never add an `info:` block to the MidiSparkAU target,
  and never let the plist into sources without the exclude. XcodeGen will silently gut it.
- Extension bundle ID must be prefixed by the app's:
  app `com.paulbarrett.MidiSpark`, extension `com.paulbarrett.MidiSpark.AU` (explicit
  PRODUCT_BUNDLE_IDENTIFIER in the MidiSparkAU target).
- Compile check from CLI (the `DEVELOPER_DIR` prefix is REQUIRED — `xcode-select`
  points at CommandLineTools, whose older Swift can't parse the Xcode SDK):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project
  MidiSpark.xcodeproj -scheme MidiSpark -destination 'generic/platform=iOS'
  CODE_SIGNING_ALLOWED=NO build`. Prepend `xcodegen generate &&` only after
  adding/removing files. *Device install* happens in Xcode.
- Off-device unit tests (FIRST line of verification, ~seconds, no simulator):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test
  -project MidiSpark.xcodeproj -scheme MidiSparkTests -destination
  'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData`. The pinned
  `-derivedDataPath` is REQUIRED: the default DerivedData intermittently serves a
  STALE test bundle (old count, hidden failures). The macOS `MidiSparkTests`
  target compiles the Foundation-only pure sources directly (no iOS/CoreAudio
  link); keep new pure logic in Derivations.swift so it stays testable.
- Device testing is manual: the human runs from Xcode onto the iPad and verifies in AUM.
  You cannot hear anything. When behaviour needs verification, say exactly what to check
  in AUM (the diagnostic panel in the plugin UI shows live kernel state at 4 Hz).

## Current status (update this section as work lands)
- **▶ EUCLIDEOUS — a banner replaces the I/O tab's MIDI IN/KEY/CHORDS buttons whenever RIFF has overridden
  them (2026-10-09, on `fix/euclid-no-scroll-direction-order-2x2-grid`; macOS 1243 green incl. +1, iOS builds
  clean). Paul: "Something is up with the midi in settings. When I choose midi in it plays something else - a
  chord grid maybe? I choose key and nothing plays. Please review this." Investigated both reports. **MIDI IN
  "plays a chord grid" — a real, traceable interaction, not a bug in the engine:** the pre-existing `useRiff`
  mechanism (built well before this session's CHORDS work) makes a lane's RIFF tab, when its own direction is
  set to anything but OFF, COMPLETELY REPLACE that lane's `noteSel`/octave — `runEuclidLine`'s `if useRiff {`
  branch never even looks at the lane's own `sourceMode`. This was already true and already documented as
  deliberate ("replaces NOTE/OCT entirely") — but this SAME session's earlier CHORDS turn changed what the
  riff pool itself contains: it now copies `laneNotes(0)`/`laneCount(0)` (lane 1's own resolved pool, whatever
  source lane 1 happens to be on), so if lane 1 is on CHORDS, EVERY riff-enabled lane audibly plays the chord
  progression regardless of its own I/O tab's MIDI IN/KEY/CHORDS selection. The I/O tab gave no on-page
  indication this was happening — a lane's own buttons looked live and selectable while being entirely
  inert. **KEY "plays nothing" is separate, pre-existing, and correct per spec** — confirmed via
  `Router.swift`'s `.key` branch and this file's own §4.4 note ("KEY-mode pool mapping stays unresolved") —
  not a regression, not touched this round. **FIX, UI-clarity only, no behaviour change:** `ioSourceRow`
  (EuclideousPage.swift) is now `@ViewBuilder` and branches on `line.useRiffResolved` — when true, it shows a
  plain banner ("RIFF IS ON — SOURCE FOLLOWS LANE 1 (SEE RIFF TAB)") instead of the three now-inert MIDI IN/
  KEY/CHORDS buttons, so a lane's I/O tab can no longer look actionable while doing nothing; when false, the
  three buttons render exactly as before. Also fixed a stale Router.swift comment inside the `if useRiff {`
  branch left over from the riffSrcChanMask→`laneNotes(0)` refactor (described the deleted mechanism, not the
  current one) and added `testEuclideousUseRiffIgnoresItsOwnLaneSourceModeEntirely` (a riff-enabled lane with
  its own `sourceMode` explicitly set to MIDI still plays lane-0's CHORDS-sourced pitches, proving the
  override is real and total, not a display quirk) as a permanent regression guard for the exact interaction
  that prompted the report. **DEVICE-OWED:** the banner's legibility/wording at real lane width; confirm it
  reads as an explanation rather than an error; confirm toggling a lane's RIFF direction to OFF and back
  correctly swaps the banner and the three buttons live.**
- **▶ EUCLIDEOUS — the 3 gesture pads become 4: TILT/HITS · OFFS/CNT · GATE/VEL · NOTE/OCT, and a new TILT
  parameter biases a lane's own Euclidean hit distribution left/right (2026-10-09, on `fix/euclid-no-scroll-
  direction-order-2x2-grid`; macOS 1242 green incl. +5, iOS builds clean, no new warnings). Paul: "I'm
  interested in a TILT control to bias the distribution of hits to the left or right. This should be the
  horizontal axis on the first xy box, with hits being the vertical. Next to that is another with offset on x
  and count on y, then another with x as gate and y as velocity, then the final x/y as it is now." A genuinely
  NEW algorithmic concept (no prior "temporal/positional tilt" anywhere in this codebase — the existing
  `*Tilt` fields, velTilt/chanceTilt/strumVelocity's tilt, all bias VELOCITY by pool rank, a different axis
  entirely) — built as a reasoned, deterministic first pass and flagged for ear-verification rather than
  guessed silently. **`euclidTiltPattern`** (Derivations.swift, pure): reshapes an ALREADY-BUILT K-of-N
  pattern (called right after `euclidPatternInto`, post-rotation) by taking the K existing hits in ascending
  order, normalising each one's RANK among the K hits to 0...1, warping that rank through a power curve
  (`t^gamma`, `gamma = 2^(-2×tilt)` — tilt=-1 ⇒ gamma=4, compresses hits early; tilt=+1 ⇒ gamma=0.25,
  compresses them late), then re-placing each at `round(warpedRank × (N−1))` with a deterministic forward-
  nudge on collision. `tilt=0` is an EXACT no-op (gamma=1, the identity warp) — chosen specifically because
  this engine's own standing invariant (derived, never accumulated — replay-exact) rules out the more
  obvious-sounding "randomly reshuffle toward one side" reading of "bias the distribution." `EuclidLine.tilt:
  Double?` threaded through all 4 required sites (struct/decoder/resolved-accessor/SnapshotBuilder's fresh-
  literal rebuild); `runEuclidLine` gained one `tilt: Double` parameter and ONE insertion point — every
  downstream read of `euclidBuf` (the hit/rest test, the CYCLE/RANDOM ordinal walk, MISS's complement) picks
  up the tilted shape for free, zero other changes needed anywhere in that function. **THE PAD RESHUFFLE:**
  `EuclideousGestureTab` widened 3→4 (`tiltHits`/`offsetCount`/`gateVelocity`/`noteOctave`) — HITS and OFFSET
  (rotate), which used to share one pad, now split across the first two pads, each paired with a NEW axis
  (pad 1 Y stays HITS, X becomes TILT; pad 2 X stays OFFSET, Y becomes the step COUNT — a brand-new drag
  control for STEPS, previously reachable only via pinch on the comet bar, now ALSO here, mirroring the
  pinch's own clamp-pulses-down-if-steps-shrinks rule exactly); GATE/VELOCITY's axes SWAP (gate now X, was
  Y); NOTE/OCT is byte-identical, per Paul's own "the final x/y as it is now." Two new HUD/face formatters
  (`euclideousTiltHitsHUDInfo`/`euclideousOffsetCountHUDInfo`); the existing VEL/GATE formatter is reused
  UNCHANGED for the swapped pad (it already showed both resolved values regardless of axis). **A DISCLOSED,
  UNAVOIDABLE SIZE CONSEQUENCE:** `minLaneSize` (the touch-target floor every lane card's own minimum size
  derives from) grows from `3×minPadSize` to `4×minPadSize` (132→176pt) — a lane can no longer usefully
  shrink as far as before without its 4th pad going sub-floor. The gesture-pad row also now computes its OWN
  width (`size/4`) SEPARATELY from the PATTERN tab's DIRECTION/HIT-MISS-RATE rows beneath it (still `size/3`,
  untouched, nothing asked to change there) — meaning the two previously-aligned row sets no longer line up
  column-for-column, a cosmetic side effect of widening one without the other, named here rather than quietly
  absorbed. **DEVICE-OWED:** the TILT formula's actual musicality across a range of K/N combos (a first-pass
  power-curve choice, not device-tuned); the 4-pad row's legibility/touch-feel at the new, necessarily-larger
  minimum lane size; whether the gesture-pad-row/pattern-tab-row misalignment reads as a problem worth a
  follow-up fix.**
- **▶ EUCLIDEOUS — a CHORDS button beside KEY in the header opens a pop-up chord grid (degree matrix + rate),
  giving the page its own self-contained progression generator — replacing the "find an external chord-door
  receiver" CHORDS mechanism shipped minutes earlier the same day (2026-10-08, on `fix/euclid-no-scroll-
  direction-order-2x2-grid`; macOS 1242 green incl. +5 new/+2 rewritten/-1 redundant, iOS builds clean). Paul:
  "Move the key selector to the top header. Next to it place a chords button that opens a pop-up to a chord
  grid with rate control. Base this on the existing chord grid used on the chord door." Read as — and flagged
  as the judgment call it is — closing the exact gap named at the end of the PREVIOUS entry ("CHORDS needs an
  actual receiver already configured as a chord door... no in-page way to tell which"): CHORDS now generates
  its own content instead of depending on external configuration. **HEADER COLLAPSED TO ONE ROW:** KEY (−/
  chip/+) moved from row 2 into row 1, alongside a new CHORDS button; row 2 had nothing left in it once KEY
  left (its own LANES switch was already retired into the per-lane I/O tab the entry below built), so the
  header simplified to a single row — freeing real vertical space for the lane/riff grids, not scope creep.
  `headerScale`'s own width budget widened 620→860 to match the busier row. **MODEL:** `PluginState.
  euclideousChords: MachineParams?` — the EXACT same storage shape the chord door's own `Receiver.chordSeqs:
  [MachineParams]?` already uses (only `chords*` fields ever touched) — PATTERN mode only, no MODE/SCALE-FROM/
  VOICING/SPREAD/WALK (named scope: "a chord grid with rate control," not the full chords-processor feature
  set); nil ⇒ `MachineParams()`'s own already-sensible I-I-V-V-IV-IV-V-V default, audible immediately, not
  silent. **ENGINE:** resolved in SnapshotBuilder directly into the SHARED `chordsMode`/`chordsDegrees`/
  `chordsSteps`/`chordsRateBeats`/`chordsRotate`/`chordsVoicing`/`chordsSpread` SnapParams fields (confirmed
  safe to reuse, not a parallel set — `chordSeqNotes`'s own doc comment explicitly designs it to take any
  SnapParams: "SHARED by the CHORDS PROCESSOR stage AND the chord DOOR pool-fill... this is the 'future
  processor work reflects on the door' contract") plus 2 new dedicated fields (`euclideousChordKeyRoot`/
  `KeyTones`, since `chordSeqNotes` takes the key as explicit params, not read from the shared fields — fed
  from Euclideous's OWN page-level KEY, not a receiver door, since this page has no door reference for CHORDS
  the way the regular processor's SCALE FROM does). Router.swift's per-lane fill loop (built minutes earlier
  the same day) now branches on `sourceModeResolved` directly for CHORDS — calling `chordSeqNotes` once per
  cell-render (not per-tick, matching every other pool-fill's own "stable across the column" convention) —
  instead of resolving a chord-door channel mask; the riff's own pool (already "follows lane 1") copies lane
  0's resolved pool wholesale now (`laneNotes(0)`/`laneCount(0)`), so it transparently picks up whichever
  source — MIDI, CHORDS, or the legacy-OMNI fallback — lane 0 is actually on, with zero separate logic.
  `riffSrcChanMask`/`fillRiffSrcFromPool` deleted outright (confirmed zero remaining references anywhere,
  tests included) — genuinely dead once riff stopped needing its own independent channel-mask resolution.
  **A REAL, SIGNIFICANT GAP FOUND BY A FAILING TEST, not inspection:** a pre-existing top-level guard in
  `Router.process()` — `guard pool.count > 0 || latchMask != 0 else { ...; return }` — silently skipped ALL
  per-row tick emission (never even reaching `emitGeneratorRow`) whenever NOTHING was held or latched
  ANYWHERE in the whole session. Totally safe before this feature (every processor type has always needed
  SOME live input to make sound) — CHORDS breaks that assumption outright, generating content with zero live
  input by design. Traced with two rounds of throwaway `FileHandle.standardError.write` RTCDEBUG tracing
  (confirmed `emitGeneratorRow` was never even being called, not that chord resolution was computing the
  wrong answer) after a test with a genuinely empty `NotePool()` kept failing both its assertions at once —
  fixed by widening the guard's own condition with one cheap, allocation-free check
  (`euclideousChordsActive`, `box.cells[Snap.euclideousRow].procs.first?.euclidLines.contains { $0.
  sourceModeResolved == .chords } ?? false`), mirroring the SAME "must run regardless of the pool" exception
  `emitFreeMod`/`emitColumnRatchetPattern` already get, just folded into this guard instead of a separate
  pre-guard subsystem call since CHORDS rides the normal dispatch once past it. Without this fix, a
  Euclideous session with every lane on CHORDS and nothing else held anywhere in the whole document would
  have stayed PERMANENTLY SILENT. **UI (EuclideousPage.swift):** a new `chordsPopupCard` — NOT a literal
  `ProcessorBox(type:.chords)` mount the way the chord door reuses the whole processor editor (that
  component's own SCALE-FROM door-picker control would be a convincing-looking but genuinely dead control
  here, since Euclideous has no doors and always feeds its own page-level key directly) — instead a bespoke
  grid reusing the real PURE functions the matrix is built from (`chordsMatrixCell`/`degreeLabel`, already
  free/shared in Derivations.swift), modelled closely on this page's own `riffGridView` tap-to-set pattern: a
  STEPS stepper, a 6-case StepRate seg row, and an 8-row (I...vii + REST) × STEPS-column degree matrix, tap-
  to-set (no toggle-to-clear — matches the regular CHORDS processor's own unconditional-write behaviour
  exactly, not the riff grid's different convention). **TESTS:** 2 pre-existing tests from the earlier-same-
  day per-lane-I/O work (`testEuclideousLanesEachResolveTheirOwnIndependentSourceMode`,
  `testEuclideousRiffPoolIsGovernedByLane1EvenWhenADifferentLaneConsumesIt` — the latter rewritten TWICE in
  one session as the CHORDS mechanism itself evolved) updated to configure `euclideousChords`/`euclideousKey-
  Root/Type` instead of a `doorMode: .chord` receiver, verified against `diatonicChord`'s own exact formula
  (C major degree 0 ⇒ triad [48,52,55]); a third, now-fully-redundant sibling test
  (`testEuclideousRiffPoolFollowsLane1sOwnSourceChoice`) deleted outright rather than also rewritten, since
  the kept test already subsumes its claim plus more. +2 SnapshotBuilderTests (chords resolve into the shared
  fields on Euclideous's row only, a different row's cell stays at the bare SnapParams defaults; an untouched
  config resolves to the audible default, not silence). **DEVICE-OWED:** the new one-row header's real-width
  legibility with KEY+CHORDS both present; the chord grid popup's own size/legibility; confirm a CHORDS-mode
  lane actually sounds correctly with the live plugin, not just in the test harness.**
- **▶ EUCLIDEOUS — a new per-lane I/O TAB (MIDI IN · KEY · CHORDS + the lane's own OUT toggles), replacing
  the GLOBAL "LANES KEY|MIDI" switch and the riff's own "SOURCE KEY|MIDI" switch entire (2026-10-08, on
  `fix/euclid-no-scroll-direction-order-2x2-grid`; macOS 1236 green incl. +4 new/+3 rewritten, iOS builds
  clean). Paul: "I a new tab for input/output per lane control, as the first tab. It will have midi in/key/
  chords on the first row, and the four emitter toggles on the second row. Get rid of the similar controls on
  the header and riff." Three real decisions needed before any code, asked via AskUserQuestion rather than
  guessed (wrong guesses here meant real engine rework, not a UI redo): **CHORDS = a receiver configured as a
  CHORD door** (not a key-built chord); **MIDI IN/KEY/CHORDS are independent PER LANE** (not a relocated
  single global value); **the riff's shared pool now FOLLOWS LANE 1's own choice** (not a fixed receiver, not
  its own separate control). **ENGINE (the real work — the UI tab itself is thin):** new `EuclideousLaneSource`
  enum (`midi`/`key`/`chords`) + `EuclidLine.sourceMode: EuclideousLaneSource?` (nil ⇒ `.midi`, threaded
  through all 4 EuclidLine sites — struct/decoder/resolved-accessor/SnapshotBuilder's fresh-literal rebuild,
  this file's own standing hazard checklist). Needed NO separate MachineParams/PluginState hop — `EuclidLine`
  already flows PluginState→(composeSceneMeta)→MachineParams→(resolve())→SnapParams end-to-end for every other
  per-lane field (`useRiff`/`mask`/etc.), so `sourceMode` rides the same path for free. **NEW `SnapParams.
  laneSrcChanMasks: [UInt16]`** (4 entries, Euclideous's row only) resolved in SnapshotBuilder's existing
  post-hoc receiver block (same spot `riffSrcChanMask` already lived, since both need `doc.receivers`, which
  `resolve()` itself has no row-aware access to): MIDI = the unchanged lanes receiver (index 3, "receiver 4");
  CHORDS = the first receiver found with `doorModeResolved == .chord` (no picker for WHICH one — no receiver-
  picking UI returns to this page, by design; an unconfigured CHORDS lane is honestly silent); KEY = 0, silent
  (§4.4's KEY-mode pool mapping stays unresolved, untouched by this feature). `riffSrcChanMask` is now simply
  `laneMasks.first ?? 0` — lane 1's own resolved mask, not a second independent computation. **ROUTER.SWIFT,
  the real surgery:** `.euclid` previously filled ONE shared `srcNoteBuf`/`srcNoteCount` pool per CELL, used
  by all 4 lines alike — now a NEW `fillLaneSrcFromPool` (mirrors the existing `fillRiffSrcFromPool` exactly)
  fills 4 INDEPENDENT buffers (`laneSrcBuf`/`laneSrcCount`, fixed-size, no render-thread allocation), one per
  lane, from that lane's own resolved chanMask — gated `isEuclideousRow`, so every OTHER `.euclid` cell
  anywhere else in the grid (the regular BUILD-page processor) keeps reading the single shared pool exactly as
  before, byte-identical. `resolveEuclidPick` gained an explicit `count:` parameter (was a closure-captured
  shared `srcCount`); `strikeChord` gained an optional `srcOverride` (nil for every non-Euclideous caller,
  byte-identical) so the HIT/MISS pick-and-strike calls inside `runEuclidLine` can target the CALLING line's
  own pool, not the cell's. **A REAL REGRESSION CAUGHT BY THE TEST SUITE, not inspection:** the first cut
  defaulted `laneCount`/`laneNotes` to the per-lane buffers whenever `isEuclideousRow`, full stop — broke 2
  existing reset-span tests that never configure `doc.receivers` at all. Traced to the pre-existing LEGACY
  fallback (no receivers configured ⇒ the cell's own `inputChanMask` resolves to OMNI `0xFFFF` via a
  completely different code path) having no equivalent in the new per-lane world — SnapshotBuilder's post-hoc
  block skips entirely when `doc.receivers` is nil/empty, leaving `laneSrcChanMasks` at its empty default,
  which read as "every lane's mask is 0" (silent) instead of falling back to that legacy OMNI pool. Fixed by
  gating the per-lane path on `!p.laneSrcChanMasks.isEmpty` too — empty ⇒ every lane transparently falls back
  to the shared `srcCount`/`srcNotes`, restoring the pre-existing no-receivers-configured behaviour exactly.
  **3 PRE-EXISTING TESTS REWRITTEN, not left broken or silently deleted** (their premises were genuinely
  superseded, not merely stale): `testEuclideousRiffPoolResolvesFromReceiverZeroIndependentOfLanesReceiverThree`
  asserted riff was FIXED to receiver index 0 regardless of the lanes — now rewritten as `…IsGovernedByLane1-
  EvenWhenADifferentLaneConsumesIt`, proving the still-true spirit of the original claim (riff and a lane CAN
  read different pools) under the new mechanism, PLUS the one new subtlety it exposes: a useRiff-line's OWN
  sourceMode is irrelevant to what the riff plays — only lane 1's (array index 0's) choice ever governs it,
  confirmed by setting the CONSUMING line's own sourceMode to KEY and showing it's ignored. The two KEY-mode-
  yields-silence tests (riff's and the lanes') had set the now-fully-RETIRED global switches
  (`euclideousRiffSourceMidi`/`euclideousLanesSourceMidi`) — rewritten to set the new per-line `sourceMode:
  .key` directly instead, same narrow single-concern assertions. **+4 NEW tests:** per-lane independence (3
  lanes, 3 different sourceModes, 3 genuinely different outcomes incl. KEY's silence) · the retired global
  `euclideousLanesSourceMidi` switch is now provably inert (set to its old "KEY" value, confirm an untouched
  lane still sounds via MIDI anyway) · `sourceMode` survives the SnapshotBuilder fresh-literal rebuild +
  defaults to MIDI when untouched. **UI (EuclideousPage.swift):** `EuclideousLaneTab` gains `.io` as case 0
  (PATTERN/RIFF/MASK shift to 1/2/3 — harmless, this state is purely ephemeral/never persisted); new
  `ioSourceRow` (3 equal buttons, same visual language as `directionRow`, editing `sourceMode` via the SAME
  generic `edit(idx){...}` every other per-lane field already uses — no new onEdit/AU plumbing needed for this
  half of the feature at all) + the EXISTING `laneOutRow` MOVED here as row 2 (was always-visible below every
  tab; now only visible on the I/O tab — a direct, named consequence of "a new tab for input/output," not an
  accident). Removed: header row 2's trailing "LANES" switch (now just the KEY picker, left-hugging) and the
  riff panel's own "SOURCE" switch (its subtitle now reads "...FOLLOWS LANE 1'S SOURCE" so the dependency
  isn't invisible); the now-fully-unused `sourceSwitch`/`sourceSegButton` helpers deleted outright (confirmed
  zero remaining call sites before removing). `riffSourceMidi`/`lanesSourceMidi`/`onSetRiffSourceMidi`/
  `onSetLanesSourceMidi` dropped from `EuclideousPage`'s own parameter list; the underlying `@State` vars +
  their AU getter/slow-timer-resync plumbing in `AudioUnitViewController.swift` are LEFT IN PLACE, just
  unreachable from this call site — decode-safety for an old saved doc, matching how `euclideousReceiver` was
  handled when its own control was dropped. **FLAGGED MISMATCHES, named plainly rather than absorbed:** the
  lane's own OUT toggles are no longer always-visible — switching to PATTERN/RIFF/MASK now hides them
  entirely, which is exactly what was asked but is a real, visible behaviour change from before; the riff's
  source has NO visible control or indicator beyond one line of header subtitle text — changing lane 1's own
  I/O silently changes what the riff sounds like, with nothing on screen pointing at why; CHORDS needs an
  ACTUAL receiver already configured as a chord door somewhere in the document, or it's honestly silent, not a
  guessed substitute — there is deliberately no in-page way to tell which receiver (if any) is currently
  serving that role. **DEVICE-OWED:** the new tab's 3-button row legibility at real lane-card width; confirm a
  CHORDS-mode lane genuinely tracks a live chord-door progression, not just a static pool; confirm the OUT-
  toggles-now-tab-gated change doesn't read as "where did my routing go" on first touch.**
- **▶ EUCLIDEOUS — a cog setting controls which view a FRESH plugin instance opens into (2026-10-08, on
  `fix/euclid-no-scroll-direction-order-2x2-grid`; iOS builds clean, no warnings in the touched files; no macOS
  test-target reach — pure UI/@AppStorage glue; DEVICE eye owed). Context: Paul asked whether Euclideous was
  worth extracting into its own standalone app/plugin now — recommended not yet (it's one reserved row inside
  the shared engine, not a self-contained module, and several of its own design questions are still explicitly
  open per spec §4) — Paul's follow-up: "In that case, I want it to load as euclidious, maybe with a cog
  setting to switch between them." Built the lighter-weight version of that ask: a new DISPLAY preference,
  **STARTS ON: WORKBENCH | EUCLIDEOUS**, on the cog page, governing which view a plugin instance shows the
  INSTANT it's created — not a live in-session switch (the existing header icon + `showEuclideous` already
  provide that; closing Euclideous still always falls back to the normal workbench, unchanged). **MECHANISM:**
  `launchIntoEuclideous` is a new `@AppStorage("midispark.launchIntoEuclideous")` Bool (default false — the
  same device-wide DISPLAY-preference class as `showScenes`/`roomsLeftOriented`, not a PluginState/document
  field, since this is about the user's own setup, not any one project). `DiagView` gained its FIRST custom
  `init(au:)` (it previously relied entirely on the synthesized memberwise init, confirmed via grep to have
  exactly one call site, `AudioUnitViewController.embedUI()` — safe to add) which seeds `_showEuclideous =
  State(initialValue: UserDefaults.standard.bool(forKey: "midispark.launchIntoEuclideous"))` — read directly
  off `UserDefaults.standard` (the same implicit store `@AppStorage` with no explicit `store:` argument always
  uses) since a struct's own init runs before any of its `@AppStorage`-wrapped properties exist to read from.
  Every OTHER `@State` property on `DiagView` keeps its own declared default — confirmed Swift runs a stored
  property's own default initializer automatically for anything a custom init doesn't explicitly touch, so
  this is a 2-line init, not a full property-by-property rewrite. `embedUI()`'s `DiagView(au: audioUnit)` call
  site needed NO change — the new `init` has the same external signature as the old synthesized one for `au`.
  **WHY `viewDidLoad`-adjacent construction is the right trigger, not a plain `.onAppear`:** `embedUI()` is
  itself guarded (`guard children.isEmpty else { return }`) and only ever constructs ONE `DiagView` per real
  AU view-controller instance — i.e. once per actual "this plugin was just loaded into the host" event,
  exactly matching "load as X." A bare `.onAppear` on the SwiftUI tree would have fired on every reappearance
  (backgrounding/foregrounding, switching away and back in a multi-plugin host), silently re-forcing Euclideous
  back open even after the user had deliberately closed it mid-session — considered and rejected before
  writing any code, not discovered as a bug afterward. **CONTROL:** `CogPage` gained a `@Binding var
  launchIntoEuclideous: Bool` (threaded from the one real construction site in `DiagView.body`) and a new
  `startupToggle` helper — a two-way WORKBENCH|EUCLIDEOUS segmented control, same visual family as the
  existing `leftRightToggle` (ORIENTATION) but with named segments at a wider 74pt (vs. LEFT/RIGHT's 40pt, to
  fit "EUCLIDEOUS") rather than `onOffToggle`'s bare ON/OFF, since neither side reads as a default "off" state.
  Placed directly under ORIENTATION in the existing DISPLAY section — no new section needed. **DEVICE-OWED:**
  confirm a fresh plugin instance (a real Xcode reinstall, or AUM adding a new instance) actually opens
  straight into Euclideous when the toggle is set that way, and that flipping the toggle while an instance is
  already running does NOT retroactively reopen/close anything in that running instance (by design — it only
  seeds the NEXT instance's startup) — worth confirming that reads as expected rather than as unresponsive.**
- **▶ EUCLIDEOUS — a FERRY doc reverses the single-row riff + note display, and the page becomes genuinely
  orientation-aware (2026-10-08, on `fix/euclid-no-scroll-direction-order-2x2-grid`; iOS builds clean, no
  warnings; no macOS test-target reach — UI-only; DEVICE eye owed on everything, more than usual — see the
  note below). A FERRY message (relayed directly in chat, not via `_dear_claude_code/` this round) gave three
  rulings. **(1) THE RIFF GRID IS BACK to the original 8-column × 8-rank MATRIX** — the 2026-10-07 single-row/
  level-bar redesign (and its 2026-10-08 rank+note-name readout addition) is GONE entire, not layered
  alongside the matrix. Tap sets a step's rank to the tapped row; tapping the already-selected cell again
  clears it to rest — the exact `rr[col] = (rr[col] == rank ? 0 : rank)` toggle the original popup used.
  Cells are NEUTRAL (`Color.white.opacity(0.85/0.08)` on/off) — not lane-coloured, since the pattern is
  shared, not owned by any one lane; the per-lane position DOTS above the columns stay lane-coloured
  (they're genuinely per-lane state) and are unchanged. **(2) THE NOTE-NAME READOUT IS FULLY REVERSED** —
  not relocated as row labels, not kept anywhere — a direct, acknowledged reversal of the "I do want both
  the note number and the resolved note" request from two messages earlier; `riffResolvedNoteLabel` and its
  call site are deleted. The underlying poll plumbing (`riffLivePool`, Router→Kernel→AU→VC) is LEFT IN PLACE,
  unused by the UI — cheap to keep, expensive to rebuild if a future ask wants it back. **(3) THE WHOLE PAGE
  IS NOW ORIENTATION-AWARE**, not a single always-vertical stack: `body`'s GeometryReader computes
  `isLandscape = geo.size.width > geo.size.height` FRESH on every layout pass (no caching) and branches to
  `portraitLayout`/`landscapeLayout`. PORTRAIT keeps the existing header→2×2 lanes→riff-below stacking, with
  the lane grid's own height budget reserving genuine room for the riff grid's real minimum (computed from
  the SAME shared constants the riff grid itself draws with, not a re-guessed number — the RATCHET/DEST class
  of bug this codebase's history keeps naming, caught and fixed here BEFORE shipping: an early draft had the
  reservation's own chrome-height and cell-gap constants silently disagree with the grid's own drawing code
  by 8pt and 1pt respectively). LANDSCAPE is a NEW layout: header across the top, lane grid on the LEFT sized
  from the available height first (landscape is usually height-constrained, not width-constrained) and capped
  at 60% of total width so the riff grid always keeps a meaningful share, riff grid on the RIGHT filling
  whatever width remains, full height below the header. **PROTECTED MINIMUMS (ferry §3 — "do not shrink...
  below comfortable touch size, and do not make lane OUT or MAIN OUT any smaller than they are now"):** XY
  pads floored at 44pt (the HIG touch minimum — `minLaneSize` falls out of it, 3×44, since pads are literally
  `laneSize/3`), riff cells floored at 24pt, lane OUT fixed at 30pt and MAIN OUT at 36pt regardless of any
  scaling elsewhere. **THE SPECIFIC REPORTED FAULTS, traced to root cause, not patched symptom-by-symptom:**
  portrait's cut-off ON button/LANES switch/step-count buttons/riff right edge were ALL the same bug — the
  header's own HStack rows assumed "enough" width unconditionally, with zero adaptive behaviour, so trailing
  content silently ran off the right edge on a narrower-than-assumed panel; fixed with an explicit
  `headerScale(width)` (a reasoned, not measured, ratio against the row's own estimated full-size content
  width) applied to every label/chip/button's font and padding — MAIN OUT's 4 circles are the one thing in
  that row NEVER scaled, per the floor above. Landscape's lane-card overlap + top-clipping was the deeper
  issue: the page had only ONE layout shape (always vertical: header, lanes, riff stacked top-to-bottom)
  regardless of orientation — cramming three stacked sections into a WIDE-but-SHORT landscape frame is
  structurally wrong for that aspect ratio, not a sizing bug fixable by tuning numbers; needed the genuinely
  separate landscape layout built above. HITS/OFFS's "3 HITS OUT OF…" truncation was a reuse mismatch: the pad
  face was calling the SAME formatter built for the much roomier floating drag-HUD overlay, which was never
  going to fit a ~44-70pt pad face — fixed with a dedicated compact formatter ("K/N · ±R", e.g. "3/8 · +0",
  matching the format VEL/GATE already used and the ratified mockup's own literal example string) for the
  permanent face only; the transient drag-HUD keeps its original, roomier verbose form unchanged, since
  nobody asked to compact that one and it has the space. **HONESTLY FLAGGED, found while hand-tracing the
  geometry at a few plausible panel sizes (not device-measured, just arithmetic):** the riff grid's own cell
  proportions come out quite different between orientations — wide-and-short in portrait (ample width, tight
  reserved height), tall-and-narrow in landscape (the opposite ratio of constraints) — both avoid clipping
  and respect the 24pt floor, but the matrix's look shifts noticeably between the two, which may read as
  inconsistent on a real screen; worth a look once device-tested, not hidden as a surprise. **DEVICE-OWED,
  more than the usual disclosure — this whole ferry is about pixel-level clipping/overlap/truncation that
  cannot be verified without seeing a real render, and no screenshots could be produced for the requested
  acknowledgment** (no device/simulator visual access exists in this environment): confirm nothing clips or
  overlaps in EITHER orientation at AUM's windowed AND full-screen sizes (4 combinations minimum); confirm
  the header's scale-down actually reads legibly rather than just small; confirm the riff matrix's shifting
  proportions between orientations are acceptable or need a different sizing rule; confirm HITS/OFFS's new
  compact format reads clearly without its old explanatory wording.**
- **▶ EUCLIDEOUS — a self-review pass found + fixed one real bug, and Paul asked for two §4 items (reset
  span, live riff notes) to be built properly rather than left open (2026-10-08, on `fix/euclid-no-scroll-
  direction-order-2x2-grid`; macOS 1232 green incl. +2, iOS builds; DEVICE eye/ear owed on both). Paul asked me
  to re-review the whole rework against his original request for shortfalls/shortcuts. **A fresh line-by-line
  read (not a recall of what I'd already written) found ONE real bug**: `maskCometRow`'s play button/step
  badge enforce a 36pt touch-target floor regardless of the budgeted row height (30pt), so the MASK tab
  rendered 6pt taller than PATTERN/RIFF, shifting the card's layout on every tab switch. Fixed by raising the
  shared per-tab content budget to 36pt instead of shrinking MASK's touch targets down to it (`d8a939f`) — all
  three tabs now render identically, and PATTERN/RIFF's own touch targets grow slightly as a side effect.
  **Flagged, not yet built, in that same review:** KEY mode's silence-not-alternate-source behaviour (by
  design, named as a likely "feels broken on first touch" moment); the MASK tab's zero audible effect
  (confirmed by grep — `line.mask` is read nowhere in Router.swift); RESET SPAN being UI-only, nothing
  wired to it. **Paul's direct response: "I do want both the note number and the resolved note. I also want
  reset span to be correctly implemented."** Both built as real engine features, not UI stubs.
  **LIVE RIFF NOTES:** a new Router-owned stable snapshot (`euclideousRiffLiveNotes`/`Count`, written only for
  Euclideous's own row right where the riff's pool is filled, zeroed at the SAME pool-empty guard
  `euclidLineReady` already uses) — polled on the existing fast ~30fps cadence via the SAME 3-layer forward
  (`Router.euclideousRiffLivePool()` → `Kernel` → `MidiSparkAudioUnit.pollEuclideousRiffLivePool()`) that
  `euclideousRiffPositions` already established. The riff panel resolves each column's live note via the
  EXISTING `riffResolve` fold (the SAME function the real render path uses) against this live pool — so what's
  shown is provably what would actually sound, not a parallel guess. Shows blank (not a placeholder) when the
  pool's empty or KEY mode is selected, honestly reflecting that §4.4's KEY-mode pool mapping is still unbuilt.
  **RESET SPAN, built on the EXISTING span-re-anchor idiom already proven for the regular (non-Euclideous)
  EUCLID processor** (`spanLadderBeats`/`runEuclidLine`'s own re-anchor), not a new mechanism: a bar count
  (`SnapParams.euclideousResetSpanBars`, resolved from `doc.euclideousResetSpanBarsResolved`, gated to
  `Snap.euclideousRow`) OVERRIDES the regular machine-wide `euclidSpanN` ladder when set, computed as a literal
  `Double(bars) × cyc` rather than routed through `spanLadderBeats`'s own ladder — that ladder tops out at 8
  bars (its n=64 case) with no slot for 16, confirmed by reading its switch statement before relying on it.
  **Traced through what this actually resets, rather than assuming:** the lane's own K/N/rotate pattern phase
  AND the riff's own per-hit advance ordinal (`ord`) are BOTH already pure functions of the span-re-anchored
  local beat — re-anchoring needed zero new accumulated state for 5 of 6 riff directions, confirmed by reading
  `ord`'s own formula (`cy × effHits + hitsUpTo − 1`, where `cy` is "cycles within the CURRENT re-anchored
  span window"). **DRUNK is the one exception** — a random walk's POSITION depends on its own history, not
  just "what time is it," so re-anchoring the ordinal alone doesn't reset the walk itself. Added a small,
  scoped exception (`euclideousRiffLastSpanStart`, 4 entries, mirroring the EXISTING `euclideousRiffDrunkPos`
  state-exception class already disclosed in this file): when a lane's hit detects the span-start beat has
  changed since last observed, hard-resets the walk to position 0 — the identical "fresh start" treatment the
  very-first-hit-ever case already gives it. Reset alongside the rest of DRUNK's state on a transport restart.
  **TESTS, both self-caught wrong on the first attempt, fixed by tracing not re-guessing:** the first draft of
  the pattern-reset test used a 4-of-8 Euclid pattern, which ALREADY naturally repeats every bar even with
  span OFF (8 ticks/cycle happens to equal 1 bar exactly at the test's own rate) — made span's effect invisible
  by construction, caught empirically when the "ON" and "OFF" cases produced identical onset counts. Rebuilt
  around a 3-of-5 pattern (deliberately non-bar-dividing) using `noteSel: .cycle` to read the engine's own
  `ord` state via which pool-rank note sounds — the same proven technique the DRUNK test already uses.
  **A second self-caught mistake in the same test:** an early version compared reset-ON's bar-2 sequence
  against FREE's bar-1 PREFIX, which is trivially identical regardless of span (any fresh run starts at
  ord=0) — fixed to compare against FREE's own bar-2 SUFFIX, the actually meaningful comparison.
  `testEuclideousResetSpanOneBarReAnchorsThePatternEveryBar` (bar 2 replays bar 1 exactly under a 1-bar reset;
  FREE's bar 2 does not replay bar 1) + `testEuclideousResetSpanHardResetsDrunksWalkAtEachBoundary` (a 2-bar
  DRUNK run's second bar exactly replays its first bar's rank sequence, proving the walk genuinely restarted,
  not merely continued). **DEVICE-OWED:** the riff panel's new resolved-note text at real size (now a 3rd
  stacked line per cell, on top of the rank number and the bar); whether "silence when source is empty/KEY"
  reads clearly as "no note to show" rather than a blank-looking bug; the reset-span picker now has a real,
  audible effect — confirm 1/2/4/8/16 bars all feel like genuine, musically distinct re-anchor points; DRUNK's
  hard-reset feeling like a clean restart rather than an audible glitch at the boundary.**
- **▶ EUCLIDEOUS — the FULL PAGE REWORK, ratified spec built end-to-end (2026-10-08, on
  `fix/euclid-no-scroll-direction-order-2x2-grid`; macOS 1230 green incl. 7 new, iOS builds; DEVICE eye/ear
  owed on the whole UI). A design-channel spec (`FERRY-euclideous-page-rework.md`, ratified by Paul 2026-10-07
  including its mockup) arrived via `_dear_claude_code/`; archived as `Docs/SPEC-euclideous-rework.md` +
  `Docs/euclideous-rework-mockup-2026-10-07.html`. Planned first (full Plan Mode: 3 parallel Explore agents + a
  Plan-agent validation pass, then — per Paul's own standing mid-planning instruction, "once all tasks are
  complete... run a full review... root out shortcuts and find better ways" — TWO audit passes, one against the
  plan before coding, one against the actual shipped code after). Plan: `~/.claude/plans/woolly-crafting-
  music.md`. **RECEIVER POOL-SPLIT:** the lanes' pool is hardcoded to receiver index 3 ("receiver 4") directly
  in `BuildSceneLogic.composeSceneMeta` (`i.euclideousReceiver` now unreachable, left inert — the OLD IN A/B/
  C/D selector UI is gone, matching how `riffDirBias` was handled when ITS control was dropped); the riff's
  pool is genuinely NEW — a parallel Router.swift scratch buffer (`riffSrcNoteBuf`/`riffSrcNoteCount`, mirroring
  `fillSrcFromPool`'s own shape) filled from `doc.receivers[0]` ("receiver 1") via a new `SnapParams.
  riffSrcChanMask`, resolved in SnapshotBuilder gated to `Snap.euclideousRow` only. **A REAL BUG CAUGHT BY THE
  TEST SUITE, not by inspection:** the first cut of this gating broke the PRE-EXISTING `useRiff` RouterTests
  (5 tests, all placed at row 0 not `Snap.euclideousRow`, since the underlying `useRiff`/`EuclideousRiff`
  mechanism is row-agnostic in the model — only Euclideous's own UI happens to be the one place that sets
  these fields today) — fixed by falling back to a COPY of the lane's own `srcNoteBuf`/`srcNoteCount` for any
  row OTHER than Euclideous's reserved one, restoring byte-identical pre-split behaviour everywhere else.
  **MAIN OUT MASK:** a new global `SnapParams.mainOutMask` (default `0b1111`), applied in `strikeChord` as
  `chopMask(...) & p.mainOutMask` — AFTER `chopMask`'s full result, not pre-masked into `base`, PROVEN from
  actual source (not reasoning alone) during planning: `chopBusMask`'s ALT path and DEST's own routing both
  build their bus bits completely INDEPENDENT of `base`, so pre-masking would silently fail to suppress an
  ALT- or DEST-routed note. **A SECOND real gap found while writing the TEST for this, not shipped blind:** a
  3rd planned test case (mainOutMask suppressing a DEST-routed note) failed — traced to `strikeChord`'s
  `hasDownstream` branch, which routes emission through `emitDriverNote` (a SEPARATE function with its OWN
  internal bus resolution that never reads `tbm`/`mainOutMask` at all) whenever EUCLID has ANY following
  processor slot in the SAME chain. Confirmed this is NOT reachable by the real feature (Euclideous's own cell
  is structurally always exactly ONE slot, so a DEST slot can never coexist with EUCLID there, and
  `mainOutMask` has no UI path to reach any OTHER chain shape) — dropped the DEST sub-case rather than chase a
  fix into `emitDriverNote`'s shared per-note fold (used by every driver type with downstream processors) for
  a combination nothing can actually trigger; flagged honestly inline and here, not silently absorbed. **NEW
  GLOBAL FIELDS** (`PluginState.euclideousResetSpanBars`/`KeyRoot`/`KeyType`/`RiffSourceMidi`/`LanesSourceMidi`/
  `MainOutMask`, all additive-Optional): source-mode fields default to **MIDI, not KEY** — a deliberate
  correction during planning (the Plan agent's own suggestion of nil⇒KEY would have silently SILENCED every
  existing Euclideous session the moment this shipped, since KEY mode resolves to an empty pool and nothing
  had opted into it yet). New `EuclidLine.mask: EuclidLineMask?` (nested struct: enabled/pulses/steps/rotate,
  mirroring the existing `Chop`-on-`Cell` precedent) threaded through all 4 required EuclidLine sites incl. the
  SnapshotBuilder fresh-literal rebuild hazard spot. Every new field added to the AudioUnitViewController.swift
  slow-timer `euclideousResynced` checklist — this project's own documented "Euclideous has silently reset on
  reload before from a field missing there" bug class, treated as a literal must-do, not a maybe. **UI
  (`EuclideousPage.swift`, rewritten in full):** header row 1 = title · RESET SPAN chip+popup (OFF/1/2/4/8/16
  bars) · MAIN OUT A/B/C/D (36pt) · ON · close; row 2 = KEY −/chip/+ (reuses the canonical 13-case `ScaleType`
  + the standard 12-note-name array — §4.3's deeper "reuse SCALE-door/FOUNT machinery?" question stays
  explicitly OPEN, flagged not answered) · LANES KEY|MIDI switch. The riff editor moved ONTO the page (no more
  popup/expand-collapse): a single full-width row of 8 hardcoded cells (rank number + a bar encoding pitch rank
  — NOT a resolved note NAME per the mockup's own sample data, since no live-pool data reaches this page today
  to resolve one from; a named simplification, not a silent gap) + per-lane cursor dots + its own SOURCE
  KEY|MIDI switch; tap-to-cycle rank 0...8 is an explicit INTERIM editing gesture (the real one is §4.6,
  explicitly open). Lane boxes are SQUARE, sized from width per the mockup's own rule — **with one shortcut-
  audit addition beyond the plan's literal wording:** a height budget cap (reserving a header allowance + a
  riff-panel minimum) so a wide/short real host panel can't derive a lane size so large it starves the riff
  panel of all remaining space, directly undermining "give the space to the lane boxes"; still square (one
  `size` drives both axes), just the smaller of the width- and height-derived candidates — still flagged
  device-owed, a reasoned cap not a measured one. Each lane gained PATTERN/RIFF/MASK tabs (own `@State` array,
  switching independently per lane) under the XY pads — PATTERN wraps the existing direction+hit/miss/rate rows
  verbatim (empty rate now reads FOLLOW, not "—"); RIFF relaid as a 4-column×2-row grid with LOCAL short labels
  (PEND/PING/RAND, a scoped lookup that never touches the shared `RiffDir.displayLabel` enum — that enum also
  serves the unrelated regular chainable RIFF processor elsewhere in the app); MASK is new. **PER-LANE EUCLID
  MASK:** a SECOND, independent `EuclidCometBar`+`EuclidGesturePad` pair per lane (not `EuclidLaneBox` itself —
  its select/trailingContent machinery has no meaning here), wired so dragging its OWN grid mutates `line.
  mask?.rotate` directly (rotation IS the gesture, no separate control, per the spec) — confirmed by direct
  grep that `line.mask` is read NOWHERE in Router.swift's emission path, so the mask has GENUINELY zero effect
  on sound, satisfying "must not change the lane's output" by construction, not by promise. Its own line 2 (the
  effect/amount/hit-count the mockup drew) is a plainly-labelled "EFFECT — NOT YET AVAILABLE" stub, not omitted
  and not a dead-looking-but-tappable control. `EuclidLaneBox` gained one small additive (`nil`-default)
  `stepCountBadge` param for the passive step-count numeral beside the lane's own comet bar — the ONE edit to
  the shared `EuclidLaneUI.swift` component, safe for its other caller (the regular BUILD-page EUCLID editor,
  which never passes it). The 3 XY pads now show their value PERMANENTLY on their own face (reusing the 3
  existing HUD formatter functions for both the face text and the transient drag overlay, so the two can never
  disagree) — a genuine behaviour change from today, per the mockup. OUT row: lane toggles 18→30pt, a new
  36pt MAIN OUT tier; two genuinely SEPARATE conditions (not one "something's wrong" treatment) — NO OUTPUT
  when a lane's own `emitterMask` is empty, dashed/hollow stroke when a bit is set but that bus's MAIN toggle
  is off. Both `EuclidBeacon` calls removed entire. **+7 tests** (RouterTests: riff pool reads receiver 0
  independent of the lanes' receiver 3; KEY mode on either switch yields a genuinely empty pool, not a silent
  MIDI fallback (2 tests); mainOutMask suppresses a plain AND a CHOP-ALT-routed note alike, the ordering proof,
  with the DEST case's omission documented inline. SnapshotBuilderTests: `EuclidLine.mask` survives the fresh-
  literal rebuild + stays nil when untouched; `mainOutMask` resolves/clamps to 4 bits; the new source-mode
  fields default to MIDI on an untouched document). **DEVICE-OWED, the whole feature:** the 2-row header's
  real-width legibility; the square lanes' actual size + the new height-cap's real-world adequacy; the 30pt/
  36pt toggles sitting under the usual 44pt touch floor (the spec's own disclosed risk); the mask's independent
  comet-bar+rotate-drag feeling distinct from the lane's own pad-driven gestures rather than confusing; the
  riff panel's new tap-to-cycle gesture feel; whether "receiver 1=riff, receiver 4=lanes" (a reading of the
  spec's own prose ordering, not confirmed text) is actually correct once heard. §4's open items (mask effects,
  reset-span semantics, key-picker scope, KEY-mode pool mapping, default source, the riff editing gesture, main-
  out-off cutoff timing) are answered in the ferry acknowledgment with a named question each, not guessed.**
- **▶ EUCLIDEOUS RIFF — first device pass on the grid above: direction moved per-lane, scroll disabled, the
  overlay no longer shifts the page, VEL/GATE sensitivity tripled (2026-10-07, on `main`, `7e302ea`; macOS 1223
  green, iOS builds; DEVICE eye/feel owed on all four). Paul, after the first build: "I don't see the riff
  controls. Per lane. The back/forward, drunk controls should be per lane, not on the riff control. The
  velocity/gate controls need me to move my fingers way too far. Disable the scrolling on this page. The riff
  overlay should not move the rest of the page down." Four distinct fixes. **(1) DIRECTION IS NOW PER-LANE, A
  REAL MODEL CHANGE:** `RiffDir`/seed/bias moved OFF the shared `EuclideousRiff` struct (which now holds only
  `steps`/`ranks` — the pattern CONTENT) and ONTO `EuclidLine` itself as `riffDir`/`riffDirSeed`/`riffDirBias`
  (additive-Optional, threaded through all 4 of EuclidLine's required sites — struct/custom-decoder/resolved-
  accessors/the SnapshotBuilder fresh-literal rebuild, the same discipline the original feature's own fields
  needed). Router.swift's `runEuclidLine` reads direction from the new per-lane params instead of `p.
  euclideousRiff`; the DRUNK accumulated-state array (`euclideousRiffDrunkPos`, already per-lane by index) was
  structurally unaffected. **THE HIDDEN TOGGLE IS GONE, REPLACED BY A VISIBLE ROW:** the earlier "tap the NOTE/
  OCT pad to turn riff on" mechanism — which this file's own prior entry had already flagged as a real
  discoverability risk before shipping ("nothing currently visually distinguishes 'this pad also responds to a
  tap'") — is exactly what Paul couldn't find. Replaced with a new, plainly visible `riffDirRow` per lane: OFF +
  all 6 `RiffDir` options in one strip; picking a direction turns `useRiff` on AND sets it in one tap (no
  separate enable step), picking OFF turns it off. A conditional `riffBiasRow` (DRUNK only, costs zero height on
  the other 3 lanes) sits beneath it. The NOTE/OCT pad's own relabelling + drag-retargeting to riffRotate/
  riffOctave is UNCHANGED — only its tap-to-toggle is removed; "via the existing, relabelled note/octave
  control" still describes the drag, just not the on/off switch anymore. The shared riff grid's EXPANDED card
  dropped its own DIRECTION/BIAS row entirely (now per-lane) — it's just STEPS + the rank matrix + the per-lane
  cursor overlay. **(2) NO SCROLL:** the `ScrollView(.vertical)` wrapping the lane grid is gone — same
  reasoning already established for the regular BUILD-page EUCLID editor (a SwiftUI ScrollView's own pan
  recognizer competes with every `EuclidGesturePad`'s UIKit pan/pinch recognizers, and this page has far more of
  those — 3 pads × 4 lanes — than that one ever did). **FLAGGED, not silently assumed safe:** removing the
  scroll's overflow safety net means the now-5-row-tall lane cards (gesture pads + direction + hit/miss/rate +
  the new riff-direction row, +bias conditionally) must fit the real screen without clipping — worked through
  the arithmetic (≈310-334pt per lane × 2 rows + gaps + header ≈ 690-740pt) and it should fit a typical
  landscape AUv3 panel, but this is exactly the kind of sizing claim that needs a real device to confirm, not
  arithmetic alone. **(3) THE OVERLAY NO LONGER MOVES THE PAGE:** the collapsed riff pill (step count + mini
  tick-strip + live per-lane cursor dots) moved OUT of the scrolling/flowing body and INLINE into the header
  row — a fixed single row regardless of state, so toggling it can never shift anything. The EXPANDED view
  became a true floating scrim+card overlay (the exact same pattern the RATE pop-up a few entries below already
  uses), positioned independently of the page's own layout flow rather than occupying space inside it. **(4)
  VEL/GATE SENSITIVITY TRIPLED:** `applyX`/`applyY`'s `.velocityGate` per-step deltas (0.05→0.15 for VELOCITY's
  0...2 range, 0.03→0.09 for GATE's 0.05...1 range) — Paul: "need me to move my fingers way too far"; a plain
  output-scale increase, no change to the underlying pixel-to-step quantization shared with the other two tabs.
  **TESTS:** the 4 Router/SnapshotBuilder/EffectiveParams tests from the original feature that constructed
  `EuclideousRiff(direction:...)` were updated to set direction on the `EuclidLine` instead (not deleted — the
  same assertions, relocated to match the new model) +1 new Router test
  (`testEuclidLinesEachHaveIndependentRiffDirectionIntoTheSharedPattern`) proving two lanes with different
  `riffDir` on the SAME shared pattern land on different positions — the direct regression guard for "per lane,
  not shared." **DEVICE-OWED:** the per-lane direction row's legibility at 7 buttons across one lane's width;
  confirm the lane cards now fit without clipping on the real panel with scrolling gone; the VEL/GATE feel at
  the new sensitivity (tripled is a first-pass guess, not device-tuned); the overlay genuinely reads as floating
  rather than still perceptibly shifting anything underneath it.**
- **▶ EUCLIDEOUS — a shared RIFF grid, hit-triggered advancement, PLANNED THEN SHIPPED (2026-10-06/07, on
  `main`, `7ab577c`; macOS 1221 green incl. 13 new, iOS builds; DEVICE eye/ear owed on the whole feature). Paul:
  "At the top center of the page, I want a riff grid, with step count. This will appear small until touched,
  then it will take up more of the screen. Each Euclid control will have a riff option. When enabled, each hit
  will progress riff by 1 step. It will have forward, backwards, drunk, and all options of that type currently
  on riff. It will have vertical and horizontal offset." PLANNED FIRST (full Plan Mode — 3 parallel Explore
  agents + a Plan-agent validation pass, this project's own standing practice for Euclideous-class features) —
  3 architecture forks ratified with Paul via AskUserQuestion before any code: (1) riff enabled REPLACES a
  lane's NOTE/OCT behaviour ENTIRELY, not layered on top; (2) each lane gets an INDEPENDENT cursor into one
  SHARED riff pattern, not one global shared cursor; (3) "vertical and horizontal offset" = the EXISTING NOTE/
  OCTAVE gesture pad, relabelled — reused in place rather than a new control. **THE CENTRAL TENSION, RESOLVED BY
  REUSE, NOT A NEW EXCEPTION:** "each hit progresses riff by 1 step" sounds like it needs genuinely accumulated,
  cross-render state — in tension with invariant 2 ("derived, never accumulated"). Turns out true for only 1 of
  6 directions: EUCLID's own per-hit ordinal (`ord`, Router.swift's `runEuclidLine`, already computed stateless
  — "which hit number is this," a pure function of the line's own K/N/rotate pattern and tick position) drives
  `riffStepAt` directly for FWD/REV/PENDULUM/PINGPONG/RANDOM — ZERO new persisted state. Only DRUNK is genuinely
  path-dependent (a random walk's position depends on its own history, not just "what time is it now") — gets a
  NEW, small (4 lanes, not `Snap.cells`-sized) accumulated pair (`euclideousRiffDrunkPos`/`LastOrd`), modeled
  EXACTLY on the existing `riffDrunkPos` precedent but keyed on *distinct `ord`* (hit-triggered) instead of
  *distinct tick* (time-triggered) — same disclosed-exception class, same transport-edge reset site. A
  Plan-agent validation pass caught 2 real gaps before any code: `useRiff` must pre-empt `noteSel` ENTIRELY
  (checked before the existing `.riff`/`.arp` sequential-source branch, not merely after it) to honour "replaces
  it entirely" regardless of whatever `noteSel` happens to be stored; and `SnapshotBuilder`'s `EuclidLine(...)`
  reconstruction is a FRESH LITERAL, not copy-with-mutation — the 3 new fields needed threading through a 4th
  site beyond the struct/decoder/resolved-accessors, "the exact gotcha a prior RATE-automation feature was
  bitten by" (already logged in this file). **MODEL:** new `EuclideousRiff` struct (steps 1…32 · per-step MONO
  rank 0…8 · `RiffDir` · seed · bias) — ONE shared struct, not an array-of-4 like `euclideousLinesResolved`'s own
  lines, since the PATTERN is shared and only each lane's own cursor/rotate/octave is independent. Deliberately
  scoped OUT: POLY/TIE/SLIDE/ACCENT/WRAP (not asked for) and RATE/SPAN (advancement is hit-triggered, not
  time-triggered, so neither applies). `PluginState.euclideousRiff`/`MachineParams.euclideousRiff`/
  `SnapParams.euclideousRiff` thread it through the usual 3-layer resolve. `EuclidLine` gains `useRiff`/
  `riffRotate`/`riffOctave` (additive-Optional, in all 4 required sites). **ENGINE (Router.swift):** a new
  branch in `runEuclidLine`'s hit closure, inserted right after `ord` is computed, before the `.riff`/`.arp`
  check — resolves the lane's own step via `riffStepAt`(5 directions)/`euclideousRiffDrunkStep`(DRUNK) → applies
  `riffRotate` via a new pure `riffRotateStep` (Derivations.swift, mirrors `euclidPatternInto`'s own `(i+rot)%n`
  convention) → resolves the rank via the EXISTING `riffResolve` against the cell's own plain pool (`srcNotes`/
  `srcCount` — Euclideous's cell has no chain predecessor, so this is the right pool, not `chainScratch`) →
  strikes via `strikeChord(explicitNote:explicitVel:)`. **OCTAVE REPLACES, doesn't stack** — `octave: 0` passed
  to `strikeChord`, `riffOctave` does the only shifting — the gesture pad that used to drive `octave` now drives
  `riffOctave` exclusively; consulting the old frozen value too would silently reintroduce an invisible offset.
  Every direction (not just DRUNK) writes its resolved step into a new unified `euclideousRiffStep[4]` — the
  UI-poll layer reads one simple array regardless of direction. **UI POLL (4-tier, mirrors `euclidLineReady`
  exactly):** `Router.euclideousRiffPositions()` → `Kernel`/`MidiSparkAudioUnit` thin forwards →
  `AudioUnitViewController`'s fast ~30fps `meterTimer` block (NOT the slow ~4Hz config-resync timer — a live,
  responsive per-hit indicator, not config). **UI (EuclideousPage.swift):** a new top-center riff grid — small
  pill (step count + a mini rank-tick strip + each `useRiff`-on lane's own live cursor dot, visualizing "4
  independent cursors, one shared pattern" even collapsed) that expands on tap into the full MONO rank matrix
  (radio-per-column) + STEPS ± + a 6-way DIRECTION seg + a BIAS slider (DRUNK only) — kept deliberately simple
  (an `@State` bool + animated frame change inside the existing ScrollView, so expanding pushes the lanes down;
  no prior art for this interaction anywhere in this codebase). **THE NOTE/OCT PAD REPURPOSED IN PLACE, not a
  new row:** reuses the EXACT tap-under-drag technique `EuclidLaneBox`'s own PLAY/STOP button already proves
  safe in this file (a stationary tap never arms `EuclidGesturePad`'s pan/pinch recognizers, so a sibling
  `.onTapGesture` on the same cell catches it cleanly) — a plain tap toggles `useRiff`; the pad's label/tint
  change ("RIFF H/V") and its drag retargets from noteSel/octave to riffRotate/riffOctave, all on the SAME
  gesture-pad cell — `euclidBoxH`/`trailingHeight`'s height arithmetic is untouched, confirmed no new row
  needed. **TESTS (+13):** EuclidLine's 3 new fields' decode-safety/round-trip/clamp (EffectiveParamsTests);
  the SnapshotBuilder fresh-literal regression for all 3 fields + the new struct (SnapshotBuilderTests,
  mirroring `testEuclidLineRateAndEmitterMaskSurviveSnapshotBuild` exactly — this project's own standing lesson
  about this exact bug class); `riffRotateStep`'s wrap behaviour (DerivationsTests); 4 Router integration tests
  — useRiff genuinely REPLACES noteSel (set `noteSel: .high`, confirm the top note never sounds and the riff
  ranks' notes do instead), riffRotate shifts which rank a hit reads (isolated via `forceColumn: 0` to the very
  first hit), riffOctave replaces (not stacks with) the line's own octave, and DRUNK produces valid, varied,
  pool-bound notes over many hits (membership/variety checks, not a hand-derived exact sequence — this
  project's own standing preference for this class of test). **DEVICE-OWED, the whole feature:** the riff
  grid's expand/collapse feel at real size; the 4-lane independent-cursor model actually reading clearly in the
  collapsed mini-strip; the relabelled NOTE/OCT pad's tap-to-toggle not fighting its own drag in the hand
  (flagged to Paul as a real discoverability risk before shipping — nothing currently visually distinguishes
  "this pad also responds to a tap" ahead of the first touch); DRUNK's walk feeling musical when hit-triggered
  rather than time-triggered; the velocity read on a riff-sourced note (an honest approximation — reads
  `srcNotes[(rank-1) % srcCount].vel`, not provably the exact pool index FOLD would resolve for a rank that
  wraps the pool more than once — flagged for an ear-check rather than deriving FOLD's own index formula up
  front).**
- **▶ EUCLIDEOUS — INVERT rebuilt as a symmetric HIT|MISS selector, RATE rebuilt as a real pop-up (2026-10-06,
  on `main`; macOS 1208 green (DerivationsTests re-run after removing dead code), iOS builds; DEVICE eye owed).
  Paul: "Directly below the last set of buttons that were added, put the invert button and rate button. Rate
  should be nil by default. I hate the current control and want a pop-up. For invert, I want the outline of
  the hit button to look selected and the misses to appear like hits do now." **LAYOUT:** a THIRD row —
  `hitMissRateRow` — stacked with zero gap directly beneath the DIRECTION row (same pattern: combined into
  ONE `trailingContent` VStack, `euclidBoxH`/`trailingHeight` both gained the new row's height), 3 columns at
  the SAME width as the gesture pads/direction buttons above: HIT · MISS · RATE. **INVERT, redesigned not
  just relabelled:** the old single "INV" pill (which performed `euclideousInvertLine`'s field-swap with no
  visual feedback about which side was "currently" hit vs miss) is GONE — replaced by a genuinely symmetric
  2-way toggle. New `missSelected: [Bool]` (per-lane, purely local/ephemeral — `EuclidLine` has no persisted
  "which side is primary" flag, since the invert function performs a destructive field SWAP, not a flag flip,
  so the swapped state alone can't say which side was "originally" hit) tracks which of HIT/MISS currently
  reads as selected, starting at HIT (not inverted) for all 4 lanes. Tapping the NON-selected side triggers
  the real invert AND flips the selection; tapping the ALREADY-selected side is a no-op (not a second,
  cancelling invert). "The outline... to look selected" is literal — SELECTED is an accent-coloured STROKE
  (`RoundedRectangle.stroke`, matching `EuclidLaneBox`'s own pre-existing `selected` convention exactly), not
  a filled background like the gesture pads/direction buttons use — a deliberate, different visual language
  for this ONE control, per Paul's explicit wording. "The misses to appear like hits do now" needed no
  separate code path: both buttons share ONE `sideButton` helper, so whichever one is currently selected
  automatically gets the identical treatment "hit" has right now — symmetry by construction, not a special
  case for misses. **RATE, a real pop-up replacing a tap-to-cycle control:** the old control
  (`Text(rate.rawValue)...onTapGesture { rate = euclideousNextRate(rate) }`) cycled through all 18 `ArpRate`
  cases one tap at a time — confirmed via `euclideousNextRate`'s own body before touching anything (`(i+1) %
  allCases.count`) — meaning reaching a distant rate took UP TO 17 TAPS, and there was NO WAY BACK to nil
  ("inherit the machine-wide rate") once ANY rate had been explicitly set, since the function always lands on
  a concrete `ArpRate`, never nil. Confirmed `EuclidLine.rate`'s own struct default IS already `nil` — "rate
  should be nil by default" was about the UI never being able to genuinely RETURN to or correctly DISPLAY that
  default, not a model change. **FIX:** `euclideousNextRate` deleted entirely (zero other callers, confirmed
  by grep, zero test references) — replaced with `ratePopupLane: Int?` (which lane's pop-up is open, nil =
  none) and a new `ratePopupCard` — a scrim + centred card (the SAME "tap outside to dismiss" shape already
  used elsewhere in this app for the scale-pool/chord popups), showing an explicit "— (MACHINE RATE)" row
  (sets `rate = nil`) plus all 18 `ArpRate` cases in their own natural 3-row grouping (6 straight · 6 dotted ·
  6 triplet, `ArpRate.allCases`'s own declared order — no re-sorting needed). The ROW BUTTON itself now shows
  "—" when `line.rate == nil`, not a misleading "1/16" — the OLD code's `(line.rate ?? .r1_16).rawValue`
  pattern (still used elsewhere for passing a CONCRETE rate into `EuclidBeacon`/`EuclidCometBar`, which
  genuinely need a real number to animate against) made every line look like it had an explicit rate even
  when none was ever set; the DISPLAY-only read is now the one place that shows the honest unset state.
  UI-only, no engine/model change — `ArpRate`/`EuclidLine.rate` are pre-existing, unchanged.
  **DEVICE-OWED:** confirm the HIT|MISS outline reads clearly as "selected" against this page's dark
  background; the pop-up's legibility/tap targets at real size; picking "— (MACHINE RATE)" and confirming the
  lane's rate genuinely reads as inherited (matching whatever the OTHER lanes'/the machine-wide rate produces)
  rather than silently keeping its last concrete value.**
- **▶ EUCLIDEOUS — a DIRECTION row added directly beneath the 3 gesture pads (2026-10-06, on `main`; iOS
  builds, no test-target reach (EuclideousPage.swift-only); DEVICE eye owed). Paul: "Directly below the x/y
  control, put short backwards, ping pong, forwards buttons, aligned with the three x/y controls. Represent
  fwd etc with >,>< and <." A plain 3-way exclusive tap-to-select (not a drag pad — direction is a discrete
  choice, not a continuous target), reusing the SAME glyph convention the regular BUILD-page EUCLID editor's
  own DIRECTION control already established (">"=forward, "<"=backward, "><"=ping-pong) rather than inventing
  a new one. **LAYOUT:** `directionRow` is a new SHORT (32pt, vs. the gesture pads' own square ~width/3) row,
  3 columns at the EXACT SAME width as the 3 gesture pads above it (`cellSize`, passed through unchanged) so
  the two rows line up column-for-column as asked. Left-to-right order matches Paul's own wording exactly:
  BACKWARDS("<") · PING-PONG("><") · FORWARDS(">") — NOT alphabetical or the enum's own declaration order.
  Combined with `gesturePadRow` into ONE `VStack(spacing: 0)` passed as `EuclidLaneBox`'s single
  `trailingContent` slot (that slot only accepts one view) — zero gap between the two new rows, matching the
  same "no gap or padding" convention already established for the step-boxes→gesture-pads seam. `euclidBoxH`
  (the lane's own bottom-up height computation, introduced in the previous redesign) gained `+ directionRowH`
  to account for the new row; `trailingHeight` passed to `EuclidLaneBox` likewise became `gestureRowH +
  directionRowH` so its internal comet-row-vs-trailing-content math stays self-consistent (unchanged formula,
  just handed the new combined total). Tapping a button sets `EuclidLine.direction` directly (not a drag
  delta); the currently-resolved direction (`directionResolved`, honouring the legacy `reverse` bool fallback
  for old docs) highlights with the lane's own accent colour, matching the gesture pads' own touched-state
  styling language. UI-only, no engine/model change — `EuclidDir`/`directionResolved` are pre-existing,
  unchanged. **DEVICE-OWED:** confirm the two rows visually read as one continuous, column-aligned block;
  the 32pt row height feels proportionate next to the much taller square pads above it; the glyphs are legible
  at this size; tapping each button audibly changes the lane's direction as expected.**
- **▶ EUCLIDEOUS — an alternative gesture control: 3 square per-tab pads replace toggle-then-drag; lanes grow
  to fit; per-tab drag HUDs (2026-10-06, on `main`; iOS builds, no test-target reach (EuclidLaneUI.swift/
  GridUI.swift/BuildPage.swift/EuclideousPage.swift/AudioUnitViewController.swift); DEVICE feel owed — this
  is a genuinely new interaction, the one area most resistant to verification by reading code). Paul: "I want
  to try an alternative gesture control. Change the toggle buttons to be square, with each button taking up a
  third of the width of the Euclid lane to which it is attached. Each of these buttons, instead of toggling
  x/y, will act as an x/y pad in itself. The user holds, for example, velocity/gate, drags away and it behaves
  exactly as the lane gestures do now (except the pinch)." **A REAL GEOMETRIC CONFLICT, surfaced before
  touching code, not discovered mid-build:** a literal square button at 1/3 a quarter-screen-WIDE lane's width
  (~300pt on a typical iPad → ~100pt square) would, by itself, consume nearly ALL of a quarter-screen-TALL
  lane's height budget (confirmed by exact arithmetic: even squeezing the play button and existing controls to
  their bare minimums, the total still exceeded a typical quarter-screen height) — asked Paul via
  AskUserQuestion rather than silently picking a resolution; he chose "grow the lane taller." **LAYOUT,
  rebuilt bottom-up instead of top-down:** `laneCard` no longer takes an explicit `height:` — it computes its
  OWN exact height from its content (`12`pt padding + a new fixed `cometRowH=56` play/comet row, matching the
  regular BUILD-page editor's own established `euclidLaneH` constant, + the gesture row's own exact
  `width/3`) and lets the VStack size naturally; `laneGrid` dropped its OWN height computation entirely. Width
  stays a literal screen quarter (never in tension the way height was). The whole grid is now wrapped in a
  `ScrollView` (was a fixed, non-scrolling 2×2) since 2 rows of taller lanes may exceed some screens' height —
  flagged to Paul as an accepted consequence of his own chosen resolution, not a bug. **THE GESTURE MODEL
  ITSELF:** the old `gestureTab: [Int]` — a PERSISTED-per-lane "which tab is currently selected, dragging
  the comet bar affects THAT one" flag — is GONE entirely (removed from `AudioUnitViewController.swift`'s
  `@State` and the `EuclideousPage` call site cleanly, not left half-wired) — there is no more "selected tab"
  concept, since each of the 3 new buttons is now its OWN ALWAYS-LIVE pad for its OWN fixed mapping. Each
  button gets its own `EuclidGesturePad` instance (the SAME shared UIKit pan/pinch bridge the comet bar
  already used — dropped from `private` to internal so `EuclideousPage.swift` can construct it directly,
  "share the component, don't duplicate it" extended to a second caller) wired straight to that button's own
  tab via the EXISTING `euclideousApplyX`/`Y` functions (now refactored into pure `applyX`/`applyY(inout
  EuclidLine, tab, d)` + thin single-lane/all-lanes wrappers, so both paths share one mutation definition).
  PINCH (`onStepsDelta`) is a deliberate no-op on all 3 new pads — "except the pinch" — and stays on the comet
  bar itself instead, which is otherwise NEUTERED (its own `onRotateDelta`/`onHitsDelta`/`onAllRotateDelta`/
  `onAllHitsDelta`/`onDragState` are now plain no-ops, since the 3 buttons own that role exclusively — a 1-/2-
  finger drag directly on the step boxes themselves no longer does anything but pinch still resizes steps
  there). **A FREE FIX, not deliberately targeted:** the OLD 2-finger "all lanes" gesture was hard-coded to
  rotate/hits ALWAYS, regardless of whichever tab happened to be selected at the time (a real, pre-existing
  limitation, never by design) — the new `euclideousApplyAllX/Y(tab, d)` genuinely respect the tab the touched
  button represents, closing that gap as a natural side effect of each button now carrying its own explicit
  tab rather than reading a shared "current selection." **SENSITIVITY — "exactly as the lane gestures do
  now":** recomputes the SAME box-pitch-derived `rotateStepPt` the comet bar's own X-axis already used
  (`euclidBoxGeometry`, the identical formula/inputs) and applies it UNIFORMLY to all 3 buttons' X-axis — not
  just HITS/OFFSET — because the comet bar's existing sensitivity was never actually tab-specific either (one
  `rotateStepPt` served whichever tab was selected), so this is a faithful match, not a new behaviour invented
  for VEL/GATE or NOTE/OCT. **THE DRAG HUD, extended mid-task (Paul, before this was even fully wired up):
  "There's an overlay that shows the number of hits and steps. We need different overlays for velocity, gate,
  etc."** `EuclidDragHUDInfo` (GridUI.swift) was rigid — hardcoded `hits`/`steps`/`offset` ints, rendered as
  "N HITS OUT OF M" / "OFFSET BY K" with no way to show anything else. Generalized to `primary`/`secondary`
  STRINGS instead, pre-formatted by whichever caller builds the info — `euclidLaneDragHUDInfo` (the ONE
  existing, SHARED constructor, still used by both the regular BUILD-page editor and Euclideous's own HITS/
  OFFSET pad) keeps its exact original text; two NEW, Euclideous-only formatters
  (`euclideousVelGateHUDInfo`/`euclideousNoteOctHUDInfo`) show "VEL N%"/"GATE N%" and the note-select's own
  `rawValue`/"OCTAVE ±N" respectively — the BUILD-page editor has no VEL/GATE or NOTE/OCT tab, so it was never
  touched. Both HUD-rendering functions (`buildEuclidDragHUD` in BuildPage.swift, `euclideousDragHUD` here)
  now just display `info.primary`/`.secondary` directly instead of formatting from raw ints — genuinely
  format-agnostic now, not hardcoded to one meaning. **CAUGHT BY THE COMPILER, not a hand-check:** a first
  draft of `euclideousNoteOctHUDInfo` (which needs a local `let oct = ...` before building the struct, unlike
  the other formatters' single-expression bodies) omitted the `return` — Swift's implicit-return sugar only
  applies when a function body is a SINGLE statement; the build caught this immediately, fixed before it ever
  reached the output. **FLAGGED, not silently assumed:** the VEL/GATE button's X-axis (velocity) and the
  NOTE/OCT button's X-axis (note-select stepping) now ALSO use the box-pitch sensitivity by faithful
  replication of existing behaviour, even though neither has any visual "box" relationship to that pitch — an
  honest consequence of "exactly as now," not a new design choice; the square buttons' corner radius (6pt,
  not a literal sharp square) and label font size (13pt, up from the old chips' 10pt) are first-pass aesthetic
  judgment calls, easily tunable. UI-only, no engine/model change. **DEVICE-OWED, the whole feature:** the
  actual feel of holding a square pad and dragging immediately (vs. the old select-then-drag-elsewhere model);
  whether the grown lane height / scroll reads as acceptable on the real device; each of the 3 per-tab HUDs
  actually showing sensible values live; confirm the regular BUILD-page EUCLID editor's own comet-bar drag
  still works exactly as before (it was never touched, but it shares `EuclidGesturePad`/`EuclidDragHUDInfo`
  with everything changed here).**
- **▶ EUCLIDEOUS — the gesture-tab row (HITS/OFFS·VEL/GATE·NOTE/OCT) sits flush beneath the step-box row, zero
  gap (2026-10-06, on `main`; iOS builds, no test-target reach (EuclidLaneUI.swift-only); DEVICE eye owed).
  Paul: "I want the buttons that toggle x/y to be directly under the boxes on the lane with no gap or
  padding." Since the gesture-tab row merged INTO `EuclidLaneBox`'s own `trailingContent` slot (a few commits
  earlier), it sat below the play+comet row separated by the box's own `VStack(spacing: 6)` — a deliberate
  6pt gap at the time, now removed: `VStack(spacing: 0)`, and `reserve` (how much height the comet row cedes
  to trailingContent) drops its own `+6` to match exactly — the comet bar simply claims those 6pt instead,
  so nothing is lost, the gap is just gone. Confirmed byte-identical for the regular BUILD-page EUCLID editor
  (`ProcessorBox`'s own `case .euclid:` never passes `trailingContent`, so `reserve` was already 0 there, and
  a single-child VStack's spacing has no visible effect regardless). **FLAGGED, not silently assumed covered:**
  the step BOXES themselves (drawn inside the comet bar's own Canvas) are vertically CENTRED within whatever
  height the comet bar receives, not bottom-anchored — so if the comet bar ends up taller than the ~30pt the
  boxes themselves occupy (plausible, given Euclideous's generously-sized lanes), there could still be a
  SMALL residual visual gap below the boxes even with zero SwiftUI-level spacing, independent of this fix.
  Deliberately NOT touched this round — reworking the Canvas's own vertical anchor would also require moving
  the comet's OWN position (currently centred at the same `midY`, its glow/trail/burst math all keyed off it)
  to match, a materially bigger and riskier change than what was asked; worth a direct look first, since the
  gap this fix removes is likely the dominant, most visible one. UI-only, no engine/model change. **DEVICE-
  OWED:** confirm the tab row now reads as flush against the step boxes; if a smaller gap is still visible,
  that's the Canvas-centring nuance above, not an unfixed version of this same request.**
- **▶ EUCLIDEOUS — each lane control is now a literal quarter of the SCREEN, the 2×2 block centred (2026-10-06,
  on `main`; iOS builds, no test-target reach (EuclideousPage.swift-only); DEVICE eye owed). Paul: "I want each
  Euclid lane control to be 1 quarter width and quarter height of the screen. I want the four boxes to be
  centred in 2x2 alignment." The prior sizing (`laneGrid`) derived each cell from the space LEFT OVER after
  subtracting outer padding/gaps, filling that space edge-to-edge with no margin — not a literal screen
  quarter, and nothing centred (the grid just sat flush under the header, pushed up by a trailing `Spacer`).
  **FIX:** `cellW`/`cellH` are now `size.width / 4` / `size.height / 4` exactly (`size` = `geo.size`, the FULL
  page geometry from the outer `GeometryReader` — a true screen quarter, not the post-padding remainder); the
  12pt inter-card `gap` is extra breathing room ON TOP of these exact quarters, not carved out of them, so the
  full 2×2 block is slightly LARGER than exactly half the screen each way, by `gap`. **CENTRING:** restructured
  `body` — the header keeps its own fixed `.padding(16)` at the top; `laneGrid(geo.size)` gets
  `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)`, expanding to fill all remaining
  space below the header and centring its now-fixed-size (and generally SMALLER than before) 2×2 content
  within it, on both axes — replacing the old single trailing `Spacer` that only pushed content up, never
  centred it. UI-only, no engine/model change. **FLAGGED, not silently absorbed:** quarter-SCREEN sizing
  (rather than quarter of the space already excluding the header) means the lane cards are now noticeably
  SMALLER than before on every screen size, and on a shorter/landscape iPad the available height could leave
  `EuclidLaneBox` close to its own 80pt floor (worked through the arithmetic: at a ~600pt page height, the box
  lands around 74–80pt, right at that floor, with `laneControls` below it correspondingly tight) — this is the
  literal result of "quarter of the screen," not a bug, but worth a direct look on the actual device/iPad size
  you're using, since I can't verify real screen proportions from here. **DEVICE-OWED:** confirm the 2×2 block
  reads as genuinely centred (not just vertically centred below the header, which is what this implements, vs.
  centred on the TRUE full-screen midpoint if that's what was actually meant); confirm each card's quarter
  size still leaves every control (including the RATE row fixed last entry) comfortably legible and tappable
  at the real, smaller size — not just structurally present per the arithmetic above.**
- **▶ EUCLIDEOUS — fixed a lane-card height-budget miscalculation that left the RATE button (and the rest of
  its row) unresponsive to touch (2026-10-06, on `main`; iOS builds, no test-target reach (EuclideousPage.swift-
  only); DEVICE feel owed). Paul: "The rate button doesn't respond to touch." Traced via exact arithmetic, not
  guessed. `laneCard`'s height split (the entry 3 commits earlier, "merge the gesture tab into the lane's own
  box") reserved `EuclidLaneBox` `height − 60`, leaving only 60pt external for `laneControls` below it — but
  `laneControls` actually needs `16` (the outer `.padding(8)`×2) `+ 8` (the VStack's own spacing) `+ 46`
  (`laneControls`' own 2 remaining rows: 22 INV/beacon + 6 internal spacing + 18 OUT/RATE) `= 70`pt, a 10pt
  shortfall. The overflow pushed `laneControls`' LAST row — OUT/RATE, where the RATE chip lives — past this
  card's own nominal bottom edge, into the NEXT lane card down in the 2×2 grid; since that sibling is declared
  LATER in the outer VStack, it wins hit-testing in the overlapping region — a tap aimed at RATE was landing on
  whatever actually sat on top there instead, reading as "doesn't respond." Fixed the split to `height − 76`
  (a few pt of margin over the bare 70pt minimum, matching the pre-merge code's own built-in slack rather than
  computing to the exact byte). UI-only, no engine/model change. **DEVICE-OWED:** confirm RATE (and the rest of
  the OUT/RATE row) now responds reliably across all 4 lane positions, including the bottom row (lanes 2/3),
  which has no sibling below it to overlap but should read identically now that the budget itself is correct.**
- **▶ EUCLIDEOUS — a silent, never-restored state finally traced to its REAL root cause: the persisted config
  was never resynced on a fresh plugin load, at all (2026-10-06, on `main`; iOS builds, macOS 1207 green
  (Models.swift-only reach); DEVICE ear owed — the other two prior "fixes" this session were real but
  insufficient on their own, confirmed only by this third one). Paul, after the pulses:0 default fix two
  commits earlier: "I still don't hear this euclidius playing." Traced methodically rather than assuming the
  prior fix had simply failed. **FINDING 1 (closes a real but narrower gap):** ANY edit to ANY of Euclideous's
  4 lines — even an unrelated one, e.g. an emitter-toggle tap — persists the WHOLE 4-line array wholesale via
  `editDocument`. So a session that touched Euclideous even ONCE during the brief window the pulses:0 bug was
  live got the bad value baked into the DOCUMENT as real, non-nil data — which the earlier padding-fallback
  fix never even runs for (padding only applies when the field is nil/short). Fixed by moving the pulses-floor
  from the PADDING step into `euclideousLinesResolved` itself, applied to EVERY resolved line unconditionally
  (`if pulses <= 0 { pulses = 1 }`) — repairs an already-stuck persisted document on its very next resolve,
  not just a never-touched one. 0 hits is never musically meaningful for a EUCLID line (`enabled: false` is
  the real, existing mute) and was never reachable via the gesture before this session anyway, so this is
  safe going forward too; the gesture clamps (`euclideousApplyY`/`onAllHitsDelta`) were floored at 1 to match,
  so the live HUD readout never shows a value the engine won't honour. +1 regression test exercising the
  exact stuck-document shape. **FINDING 2 (the ACTUAL root cause of "still doesn't play"):** traced the full
  document-load lifecycle by hand rather than assuming `refreshFromDocument()` covers every load path — it
  doesn't. `fullState.set` (AUM loading a saved project — the single most common real path, and what happens
  on EVERY Xcode reinstall) reassigns `document` wholesale but calls NEITHER `refreshFromDocument()` NOR
  anything that would notify the SwiftUI layer. The OTHER persisted BuildPage subsystems (`buildPlayGrid`/
  `partAuto`/`buildScenes`/`buildUnassigned`) are robust to this ONLY because `buildPersistTick()`'s own
  recurring consume-poll (on the existing ~4Hz timer) periodically re-checks "is there new document data I
  haven't picked up yet" — a self-healing pattern Euclideous was simply never wired into when it shipped.
  Net effect, confirmed by tracing rather than guessed: EVERY fresh plugin instance (any Xcode rebuild+
  reinstall, or AUM reopening a saved session) silently reset Euclideous to OFF + the bare default lines,
  REGARDLESS of what had been authored/saved — and since OFF never even composes into the scene, this alone
  fully explains continued silence no matter how correct the pulses floor was. **FIX:** added a parallel,
  UNGATED poll-and-compare alongside the existing `buildPersistTick()` call in the same `.onReceive(timer)`
  block (AudioUnitViewController.swift) — reads `au.uiEuclideousLines/Enabled/Receiver()` every tick,
  writes `@State` ONLY on change (matching this poll's own stated "don't force a re-render every tick"
  convention), and calls `buildPublishScene()` once if anything actually changed (the engine only ever reads
  these @State vars through that function's own `Input` fold — a silent resync with no republish would sit
  unapplied). NOT a pending/clear transport like `buildPlayGrid` (which gets unconditionally re-written every
  tick regardless, so nil-ing after consuming is safe there) — Euclideous's fields are ONLY written on a real
  user edit, so nil-ing them after a read would have silently discarded a user's saved configuration on the
  very next encode; a plain, non-destructive read-and-compare was the correct, safer shape for this field.
  Confirmed safe against a live drag: `editDocument` mutates `document` SYNCHRONOUSLY on every call —
  `coalesceKey` only coalesces the UNDO SNAPSHOT, never the write itself — so the document and the @State
  can never differ mid-gesture, ruling out the race a naive "always re-read" approach could otherwise hit.
  NOT gated on `buildPersistTick()`'s own `activeTab == .build` guard, since Euclideous opens from the
  persistent header, independent of which tab is active. **DEVICE-OWED:** the actual, concrete test this
  whole chain of fixes needs — rebuild, reinstall fresh via Xcode (a genuinely NEW plugin instance, not just
  reopening the still-running one), open a session that previously had Euclideous configured, and confirm it
  now shows ON/the saved pattern/the saved receiver immediately, without needing to manually re-toggle
  anything; separately, confirm a brand-new, never-touched Euclideous session still opens with all 4 lanes
  audibly playing as soon as a note is held (the pulses-floor fix's own, narrower claim).**
- **▶ EUCLID/EUCLIDEOUS — the drag-slide visual from the entry below was REVERTED same day; offset-drag
  sensitivity now matches box pitch instead (2026-10-06, on `main`; iOS builds, no test-target reach
  (EuclidLaneUI.swift-only); DEVICE feel owed). Paul, after trying the sliding-belt visual: "I don't like the
  way the offset now works after your last change. I preferred it as it was, but with the distance the
  finger moves to [sic] moves should line up with the number of spaces a hit moves." Two parts: (1) revert
  the sliding-box rendering entirely — restored the comet+flare+static-box drawing unconditionally (removed
  `@State dragOffsetX`, the `if let dragOffsetX {…} else {…}` branch, and `EuclidGesturePad`'s
  `onDragOffsetX` callback + its two `Coordinator` call sites, all clean deletions, not dead code left
  behind). (2) the ACTUAL ask, a genuine sensitivity fix: the horizontal (rotate) drag used a FIXED 18pt-per-
  step regardless of the lane's own step count/width, so a visual box's on-screen width almost never matched
  how far the finger had to travel to move it — "the distance moved should line up with the number of
  spaces moved" names this mismatch precisely. New shared `euclidBoxGeometry(n:usableWidth:) ->
  (boxW:gap:pitch:)` (ONE formula, so the Canvas's own box layout and the gesture's rotate sensitivity can
  never compute two different box widths for the same lane — the RATCHET/DEST class of bug this codebase
  keeps guarding against). `EuclidCometBar` gained an explicit `width: CGFloat` param — NOT measured via a
  new GeometryReader, but derived EXACTLY from `EuclidLaneBox`'s own existing layout math at its one call
  site (`width - 64`: the 6pt×2 outer padding + the 44pt play button + 8pt HStack spacing the comet bar never
  occupies) — so the pitch computed for gesture sensitivity is provably the SAME width the Canvas will
  actually render at, no approximation. `EuclidGesturePad` traded its removed `onDragOffsetX` for a new
  `rotateStepPt: CGFloat` (the caller-computed, box-pitch-matched points-per-step), used ONLY for the
  horizontal axis in `Coordinator.handlePan`; the vertical (hits) axis and the pinch (steps) handler keep the
  original fixed `euclidDragStepPt` — Paul's wording named "offset" specifically, not hits. Shared component
  (`EuclidCometBar`/`EuclidGesturePad`), so this also fixes the regular BUILD-page EUCLID editor's own rotate-
  drag feel, not just Euclideous's. **DEVICE-OWED:** confirm a drag across exactly one visible box's width
  now moves the offset by exactly one step, at a few different step counts (2, 8, 16) where the box pitch
  differs substantially; confirm the regular BUILD-page EUCLID editor's drag feels right too.**
- **▶ EUCLIDEOUS — the offset drag now visually SLIDES the box grid with the finger — REVERTED same day, see
  the entry above (this entry is kept as history, not current behaviour) (2026-10-06, on `main`;
  iOS builds, no test-target reach (EuclidLaneUI.swift-only); DEVICE feel owed — genuinely untestable off-
  device). Paul: "When I move offer [offset], I want the boxes to move left/right alongside my finger. I want
  it to feel like I'm dragging the box forward or back in place." SUPERSEDES, for the DURATION of an active
  horizontal drag only, several earlier sessions' own deliberate "box content is direction-independent, the
  grid itself never relocates" design (still true at rest and for the DIRECTION toggle — this ask was
  specifically about the live feel of the ROTATE DRAG gesture, a different interaction this codebase hadn't
  previously targeted). **MECHANISM:** `EuclidGesturePad`'s pan handler already computed, each `.changed` tick,
  a discrete step count via `round(t.x/stepPt)` — the ACTUAL `rotate` value only ever moves in whole steps,
  unchanged by this fix. New `onDragOffsetX: (CGFloat?) -> Void` callback reports the SUB-STEP LEFTOVER (`t.x −
  committedSteps×stepPt`, always within ~±stepPt/2, nil when no horizontal drag is active) on every tick;
  `EuclidCometBar` holds this in a new local `@State dragOffsetX` and, while non-nil, renders a SIMPLIFIED
  "sliding belt": every box's screen x shifts by `(dragOffsetX/stepPt) × boxPitch` — scaling the raw finger
  leftover into box-pitch units so the visual tracks 1:1 and lands in sync with each discrete rotate-commit —
  with TWO extra virtual boxes just outside the normal `0..<n` range (indices −1 and n, content read via `((i
  mod n)+n) mod n`) so whichever sliver is entering from the wrap edge is always covered, no actual position-
  wrapping math needed. The comet + per-box flare/burst are SUPPRESSED during this mode (flagged, not silent) —
  both are tied to PLAYBACK TIME and keyed on each box's STATIC screen position, which is meaningless while
  boxes are themselves sliding; they resume unchanged the instant the drag ends, by which point `rotate` has
  already landed on its new value via the SAME discrete `onRotateDelta`/`onAllRotateDelta` calls this gesture
  has been sending throughout — so there's no pop/mismatch at release, only a loss of the comet/flare DURING
  the brief scrub itself. Hoisted the `18pt`/step sensitivity from a `private` constant inside
  `EuclidGesturePad.Coordinator` to a shared file-level `euclidDragStepPt`, so the Canvas's visual scaling and
  the gesture's own discrete stepping can never drift onto two different numbers. Applies to BOTH the 1-finger
  (this lane) and 2-finger (every lane) horizontal drag alike — only on whichever lane(s) the touch physically
  lands on, since each lane owns its own `EuclidGesturePad`/`@State`; a lane nudged along by a 2-finger
  ALL-LANES drag on a DIFFERENT lane still just updates its static grid in discrete jumps, as before. Shared
  with the regular BUILD-page EUCLID editor (`EuclidCometBar` is the one component both use) — the new visual
  applies there too, not just Euclideous, since Paul's asks about this comet bar have never previously
  distinguished the two editors. Vertical (hits) drag is UNTOUCHED — scoped to "left/right" exactly as asked.
  UI-only, no engine/model change. **DEVICE-OWED:** the slide reading as smooth/responsive rather than janky;
  confirm no visible pop or stutter at the moment the drag ends and the comet/flare reappear; the wrap-around
  feel at the pattern's edges; confirm the regular BUILD-page EUCLID editor's drag now feels the same way,
  which is intended, not a regression if unexpected.**
- **▶ EUCLIDEOUS — a new standalone, playable 4-lane EUCLID instrument page, SHIPPED end-to-end (2026-10-05/06, on
  `main`, `7cf1856`…`6d3514b`; macOS 1207 green incl. 19 new, iOS builds; whole-feature DEVICE pass owed). Paul:
  "I want a new page on the app called Euclideous... centre around four Euclid lanes in the centre of the
  screen... as part of the same Euclid control will be tabs for x/y gestures. Default is hits/offset, then
  velocity/gate, then note/octave. It should have rate per lane, invert, and one or more emitters can be toggled
  per lane. The goal is to make it feel like a playable, grabbable instrument." Also named as a future standalone-
  app extraction candidate. **PLANNED FIRST** (EnterPlanMode, 3 parallel Explore agents covering the EUCLID
  engine internals / the existing lane UI / the live-cell+standalone-seam architecture, then a dedicated Plan-
  agent validation pass that caught two real `composeSceneMeta` guard bugs, a missing `machineID`-resolution
  requirement, and a genuine correctness bug in the first-draft INVERT design before any of it shipped) — plan at
  `~/.claude/plans/woolly-crafting-music.md`. Three architecture forks ratified with Paul via AskUserQuestion
  before planning: navigation = a header-icon overlay (CogPage's presentation precedent); lane architecture = ONE
  EuclidMachine with 4 EuclidLines (today's model, extended), not 4 separate cells; gesture tabs = independent per
  lane. **A self-caught plan revision, flagged back to Paul before implementing:** my own first plan draft said
  "mirror CogPage's shape exactly," conflating CogPage's presentation MECHANISM (a plain overlay, engine never
  stops — worth reusing) with its SIZING (a small ~540×620 settings card — wrong for "centre of the screen... a
  playable, grabbable instrument"); caught on Paul's own "check for shortcuts" prompt, corrected before
  ExitPlanMode, and (separately) the extracted lane box's `height` was about to inherit a hardcoded 56pt constant
  tuned for BuildPage's cramped inline panel — added as an explicit parameter specifically so Euclideous isn't
  silently stuck at BUILD-page size. **ENGINE (Models.swift/SnapshotBuilder.swift/Router.swift):**
  `EuclidLine.rate: ArpRate?` (nil ⇒ inherit the machine-wide rate) and `.emitterMask: UInt8?` (bit i = emitter
  A–D, nil ⇒ inherit the cell's own bus mask — mirrors `echoInKeyReceivers`'s exact convention) — threaded through
  the CR-8 decoder, the SnapshotBuilder's explicit `EuclidLine(...)` reconstruction (a fresh literal, not copy-
  with-mutation — the exact gotcha a prior RATE-automation feature was bitten by), `strikeChord`'s new
  `busOverride` param (reaches `chopMask`'s `base:` only — EUCLID is structurally always the chain tail for
  Euclideous's one-slot cell, a provable consequence of its own shape, not a separately-enforced limit), and
  `runEuclidLine`'s now-explicit `rate`/`busOverride` params (was a closure-captured machine-wide field). Shared
  with the existing BUILD-page EUCLID processor — nil-default byte-identical either way, disclosed in the field's
  own doc comment. **PERSISTENCE:** `PluginState.euclideousLines/Enabled/Receiver` — genuinely authored, saved-
  document state (not an ephemeral BUILD-page audition, which never survives closing the plugin).
  **ROW RESERVATION (Snapshot.swift/BuildSceneLogic.swift):** all 32 existing engine rows are permanently claimed
  (8 ferries × 4 rows); the existing chain-audition mechanism was rejected as a foundation (squats in whichever
  row is free in the CURRENTLY ACTIVE ferry's block, singular, coupled to unrelated BUILD-page resets — wrong for
  "a reliable, always-on instrument"). Confirmed the render engine itself is ferry-agnostic (every full-row loop
  in Router/Kernel/SnapshotBuilder treats every row identically; ferry semantics live only in BUILD-page authoring
  code, which derives rows FROM a ferry index, never the reverse) — so `Snap.rows` widened 32→33, with
  `Snap.euclideousRow` the new reserved index. `composeSceneMeta` composes+pins Euclideous's one cell there
  unconditionally when enabled — needed two specific, easy-to-miss guard edits (the function's own opening
  early-return, and the `rowLane` PUBLISH guard — a full-vs-empty-array contract separate from computing the pin
  itself), both caught by the Plan-agent validation pass before shipping, not discovered as a device bug. A narrow
  pre-existing `AutoLane` legacy decoder (`cells / Snap.rows`, targeting pre-2026-09-04 docs) was frozen to the
  literal 32 so the live widening can't misread it. **UI EXTRACTION (GridUI.swift → new EuclidLaneUI.swift):** the
  existing BUILD-page EUCLID editor's lane box/comet bar/gesture pad/beacon were ALL private members nested inside
  the one ~3600-line `ProcessorBox` — unreachable from a new page by both access control and implicit-`self`
  coupling to ~10 stored properties. Extracted (not duplicated — this codebase's own standing "share the formula,
  never re-derive it" discipline, applied to UI) into `EuclidLaneBox`/`EuclidBeacon`/`EuclidGesturePad`, each
  explicitly parameterized (a new `EuclidLiveClock` bundles the 6 shared "live clock" scalars); `ProcessorBox`'s
  own `case .euclid:` now calls the same shared components — a pure refactor, its behaviour should be unchanged.
  **THE PAGE ITSELF (new EuclideousPage.swift):** reuses CogPage's presentation mechanism only (a plain
  `if showEuclideous {}` sibling in `DiagView`'s root ZStack, confirmed not to stop the engine), filling the
  screen rather than a bounded card. A fixed sentinel ephemeral machine id (`"euclideous"`) makes the cell's
  `machineID` resolve at all (confirmed the registered machine's own stored params are irrelevant at render time —
  `emitGeneratorRow` always overwrites `.a` with the cell's own chain — so re-registering it every publish is
  simple, not wasteful in any way that matters). `setFreeRunEnabled`'s OR-chain gained `euclideousEnabled`; a new
  poll for beacon readiness runs independent of the existing `editorOpen`-gated one. **GESTURE TABS** (HITS/OFFSET
  → VELOCITY/GATE → NOTE/OCTAVE, independent per lane) retarget the SAME `onRotateDelta`/`onHitsDelta` closures
  `EuclidGesturePad` already exposes — their callback type was already a bare, meaning-free `(Int) -> Void`, so
  zero gesture-component changes were needed, only per-lane tab state at the call site. NOTE/OCTAVE's cycle
  deliberately excludes `.riff`/`.arp` (only resolve against a matching predecessor chain slot; Euclideous's cell
  has none by construction — landing on either would silently go silent). **INVERT** is built entirely from the
  existing, already-live HIT/MISS split — not a revival of the old dead `invert` field, which would have changed
  the SHARED `EuclidLine` model's behaviour for the existing BUILD-page processor too. A first-draft naive 4-field
  swap was WRONG for the single most common case (a fresh hit-only lane): `missNoteSel == nil` is the engine's own
  "MISS off" sentinel, but `noteSel == nil` falls back to legacy target/pick resolution (audible `.all`, not
  silence) — the two sides aren't symmetric by default. Fixed by establishing a real invariant first
  (`missNoteSel` always populated once touched, `missVelocity <= 0` is this page's own "off" signal, symmetric
  with the hit side's existing convention) — the pure swap logic lives in Derivations.swift specifically (not
  EuclideousPage.swift, which imports SwiftUI) so it reaches the macOS test target; verified by hand AND by test
  that inverting twice is a genuine behavioural no-op. **TESTS:** +19 across Models/SnapshotBuilder/Router/
  BuildSceneLogic/Derivations (decode-tolerance, the SnapshotBuilder reconstruction gotcha, per-line rate density,
  per-line emitter routing, the two composeSceneMeta guards in isolation, the INVERT fresh-lane/round-trip/both-
  sides-configured cases, the note-select cycle's riff/arp exclusion). **DEVICE-OWED, the whole feature:** every
  item any prior EUCLID UI entry in this log has owed, now compounded across 4 simultaneous lanes — real size/
  touch-target feel, all 3 gesture tabs actually retargeting correctly in the hand, beacon accuracy, surviving
  host stop/resume and a full app relaunch (persistence), coexisting with an active ferry, free-running with the
  page closed, and confirming the BUILD-page EUCLID editor is still pixel/gesture-identical after the extraction.**
- **▶ EUCLIDEOUS — two follow-up fixes: total silence (self-inflicted) + the gesture tabs merged into the lane's
  own box (2026-10-06, on `main`, `f3cbe05`+1 more; macOS 1207 green, iOS builds; DEVICE eye/ear owed on both).
  **SILENCE, Paul: "It's not making any sound at all, regardless of what emitters, receivers, notes, etc I use."**
  Traced empirically (ruled out the row-pin math, the per-row clock fallback, and a stale-decode-array theory in
  turn, each by direct code reading, before finding it) to `euclideousLines` defaulting ALL 4 lanes to `pulses: 0`
  in three places (the `@State` default, `PluginState.euclideousLinesResolved`'s padding, a UI fallback) — a
  copy-paste of `euclidLinesForEditing()`'s OWN "rows 1-3 pad silent" convention (correct THERE — only row 0 of
  the BUILD-page's 4-row widget is meant active by default), wrongly applied to Euclideous's 4 INDEPENDENTLY-live
  lanes. A zero-hit pattern can never sound regardless of anything downstream, exactly matching the report. FIX:
  all 3 spots now fall back to `EuclidLine`'s own plain default (`pulses:1, steps:8` — "a fresh lane defaults to
  1 of 8," already an established convention elsewhere in this codebase) instead of overriding it with silence.
  Also fixed the 2 existing unit tests that had encoded the bug as expected behaviour (written to match my own
  implementation, not the actual intent) — a lesson on its own: a passing test is only as good as what it asserts.
  **TAB MERGE, same session, Paul: "I want the x/y toggles to be named more clearly (vel/gate, note/oct,
  hits/offs). I want this tab to appear as the same control as the Euclid lane, as opposed to being in a separate
  box."** Labels: H/O·V/G·N/O → HITS/OFFS·VEL/GATE·NOTE/OCT (`EuclideousGestureTab.label`, display-only, no
  persisted-value change). **LAYOUT:** `EuclidLaneBox` (EuclidLaneUI.swift, SHARED with the regular BUILD-page
  EUCLID editor) gained an optional `trailingContent: AnyView? = nil` + `trailingHeight: CGFloat = 0` — type-
  erased rather than generic, so the struct's own type stays unchanged for its existing caller, and nil (every
  BUILD-page call site) is byte-identical to before. Its `body` now wraps the play+comet row and `trailingContent`
  in ONE `VStack`, with the box's existing border/background/selection-highlight modifiers applied to THAT VStack
  — so a caller's trailing content renders INSIDE the same bordered box as the lane itself, not floating in a
  separate, unbordered area below it (confirmed this was the actual visual cause: `EuclidLaneBox` already drew
  its own visible border/fill; the gesture-tab row lived in a plain, borderless `laneControls` block beneath it,
  reading as two different things even though both sat inside one near-invisible 3.5%-opacity outer card).
  `EuclideousPage.swift`'s `laneCard` now hands the (factored-out) `gestureTabRow` to `EuclidLaneBox` as
  `trailingContent`, with `trailingHeight: 22` so the comet bar correctly cedes exactly that much internal room
  rather than guessing; `laneControls` lost its tab row (now just INV + 2 beacons + the OUT/RATE row) and the
  height split between `EuclidLaneBox`/`laneControls` was recomputed from the real per-row heights (92→60
  external reserve, the difference moving into `EuclidLaneBox`'s own now-larger budget). UI-only (EuclidLaneUI.
  swift + EuclideousPage.swift), no engine/model change, no test-target reach. **DEVICE-OWED:** confirm all 4
  lanes genuinely sound the instant a note is held post-fix; the merged box reads as one continuous control
  rather than a border mismatch; the longer tab labels fit without wrapping/clipping at real lane width; confirm
  the regular BUILD-page EUCLID editor is still pixel-identical (its own call site never passes the new params).**
- **▶ EUCLID BEACON — the full-guard-chain gap CLOSED FOR REAL via render-thread readiness, not a door-note
  approximation (2026-10-05, on `main`, `e4f252b`; macOS 1193 green incl. 3 new, iOS builds). Direct follow-up:
  Paul asked "are there any outstanding bugs?" after the prior session's 19-bug sweep closed 18/19 — the one
  disclosed partial was the beacon's own `canPlay` check approximating the engine's real emission guard chain
  off a door's raw held-note count. Paul: "Please fix that bug." **THE REAL FIX NEEDED LIVE ENGINE STATE, not a
  better UI-side guess:** `composeChainSet`/`chainScratch` (the functions that resolve RIFF/ARP predecessors and
  the true upstream pool) mutate shared render-thread scratch buffers — calling them from a UI-polling thread
  would race against the real render path using the SAME buffers concurrently. Followed this codebase's own
  established idiom instead (the same one `cellSoundingNotes`/`riffDrunkPosAt`/`rowSoundingVoices` already use):
  compute the answer ONCE per cell per render, ON the render thread, write it into a plain per-cell array, and
  let the UI poll that. **NEW `Router.euclidLineReady: [UInt8]`** (2 bits per line — hit/miss — packed per cell),
  computed inside `case .euclid:` itself using the EXACT guards `runEuclidLine`'s hit/miss closures apply:
  velocity>0 (a genuinely MISSED guard, not just approximated — the beacon never checked this before at all); for
  a RIFF pick, at least one non-rest authored step AND a non-empty pool feeding riff's own slot (confirmed via
  `riffResolve`'s own doc comment — it only ever fails for rank<1 or an empty pool, so "pool non-empty" is
  exactly sufficient, not an approximation); for an ARP pick, a non-empty pool feeding arp's own slot (same
  confirmation via `arpPick`'s "returns -1 for an empty pool" doc comment); for every other pick, the TRUE
  upstream `srcCount` already composed for this cell's chain — not the door's raw held notes, closing the
  originally-disclosed gap exactly. Explicitly zeroed at `process()`'s pool-empty guard so "nothing held" reads
  as "nothing can play" promptly rather than going stale between renders. **THREADED through the identical chain
  `riffDrunkPos` already established:** `Router.euclidLineReadyAt` → `Kernel.euclidLineReadyAt` →
  `MidiSparkAudioUnit.pollEuclidLineReady` → the existing ~30fps `editorOpen` poll in AudioUnitViewController
  (`@State buildEuclidLineReady`) → `BuildPage`'s `ProcessorBox` construction → `GridUI`'s
  `euclidLineReadyLive` — `euclidBeaconCanPlay` collapses to a single bit-read; every approximate check that used
  to live in GridUI.swift (door-note counting, predecessor-type-only matching) is gone. **+3 RouterTests**
  exercising `Router.euclidLineReadyAt` directly via a new `runKeepingRouter` test helper (the shared `run()`
  helper discards its `Router` instance; this one hands it back) — velocity 0 vs 1 on the same line; a
  `[CHANCE(0%)→EUCLID]` chain reading not-ready despite a healthy 3-note held chord (the core "composed pool, not
  door count" proof) vs. CHANCE fully open reading ready; a RIFF predecessor with an all-rest pattern vs. one
  with a genuine non-rest step; an ARP predecessor fed by an emptied upstream pool despite the predecessor TYPE
  matching. **PROCESS NOTE:** the iOS build's own background-task notification falsely reported "failed, exit
  code 1" — traced to my own verification script's trailing `grep -c "BUILD FAILED"` legitimately exiting 1 for
  finding zero matches (the GOOD outcome), which the harness surfaced as the overall command's exit status; the
  actual log, read directly, showed `BUILD SUCCEEDED` with zero "error:" lines across all 453 lines — the
  standing "always check the real log, never trust the notification alone" lesson, confirmed yet again, just in
  the opposite direction this time (false failure, not false success). **DEVICE-OWED:** the beacon's accuracy is
  now machine-verified end-to-end for the engine half (Router.swift, full test coverage); the UI threading
  (GridUI/BuildPage/AudioUnitViewController/MidiSparkAudioUnit) has no macOS test-target reach as always — confirm
  on device that a RIFF/ARP-sourced or rank-beyond-pool-size lane now correctly stays dark instead of flashing for
  a strike that never sounds.**
- **▶ CODE REVIEW — 5 parallel reviews of the 5 most critical subsystems (named off CLAUDE.md's own architecture
  invariants: the render/SnapshotStore boundary, the derived-never-accumulated discipline, Codable decode-
  safety, the dual host-automation routes, render-path allocation), every finding independently re-verified
  before acting (2026-10-05, on `main`; macOS 1184 green incl. +4, iOS builds). Paul: "Please perform code
  reviews of the 5 most critical parts of the system," then "Please fix this." **DECODE-SAFETY (CR-8 class):**
  ten structs had either NO custom decode-tolerant `init(from:)` at all, or sat NESTED inside an already-"safe"
  parent whose own `decodeIfPresent(NestedType.self, forKey:)` only guards a MISSING KEY — if the key IS present
  but the nested type's OWN synthesized decode throws (because one of ITS non-Optional fields is missing), that
  throw propagates straight through the parent's "safe" init, defeating it entirely. Found + fixed across all
  nesting levels, not just the top: `OnConfig` (16 fields, nested under `Machine`), `ChordSplit`/`VelWindow`/
  `Chop` (nested under `Cell`), `ScalePool` (nested under `Receiver`), `MacroTarget`/`MacroEmitterTarget`/
  `MacroCellValue` (nested under a macro slot, previously ZERO Optional fields and no custom init at all — the
  worst-exposed of the ten), `EuclidLine` (the 5 ORIGINAL day-one fields — target/pulses/steps/rotate/invert —
  were still plain non-Optional despite 13 fields added since; EUCLID is the most actively-developed struct in
  the codebase, so this was the single highest-probability next factory-reset), `ParamLFO` (target/shape/period).
  Each gets the house `decodeIfPresent(...) ?? default` pattern, one line per field, in a separate `extension`
  (preserves the memberwise init + synthesized Encodable/CodingKeys, matching Cell/Machine's own precedent).
  **DEAD-CODE:** `isModifierFoldable` checked `.velocity`/`.euclidMask` alongside `.shift`/`.humanize`, but its
  ONLY caller (`chainDriverIndex`) only ever evaluates it inside an `isDriverType(...)` guard whose exhaustive
  switch never includes those two types — the arms could never fire. Removed; both types' real fold-eligibility
  is handled correctly elsewhere (`downstreamMaskFoldIndex`, VELOCITY's own dedicated fold in `emitDriverNote`),
  so this changes nothing behaviourally. **RENDER-THREAD ALLOCATION:** `PassthroughGate.drainActive()` built and
  returned a fresh `[(UInt8,UInt8)]` on the genuinely-stranded-echo path (PANIC) — a real heap allocation on the
  render thread, violating invariant 3, just rare enough (only fires when echoes are ACTUALLY stranded) to have
  gone unnoticed. Fixed with a preallocated, fixed-size `drainScratch` (16×128, the absolute worst case) filled
  IN PLACE; `drainActive()` now returns a count, a new `drained(_:)` reads each entry — the Kernel.swift PANIC
  call site and its one test updated to match. **PARAMETER RAMPS NEVER SMOOTHED (the big one):** a host
  `.parameterRamp` event (automation drawing a continuous sweep, not a step) was applied EXACTLY like a plain
  `.parameter` event — `applyParamEvent` snapped `overrides[idx]` straight to the final value, discarding
  `rampDurationSampleFrames` entirely (confirmed via grep: that field was referenced NOWHERE in the codebase
  before this). A host sweep rendered as a staircase of per-block jumps, not a ramp. **FIX:** 4 new parallel
  arrays (`rampFrom`/`rampTo`/`rampStartSample`/`rampDurationSamples`, fixed-size, matching `overrides`) + a new
  `tickRamps(atSample:)` called once at the top of `process()` (before anything reads `over(_:_:)`), which
  linearly interpolates any in-flight ramp to its value at this render window's start sample, settling exactly
  at the target once the ramp's duration elapses. `applyParamEvent` now takes `atSample`/`rampDurationSampleFrames`
  (threaded from the real `AUParameterEvent` at the Kernel.swift call site) and ARMS a ramp instead of snapping,
  UNLESS nothing has overridden that slot yet — a first touch with no known starting value snaps instead of
  fabricating a baseline (an honest limitation, not silently guessed). Ramp state clears alongside `overrides`
  on both existing drop-points (`reset()`, and `refreshOverrides` on a real generation change) — a document edit
  is still the one truth that cancels any in-flight automation. **A MORE SEVERE DISCOVERY, flagged not fixed:**
  tracing this surfaced that MACRO automation via this route is a complete NO-OP, not merely unsmoothed —
  `slot(for:)` never maps macro addresses (400+i) at all, so `applyParamEvent` silently no-ops for them via its
  own `guard let idx = slot(for: address) else { return }`; and separately, `box.macroValues` (the field that
  WOULD carry a live macro value into the render path) is read NOWHERE in Router.swift — macro effects are
  baked into their target params entirely at BUILD TIME (`SnapshotBuilder`, main thread), never read live by the
  render thread. So a macro's only functioning automation route today is the AUParameterTree's `implementorValue
  Observer` → `scheduleRebuild()` → a full rebuild, with no sample-accuracy guarantee at all. Properly fixing
  this needs a genuinely bigger architectural change (moving macro modulation from build-time-bake to render-
  time-read) — deliberately SCOPED OUT of this fix as too large/risky to bundle with the rest; swing/stepRate/
  transpose (the params that DO flow through the override-read path) are the ones this fix actually smooths.
  **SNAPSHOTSTORE (theoretical, practically-mitigated use-after-free):** `acquire()` is deliberately
  `takeUnretainedValue()` (zero retain traffic on the render path) — the ONLY thing keeping an acquired box
  alive while render reads it is the main-thread `live` array's strong reference, and the old retention window
  (`keep last 3`) was close enough to a plausible publish-storm (e.g. a fast UI drag, each tick calling
  `scheduleRebuild()`) that a render call stretched by OS scheduling jitter could plausibly outlive it — a real,
  if rare, risk, not purely theoretical. Widened the retention window 3→16 (cheap — `SnapshotBox` instances, not
  audio buffers) and documented the real fix (an acquire/release handshake, render reporting back which
  generation it's done with) as deliberately not built, since it would add atomic traffic to the render path for
  a finding this margin already covers. +4 RouterTests (the two pre-existing `applyParamEvent` call sites
  updated to the new signature; one new test driving a ramp end-to-end — no-prior-override snaps, mid-ramp reads
  the linear midpoint, past the ramp's end sample settles exactly at the target). **DEVICE-OWED:** none of this
  is UI — every fix lands inside the macOS test target or is covered by the existing iOS build; nothing here
  needs a device pass.**
- **▶ EUCLID / PART-GRID BUG-HUNT ARC — a 20-bug sweep, the "hardcoded 8 columns" cluster, AU thread-safety, +4
  closing fixes (2026-10-04/05, on `fix/euclid-no-scroll-direction-order-2x2-grid` → `main`, `28b7d1f`…`e638d77`;
  macOS 1189 green (was 1183 at the start of this arc, +6 net), iOS builds; DEVICE-owed per item, noted below).
  Paul reported two bugs in one message ("I sometimes see euclid play for only half the duration of a pass on the
  part grid. I've also cloned a row and found that the additional rows don't sound"), then — after the first fix —
  asked me to "search for 20 bugs," approved the primary recommendation with "I'll follow your advice. Go," then
  "please move onto the next problem" (autonomous, one item at a time), then "I want all of these done, please" for
  the remaining 4. **ROW-CLONE MULTI-SELECT WIPE (`28b7d1f`):** cloning/mutating/randomizing/creating a row from the
  row-creator menu REPLACED the column's active-rungs selection with just the new row, instead of ADDING to it — so
  a MULTI-selected column lost its other rows' sound the instant a new row was created in it. `buildSelectRow` (the
  shared selection-setter every row-creation path already called) gained an `additive: Bool = false` param; the 4
  row-creation call sites (CLONE/MUTATE/RANDOM/CREATE NEW) pass `true`. **THE "HALF A PASS" REPORT, root-caused —
  EUCLID's STANDALONE-DRIVER dispatch silently hardcoded an 8-column pass (`47537cc`):** `emitTickRow`'s two
  per-tick generator dispatch switches (one for a real chain driver, one for a bare standalone driver) had
  DIVERGED in which params they forwarded — the chain-driver switch passed `cycleBeats`/`chainDriver` to EUCLID (and
  BURST/CASCADE/DRONE/SHIFT/HUMANIZE/HOCKET/WEAVE); the standalone-driver switch didn't, so those cases fell back to
  a literal `Double(Snap.cols) * S` (Snap.cols = 8) instead of the row's REAL length — correct only by coincidence
  on a default 8-column, default-rate part; silently wrong (effectively halving the audible pass) on a 16-wide part
  or any row with a custom per-row rate. Fixed by passing `cycleBeats`/`chainDriver` through both switches
  identically. **THE SAME BUG, SWEPT EVERYWHERE ELSE IT HAD SPREAD (`b94516d`):** a full sweep of
  `Double(Snap.cols) * S`-shaped hardcoding found it ALSO in `emitColumnHolds`/`emitColumnTransition` (STRIKE PER
  SPAN + the CHORDS-hold pool compose), `emitTuttiPatternRow`, `emitLengthRow`, `emitStrumRow`, and
  `modPeriodBeats`/`applyInternalMods` (MOD's own span) — all six gained/threaded a real `cycleBeats: Double`
  parameter instead of the hardcoded literal. Mirrored on the UI side (GridUI.swift): `ProcessorBox` gained
  `gridCols: Int = Snap.cols` (threaded from `buildSlotBox` in BuildPage.swift as `roomsRoom == .part ?
  buildPartCols : Snap.cols`) and 7 call sites (EUCLID's comet bar, BURST, TUTTI, RIFF, the LFO editor's live-rate
  readouts) switched from a bare `8 *` to `Double(gridCols) *` — so the editor's own live sweep can't show a
  DIFFERENT pass length than what's actually heard. +6 RouterTests comparing a 16-column/custom-rate row against an
  equivalent 8-column-with-explicit-span reference (this codebase's own standing lesson: prefer equivalence checks
  over hand-derived exact-tick predictions) — one (`testModRowSpanUsesTheRealRowLength`) needed a full redesign
  mid-build after discovering `SnapshotBuilder` clamps `modSteps` to exactly 8/16/32 entries regardless of row
  width (`cycleBeats` only changes traversal SPEED, not which indices exist) — rewritten to check WHEN a step lands
  rather than WHICH indices are reachable. **AU PARAMETER THREAD-SAFETY (`e494f9d`):** a 20-bug sweep turned up
  `wireParameterTree()`'s `implementorValueObserver`/`Provider` closures mutating/reading `self.document` directly
  — Apple's own docs say these can be called from ANY thread including realtime ones, but this codebase's own
  convention enforces main-thread-only document mutation elsewhere (`dispatchPrecondition(.onQueue(.main))`, e.g.
  `loadTestSession`/`setActiveScene`) and had no such guard here. Restructured into `applyParamValue`/
  `currentParamValue` (both asserting main-thread via `dispatchPrecondition`) with the observer/provider closures
  hopping to main (`DispatchQueue.main.async`/`.sync`) when called off it, rather than assuming the host always
  calls on main. **HARDENING SWEEP (`031f9a2`):** a latent `UInt8(1 << row)` overflow-trap risk in `buildSelectRow`
  tightened from `row < 8` to `row < Snap.rowsPerFerry` (+3 call sites, `buildCreateRowMachine`/
  `buildToggleSelectRow`/`buildRowMachine`, same tightening); a dead `top: String` param removed from
  `buildIOSelectChip` (+ its now-orphaned `letter` local); stale `Array(repeating: nil, count: 8)` fallbacks (3
  sites across BuildPage.swift/AudioUnitViewController.swift) resized to `count: Snap.rowsPerFerry`. **THE FINAL
  FOUR, closing out the full bug list (`e638d77`):** (1) `euclidTouchedLanes` (GridUI.swift) was one shared `Set`
  trying to represent two independent things — "all 4 lanes lit by a 2-finger ALL-ROWS gesture" and "lane 2 ALSO
  independently lit by its own single-finger touch" — so ending the ALL-ROWS gesture's `.removeAll()` wrongly wiped
  an unrelated lane's still-held touch too; split into `euclidSingleTouchedLanes`/`euclidAllRowsTouched`, two
  sources that can only ever clear their own contribution. (2) `pinchTouchDistance`'s `<2-touches` fallback changed
  from a guessed `60` to `0` — UIKit guarantees 2 touches by `.began` so this shouldn't trigger, but IF it ever
  did, `0` makes `delta = pinchStartDist*(scale-1)` a clean no-op instead of a guessed-and-possibly-wrong step
  change. (3) **THE ARCHITECTURAL FIX:** `lastTick[row]` (Router.swift's `iterateTicks`, shared by ARP/RIFF/
  RATCHET-ALL/HOCKET/EUCLID) was a single per-ROW dedup scalar — already flagged in an earlier session's own
  investigation as "a known limitation for 2+ real lines sharing a row" (one EUCLID line's tick could advance the
  shared dedup past a tick a SECOND line on the same row hadn't reached yet, smearing that line's onset into a
  later render window). Widened to `Snap.rows * tickDedupSlotsPerRow`(4) with a new `lineIndex` threaded through
  `iterateTicks`/`runEuclidLine`/the calling `for (lineIndex, L) in p.euclidLines.enumerated()` loop, so each of
  EUCLID's up to 4 lines gets its own dedup slot; added `resetTickDedup(row:)`/`resetAllTickDedup()` helpers and
  updated all 6 reset/flush call sites that used to index `lastTick.indices` directly in a shared loop with the
  (still row-sized) `strumProgress`/`lastGenStep` arrays — left as-is, those would have read/written out of bounds
  once `lastTick` grew to 4× their length. Full 1189-test macOS suite green after the widening — the most
  render-critical change in this whole arc. (4) the EUCLID hit/miss beacon's `canPlay` check (previously ONLY "is
  MISS configured") gained `euclidBeaconCanPlay`, additionally checking a RIFF/ARP pick whose predecessor doesn't
  match (mirrors Router.swift's own early-return) and a numbered-rank pick beyond the held note count or against an
  empty pool (mirrors `resolveEuclidPick`'s index math) — disclosed as still approximate (doesn't walk RIFF/ARP's
  own resolved note; reads the door's raw held notes, not the fully-resolved upstream-chain pool right before this
  EUCLID slot). **DEVICE-OWED, per item:** items 1/2/4 above and the row-clone/UI-sweep halves of the earlier fixes
  are UI-only with no macOS test-target reach (GridUI/BuildPage, as always) — confirm two independently-touched
  EUCLID lanes no longer cross-clear, a real pinch gesture still feels unchanged, and the beacon now stays dark for
  an out-of-range RIFF/ARP/ranked pick instead of falsely flashing; item 3 (the `lastTick` fix) is machine-verified
  by the full suite but its audible effect (two real EUCLID lines sharing a row no longer smearing a tick into the
  wrong render window) is a genuinely subtle, narrow-window timing case worth an ear-check if ever suspected again.**
- **▶ EUCLID PINCH — a self-inflicted reliability bug fixed, same day as the jumpiness fix below (2026-10-04,
  on `main`; iOS builds, no test-target reach (GridUI-only); DEVICE feel owed — genuinely untestable off-
  device). Paul, testing the jumpiness fix: "I find the pinch gesture on Euclid lanes quite unreliable (often
  snapping back to 2). Is this due to the overrides I requested? Maybe a simple pinch within the confines of
  the lane would work better to simplify." **YES — confirmed, traced not guessed:** the jumpiness fix's own
  `pinchTouchDistance` re-queried `location(ofTouch: 0/1, in:)` on EVERY `.changed` tick, falling back to `0`
  whenever `g.numberOfTouches` momentarily read below 2 — a known UIKit edge case, especially right as a
  finger lifts at the end of the gesture. Since `pinchStartDist` is typically 60–150pt, that single bad
  reading computed a huge SPURIOUS negative step delta in one tick, slamming `steps` straight down to its
  floor of 2 — exactly the reported symptom, and a direct, self-inflicted consequence of that same-day change.
  **SIMPLIFIED per Paul's own instinct, not patched with another guard:** the live distance is now derived
  from UIKit's OWN `scale` property (`pinchStartDist × scale` — exactly recovers the current distance by
  definition, since `scale` literally IS currentDistance/initialDistance) instead of re-deriving it from raw
  touch positions every frame. `scale` is maintained internally by UIKit's own touch tracking and was never
  subject to the `location(ofTouch:)`-style transient misread — `location(ofTouch:)` is now called exactly
  ONCE per gesture, at `.began`, to establish the starting distance (with a defensive 60pt fallback, which
  shouldn't trigger in practice since UIKit guarantees 2 touches by the time `.began` fires), never touched
  again. Keeps the SAME goal the jumpiness fix introduced (fixed points-per-step, independent of where the
  pinch started) — just computed the robust way instead of the fragile one. UI-only (GridUI.swift), no
  engine/model change, no test-target reach. **DEVICE-OWED:** whether the pinch now holds steady through a
  full gesture including the release at the end (the specific moment most likely to have triggered the old
  bug); the 18pt-per-step sensitivity re-derived this way still feeling right.**
- **▶ EUCLID DRAG HUD — the pinch gesture's jumpiness fixed, two separate causes (2026-10-04, on `main`; iOS
  builds, no test-target reach (GridUI-only); DEVICE feel owed — genuinely untestable off-device). Paul: "The
  overlay for the 9 of 12 euclid info overlay is very jumpy on the pinch gesture." Two compounding, independent
  causes, both specific to pinch (the pan gesture never had either problem, which is why only pinch was
  flagged): **(1) NUMBER jumpiness** — the steps count was computed from `UIPinchGestureRecognizer.scale`, a
  RATIO against the pinch's own STARTING finger separation; the SAME absolute finger movement produced a
  bigger step jump when the two fingers happened to start close together than when they started far apart —
  inconsistent, position-dependent sensitivity, not something a different constant could fix. Replaced with
  the ABSOLUTE distance CHANGE between the two touches, in points, read via `location(ofTouch:in:)` — the same
  fixed-points-per-step convention (`stepPt`, 18pt) the pan gesture's own rotate/hits already uses and which
  has never been reported as jumpy; the log-ratio math and its `pinchStepRatio` constant are gone entirely, not
  just retuned. **(2) POSITION jumpiness** — `g.location(in:)` for a 2-touch gesture is the CENTROID of both
  touches, recomputed on every `.changed` tick; real pinches are rarely symmetric (one finger often moves more
  or sooner than the other), so that midpoint wanders far more than the pan gesture's own single, stable touch
  point ever did. Fixed by reporting the HUD's position ONCE, at `.began`, and leaving it there for the rest of
  the gesture — the STEPS number inside the card still updates live via the unchanged `onStepsDelta` path; only
  the floating card itself stops chasing a noisy two-finger midpoint. UI-only (GridUI.swift), no engine/model
  change, no test-target reach. **DEVICE-OWED:** whether the pinch now feels consistently sensitive regardless
  of starting finger spacing, and whether the frozen-position HUD still reads as clearly tied to the gesture
  (vs. feeling detached) once it stops moving — the 18pt-per-step reuse is a reasonable first guess, not
  independently re-tuned for the two-finger case.**
- **▶ EUCLID LANES — REMOVED the second-finger-anywhere catcher; TWO (OR MORE) LANES can now genuinely be
  touched independently at once, each with a live scale-up "in use" cue (2026-10-04, on `main`; iOS builds, no
  test-target reach (GridUI+BuildPage+AudioUnitViewController); DEVICE feel owed — genuinely untestable off-
  device). Paul, after I asked whether the then-current "second finger anywhere = steps for lane 1, even over
  another lane's own pad" behaviour should be clarified or changed: "On touch, I want the first selected lane
  to increase in size a little without misaligning the space around it. If a second lane is pressed then the
  gestures should work around that too. So touches elsewhere on the screen shouldn't work after the first
  lane touch, unless it's on another Euclid lane. The idea is that we allow a user to control hits and offset
  for two or more lanes simultaneously." **THE REAL FIX TURNED OUT TO BE A REMOVAL, not new routing logic:**
  `EuclidSecondFingerCatcher` (yesterday's window-wide overlay, built for the ORIGINAL "second finger anywhere
  = steps" ask) sat TOPMOST in z-order and claimed EVERY second touch once armed, REGARDLESS of where it
  landed — including squarely over a DIFFERENT lane's own comet-bar pad, stealing that touch away from that
  pad's own, otherwise perfectly capable `UIPanGestureRecognizer` before it ever arrived. That was the ONE
  thing standing between "two lanes independently touched" and working: UIKit already supports multiple
  sibling views each tracking their own independent touch simultaneously, completely natively, with ZERO extra
  plumbing needed — once nothing is stealing the second touch first. **REMOVED ENTIRE** (not narrowed, not
  kept-as-dead-code): `EuclidStepsArm` struct, `onArmedStepsHandler`/`onEuclidStepsArm`/`onStepsArm` at every
  layer (`EuclidGesturePad` → `euclidCometBar` → `euclidLaneBox` → `ProcessorBox` → `buildSlotBox`), the
  `@State euclidStepsArmedHandler`, and the `EuclidSecondFingerCatcher` struct + its construction site in
  `DiagView.body` (AudioUnitViewController.swift) — along with the now-unneeded `import UIKit` there (restored
  once the build showed `UIHostingController`, used elsewhere in that file, genuinely needs it after all).
  PINCH-to-steps on each lane's OWN pad is completely untouched — this only ever affected the brand-new second-
  finger mechanism, not the original gesture set. **NEW "IN USE" SCALE-UP, replacing it:** a new TRANSIENT
  `@State euclidTouchedLanes: Set<Int>`, distinct from the existing STICKY `euclidSelectedLane` (which persists
  after the touch lifts and drives the settings panel below) — populated/cleared directly from each lane's own
  `onDragState` (already fired by `EuclidGesturePad` on every `.began`/`.changed`/`.ended`, no new plumbing
  needed): a plain single-finger touch marks only its own lane; the existing 2-finger-ALL-ROWS gesture marks
  all 4, since it genuinely reshapes every lane's pattern together. Each lane's box gets `.scaleEffect(touched
  ? 1.07 : 1.0)` + `.zIndex(touched ? 1 : 0)` + a short `.easeOut` transition — `.scaleEffect` is a pure RENDER
  transform, never a LAYOUT one, so SwiftUI's layout system never sees a size change and neighbouring lanes in
  the 2×2 grid never shift — satisfying "increase in size a little without misaligning the space around it"
  exactly. `.zIndex` keeps a touched lane drawing over its neighbours so the (modest, ~7%) overlap never reads
  as clipped. Since EACH lane independently computes its own `touched` from the SAME shared
  `euclidTouchedLanes` set, two lanes touched at once each scale up simultaneously, with no coordination code
  needed beyond the set itself. UI-only, no engine/model change, no test-target reach. **DEVICE-OWED, and this
  is the one area most resistant to verification by reading code — real multi-touch arbitration across sibling
  UIKit views only shows itself on a touchscreen:** whether two lanes really do respond independently and
  simultaneously to two separate fingers now that the one thing blocking it is gone; the 7% scale amount/0.12s
  transition feel; confirm the scaled-up box's slight overlap into its neighbour's margin reads as "a lane
  lighting up," not as a glitch.**
- **▶ EUCLID HIT/MISS BEACON — a small live flash beside each "LANE N HIT"/"LANE N MISS" label (2026-10-03, on
  `main`; iOS builds, no test-target reach (GridUI-only); DEVICE eye owed — genuinely untestable off-device).
  Paul: "next to the labels mentioning hits and misses, without changing the height used, [add] a small beacon
  flash on every playing hit/miss[]. Ensure it's accurate and reliable." New `euclidBeaconDot(_:isMiss:)` —
  a 6pt `Circle`, sized well under the label's own ~9pt-font line height so wrapping it in an `HStack` beside
  the label doesn't change the row's height at all. **ACCURATE BY CONSTRUCTION, not just by eye** — reuses the
  EXACT same pure functions the real render path uses for its own per-tick hit decision (`euclidReadIndex`/
  `euclidCycleLen`/`euclidPatternInto`, Router.swift's `runEuclidLine`) via the SAME continuous tick-count the
  comet bar already drives its own sweep from (`euclidCometRaw`) — the identical "share the engine's own
  formula, never re-derive it" discipline this file has standardized on since the RATCHET-PATTERN/DEST class
  of bug. Floors that continuous value to the current INTEGER tick, resolves it through `euclidReadIndex`
  exactly as the engine does to decide which buffer entry sounds at that tick, and flashes the HIT dot when
  that tick is a hit, the MISS dot when it's a rest — the two dots are mutually exclusive by construction
  (`isHitTick` vs `!isHitTick`), never both lit. **RELIABLE, honestly scoped (flagged, not silently assumed):**
  this mirrors the PATTERN-level hit/miss decision — the same one the comet bar's own box content already
  reflects — it does NOT re-run the full emission guard chain (RIFF/ARP predecessor matching, pool-size clamps,
  the chain-context guards `runEuclidLine`'s own RIFF/ARP branch applies) that could silently make a nominal
  "hit" produce no actual sound in some edge cases; replicating that fully here would need live chain/pool
  state this widget was never given. The ONE condition it DOES check beyond the bare pattern, because it's
  both simple and load-bearing: a MISS tick never actually sounds unless `missNoteSel` is set — an
  unconfigured MISS dot stays permanently dim/dark rather than flashing for a strike that never happens,
  matching the literal "on every PLAYING hit/miss" wording. **A real compile error hit and fixed, not guessed
  around:** the first draft inlined the whole computation inside the `TimelineView`'s own trailing closure —
  the iOS build failed outright ("generic parameter 'Content' could not be inferred," Swift's result-builder
  type inference choking on the longer inline expression chain) — fixed by extracting the scalar math into a
  plain `euclidBeaconFlash(...)` function returning a bare `Double`, leaving the TimelineView closure as a
  single simple call into a tiny `beaconCircle(flash:)` view-builder. UI-only, no engine/model change, no
  test-target reach. **DEVICE-OWED:** the dot's legibility/size beside the label at real panel width; the
  0.4-tick decay window's "short, sharp pulse" feel (a first-pass, tunable constant); confirm the row's height
  genuinely hasn't shifted now that it carries the dot.**
- **▶ EUCLID SECOND-FINGER STEPS — made SIDE-AWARE (2026-10-03, on `main`; iOS builds, no test-target reach
  (GridUI+BuildPage+AudioUnitViewController); DEVICE feel owed — genuinely untestable off-device). Direct
  follow-up to the same-day feature: Paul, after I confirmed the first build only read the second touch's own
  ABSOLUTE left/right drag (oblivious to where it landed relative to finger 1): "I want it to know if it's the
  left side or the right side of the pinch." A plain absolute mapping (right always adds, left always removes)
  would feel backwards half the time compared to a REAL pinch, where which way a given finger needs to move
  depends on which side of the OTHER finger it's on — moving AWAY from the other finger spreads/adds, moving
  TOWARD it pinches-in/removes, regardless of which finger is on which side. **NEW `EuclidStepsArm` struct**
  (GridUI.swift, beside `EuclidDragHUDInfo`) replaces the bare `((Int) -> Void)?` the arm signal used to carry —
  now bundles the armed lane's `onStepsDelta` WITH finger 1's own live window-space position (`anchor`), re-
  reported on every `.changed` tick of `EuclidGesturePad`'s single-finger drag (same convention as
  `EuclidDragHUDInfo.point`'s own continuous-update pattern) so it stays current while finger 1 is still being
  dragged. Threaded through the exact same path as before (`onArmedStepsHandler` → `onStepsArm` →
  `ProcessorBox.onEuclidStepsArm` → `euclidStepsArmedHandler`), just carrying the richer type. **THE SIDE
  DECISION (`EuclidSecondFingerCatcher.Coordinator`, AudioUnitViewController.swift):** at the second touch's
  OWN `.began`, compares its location against the LATEST reported `anchor.x` — `isRightSide`, decided ONCE and
  LATCHED for the rest of that gesture (mirroring `EuclidGesturePad`'s own `twoFinger` latch, for the identical
  reason: a touch drifting across the anchor mid-drag shouldn't flip the sense partway through). A right-side
  touch keeps the original mapping (right = add); a LEFT-side touch's raw translation is NEGATED before
  mapping to steps, so moving further LEFT (away from finger 1) now also adds — "spread apart = add, pinch
  together = remove" holds regardless of which side the second finger lands on, faithfully mirroring the real
  pinch gesture this feature stands in for. UI-only, no engine/model change, no test-target reach.
  **DEVICE-OWED:** whether the side-mirroring actually reads as a natural pinch-equivalent in the hand — the
  `.began`-time anchor comparison depends on real multi-touch timing (finger 1's reported anchor could be a
  few milliseconds stale relative to the exact instant finger 2 lands) that only shows itself on a touchscreen.**
- **▶ EUCLID — rotate-drag direction fixed for real (round 3) + a SECOND-FINGER steps gesture, anywhere on
  screen (2026-10-03, on `main`; iOS builds, no test-target reach (GridUI+BuildPage+AudioUnitViewController);
  DEVICE feel owed on both — genuinely untestable off-device). Paul: "the right/left drag gesture for offset
  isn't reflected correctly on the lane (as in it sets the offset the wrong way)," plus: "when a single finger
  drag is used for adding or removing hits, while held, if a second finger drags left or right anywhere on the
  screen then I want this to work as the same pinch gesture for adding or removing steps." **DRAG-DIRECTION,
  THE REAL STORY (two passes, same session):** pass 1 re-derived the 2026-09-28 fix (FWD/PING-PONG →
  `rotate - d`, BKW → `rotate + d`) via a throwaway script and it checked out — so pass 1 just blindly flipped
  both branches, trusting the device report over paper math it couldn't fault. That flip was WRONG, but not
  because the device report was wrong — because a CONCURRENT fix on another worktree (`ceedff7`, "fix the
  comet grid jumping on direction change," landed the same day) had changed the premise pass 1's re-derivation
  depended on: box content used to be `buf[euclidReadIndex(i,n,dir)]` (BKW mirrored — the EXACT reason the
  2026-09-28 fix needed a separate BKW sign at all); `ceedff7` made every box always show `buf[i]` directly,
  for every direction, so a box's screen position no longer depends on DIRECTION at all. Re-verified with a
  FRESH throwaway script against this current rule: increasing `rotate` now shifts the screen-visible pattern
  LEFT by one slot, UNIFORMLY, for FWD/BKW/PING-PONG alike — so the whole BKW-vs-other conditional is not just
  wrong-signed, it's categorically unnecessary now. **THE ACTUAL FIX (pass 2, supersedes pass 1 same-session):**
  one formula, no direction split — `rotate - d` for both the single-row and all-rows gestures. This also
  retroactively explains why pass 1's blind flip probably didn't help: Paul was very likely already testing
  against a build carrying `ceedff7`, where the split itself (not just its sign) was the problem.
  **SECOND-FINGER STEPS, new feature:** a new `ProcessorBox.onEuclidStepsArm` callback (default no-op, same
  convention as the existing `onEuclidDragInfo`) fires with a given lane's own `onStepsDelta` the instant that
  lane's `EuclidGesturePad` recognizes a genuine SINGLE-finger drag (`.began`, `!twoFinger`), and with `nil`
  the instant it ends — a 2-finger drag starting directly on the pad is the EXISTING, distinct ALL-ROWS
  gesture and never arms this. Threaded up through `euclidLaneBox`/`buildSlotBox` to a new
  `AudioUnitViewController` `@State euclidStepsArmedHandler`, read by a new top-level
  `EuclidSecondFingerCatcher` (a `UIViewRepresentable` rendered once at the SAME top tier as the drag HUD, in
  `DiagView.body`'s outer ZStack — genuinely window-wide, not scoped to any one lane's small pad, since the
  whole point is catching a touch that lands somewhere ELSE). **PASS-THROUGH BY CONSTRUCTION, not a guess:**
  its `hitTest` returns nil (never intercepts anything, anywhere) whenever the armed handler is nil, so it's a
  complete no-op the rest of the time. Once armed, a NEW touch landing anywhere is claimed and its horizontal
  drag converted to Δsteps via the SAME 18pt-per-step convention the pad's own 1-finger rotate/hits drag
  already uses (a plain linear mapping, not the pinch's log-ratio one, since this is a drag not a scale
  gesture) — fed straight into the armed lane's `onStepsDelta`, exactly as if it were a pinch. **WHY THE FIRST
  FINGER CAN NEVER BE ACCIDENTALLY STOLEN, reasoned through before shipping:** `hitTest` fires exactly ONCE per
  touch, at that touch's own touch-down — and arming only happens once the lane's OWN pan recognizer reaches
  `.began`, which is strictly AFTER that same touch's touch-down has already been dispatched (a recognizer
  only reaches `.began` once a touch has moved past UIKit's own recognition threshold). So finger 1 is always
  hit-tested while still unarmed and always passes through correctly to its own pad; only a genuinely separate,
  LATER touch can ever be claimed by the catcher. UI-only (GridUI.swift + BuildPage.swift +
  AudioUnitViewController.swift, which gained a new explicit `import UIKit`), no engine/model change, no
  test-target reach. **DEVICE-OWED, both fronts:** whether the rotate-drag now actually tracks the finger
  correctly (and if it's STILL wrong, that's the signal to stop guessing the sign and look elsewhere); the
  whole second-finger mechanism — real multi-touch/hit-testing arbitration across two independent gesture
  recognizers in different views only shows itself on a touchscreen; a known, accepted consequence worth
  naming plainly: while armed, the catcher claims ANY new touch anywhere on screen, including one the user
  didn't intend for this feature (e.g. reaching with their other hand to tap an unrelated button while still
  holding the first finger down) — this is the literal "anywhere on the screen" Paul asked for, not an
  oversight, but worth knowing if it ever surprises in practice.**
- **▶ EUCLID — scrolling disabled on its own panel, DIRECTION reordered, HIT/MISS boxes rebuilt as a true 2×2
  (2026-10-03, on `fix/euclid-no-scroll-direction-order-2x2-grid`; macOS 1183 green, iOS builds; DEVICE eye/feel
  owed). Paul: "On the Euclid processor only, prevent scrolling. Change the order of direction to forward, ping
  pong, backwards. Put more work into ensuring that note selector, octave, velocity and gate are perfectly lined
  up 2x2." **NO SCROLL:** `buildProcessorPanel` (BuildPage.swift) now branches on `proc.type == .euclid` — every
  OTHER processor keeps its `ScrollView(.vertical)` wrapper unchanged; EUCLID gets a bare `VStack` instead. Two
  real reasons, not just "because asked": the comet bar's own `EuclidGesturePad` hosts a genuine UIKit
  `UIPanGestureRecognizer`/`UIPinchGestureRecognizer` pair for 1/2-finger drag + pinch, and a SwiftUI ScrollView
  wrapping it adds the page's OWN vertical-drag recognizer competing for the exact same touches — one less
  source of gesture-fighting on a control surface already proven fragile around exactly this kind of
  interaction (the whole `cancelsTouchesInView=false`/raw-touch-channel saga earlier this session). Separately,
  EUCLID's panel is now a fixed, bounded 2×2 layout with no open-ended list, so there's nothing left to scroll
  to anyway. **A real Swift constraint hit and fixed along the way:** the first draft wrote the shared body as a
  local `@ViewBuilder func panelBody()` nested INSIDE `buildProcessorPanel`, itself a `@ViewBuilder` function —
  the iOS build failed outright ("closure containing a declaration cannot be used with result builder
  'ViewBuilder'"; Swift's result-builder transform doesn't permit a local declaration inside a transformed
  body). Fixed by extracting it to a proper sibling method, `buildProcessorPanelBody(slot:proc:cid:hue:)`, called
  identically from both the EUCLID and non-EUCLID branches — caught by the real compiler, not a review pass; the
  background-build notification claimed success on the FAILED run (standing lesson re-confirmed: always grep the
  actual log, never trust the summary alone). **DIRECTION reordered:** `euclidSettingsPanel` (GridUI.swift) now
  presents **forward · ping-pong · backward** (was forward · backward · ping-pong) via new local `dirOrder`/
  `dirLabels` arrays — display order only; `EuclidDir`'s own raw values/persistence are untouched, and `dirSel`
  is still computed by mapping the resolved direction through the new label order (not by string-matching the
  persisted raw value), so the highlight can't desync from the reorder the way a naive relabel would. **2×2
  GRID:** `euclidHitMissBox` rebuilt from two independently-sized VStack columns into two true `HStack(alignment:
  .top)` rows sharing one fixed-width right column (`rightColW: CGFloat = 165`, sized off `NumPair`'s own natural
  width) and one flexible `.frame(maxWidth: .infinity)` left column — row 1 is NOTE SELECTOR (left) + OCTAVE
  (right), row 2 is VELOCITY (left) + GATE (right), so OCTAVE sits directly above GATE and NOTE SELECTOR directly
  above VELOCITY, both columns now the same width top-to-bottom in both the HIT and MISS boxes. **DEVICE-OWED:**
  confirm EUCLID's panel genuinely no longer scrolls (and that nothing inside it actually needed to); the 2×2
  alignment reading as a clean grid at real panel width, not just close; the new forward/ping-pong/backward
  DIRECTION order feeling natural tapped in sequence.**
- **▶ EUCLID — investigated stuck/held notes (two lanes, same note) + zero-velocity lanes; fixed the real finding
  (2026-10-03, on `fix/euclid-direction-label-and-box-jump`; macOS 1183 green incl. 2 new/rewritten, iOS builds).
  Paul asked to investigate both. **STUCK NOTES — investigated, NONE FOUND, traced with an RTCDEBUG trace not
  guessed (the repeated lesson in this file: hand-derived tick arithmetic is routinely wrong here, verify
  empirically).** Two fully-dense (K=N=8) lines on the SAME note, same machine-wide rate — the worst-case
  always-overlapping shape — run clean under `assertNothingLeftSounding` every time, including a `forceColumn:0`
  stress run to 97 events. A REAL, separate timing quirk was found along the way: `iterateTicks`' per-ROW
  `lastTick` dedup is a SINGLE scalar shared by all 4 lines on one row (already flagged in `runEuclidLine`'s own
  standing comment as "a known limitation for 2+ real lines sharing a row across a window boundary") — when one
  line's tick advances that shared scalar past a tick the OTHER line hasn't reached yet, the other line's
  catch-up fire computes its `sampleOf` conversion in a LATER window's frame, landing its onset roughly one
  render-window late. Confirmed this is a TIMING SMEAR, not a stuck voice: `strikeChord` always computes its
  on/off pair together from whatever `tau` it's given, so even a late-computed strike still gets a valid, finite
  gate — no voice is ever left open without a scheduled close. **NOT FIXED, flagged rather than attempted
  blind:** correcting the smear needs `lastTick` keyed per-LINE instead of per-ROW, which touches shared
  `iterateTicks` infrastructure ARP/RIFF/RATCHET-ALL also depend on — a materially bigger change than this
  investigation asked for. `testEuclidTwoLinesSameNoteNeverStickRegardlessOfOverlap` locks in the no-stuck-note
  finding as a permanent regression guard. **ZERO VELOCITY — investigated, CONFIRMED A REAL GAP, FIXED.**
  `velocity: 0` was NOT silent: `strikeChord`'s own `clampVel` floors every note to MIDI 1...127 (a floor meant
  to protect an INHERITED velocity from ever rounding to an inaudible 0, not a deliberate "silence this" request)
  — so a line explicitly scaled to 0% was still striking audibly at velocity 1. Confirmed empirically before
  fixing (`vel0 = 1`), then fixed with an explicit `guard velocity > 0 else { return }` ahead of BOTH the HIT and
  MISS strike paths in `runEuclidLine` (Router.swift) — checked early, before any RIFF/ARP/pool resolution work,
  not just at the final strike call. `testEuclidZeroVelocityIsActuallySilentNotVelocityOne` (+1, replacing a
  force-unwrap in the existing velocity test that would have crashed once 0 genuinely stopped emitting) locks
  this in for both HIT and MISS. **DEVICE-OWED:** none specifically new — both findings were fully verified by
  the macOS test target; the timing smear, if ever pursued, would need a real device/ear check once fixed.**
- **▶ EUCLID — DIRECTION label removed; the comet box grid is now genuinely direction-independent (2026-10-02, on
  `fix/euclid-hud-escape-card-clip`; iOS builds, no test-target reach (GridUI.swift-only); DEVICE eye owed). Two
  asks, same message. **LABEL:** `field("DIRECTION") { seg(...) }` dropped the `field()` wrapper — the `>`/`<`/
  `><` chips render directly, no "DIRECTION" text above them, same decluttering as the same-day "LANE N" header
  removal. **BOX JUMP, a real bug not a new design ask — Paul: "when I change the direction, I don't want the
  lit cell(s) to jump to the opposite side. These should remain static."** Root-caused by reading, not guessed:
  the SAME-DAY comet-direction rewrite (entry below) already documented the INTENT twice over — `euclidCometPos`'s
  own doc comment ("Box CONTENT... is untouched by this") and a comment inside `euclidCometBar` itself ("The
  per-box HIT/REST content... is untouched — only the comet's own visual sweep motion changed") — but the actual
  box loop still computed `hit` via `buf[euclidReadIndex(i, n, dir)]`, which DOES remap by direction (BKW mirrors
  screen i ← buffer n-1-i) — the code never caught up to what its own comments already claimed. Fixed to
  `buf[i]` directly — box `i` always shows the raw pattern buffer at that screen position, full stop, regardless
  of DIRECTION. **Verified, not just asserted, that this stays musically accurate:** the flare/age timing a few
  lines below was ALREADY keyed on screen position `i` and the separately direction-aware `cometRaw`, never on
  the old `ri` — worked through the tick arithmetic by hand for BKW (the comet's own position formula lands it
  at box `i`'s edge at the exact real tick the engine actually strikes `buf[i]` under BKW) to confirm the comet
  still visits each visible box in the true real-time strike order post-fix, not just that the boxes stopped
  moving. Router.swift (the real render path) is completely untouched — this was a UI-only display bug, the
  engine's own `euclidReadIndex` usage for actual playback was never wrong. **DEVICE-OWED:** confirm the grid now
  stays visually still across all 3 DIRECTION settings, and that the comet's sweep (left→right FWD, right→left
  BKW, bounce PING-PONG) still reads as correctly timed against the now-static boxes.**
- **▶ EUCLID PANEL — DIRECTION shrunk further, OCTAVE/GATE relaid out, the +/- STEPS glyphs removed (2026-10-02,
  on `fix/euclid-hud-escape-card-clip` → `main`; iOS builds, no test-target reach (GridUI.swift-only); DEVICE eye
  owed). Paul: "Reduce the size of the direction controls on the Euclid processor. Then ensure that the octave
  controls are lined up with the note selector to its left and gate below it. Remove the + and - buttons from
  the Euclid lanes." **REBASE NOTE:** landed the SAME turn another worktree independently added an almost
  identical `compact` flag to `seg()` for the SAME reason (its own commit: "seg() gains an opt-in compact flag
  (same convention as numPair's own) so only EUCLID's DIRECTION row is affected") — slightly different numbers
  (their 36/21pt vs. this session's own 34/24pt, their corner radius unchanged vs. this session's 5pt), kept
  THEIRS wholesale on rebase (already-landed, functionally equivalent, no reason to churn two near-identical
  guesses into a third). **DIRECTION:** no further size change needed beyond that already-landed `compact: true`
  — confirmed the call site still passes it. **OCTAVE/GATE RELAYOUT:** `euclidHitMissBox` restructured from
  "chip-row+OCT on one line, VEL+GATE on the next" into two COLUMNS — LEFT = note chips over VELOCITY, RIGHT =
  OCTAVE over GATE — so OCTAVE sits beside (lined up with) the note-chip row, and GATE sits directly below OCTAVE
  specifically, not sharing a row with VELOCITY anymore. **JUDGMENT CALL, flagged:** Paul named where OCTAVE and
  GATE go, not VELOCITY — placed it under the note chips (the other column) as the natural remaining slot, not
  explicitly requested. **+/- STEPS REMOVED:** the comet bar's inline tap glyphs (`onStepsDelta(±1)`) are gone
  entire — PINCH (already wired to the same `onStepsDelta`) is now the only way to resize STEPS from this bar;
  the 14pt gesture-pad inset they used to justify is deliberately left as-is, not widened to reclaim the margin
  (asked to remove the buttons, not resize the pad). **DEVICE-OWED:** the two-column box's visual balance
  (GATE's slider now constrained to the same narrow width as the OCTAVE stepper above it, by construction of
  "below it" — may read as cramped, worth a look); confirm pinch remains discoverable as the only steps control
  now that the tap glyphs are gone.**
- **▶ EUCLID COMET BAR — the sweep now genuinely reverses for BKW and bounces for PING-PONG (2026-10-02, on
  `main`; macOS 1181 green incl. 1 new, iOS builds; DEVICE eye owed). Paul: "The Euclid processor has an
  animation that runs left to right on each lane. Please change this so that it reverses directions when
  reverse is chosen, and it goes back and forth on pingpong." SUPERSEDES an earlier, deliberate same-session
  design call (the box-redesign doc comment: "the comet always travels left→right... steadier and more
  legible than having it visually reverse direction, which read as a glitch") — that call predates this ask;
  Paul's now asking for exactly the motion it had chosen not to build. **ROOT STRUCTURE, traced first:** the
  comet's screen x-position came from `euclidPhase` — a plain `raw mod n` (raw = elapsed ticks), ALWAYS
  increasing over time regardless of `dir`, so `xFor(phase)` always swept left→right; separately, `euclidPhase`
  only ever mods by `n`, never the direction's real cycle length (`euclidCycleLen` — 2n under PING-PONG), so
  PING-PONG's comet only ever showed the ascending half, repeating — never the bounce back. **FIX (Derivations.
  swift, two new pure functions, UI-only like `euclidPhase` itself — confirmed via grep, neither reaches the
  render path):** `euclidCometRaw` mods the raw tick count by `euclidCycleLen(dir, n:)` instead of a fixed `n`,
  so a full PING-PONG lap (2n ticks) is now actually representable. `euclidCometPos(raw, n, dir)` is the real-
  valued analogue of `euclidReadIndex` (same branching shape, continuous instead of integer-only): FWD `pos =
  raw` (unchanged) · BKW `pos = n − raw` (a genuine mirror — as raw climbs, pos falls, so the comet visibly
  travels right→left) · PING-PONG `raw < n ? raw : 2n − raw` (ascending left→right for the first half-lap,
  then mirrors back down right→left for the second — the literal "back and forth" asked for). The per-box HIT/
  REST content (`euclidReadIndex` against the static integer screen index) is UNTOUCHED — only the comet's own
  visual motion changed, so which boxes light up when is exactly as before. **AGE/FLARE rederived to match:**
  the per-box "how long ago did the comet pass this box" calc (`age`, driving the flare/afterglow) assumed a
  monotonically-increasing position tied 1:1 to screen index — no longer true once the comet can move backward
  or double back. Rederived per direction by inverting each `euclidCometPos` branch: FWD unchanged (`age = raw
  − i mod n`); BKW `age = raw + i mod n` (the comet visits box i when raw = n−i); PING-PONG visits box i TWICE
  per lap (ascending at raw=i, descending at raw=2n−i) — `age` takes whichever visit was more recent (`min` of
  the two, each wrapped mod 2n). **TRAIL DIRECTION:** the comet's own blurred trail (drawn "behind" the glowing
  head) used a hardcoded left-ward offset (`hx − 22`, clamped to the left inset) — now computed from a
  `movingRight` flag (true for FWD, false for BKW, and — for PING-PONG — whichever half of the lap `cometRaw`
  currently sits in), so the trail correctly extends to the RIGHT of the head when the comet is travelling
  leftward, instead of visually trailing in front of it. **TESTS:** +1 DerivationsTest
  (`testEuclidCometPosReversesAndBounces` — `euclidCometRaw` wraps by the right cycle length per direction;
  `euclidCometPos` is a genuine mirror for BKW, not just a relabelling; PING-PONG's ascending/turn/descending
  points hand-verified against the exact formula). UI+pure-function (GridUI.swift + Derivations.swift +
  Tests/DerivationsTests.swift), full macOS test-target reach for the new Derivations functions (GridUI's own
  wiring has none, as always). **DEVICE-OWED:** the whole feature — BKW's comet visibly running right-to-left
  against the still-left-to-right-laid-out boxes (a deliberate, disclosed asymmetry — the BOXES don't reorder,
  only the comet's motion does); PING-PONG's bounce reading as a smooth back-and-forth, not a jarring snap at
  the turn; the trail now correctly pointing backward (not forward) during a leftward sweep.**
- **▶ EUCLID PANEL — the redundant LANE N header removed, DIRECTION chips halved in height (2026-10-02, on
  `main`; iOS builds, no test-target reach (GridUI-only); DEVICE eye owed). Paul: "Remove the LANE 2 header
  from euclid. Halve the height of the direction buttons." The top-of-panel `Text("LANE \(idx+1)")` in
  `euclidSettingsPanel` is deleted outright — each HIT/MISS box already labels itself "LANE N HIT"/"LANE N
  MISS" directly beneath it, so the panel-level header was pure duplication. **DIRECTION:** `seg` (the shared
  content-sized-chip control, ~30 call sites across every processor editor in this file) gained an opt-in
  `compact: Bool = false` param — same convention as `numPair`'s own `compact` — halving chip height 42→21pt,
  trimming the font 15→11pt and padding/min-width to match, so the one EUCLID DIRECTION call site that now
  passes `compact: true` is the ONLY caller affected; every other `seg` usage (OCT DIR, SYNC, ROUTE, VOICING,
  etc.) is byte-identical. UI-only (GridUI.swift), no engine/model change. **DEVICE-OWED:** the DIRECTION
  row's legibility and touch target at the new half-height, and that the panel reads cleanly with no gap
  where the removed header used to sit.**
- **▶ EUCLID DRAG HUD — relocated a SECOND time, now genuinely top-level (2026-10-02, on
  `feature/euclid-hud-touch-and-polish`; iOS builds, no test-target reach — UI-only, BuildPage.swift/
  AudioUnitViewController.swift; DEVICE eye owed). Paul, after the first relocation shipped: "the euclid overlay
  still does not move over the grid. It only seems to be able to live within the confines of the processor edit."
  **ROOT CAUSE, traced not assumed:** the first relocation (entry directly below) made the HUD a sibling of
  `buildProcessorPanel`'s OWN `ScrollView` — true, but insufficient, because `roomsProcessorCardAt` (the card's
  OUTER wrapper, one level further up) applies `.frame(width:height:).background(buildPanel).clipShape(Rounded-
  Rectangle(cornerRadius: 8))` to its ENTIRE contents — tabs, `buildProcessorPanel`, and any overlay hanging off
  it, all clipped to the card's own rounded rect as one unit. No `.overlay` attached ANYWHERE inside
  `buildProcessorPanel` could ever escape that — the first fix solved a real but narrower problem (the
  ScrollView's own clip) while leaving the actual reported one (the card's clip) untouched. **FIX:** the HUD's
  RENDERING moved again, this time to `DiagView.body`'s own top-level `ZStack` (AudioUnitViewController.swift) —
  a sibling of `mainContent(geo)`, the SAME tier the manual/settings/presets/cell-library overlays already live
  at, reusing the body's own outer `GeometryReader`'s `geo` directly (no nested GeometryReader needed this time).
  Identical positioning math (the `.global`-origin conversion, the 130pt "~1 inch" offset, the X-clamp) ported
  verbatim — only WHERE it renders changed, not how it computes position. `buildProcessorPanel` no longer renders
  the HUD at all, only still SETS `euclidDragHUDInfo` (via `onEuclidDragInfo` on `ProcessorBox`, unchanged).
  `buildEuclidDragHUD` (the actual card view) dropped its `private` modifier — BuildPage.swift and
  AudioUnitViewController.swift are different files, and Swift's `private` on an extension member doesn't cross
  files even for the same type, unlike the plain (internal) functions this codebase already calls cross-file
  throughout (e.g. `buildMachineChain`). **DEVICE-OWED:** confirm the HUD can now genuinely travel over the grid
  area (not just no-longer-clipped-inside-the-card-but-still-somehow-bounded) — this is the one thing that could
  only be confirmed by the device report that triggered this fix in the first place, and is worth a direct
  on-device check before considering this closed.**
- **▶ EUCLID DRAG HUD — appears on raw touch-down + tracks the finger end-to-end, tightened to ~1 inch, arrows
  re-added; comet now respects PER-LANE PLAY/STOP; lanes default to 1-of-8 (2026-10-02, on `fix/euclid-die-removal`;
  macOS 1176 green (no new tests — all UI/engine-glue, no test-target reach), iOS builds; DEVICE eye/feel owed —
  real touch-recognizer timing and on-device inch-accuracy can't be confirmed off-device). Paul, five asks in one
  message: the overlay should be ~an inch above the touch and track finger movement; a stopped lane's comet
  shouldn't move; lanes should default to 1-of-8; the overlay should show "1 of 8" on first touch; bring back the
  4 directional arrows. **ROOT GAP, traced not assumed:** `onDragState` (the HUD's only signal) was driven
  EXCLUSIVELY by `UIPanGestureRecognizer`/`UIPinchGestureRecognizer`'s own `.began`/`.changed` — and a UIKit pan/
  pinch recognizer only transitions out of `.possible` once a touch has moved past the SYSTEM's own recognition
  slop (confirmed by re-reading this exact file's own prior doc comment: "a touch that never moves simply fails
  them, un-consumed") — so there was an unavoidable dead zone right after contact, and a touch that never moved
  enough (a near-tap) never showed the HUD at all. **FIX — `EuclidGesturePad` gained a genuine raw-touch channel,
  parallel to the recognizers, not a replacement for them:** a new nested `TouchView: UIView` overrides
  `touchesBegan`/`touchesMoved`/`touchesEnded`/`touchesCancelled` directly — these fire on the OS's own touch
  delivery, zero movement required — reporting straight to a new `Coordinator.handleRawTouch(point:allRows:)`,
  which calls the exact same `owner.onDragState` the recognizers already call. Both `pan`/`pinch` gained
  `cancelsTouchesInView = false` — **a deliberate fix for a race, reasoned through before shipping:** the default
  (`true`) would have UIKit call `touchesCancelled` on `TouchView` the MOMENT a recognizer takes over, right as
  that SAME recognizer's own `.began` starts reporting — an ordering hazard that could visibly flicker-hide the
  HUD exactly when the drag "officially" begins. With cancellation off, `TouchView` keeps tracking in PARALLEL for
  the touch's entire lifetime, two harmless near-duplicate `onDragState` calls per tick instead of a race. `Touch-
  View` NEVER calls `onRotateDelta`/`onHitsDelta`/`onStepsDelta` — only the recognizers still own those — so there
  was no risk of double-applying a value change, only the HUD-visibility signal gained a second, earlier source.
  **"1 of 8 on first touch"** falls out of this plus the new default (below) with no separate code — the HUD always
  reads the lane's OWN live `pulses`/`steps` at the moment of the call, never a hardcoded string. **~1 INCH + 
  TRACKS THE FINGER:** the Y offset was already recomputed from the live touch point on every call (confirmed by
  reading `roomsProcessorCardAt`'s overlay before touching anything — this part worked already, just gated behind
  the same dead-zone gap above); tightened the constant itself from 150pt ("an inch or two," a deliberately loose
  original guess) to 130pt, the more common iPad points-per-inch approximation — still an honest approximation,
  not a measured value. **COMET PER-LANE STOP:** `euclidCometBar` had NO idea whether its own lane was enabled —
  only `clockPlaying` (the HOST transport) gated its animation, so a lane individually stopped via its own inline
  PLAY/STOP button kept sweeping as long as the transport and at least the CARD were still running. New `lanePlaying:
  Bool` param, `let running = clockPlaying && lanePlaying`, threaded into both existing `if clockPlaying` gates (the
  per-box flare/burst and the comet draw itself — renamed `running`) and the `TimelineView`'s own `paused:` — a
  stopped lane now freezes/hides its comet exactly like a stopped transport already did, independent of whether
  OTHER lanes or the transport itself are still running; the static K-of-N step-box grid is untouched either way
  (still fully visible/editable while stopped, matching the existing transport-stop precedent). **DEFAULT 1-OF-8:**
  three separate sources of "5" fixed in lockstep — `EuclidLine.pulses`'s own struct default, `MachineParams.
  euclidPulses`'s Optional default, and `euclidLinesForEditing()`'s inline `euclidPulses ?? 5` fallback (used when
  an old doc decodes the field as nil) — all now 1; the EUCLID storefront card's own explicit preset (`4 of 4`, a
  DELIBERATE 2026-09-30 default superseded here) changed to `1 of 8` directly. `steps` was already 8 everywhere,
  untouched. Old saved docs are unaffected — Optional fields already present in a doc's JSON decode to their SAVED
  value regardless of the struct's own default; this only changes what a genuinely FRESH, never-before-saved lane
  opens on. **ARROWS RE-ADDED:** `buildEuclidDragHUD` gained 4 chevron glyphs (`.overlay(alignment:)` on all 4
  sides) — these were deliberately DROPPED earlier the same day ("they'd point in directions that no longer mean
  anything now that the card floats freely") when the HUD first started tracking the touch; Paul asked for them
  back anyway, now read as a plain "this is draggable" affordance rather than a literal directional reference, not
  a reversal of the earlier reasoning so much as a different priority winning. No new tests (GridUI.swift/
  BuildPage.swift, as always, have no macOS test-target reach — this is UIKit touch-delivery + Canvas-drawing
  behavior, verifiable only by the existing full suite staying green, which it does). **DEVICE-OWED, and this is
  the one area most resistant to verification by reading code — real multi-touch/gesture-recognizer arbitration
  only shows itself on a touchscreen:** whether `cancelsTouchesInView = false` genuinely eliminates the flicker
  race rather than introducing a new one; whether the HUD now visibly appears the INSTANT a finger lands (not just
  "sooner"); the 130pt/"1 inch" feel at real device size; confirm a stopped lane's comet freezes cleanly with no
  stale flash, and that OTHER still-playing lanes are visibly unaffected; the new arrows' legibility/spacing
  against the card's existing padding. **POST-REBASE NOTE:** landed on top of the other worktree's same-day
  HIT/MISS SPLIT (directly below) — that commit rewrote `euclidSettingsPanel` into two `euclidHitMissBox` calls
  and dropped the single shared VELOCITY/OCTAVE/DIRECTION list this session had earlier built; NONE of that
  overlaps this entry's own changes (`EuclidGesturePad`/`TouchView`/`euclidCometBar`/`euclidLaneBox`'s comet-bar
  call site, `buildEuclidDragHUD`, the 3 default-value constants) — verified by reading the post-rebase file
  directly, not just trusting a clean auto-merge, since both branches touched the same region of GridUI.swift.**
- **▶ EUCLID — HIT/MISS SPLIT: a rest step can now ALSO strike, plus per-lane VELOCITY (2026-10-02, on
  `feature/processor-live-sweep` → `main`; macOS 1180 green incl. 5 new, iOS builds; DEVICE ear/eye owed — the
  whole feature is genuinely unverifiable off-device, both the new sound and the restructured panel). Paul: "I
  want the bottom controls (velocity, gate, etc) on Euclid to split into two. On the left is 'Lane 1 hit' and
  on the right is 'Lane 1 miss', which plays the off notes. Under these titles are note selectors, one for
  each. Put velocity and gate (both controls in both sections) onto the same line. Put octave to the right of
  the note selectors, and half its height. Reduce the width of the back, forward ping-pong buttons. Ensure
  that both 'hits' and 'misses' boxes have identical controls." **MODEL (Models.swift):** 4 new additive-
  Optional `EuclidLine` fields — `missNoteSel: EuclidNoteSel?` is the WHOLE feature's on/off switch (nil ⇒ OFF,
  today's silent-rest behaviour, byte-identical for every existing doc; no separate enable flag, picking any
  chip turns it on) plus `missGate`/`missOctave`/`missVelocity`, mirroring the hit side's own fields exactly.
  **REINTEGRATION NOTE, flagged plainly:** this landed in the SAME session, on a different worktree, as the
  entry directly below this one (DIE removal + the first VELOCITY control) — `EuclidLine.velocity` had already
  been added upstream for the identical purpose (a per-line scale on the hit's own inherited velocity) by the
  time this branch rebased, so the duplicate declaration was DROPPED here in favour of the already-landed one
  (same semantics, same clamp) rather than kept as a second field. More consequentially: this feature's first
  draft also added a `missDie` (mirroring the hit side's own `die`, independently salting the miss-side CYCLE/
  RANDOM walk) — but DIE was removed ENTIRE, control and effect, by the other worktree's own same-day work
  ("drop it, please" — see below) while this branch was in flight. Reintroducing an un-asked-for `missDie`
  under a new name would have directly contradicted that instruction, so it was dropped before merging, not
  shipped then walked back — MISS's ordinal is unsalted from the start, matching the hit side's own now-
  unsalted `ord`. The regression test that had exercised `missDie`'s independence was deleted (not rewritten
  as a no-op guard) since the field was never shipped. **ENGINE (Router.swift, `runEuclidLine`):** the hit
  path's `guard isHit else { return }` became `if isHit {...} else if let missSel = missNoteSel {...}` — the
  miss branch computes its OWN ordinal (`missOrd`, counting MISSES not hits up to this tick) and resolves it
  through a NEW shared `resolveEuclidPick(sel:ord:)`, factored out of the pre-existing inline ALL/LOW/HIGH/
  BOT2/TOP2/CYCLE/RANDOM switch (confirmed behaviour-identical by direct comparison against the original
  inline code) so the hit and miss paths can't independently drift from each other's pick semantics. **RIFF/
  ARP are explicitly EXCLUDED from miss** (flagged, not an oversight) — guarded with `guard missSel != .riff
  && missSel != .arp else { return }` before calling `resolveEuclidPick`, since that function's own `default:
  return (nil, nil)` would otherwise read as ALL (strike everything) for an unhandled case — an honest silent
  no-op instead of an accidental loud one. A new `isHitAt(_:)` local helper factors the "is step s a hit" test
  that used to be inlined twice (cycleHits, hitsUpTo) and now a third time (missesUpTo) — pure de-duplication.
  **UI (GridUI.swift):** `euclidSettingsPanel` restructured — DIRECTION is the only control left in the shared
  row above both boxes (INVERT is gone entire, per the other worktree's same-day removal — "identical
  controls" never applied to it anyway, since it shapes the one underlying pattern, not a per-outcome
  setting); kept the same-day >/</>< relabel, just rendered via `seg` (content-sized chips) instead of `segV`
  (full-width stacked) — "reduce the width... of the buttons" — safe now the panel spans the full editor
  width. A new `euclidHitMissBox(idx:L:isMiss:)` renders BOTH boxes from ONE function (an `isMiss` flag
  choosing which fields to read/write) so they can't drift out of structural sync — note-select chips beside a
  labelled, `compact: true` (half-height) OCTAVE stepper, then VELOCITY+GATE sharing one line below, exactly
  per Paul's own ordering. No DIE row on either side (removed entire, per the same-day instruction above).
  MISS's note-select chip row reuses `euclidNoteSelShown` directly (no RIFF/ARP append, unlike HIT's row) —
  the UI-side half of the same exclusion the engine enforces. **TESTS:** +5 RouterTests (miss silent by
  default — byte-identical regression; miss strikes on every rest step once a pick is set; miss's own octave
  shifts independently of hit's; RIFF/ARP picks on miss stay silent, not a stray ALL; VELOCITY coverage already
  existed from the other worktree's own same-day addition, so no duplicate test was added here). UI+engine
  (GridUI.swift + Router.swift + Models.swift + SnapshotBuilder.swift + Tests/RouterTests.swift), full macOS
  test-target reach for the engine half. **DEVICE-OWED, the whole feature:** the restructured panel's
  legibility (two boxes side by side, each noticeably narrower than the old single-column settings); confirm
  OCTAVE's half-height stepper still has a usable touch target at that size; the actual SOUND of a configured
  miss — does a ghost note on the off-beat read as musically useful.**
- **▶ EUCLID DIE — removed entire, control and effect (2026-10-02, on `fix/euclid-riff-predtype-and-polish`; macOS
  1176 green incl. 3 rewritten, iOS builds; DEVICE eye owed). Paul asked what DIE was/why it was there (it predated
  this session, v1b 2026-08-26 — a per-line ordinal salt so two lines both reading CYCLE/RANDOM/RIFF/ARP could be
  staggered instead of producing the identical sequence); after the explanation, "Drop it, please." Same message:
  "octave does not work" — investigated (re-read strikeChord/runEuclidLine's 4 call sites + the shared NumPair
  widget, all correct, all covered by passing tests) — Paul then retracted it ("Actually, octave does work") before
  any fix was needed; no code changed for that report. **DIE REMOVAL:** the `HStack` DIE control in
  `euclidSettingsPanel` (GridUI.swift) is deleted outright; `runEuclidLine`'s `ord` computation drops the
  `&+ Int64(die)` term entirely (now a plain, unsalted ordinal) and the function's own `die: Int = 0` parameter +
  the `die: L.dieResolved` call-site argument are both gone. `EuclidLine.die`/`dieResolved` KEPT as decode-only
  (same treatment INVERT got the same day) — an old doc with a non-zero per-line die just stops salting, nothing
  crashes. **TESTS, 3 rewritten (not deleted — regression guards, matching the INVERT precedent):**
  `testEuclidLinesPerLinePickAndDie`'s own DIE assertion → now asserts two different die values produce the
  IDENTICAL sequence (was: different); `testEuclidDieOffsetsTheRiffSequenceStart` → `testEuclidDieIsNowANoOp-
  OnTheRiffSourcedPath` (die 0/1/2 all now land on the SAME first note, not 60/64/67); the two-lines-independent-
  phasing test, which had used matched-K/different-DIE as its proof mechanism, needed a full redesign since
  identical-K lines are now byte-identical with nothing left to tell them apart — rebuilt around DIFFERENT
  densities (K=8 dense vs K=3 sparse) instead. **A SELF-CAUGHT TEST-DESIGN BUG, not shipped wrong:** the first
  redesign asserted the combined run equals the EXACT union of each line's solo run — failed (13 ons vs 11
  expected) not because of independence breaking, but because it tripped a PRE-EXISTING, already-documented
  quirk (`runEuclidLine`'s own comment: "`lastTick[row]` SHARED across every line on this row... a known
  limitation for 2+ real lines sharing a row across a window boundary") — unrelated to DIE, unrelated to this
  change, just newly exposed by a test strict enough to notice it. Weakened to the actually-robust claim
  (`testEuclidTwoLinesSameRiffPredecessorBothContribute`: combined count > either solo count alone — neither line
  silently swallows the other) rather than fighting or silently working around a known, accepted limitation.
  Also fixed two now-stale doc comments in GridUI.swift (one above `euclidSettingsPanel` still listing
  "conditional DIE"/INVERT, missing VELOCITY) and Models.swift (`invert`'s/`die`'s own field comments, updated to
  say plainly they're decode-only and why). UI+engine, no test-target reach for the UI half (GridUI.swift, as
  always). **DEVICE-OWED:** confirm the settings panel now reads cleanly with just the NOTE chip row above
  GATE/VELOCITY/OCTAVE/DIRECTION, no dangling gap where DIE used to sit.**
- **▶ EUCLID per-line panel — a real bugfix on the RIFF/ARP feature + three polish asks: HITS/REST removed, DIRECTION
  relabelled >/</><, a new VELOCITY control (2026-10-02, on `fix/euclid-riff-predtype-and-polish`; macOS 1176 green
  incl. +1, iOS builds; DEVICE ear/eye owed). Paul, testing the EUCLID-reads-RIFF/ARP feature just shipped: "RIFF
  doesn't seem to feed into EUCLID as I expect. The notes it plays seem unrelated to what's set in riff" — then, same
  message, three unrelated polish asks: "remove the hits button and functionality," "change the direction b[u]t to
  use >, <, and >< as labels (in order to make them smaller)," "add a velocity control." **THE BUG, root-caused not
  guessed:** `BuildPage.swift`'s `precedingSourceType` (the chip-visibility gate added with the RIFF/ARP feature)
  read `buildMachineChain(cid)` — which `.filter`s OUT every empty/bypassed slot ANYWHERE in the chain, collapsing
  indices — then indexed it with `i` (`buildEditSlot`), which is an index into `selectedMachineChain()`, a DIFFERENT
  array that only trims TRAILING empties (interior ones keep their original position). The two disagree the moment
  any empty slot sits before EUCLID — an easily-reached shape, since `buildChainRemoveSlot`'s own documented
  position-preserving delete leaves exactly this kind of gap (add RIFF, add something else, add EUCLID, delete the
  middle one — the "something else" slot is still there, just bypassed-empty). `chain[i-1]` against the collapsed
  array then reads whatever slot lands at that position post-collapse — not necessarily RIFF, not necessarily even
  adjacent to EUCLID at all. **FIX:** read `buildMachineSlots(cid)` instead — the RAW array `selectedMachineChain()`
  itself is built from (same indices, same length, nothing collapsed), so the closure and `i` now provably index the
  same array the same way. Router.swift's OWN `predType` (the render-side twin check) was independently re-verified
  correct throughout — it already walks `cell.procs`/`cell.slotBypass` directly (the real fixed-8 array, matching
  `chainDriverIndex`'s own bypass-skip convention), so this was a UI-only bug, not an engine one. UI-only fix
  (BuildPage.swift), no test-target reach — this exact function isn't unit-testable, DEVICE-owed to confirm the chip
  now reflects the true predecessor in a chain with a gap before EUCLID (not just the simple adjacent case, which
  already worked and is what the shipped RouterTests exercise). **HITS/REST REMOVED:** the bottom tap-pill in
  `euclidSettingsPanel` (`Text(L.invert ? "REST" : "HITS")`, toggling `EuclidLine.invert` to strike the N−K rests
  instead) is deleted outright — control AND effect. `runEuclidLine`'s `invert` parameter is gone; every
  `invert ? !euclidBuf[x] : euclidBuf[x]` ternary (cycleHits/isHit/hitsUpTo) simplified to plain `euclidBuf[x]`.
  `EuclidLine.invert`/`MachineParams.euclidInvert` both KEPT as harmless decode-only fields (an old doc with INVERT
  engaged doesn't factory-reset — it just silently stops flipping). `testEuclidInvertPlaysTheRests` rewritten to
  `testEuclidInvertIsNowANoOp` (was 9-vs-15 ons, now 9-vs-9) — a regression guard, not a deleted test, so an
  accidental re-wire would be caught. **DIRECTION relabelled:** `segV`'s `options` array is now `[">", "<", "><"]`
  (was `["FWD","BKW","PING-PONG"]`) — display only. Caught before shipping, not after: `segV` highlights by STRING
  EQUALITY (`opt == sel`), and `sel:` was passed `L.directionResolved.rawValue` (the PERSISTED string, "FWD" etc.,
  unchanged) — relabelling `options` alone would have left the highlight permanently unlit (none of the new labels
  equal the old raw value). Fixed by computing `sel:` as the NEW label corresponding to the current direction
  (`dirLabels[[.fwd,.bkw,.pingpong].firstIndex(of: L.directionResolved) ?? 0]`) — `onPick`'s index-based mapping to
  `EuclidDir` is untouched, so the persisted raw values ("FWD"/"BKW"/"PING-PONG") never change, only what's drawn.
  **VELOCITY, new:** `EuclidLine.velocity: Double?` (additive-Optional, CR-8 safe) + `velocityResolved` (0…2, nil⇒1.0
  = unity). Threaded through `SnapshotBuilder`'s `euclidLines` resolve (clamped 0…2) and into `runEuclidLine` as a
  new `velocity: Double` parameter, replacing the hardcoded `velScale: 1.0` in all FOUR `strikeChord` calls inside
  (the plain pickIndex/pickRange strikes AND the RIFF/ARP-sourced explicit-note strikes alike) — a SCALE multiplier
  on the struck note's own inherited velocity, not ARP's "ignore the input, absolute 1…100" convention, since a
  EUCLID line can strike either a pool note (whose own velocity should still matter) or a RIFF/ARP-resolved note
  (whose own velocity formula this scale multiplies on top of). UI: a new `field("VELOCITY …%")` + slider (0...2),
  inserted right after GATE, replacing the removed HITS/REST pill's visual slot. +1 RouterTest
  (`testEuclidVelocityScalesTheStruckNote`, a higher scale produces a measurably louder note than a lower one).
  **DEVICE-OWED:** the predType bugfix against a REAL gapped chain (the shipped tests only exercise a clean adjacent
  2-slot chain, which already worked); the >/</>< labels reading clearly at the control's reduced width; VELOCITY's
  audible range at both ends of 0…2; confirm HITS/REST is genuinely gone with no dangling empty space in the panel.**
- **▶ EUCLID reads RIFF/ARP as a sequential note source (2026-10-02, on `feature/euclid-reads-riff-arp`; macOS
  1175 green incl. 10 new, iOS builds; DEVICE ear/eye owed — chip legibility and the actual sound of a riff/arp-
  sourced line are genuinely untestable off-device). Paul: "if a riff is fed into a Euclid then the riff can be
  chosen as a selected note, and each hit will sequentially play each note from the riff... Please implement this,
  with RIFF or ARP available as note options if present upstream" — planned first (3 Explore agents + a Plan
  validation pass, `~/.claude/plans/hidden-yawning-boole.md`) per Paul's own "maybe plan first?" steer, confirmed
  stateless per his answer to the one open design question. **MODEL:** `EuclidNoteSel` (Models.swift) gains two
  cases, `.riff`/`.arp` — no new fields anywhere; `EuclidLine.noteSel` already stores them. **ENGINE
  (Router.swift, `case .euclid:`):** a top-level adjacency check computed once — `predType` = the type of the
  slot immediately before EUCLID's own driver index, ONLY when that slot is non-bypassed (mirrors
  `chainDriverIndex`/`composeChainSet`'s own bypass-excludes-a-slot convention throughout this file — a bypassed
  predecessor is "not really there," same as `testChainBypassedHeadArpsSourceOnly` already locks in). Inside
  `runEuclidLine`'s hit closure, the existing per-hit `ord` (a monotonic, STATELESS "which hit number is this"
  ordinal — already driving CYCLE/RANDOM, hoisted up unconditionally so `.riff`/`.arp` can read it too) feeds a
  NEW branch, separate from the pool-index switch (since RIFF/ARP resolve an EXPLICIT note, not a pool index): a
  `.riff` line reads the predecessor's own `riffRanks`/`riffMask`/`riffOct`/`riffAccent`/`riffWrap` directly off
  `cell.procs[predIdx]`, walks its non-rest steps via two bounded (≤32) no-alloc scans (count, then locate — the
  same idiom this function's own `cycleHits`/`hitsUpTo` already uses), resolves the picked rank(s) against a
  FRESH `composeChainSet(upto: predIdx - 1)` (the pool feeding INTO riff's own slot — a no-op when RIFF is slot 0
  — deliberately not EUCLID's own already-composed pool, which would be circular for the ARP case) via
  `riffResolve` directly (POLY loops every set mask bit as a simultaneous chord-stab), with velocity via RIFF's
  own exact formula read off the CELL's raw/live pool (not the composed one — these differ in a 3+-slot chain).
  An `.arp` line composes the same predecessor pool and calls `arpPick(phaseIndex: ord, ...)` directly with the
  predecessor's own resolved pattern/octaves/velocity/velTilt — `ord` becomes `phaseIndex` unmodified (arpPick is
  fully pure/total in phaseIndex, incl. RANDOM ONCE). Both emit via a new `strikeChord(explicitNote:explicitVel:)`
  pair of params (default nil ⇒ byte-identical for every existing call) — factored the shared store+emit tail
  into a nested `strikeOne` so the explicit-note path and the existing srcNotes-indexed loop share one
  implementation, not two. A mismatched/bypassed predecessor — or an all-rest one (every non-rest scan comes up
  empty) — returns silently, never crashes, never falls back to a different pick. EUCLID's own per-line
  OCTAVE/GATE still apply on top (confirmed additive: RIFF's own octave lane bakes into the resolved note, then
  EUCLID's `octave` param shifts it again at `strikeChord`). **UI (GridUI.swift/BuildPage.swift):** a new
  `ProcessorBox.precedingSourceType` stored prop (mirrors `driverNoteRate`'s own "a neighbor slot's value
  threaded into the editor" shape, with the one correction that precedent didn't need: bypass-aware), computed at
  `buildSlotBox`'s call site and threaded in; `euclidSettingsPanel` conditionally appends a "RIFF"/"ARP" chip to
  the NOTE SELECT row only when it matches (hidden entirely, not shown-disabled, matching how the other 10
  already-trimmed `EuclidNoteSel` cases behave); the DIE control's visibility extended from `.cycle`/`.random` to
  also include `.riff`/`.arp` (DIE was already mechanically folded into `ord` for free — this just stops it going
  invisible-but-still-active when a line switches to the new sources). **TESTS:** +10 RouterTests (RIFF sequence
  skipping rests, wrapping by non-rest count · ARP sequence matching `arpPick` directly, incl. RANDOM ONCE seed-
  determinism · two lines on the same RIFF predecessor phasing independently via their own DIE · an all-rest
  predecessor, both MONO and POLY-empty-mask, silent not crashing · a bypassed predecessor silent, mirroring
  `testChainBypassedHeadArpsSourceOnly` · a POLY step striking a genuine simultaneous chord-stab · a TIE-marked
  RIFF step still counting as struck (TIE is never read by this feature) · EUCLID's own octave stacking
  additively with RIFF's per-step octave lane · DIE offsetting the walked sequence's start). One test-authoring
  lesson hit directly: a bare (un-held) test cell only ticks during its OWN grid column's real-time span by
  default — `forceColumn: 0` (PLAY: THIS CELL) was needed to reach a 2nd lap of a 5-element sequence, the exact
  same fix `testEuclidPingPongDoublesHitsOverAFullLap` already needed for the identical reason. **SCOPED OUT,
  named not accidental (per the approved plan):** a general "scan anywhere upstream" rule (adjacency only); RIFF's
  own `riffDir` (EUCLID always walks RIFF's authored step order, ignoring however RIFF itself would play back —
  DRUNK has no stateless form at all); "RIFF's own editor shows a playhead driven by EUCLID's rate" (a separate,
  visual-only follow-up). **DEVICE-OWED:** the two new chips' legibility/placement in the trimmed NOTE SELECT row;
  the actual sound of a riff/arp-sourced EUCLID line against a real chord; multi-line phasing audibly working as
  described (free architecturally — each line's own K/N/rotate/die already gives it an independent `ord`, now
  worth an ear-check against real material).**
- **▶ EUCLID EDITOR — the 2×2 lane box now spans the FULL editor width, not 50% (2026-10-02, on `main`; iOS
  builds, no test-target reach (GridUI-only); DEVICE eye owed). Paul: "extend the width of the controls so that
  they take up the entire processor control window. Currently they all sit below the first input piano at the
  top of the processor control, but they should be below the output piano too. The total width should be the
  same as the euclid controls box that sits underneath it. Basically, it's now a total 50% of the width
  available." ROOT CAUSE, traced not guessed: `buildTruthStrips()` (BuildPage.swift) renders the IN and OUT
  piano strips as two HALF-width `HStack` siblings, side by side (`VStack.frame(maxWidth: .infinity, alignment:
  .leading)` ×2) — so the editor's visible width is effectively split IN-half | OUT-half at the top. The prior
  pass's 2×2 box was deliberately half-width AND left-aligned (`geo.size.width * 0.5` + a trailing `Spacer`),
  which put it squarely under the IN half only — the OUT half had nothing below it — while `euclidSettingsPanel`
  underneath was ALREADY full width (`.frame(maxWidth: .infinity)`), creating exactly the width mismatch Paul
  described. **FIX:** dropped the `* 0.5` + `Spacer` entirely — `cellW` is now computed directly off the FULL
  `geo.size.width` (`(geo.size.width - euclidLaneGap) / 2` per cell, still a 2-column grid, just now spanning
  the whole editor), so the box reaches under BOTH piano halves and matches the settings panel's own width
  exactly. Nothing else changed — `euclidLaneBox`'s own internals (PLAY/STOP inline, tap/drag-to-select,
  comet bar) are untouched; only the OUTER width computation in `case .euclid:` moved. UI-only (GridUI.swift),
  no test-target reach. **DEVICE-OWED:** confirm the 2×2 box now visually reaches under both the IN and OUT
  piano strips with no gap/misalignment, and that each lane's comet bar — now roughly DOUBLE its prior width
  (full-width cells instead of half-width ones) — reads more legibly, not just bigger.**
- **▶ EUCLID EDITOR — PLAY/STOP back inline, SELECT chip removed, tap/drag-to-select instead (2026-10-02, on
  `main`; iOS builds, no test-target reach (GridUI-only); DEVICE eye/feel owed — the tap-vs-pan/pinch gesture
  interplay is genuinely untestable off-device). Paul, correcting the immediately-prior 2×2-box relayout: "I
  want the play button on its original position as part of the grid lane. No select button please, and if any
  lane is touched I want it highlighted (the previous behavior of the select button) which will bring its
  control into focus." SUPERSEDES that pass's separate PLAY/STOP+SELECT control row below the 2×2 box entirely
  — reverted to a SINGLE stacked section (the 2×2 box, then the selected lane's settings beneath it). PLAY/STOP
  is back INLINE inside each `euclidLaneBox` (left of the comet bar, its position from before the 2×2 pass);
  the numbered SELECT chip is GONE — no replacement control, no "select" button anywhere. In its place: tapping
  ANYWHERE on a lane's box (`.onTapGesture` on the whole cell, chained after the box's own background/border so
  it covers the full visible area) sets `euclidSelectedLane`, driving the EXACT SAME highlight (`selected`
  border/background opacity) the old SELECT chip used to drive — "the previous behaviour of the select button,"
  just triggered by touching the lane itself rather than a dedicated control. ALSO selects on a single-lane
  drag/pinch start (inside the comet bar's own `onDragState`, gated `!allRows` — the 2-finger ALL-LANES gesture
  doesn't name one lane, so it's excluded), since "if any lane is touched" reads as covering drag-starts too,
  not just a plain stationary tap. **WHY A PLAIN TAP REACHES THE OUTER GESTURE AT ALL, reasoned through, not
  assumed:** the comet bar's gesture pad occupies most of the box via `UIPanGestureRecognizer`/
  `UIPinchGestureRecognizer`, but BOTH only transition out of `.possible` once a touch moves past UIKit's own
  recognition threshold — a touch that lifts without moving simply fails them, un-consumed, so SwiftUI's
  `.onTapGesture` on the ancestor box can still recognize it. PLAY/STOP keeps its OWN inner `.onTapGesture`
  (toggles `enabled`, never touches pulses/steps/rotate) — tapping it fires ONLY that handler, not also the
  outer select-tap, by SwiftUI's standard nested-gesture precedence (confirmed behaviour, not new code — no
  special-casing needed to keep the two independent). `euclidLaneControl` (the now-empty control row) and its
  call site are DELETED outright, not left dead. UI-only (GridUI.swift), no test-target reach.
  **DEVICE-OWED, and this is the one piece that genuinely can't be confirmed by reading code — real multi-
  recognizer touch arbitration only shows itself on a touchscreen:** whether a plain tap on the comet-bar area
  (not just the blank background margin) actually reaches the outer select-tap in practice, or whether the
  UIKit pad's mere PRESENCE (even while its own recognizers stay `.possible`) intercepts/delays the touch enough
  to feel unresponsive; whether tapping PLAY/STOP ever accidentally also selects (shouldn't, per SwiftUI's
  rules, but unverified); the narrower comet bar's legibility now that PLAY/STOP occupies 44pt+8pt of the
  already-halved 2×2 cell width again.**
- **▶ EUCLID EDITOR — relayout: the 4 lanes as a 2×2 box at 50% width, controls moved below (2026-10-02, on
  `main`; iOS builds, no test-target reach (GridUI-only); DEVICE eye owed — three stacked sections with real
  interpretation room, nothing here can be confirmed by reading code alone). Paul: "change the layout so the
  four lanes sit as 2x2, taking 50% width of the processor edit box. Move the lane controls to below the box of
  4 lanes. Put the individual controls per lane below these." Supersedes the 2026-10-01 PLAY/SELECT-inline-
  beside-a-side-panel design entirely. **JUDGMENT CALL on the two "controls" phrases, flagged to Paul rather
  than guessed silently:** read "the lane controls" as PLAY/STOP + SELECT (the controls that pick/mute a WHOLE
  lane) and "the individual controls per lane" as the detailed per-lane settings (NOTE/GATE/OCTAVE/DIRECTION/
  INVERT) that used to live in the side panel — i.e. two DIFFERENT control groups stacking in that order below
  the box, not one. **THREE STACKED SECTIONS, top to bottom:** (1) a 2×2 grid of the 4 lanes' comet-bar boxes —
  `euclidRow` renamed+stripped to `euclidLaneBox` (comet bar + selection-highlight border ONLY, no inline
  buttons anymore) — sized to HALF the editor's GeometryReader-measured width, left-aligned with a trailing
  `Spacer` filling the other half (read "taking 50% width" literally — nothing stretches to fill the remaining
  space); (2) a new `euclidLaneControl` (the PLAY/STOP+SELECT pair, unchanged 44pt sizing, just relocated out
  of the box) — one row of 4, FULL editor width (four button-pairs don't comfortably fit inside the half-width
  box, so this row isn't capped to the box's own 50%); (3) `euclidSettingsPanel`, unchanged FIELDS (NOTE chips+
  DIE·GATE·OCTAVE·DIRECTION·INVERT) but stripped of its forced width/height and inner `ScrollView` — it no
  longer needs to height-match a lane column beside it (there's no "beside" anymore), so it's now a plain
  full-width section sized to its own natural content height; `buildProcessorPanel`'s own OUTER ScrollView
  (BuildPage.swift, unrelated to this change) already handles overflow for the whole editor. The comet bar's
  own gesture pad (1-finger drag, 2-finger drag, pinch) is completely UNCHANGED inside each 2×2 cell — still
  the only way to reshape hits/steps/rotate; only its SURROUNDING chrome (the buttons that used to sit beside
  it) moved. The drag-direction fix and the step-box redesign (both earlier the same day) carry through
  unmodified — neither depended on the box's position in the page, only on the comet bar's own internals.
  UI-only (GridUI.swift), no engine/model change, no test-target reach. **DEVICE-OWED, and this is a pure
  layout change with real room to read it differently than intended:** whether the 50%-width 2×2 box reads as
  deliberately compact rather than oddly cramped next to its own blank half; whether the 4-wide control row
  and the lane-above-it correspondence (left-to-right = lanes 1-4, matching 2×2 reading order top-row-then-
  bottom-row) is intuitive without an explicit visual link between a box and its control pair; confirm the
  judgment call on "lane controls" vs "individual controls per lane" above actually matches what Paul meant.**
- **▶ ROOMS GRIDS — both bottom footers removed: the PART loop-column buttons + the SELECT placeholder rail
  (2026-10-02, on `main`; iOS builds, no test-target reach (BuildPage-only); DEVICE eye owed). Paul: "Remove the
  loop buttons from the bottom of the part grid, and also remove the bottom placeholder rail of the select
  grid." Deleted BOTH footer view functions wholesale — `roomsGridFooter` (the SELECT grid's always-placeholder,
  never-wired shell) and `roomsPartLoopFooter` (the PART grid's real "repeat" toggle row, driving
  `buildPartLoopCols`) — plus the now-orphaned `buildTogglePartLoopColumn` (its ONLY caller was the deleted
  button; confirmed via grep before deleting, not assumed). In both `roomsSelectGridUnit` and `roomsPartGrid`,
  the processor card now docks flush beneath the grid rows (`cardY = interiorH + gap`) instead of below a
  footer-sized gap PLUS a second "hidden-cell gap" the footer used to leave between itself and the card (a
  2026-09-09 design choice, `ch*2/3` extra, that only made sense while a footer occupied the first third) — so
  the card reclaims ALL of that freed space, not just the footer's own height, in both grids. **FLAGGED, not
  silently absorbed: this is a real loss of reachable control for PART, not purely cosmetic.**
  `buildPartLoopCols`/`BuildSceneLogic.loopColumnPlan` are UNTOUCHED — composeScene, both playheads, and session
  persistence (save/restore, part-load) all still read/write the array exactly as before; only the UI button
  that let a user CHANGE a loop selection by tapping is gone. A part keeps whatever loop columns it last had
  (restored from a saved doc, or none if it never had any) with no way to set new ones from this page. SELECT's
  footer was always a pure placeholder (`SELECT = pages (placeholder, not wired)`) — nothing is lost there
  beyond the reserved visual space itself. UI-only (BuildPage.swift), no test-target reach.
  **DEVICE-OWED:** confirm both grids now dock their processor card flush beneath the rows with no leftover
  gap or overlap, and that the PART grid's card is noticeably taller now that both the footer AND the old
  hidden-cell gap are reclaimed.**
- **▶ EUCLID COMET BAR — redesigned around glowing STEP BOXES, not floating dots (2026-10-02, on `main`; iOS
  builds, no test-target reach (GridUI-only); DEVICE eye owed — the whole visual treatment is unverifiable off-
  device). Paul: "Incorporate boxes into the design of the Euclid lanes to represent every step. It needs to be
  easier to see the number of steps. Make it look cool." The old track was a thin 1pt baseline with small
  floating dots (hit/rest) plus a sweeping comet — the dots sat on an otherwise-blank line, so the step COUNT
  itself wasn't legible independent of which steps happened to be lit. **REDESIGN:** the track is now N bounded,
  gap-separated ROUNDED-RECT boxes — one per step, always drawn (hit or rest), so the grid's own shape
  communicates "there are N slots" by construction, not just via however many dots happen to be visible. Gap
  narrows as N grows (4pt at N≤8, 3pt at N≤12, 2pt above) and corner radius is capped relative to box width
  (`min(5, boxW/2.2)`) so a dense 16-step lane's boxes stay legible rounded rects rather than squashing into
  near-circles or overlapping. **"MAKE IT LOOK COOL":** a hit box now fills with a top-lit linear gradient
  (brighter at the top edge, settling toward the tint's own shade at the bottom) instead of a flat dot colour —
  reads as glassy/lit-from-above rather than a dead swatch — brightening further during its own burst window; a
  thin border stroke on EVERY box (hit or rest, brighter on a burst) gives the grid definition even when nothing
  is lit. The existing dramatic-hit effects (burst swell/recede afterglow, a hot white flash core, an expanding
  "shockwave" ring) are ALL PRESERVED, just re-shaped to match: the flash core is now a bright inset band inside
  the box rather than a second circle, and the shockwave is an expanding box OUTLINE (`rect.insetBy(dx:-grow,
  dy:-grow)`) instead of a circular ring — same timing/decay math as before (burst/recede unchanged), only the
  geometry changed from circles to rounded rects. The REST box keeps this session's own hard-won lesson (a
  hollow ring reads as "vanished," not "dimmed" — see the 2026-10-01 rest-marker fix) — still a plainly visible
  FILLED + bordered box, just dim (`white.opacity(0.09)` fill), same shape family as a hit. The old thin
  horizontal baseline stroke is GONE — the box row itself now IS the track, and a separate line underneath read
  as redundant clutter once the boxes carry that role. The COMET (continuous blurred trail + glowing head) is
  UNTOUCHED in position/timing/stopped-state-hiding — still rides on top of the box row exactly as before,
  independent of the discrete per-box state (`xFor` is still the same continuous-phase function). UI-only
  (GridUI.swift, `euclidCometBar` only), no engine/model change, no test-target reach. **DEVICE-OWED, and this
  is a pure Canvas-drawing aesthetic change with real interpretation room — nothing here can be confirmed by
  reading code alone:** the box grid's legibility at real panel width across the whole 2…16 step range (16
  steps is the tightest case, worth checking first); whether the gradient fill genuinely reads as "cool"/glassy
  rather than just "a gradient" at this size; the flash-core/shockwave's new box-shaped geometry feeling as
  dramatic as the old circular version; confirm the per-box border doesn't make a dense 16-step row look busy/
  cluttered rather than clean.**
- **▶ EUCLID EDITOR — the footer below the lanes removed entire: HITS FROM + GRID/SPAN (2026-10-02, on `main`;
  iOS builds, no test-target reach (GridUI-only); DEVICE eye owed). Paul: "Remove everything below the lanes on
  the euclid processor page." Deleted the `field("HITS FROM"...)` toggle and the `frameRow(grid:…, span:…)`
  footer wholesale, plus the now-unused `fromPool` local it alone was reading. **FLAGGED, not silently absorbed:
  this is a real loss of reachable control, not a cosmetic trim.** `euclidPulsesFromPool`/`euclidRate`/
  `euclidSpanN` are UNTOUCHED at the model/engine level — every lane's comet bar and the real render path still
  read them exactly as before (GRID still drives every lane's tick rate, SPAN still re-anchors, POOL still
  overrides K when set) — only the UI that let a user CHANGE these three from this page is gone. A machine now
  keeps whatever it last had for all three (defaults: GRID 1/16, SPAN free-run, HITS FROM fixed); there is no
  other control surface left in this editor to set them. UI-only, no test-target reach.
  **DEVICE-OWED:** confirm the page now ends cleanly right after the 4-lane stack + side panel, with nothing
  dangling below it.**
- **▶ EUCLID DRAG HUD — relocated OUT of the scrolling processor panel, tracks the touch, restyled (2026-10-02,
  on `main`; iOS builds, no test-target reach (GridUI+BuildPage+AudioUnitViewController); DEVICE eye owed —
  the touch-tracking math can't be confirmed off-device). Paul: "I want the overlay for count, hits to be top
  level because it's currently fixed on the scrolling processor edit page. It should be an inch or two above
  the touch location and more prominent than it is now. Style it as saying 3 hits out of 8, with offset by 2 in
  smaller text." **ROOT PROBLEM:** the old HUD (`euclidDragHUD`) was rendered INSIDE `ProcessorBox`, which is
  itself nested inside `buildProcessorPanel`'s `ScrollView(.vertical, showsIndicators: true)` (confirmed by
  reading the actual call chain, not assumed) — a plain `.overlay(alignment: .top) { ... }.offset(y: -58)`
  anchored to the lane stack's own TOP edge, regardless of which of the 4 lanes was actually being touched or
  where the panel happened to be scrolled to. `ProcessorBox` itself has no way to escape its own embedding
  ScrollView's clip/scroll — only its HOST (`buildProcessorPanel`, in BuildPage.swift) can render something as a
  true sibling OUTSIDE it. **FIX, three moving parts:** (1) a new `EuclidDragHUDInfo` struct (label/hits/steps/
  offset/point, GridUI.swift) carries everything the HUD needs, including the touch's location in WINDOW
  coordinates (`UIPanGestureRecognizer`/`UIPinchGestureRecognizer`'s own `location(in: view.window)` — NOT
  SwiftUI-local coordinates, which would be meaningless once the content is rendered somewhere else entirely).
  (2) `EuclidGesturePad`'s `onDragState` signature widened from `(Bool, Bool)` to `(CGPoint?, Bool)` — now fires
  on EVERY `.changed` tick (not just begin/end) so the reported point tracks the finger continuously, not just
  at touch-down; `nil` on lift/cancel. `euclidRow` builds the full `EuclidDragHUDInfo` from its own already-in-
  scope `L`/`idx` and reports it via a new `onDragInfo` callback, threaded up through a new `ProcessorBox.
  onEuclidDragInfo: (EuclidDragHUDInfo?) -> Void = { _ in }` (default no-op — only `buildSlotBox`, the one real
  chain-slot editor, wires it; the tab-strip/chord-sequencer-popup `ProcessorBox` call sites never show EUCLID
  and are unaffected). (3) `buildProcessorPanel` (BuildPage.swift) now owns a new `@State var euclidDragHUDInfo`
  (declared on `DiagView` itself, `AudioUnitViewController.swift`, since that's where the struct's state lives)
  and renders the ACTUAL HUD via a NEW `.overlay()` chained AFTER the panel's own `ScrollView` + its `.frame(...)`
  — a true sibling, escaping the scroll clip entirely. The overlay's own `GeometryReader` converts the WINDOW-
  space touch point into ITS local coordinate space via `geo.frame(in: .global).origin` subtraction (SwiftUI's
  `.global` space and UIKit's window space coincide for a SwiftUI root hosted directly in its window, the
  standard bridging assumption for this kind of UIKit-gesture-into-SwiftUI-overlay technique — unverified on
  THIS specific hosting setup without a device). Positioned ~150pt above the touch ("an inch or two," a
  documented approximation — iPad's logical point density isn't a fixed physical inch, flagged as tunable, not
  measured) with the X clamped so the ~230pt-wide card can't run off either edge. **STYLE:** replaced the old
  3-stat-box row (STEPS/HITS/OFFSET side by side, 16pt numbers) with a plain-English primary line — "N HITS OUT
  OF M" at 22pt — and a smaller secondary line, "OFFSET BY K" at 12pt, per Paul's own literal phrasing. Bigger
  padding, a brighter border, and a drop shadow (new) make it read as a genuine floating card, not an inline
  tag. The 4 bordering arrow glyphs from the old design are DROPPED, not kept — they were a "gestures work
  here" reminder tied to a FIXED position beside the gesture pad; pointing in 4 directions stops meaning
  anything once the card floats freely wherever the touch happens to be, so keeping them would have been
  decoration with no referent. No animation on position (deliberate) — the HUD snaps to each reported point
  immediately rather than easing toward it, so it doesn't lag behind the finger. UI-only, three files
  (GridUI.swift, BuildPage.swift, AudioUnitViewController.swift), no test-target reach. **DEVICE-OWED, and
  this is the one piece I genuinely can't verify by reading code — true cross-UIKit/SwiftUI coordinate bridging
  only shows itself on a real touchscreen+window:** whether the window-space-to-SwiftUI-global conversion lands
  pixel-accurate on THIS app's actual hosting setup (a systematic offset would show up as "the HUD is near the
  touch but consistently off by some amount," not as a crash); the ~150pt/~230pt constants' feel at real panel
  size; confirm the HUD now stays visible and tracks the finger regardless of how far the processor panel has
  been scrolled, the actual bug being fixed.**
- **▶ PLAY FERRIES — fixed a populated, selected ferry loading with the part grid invisible (2026-10-02, on `main`,
  `7f07897`; iOS builds, no test-target reach (BuildPage-only); DEVICE eye owed). Paul: "sometimes, early in the
  session, a play ferry selector is selected on a populated play ferry but the part grid isn't visible." **ROOT
  CAUSE, traced not guessed:** `buildActiveFerry` (`@State`, default `0`) and `roomsRoom` (`@State`, default
  `.select`) are INDEPENDENT defaults, both set before any document is known — `.onAppear` runs on these raw
  defaults immediately. The REAL ferry content only arrives later, via `buildPersistTick()`'s per-poll `consume`
  pattern → `buildRestorePlayGrid`, which wrote `buildFerryParts` from the saved doc but never re-checked whether
  the now-known-populated default-active ferry (0) should ALSO flip `roomsRoom` to `.part` — so a saved session
  with ferry 0 populated left `roomsRoom` stuck on its hardcoded `.select` launch default while the selector
  correctly showed ferry 0 as selected+populated: exactly the reported symptom. Explains both qualifiers Paul gave
  unprompted: "sometimes" (only visible when the default-active ferry actually has content), "early in the
  session" (only until the user's first manual ferry/room tap re-syncs both together via the normal interactive
  path, masking it for the rest of the session). **FIX:** once `buildFerryParts` is restored, re-activate whichever
  ferry is marked active via the EXISTING `buildActivateFerry(t, navigate: true)` — the same function every
  interactive ferry-select already goes through, reusing proven logic rather than hand-rolling a parallel sync.
  `buildActiveFerry` is set to `nil` immediately before the call so the function takes its "nothing was previously
  active" branch — **a hazard caught by reading the function's branch order before writing the fix, not assumed:**
  calling it naively (`t == buildActiveFerry`, true in this exact scenario) would hit the "re-tapping" branch,
  which captures the BENCH into `buildFerryParts[t]` BEFORE loading — exactly backwards immediately after a
  restore, since the bench is stale pre-load content and `buildFerryParts[t]` now holds the just-restored real
  data; calling it directly would have silently clobbered the restore with blank bench content. For a genuinely
  empty default-active ferry the fix resolves to byte-identical behaviour (`roomsRoom` stays `.select`, matching
  today) — only a populated one changes anything. Checked the sibling `buildRestoreScenes`/`buildRestoreScene`
  path for the same bug class — out of scope, it only carries ROW 8 state, no ferry/room interaction at all.
  **DEVICE-OWED:** a saved session with a populated ferry 0 (or whichever ferry was active at save time) now opens
  straight to the PART grid showing that ferry's real content, not SELECT; confirm no brief visible flash of the
  wrong room during the sub-second gap between `.onAppear` and the first persist-tick (a minor, likely-imperceptible
  timing nuance flagged here rather than silently assumed away, not something this fix tries to eliminate).**
- **▶ EUCLID COMET BAR — hidden entirely when the playhead isn't running, not frozen in place (2026-10-02, on
  `main`; iOS builds, no test-target reach (GridUI-only); DEVICE eye owed). Paul: "Don't show the playhead
  comets when the playhead isn't running." ROOT STATE: `euclidCometBar`'s `TimelineView` already paused when
  `!clockPlaying`, but pausing a TimelineView only stops `tl.date` advancing — it doesn't hide anything already
  drawn. So the comet trail + glowing head, and every hit node's age-based recede/burst flare, kept rendering at
  whatever `phase` they'd last computed the instant playback stopped — a motionless comet (and potentially a
  hit dot frozen mid-flash) sitting on screen indefinitely, not disappearing. **FIX:** both the comet trail/head
  draw and the per-hit age/recede/burst flare block are now wrapped in `if clockPlaying { ... }`; the `else`
  branch for a hit node draws one steady, unflared dot (`tint.opacity(0.5)`, no shadow/glow filter, the flare
  formula's own floor value) instead of a stale frozen flash — REST dots are untouched (already static,
  nothing to gate). Scoped to exactly the comet + its reactive flare — the static K-of-N hit/rest pattern
  itself stays fully visible and editable while stopped, only the LIVE-playhead-driven elements disappear.
  UI-only (GridUI.swift), no test-target reach, matching every prior comet-bar change in this file.
  **DEVICE-OWED:** confirm the comet/flare genuinely vanish on transport stop rather than freezing, and that
  resuming playback brings them back cleanly (no stale state left over from the stopped frame).**
- **▶ EUCLID COMET BAR — the rotate-drag direction was backwards (FWD/PING-PONG), fixed dir-aware (2026-10-02, on
  `main`; iOS builds, no test-target reach (GridUI-only); DEVICE ear/eye owed). Paul, on-device: "I grab a dot and
  drag one space to the left, but there's some kind of mismatch... the lit note doesn't move along with my
  gesture, instead it jumps somewhere else." Traced, not guessed — worked a concrete E(3,8) example by hand
  before touching code. ROOT CAUSE: `euclidPatternInto`'s `rotation` is `buf[i] = test((i+rot) % n)`, a true
  cyclic shift where INCREASING `rot` moves every hit LEFT by one screen slot (confirmed: rot=0 hits {0,3,6} →
  rot=1 hits {2,5,7} — each exactly one slot left, 0 wrapping to 7). The pan gesture's `d` carries the SAME sign
  as the raw finger translation (negative when dragging left) and was applied as `rotate + d` (`euclidRow`'s
  `onRotateDelta`/`onAllRotateDelta`) — so dragging left DECREASED rotate, which shifts the pattern RIGHT:
  backwards from the finger, exactly the reported symptom (and explains "jumps somewhere else" rather than just
  "doesn't move" — Euclidean spacing means a wrong-direction shift doesn't look like a small nudge). **FIX is
  DIRECTION-AWARE, not a blanket sign flip:** re-derived the SAME relationship for BKW (whose `euclidReadIndex`
  mirrors the read: screen position i shows buffer index n−1−i) and found it's the OPPOSITE — increasing `rot`
  moves a tracked hit RIGHT by one screen slot under BKW (verified by tracking one specific base-hit index
  through the mirrored formula, not just eyeballing the resulting sets, which the first pass did WRONG — matching
  unordered sets `{1,4,7}`→`{0,2,5}` by position looked inconsistent until each hit was tracked individually by
  identity, which showed a clean uniform +1 every time). So the fix branches on `directionResolved`: BKW keeps
  the ORIGINAL `rotate + d` (already correct there); FWD takes `rotate - d` (the flip). PING-PONG rides the FWD
  branch — its comet bar already reads the buffer identically to FWD for i in 0..<n (its own disclosed
  simplification, shown only the ascending half). Scoped to the rotate axis only — the vertical HITS delta
  already correctly compensates for screen-y-is-inverted (`-t.y`), and isn't a positional-shift parameter, so it
  has no direction-dependent sign question the way rotate does; PINCH/STEPS likewise untouched. **DEVICE-OWED:**
  confirm a 1-finger left-drag now visibly follows the finger left (wrapping at the edge) in FWD/PING-PONG, and
  separately that BKW's drag still feels right now that it's the one branch left unchanged from before.**
- **▶ EUCLID PANEL — layout fix: GeometryReader column split, 44pt touch targets, DIRECTION stacked, detail
  panel scrolls (2026-10-01, on `main`; macOS 1165 green (no test-target reach — GridUI-only), iOS builds;
  DEVICE eye owed — this pass fixes what a device screenshot showed, but was itself built and verified off-
  device, no new screenshot in hand). A "FERRY FRAGMENT" spec (relayed via the Claude↔Claude design channel,
  Paul's device screenshot of the EUCLID panel open on T24N) reported 4 concrete bugs in the Stage 3/4 redesign
  shipped the same day: the lane-detail column (LANE n/GATE/OCTAVE/DIRECTION) squeezed and truncating ("F… B…
  P…", "T…"); lane 1's selection outline running UNDER the detail column with the "LANE 1" label sitting on top
  of it; the detail column's content clipping at the bottom. **ROOT CAUSE:** the detail panel was a FIXED
  150pt-wide `.frame(width: 150)` sibling of a FLEXIBLE `.frame(maxWidth: .infinity)` lane column — implicit
  sizing with no guarantee the two could never visually collide, and 150pt was never actually wide enough for a
  3-way `seg(["FWD","BKW","PING-PONG"])` or the 5-chip NOTE SELECT row once real panel width was accounted for.
  Separately, the panel's content was forced into an EXACT height (`euclidLaneH*4+gap*3` = 248pt) it was always
  going to be taller than (NOTE row + conditional DIE + 3 `field`s + the INVERT pill), so it clipped regardless
  of width. **FIX:** `case .euclid:`'s HStack is now wrapped in a `GeometryReader` that measures the REAL panel
  width once and splits it explicitly — lanes get ~2/3, the detail panel gets the "freed third" — as exact
  complements of the same total minus the gutter, so the two literally cannot overlap by construction (not by
  hope). `euclidRow`/`euclidSettingsPanel` both now take an explicit `width:` parameter instead of relying on
  `.frame(maxWidth:/width:)` sizing applied from outside. DIRECTION moved from `seg` (one row of 3 — the thing
  that was truncating "PING-PONG") to `segV` (full-width stacked buttons — can't truncate regardless of column
  width, satisfying the spec's own "stack... do not ellipsize" instruction literally). The NOTE SELECT chip
  Text gained `.fixedSize(horizontal: true, vertical: false)` so "TOP" can't ellipsize either. The settings
  panel's content now lives inside a `ScrollView` whose OUTER frame is still pinned to the lane stack's exact
  height (so the two columns still height-match) — content that doesn't fit now SCROLLS inside that fixed box
  instead of clipping, per the spec's own §C. PLAY/STOP + SELECT buttons grew 34→44pt (the HIG touch-target
  floor the spec named explicitly), absorbing the per-button padding slack that existed at 34pt — explicitly
  SCOPED to the lane row's own controls, NOT the detail column's internal fields (GATE/OCTAVE/INVERT kept their
  existing sizes — the spec's own "OUT OF SCOPE: leave the current controls as they are, only make them fit"
  line was read literally, so only DIRECTION's truncation and the NOTE SELECT chip's truncation were touched
  inside the detail column, nothing resized there for touch-target reasons). **SPACE RECOVERED, honestly
  reported (not fabricated):** this is a REALLOCATION, not a net gain — no slack was freed on either axis.
  WIDTH: the detail column's share grew from a flat 150pt to `(panelWidth−12)/3`, and the lane column gave up
  the exact same amount it had been getting via `maxWidth: .infinity` — a transfer between the two columns, not
  new space from nowhere (the real pt figures depend on the host's actual panel width, which this codebase has
  no fixed constant for and I have no device reading of). HEIGHT: `euclidLaneH` (56) and the panel's total
  forced height (248) are BOTH unchanged — the 10pt of per-button vertical slack that existed at 34pt (5pt above
  + 5pt below inside the row's 44pt inner content area) is now fully absorbed by the 44pt buttons; zero pt left
  over on either count. **NO engine change, no identifier renames** — GridUI.swift only, matching the spec's own
  scope line. **DEVICE-OWED, honestly flagged (I have no device/screenshot capability — this is the limit of
  what could be verified off-device):** whether the 2:1 width split actually reads as uncramped at real panel
  width; whether `segV`'s 3 stacked DIRECTION buttons feel right vertically versus the old single row; whether
  the settings panel's scroll is needed/visible at typical content (NOTE SELECT without DIE showing, vs. with
  DIE+CYCLE/RANDOM showing); confirm no residual overlap at any of the 4 lane selections, exactly per the
  spec's own acceptance criteria.**
- **This section is the BACKWARD log (what landed, with commit refs). `Docs/pending-tasks.md` is the FORWARD
  checklist (what's open). Keep both current as work lands — tick pending-tasks + add a commit line here — and
  keep them from overlapping.**
- **▶ COG — a LEFT/RIGHT ORIENTATION toggle for the rooms workbench, new default LEFT (2026-10-01, on `main`,
  `f31c528`; iOS builds, macOS 1160 unaffected; DEVICE eye owed on the whole flip). Paul: a cog feature to switch
  the workbench's left/right handedness, with the machine column/receivers/emitters moving to the LEFT as the NEW
  default, the part grid's row rails swapping sides, and the machine-box's trash/verb-button flank swapping too.
  **PERSISTENCE:** `roomsLeftOriented` — a NEW `@AppStorage("midispark.roomsLeftOriented")` Bool, default `true` —
  the SAME persistence class as the existing `showScenes` (a device-wide DISPLAY preference, not a PluginState/
  document field, since handedness is about the user's own setup, not any one project). Since `DiagView` (the one
  giant SwiftUI View struct `RoomsPage.swift`/`BuildPage.swift` are both `extension` of) already owns `showScenes`
  as a stored property, every `roomsXxx`/`buildXxx` function across both files reads `roomsLeftOriented` DIRECTLY —
  no parameter threading needed anywhere except `CogPage` (a genuinely separate View struct, wired the same way
  `showScenes` already was: `@Binding`, passed from the one construction site in AudioUnitViewController.swift).
  **THREE THINGS FLIP TOGETHER:** ① `RoomsPage.roomsWorkbench` — the page-level HStack's two children (the active
  GRID, 2/3, and the MACHINE BOX, 1/3) swap which side they render on; widths unchanged, only position. ② `BuildPage.
  roomsMachineStrip` — the machine box's two flanks swap: the verb-button cluster (LIBRARY/MUTATE/RANDOMIZE/CLEAR)
  moves to wherever the trash/row-rail lived, and vice versa, in BOTH the populated and the faded-empty-row
  branches (factored each flank + the centre chain block into local `let` bindings so the if/else just reorders
  three names, rather than duplicating the actual view construction). `buildProcBox`'s drag-to-delete hit-test
  (`drag.location.x < -6` for "is the finger over the trash") now branches on orientation — the classic check stays,
  the new-default check reads the OPPOSITE edge (`> w·2+gap+6`, the exact `blockW` formula the 2026-09-28 LEFT-
  machine-column experiment used for the same purpose). ③ `BuildPage.roomsPartGrid` — the part grid's two side
  rails swap: the NUMBERED rail (part-position selector / copy source) moves to the LEFT under the new default, the
  CHEVRON rail (row-select for playback) to the RIGHT — extracted both rails + the whole interior grid/playhead/
  gesture block into `let chevronRail`/`numberedRail`/`interior` bindings for the same reason. **TERMINOLOGY
  RESOLVED BY DIRECTION, not by guessing a label:** Paul named the two part-grid rails "row selectors" (→ LEFT) and
  "line selector" (→ RIGHT) without naming which rail is which — rather than risk picking the wrong mapping, used
  his own unambiguous meta-instruction ("the opposite to how it is now") as the authority: main's CURRENT
  arrangement is chevron-LEFT/numbered-RIGHT, so the only swap consistent with "opposite" is chevron→RIGHT/
  numbered→LEFT, regardless of which name belongs to which rail. **DELIBERATELY NOT TOUCHED, flagged not silently
  dropped:** `buildChainFlowOverlay`'s two velocity circles stay LEFT=input/RIGHT=output in BOTH orientations.
  Making them follow the trash/row-rail flank (so the row-rail's existing "sized to match the input circle"
  pairing — `buttonWidth: 6 * inCircleR` — kept visually rhyming) would need the chain's own internal entry/exit
  corners (`buildChainFlowLine`, always top-left→bottom-right, independent of which flank holds the trash) to flip
  too — traced the connector-line geometry by hand before deciding this was a bigger, genuinely different change
  Paul never asked for, not a one-line follow-on. Known, disclosed consequence: the row-rail/input-circle visual
  pairing only holds in the CLASSIC orientation; under the new default it's just two unrelated adjacent elements.
  **UI (cog page):** a new LEFT|RIGHT segmented control (`leftRightToggle`, DISPLAY section, beside SCENES) — not
  the existing bare `onOffToggle`, since ON/OFF wouldn't say WHICH side is active at a glance. **DEVICE-OWED:** the
  whole flip in both rooms (SELECT and PART), the drag-to-trash hit-test at the new edge, and whether the lost
  row-rail/input-circle pairing reads as a problem worth a follow-up fix.**
- **▶ EUCLID REDESIGN — Stage 3/4: PLAY/SELECT lanes + a side settings panel with GATE/OCTAVE/3-way DIRECTION
  (2026-10-01, on `main`; macOS 1165 green incl. 9 new, iOS builds; DEVICE eye/ear owed on the whole layout +
  feel). Paul, after the gesture/HUD/note-select trims above: "Lose the existing controls for count, hits, offset
  as this can be handled with the gestures and overlay. When the user first opens the processor I want them to
  see the four lanes stacked on[e] of the other, with selector buttons on the left for play/stop and select/
  settings button to the left of each lane. At an equal height to the four lanes combined, on the right side, I
  want a panel showing the settings for the selected row. The controls in here include note (moved from its
  original position), length (or gate), Oct+-, direction (fwd, bkw, ping pong), invert (instead of the current
  option)." Flagged back which pieces were pure relocation vs genuinely new engine work (GATE/OCTAVE/PING-PONG)
  and that PLAY/STOP = mute/enable was a working assumption; Paul: "Yes please, go ahead on that basis."
  **STAGE 3 (model/engine), `AUExtension/Models.swift`/`SnapshotBuilder.swift`/`Derivations.swift`/`Router.swift`:**
  four new additive-Optional `EuclidLine` fields (CR-8 safe — an old doc without them decodes fine) — `gate:
  Double?` (nil⇒0.9, today's hardcoded value), `octave: Int?` (nil⇒0, clamped ±3 — UTILITY/ARP's own `note +
  12×shift` convention, reused not reinvented), `direction: EuclidDir?` (nil⇒derive from the legacy `reverse`
  bool), `enabled: Bool?` (nil⇒true). **DIRECTION is a real engine change:** new dedicated `EuclidDir` enum
  (FWD·BKW·PING-PONG — a SEPARATE type from RIFF's own `RiffDir`, since EUCLID needs only 3 of its 6 cases and
  RiffDir's persisted-string-vs-display-label mismatch is a RIFF-specific legacy quirk that wouldn't fit here).
  `euclidReadIndex` generalized from a binary `reverse: Bool` to `dir: EuclidDir` + a new sibling `euclidCycleLen`
  (FWD/BKW repeat every N ticks, unchanged; PING-PONG repeats every 2N — it must bounce out and back before
  repeating). PING-PONG reuses RIFF's own `.pingpong` shape (period 2n, each endpoint sounding on two consecutive
  ticks) — confirmed as the specific RIFF case to mirror, not `.pendulum` (period 2(n−1), never repeats an
  endpoint). **The CYCLE/RANDOM pick ordinal math generalizes for free, not as a special case:** looping the
  hit-count (`effHits`) and the `hitsUpTo` lookback over the FULL `cycleLen` (not just `n`) naturally double-counts
  a ping-pong's repeated endpoints the same way the real read-sequence does — verified by hand before shipping,
  not assumed. `strikeChord` gained an additive `octave: Int = 0` parameter (every one of its ~15 existing call
  sites omits it, byte-identical); its note-building line is now `sn.note + transpose + 12*octave` before the
  existing 0...127 guard. `runEuclidLine` threads `gate`/`octave`/`dir` through to both `strikeChord` calls (the
  column-boundary safety clamp loosened 0.9→0.95 so an aggressive GATE still can't bleed past its own column) and
  the render loop's guard became `where L.pulses > 0 && L.enabledResolved` — PLAY/STOP gates emission ONLY, never
  touching pulses/steps/rotate, so re-enabling a lane resumes EXACTLY the pattern it had before (deliberately NOT
  built on repurposing pulses=0, which would have silently discarded the authored hit count — the exact regression
  class the Stage-1 POOL/padding-row fix already had to catch once). **TWO TEST BUGS CAUGHT BY THE SUITE, not
  guessed, both traced with a throwaway RTCDEBUG print per this project's own standing technique:** (1) a PING-PONG
  lap genuinely needs MORE real time than this test harness's default single-column lifespan (S=2 beats) supplies
  — `run()`'s own `forceColumn: 0` (PLAY: THIS CELL) is the existing, documented bypass for exactly this, used for
  the first time in a EUCLID test; (2) forcing the column also lets the window-granularity scan run slightly PAST
  the exact lap boundary, picking up the next lap's first tick — fixed by filtering onset steps to the exact tick
  range under test rather than comparing raw totals; (3) the OCTAVE out-of-range test's first draft tried `octave:
  6` expecting silence, forgetting the field itself clamps to ±3 at resolve (SAME clamp UTILITY/ARP already use) —
  fixed to reach the real 0...127 note clamp via a high source note (110 + 12×3 = 146) instead. +2 DerivationsTests
  (3-way `euclidReadIndex`/`euclidCycleLen`, incl. a worked ping-pong hit-sequence example) +4 RouterTests (PING-
  PONG doubles hits over a full lap, hand-verified against the exact ascending+mirrored-descending step list; GATE
  changes note length audibly; OCTAVE shifts by exactly 12×shift and clamps out-of-range to silence; `enabled:
  false` silences WITHOUT touching the pattern underneath — re-enabling resumes identically). **STAGE 4 (UI),
  `AUExtension/GridUI.swift`:** `euclidRow` rebuilt — a lane is now just a PLAY/STOP icon button (flips
  play.fill/stop.fill, toggles `enabled`) + a SELECT number chip (opens that lane in the panel) + the comet bar at
  full width; the OLD inline HITS/OF/ROTATE/FWD-REV/INVERT/NOTE-SELECT controls are GONE from the row — Paul's own
  framing ("this can be handled with the gestures and overlay") — the comet bar's existing gesture pad (1-finger
  drag/2-finger drag/pinch, shipped earlier the same day) is UNCHANGED and still the way to reshape hits/steps/
  rotate. New `euclidSettingsPanel(_:idx:)` shows whichever lane `@State euclidSelectedLane` points at: NOTE
  (the existing chip row + conditional DIE, moved verbatim) · GATE (a slider) · OCTAVE (a numPair, −3…+3) ·
  DIRECTION (a 3-way `seg` FWD/BKW/PING-PONG) · INVERT (the existing tap-pill, relocated). New `euclidLaneH`
  constant (56, computed exactly from a 34pt button + a 44pt comet bar + 6pt padding, not eyeballed) sizes BOTH
  every lane's own frame AND the panel's total height (`euclidLaneH*4 + gap*3`, forced via `.frame(height:)` with
  a trailing Spacer absorbing any slack) — the SAME "two columns can't drift apart" guarantee ARP's own PATTERN/
  SPEED height-matched pair already established as this file's convention. The comet bar's own `reverse: Bool`
  param is now `dir: EuclidDir` throughout; PING-PONG's static per-node display is a disclosed, flagged
  simplification (shows only the ascending half, like BKW already shows a mirrored-but-still-single-pass view) —
  the comet's own continuous sweep motion is unaffected either way, matching the existing "always travels left→
  right regardless of direction" design choice this same bar already committed to for BKW. `HITS FROM` and the
  GRID/SPAN footer stay exactly where they were — machine-wide, not per-lane, never mentioned for relocation.
  **DEVICE-OWED:** the whole new layout at real panel width (a 150pt-wide settings panel is a first-pass guess,
  untested against real text wrapping); the panel's height genuinely lining up against the 4-lane stack; PLAY/
  STOP correctly muting/restoring a lane's pattern; GATE/OCTAVE/PING-PONG's audible feel; the SELECT chip's
  highlight reading clearly against the comet bar's own glow.**
- **▶ EUCLID COMET BAR — a drag HUD (steps/hits/offset, arrow-bordered, floats above the grid) + pinch-to-resize
  steps (2026-10-01, on `main`; iOS builds; DEVICE eye/feel owed — gesture interplay is genuinely untestable off-
  device). Paul: "On drag, I want something to appear above listing the steps, hits and offset, clear enough that
  it's not obscured by the user's finger (maybe sitting above the grid). It will have small up/down/left/right
  arrows bordering it to make it clear that gestures work. Change the pinch gesture to add remove steps."
  **THE HUD:** new `@State private var euclidActiveDragRow: Int?` on `ProcessorBox` — the SAME idea as the
  existing `laneReadout` (idea 18, "the value floating while a lane bar is dragged"), just scoped to WHICH row's
  gesture is live (nil = none; 0…3 = that row; -1 = the 2-finger "every row" edit) rather than carrying a value
  itself — `euclidDragHUD(_:)` reads the CURRENT steps/hits/rotate straight off the same `rows` array `euclidRow`
  is already drawing from, so it can't show a stale number lagging the gesture. **POSITIONED ABOVE THE WHOLE
  4-ROW STACK**, not per-row (`.overlay(alignment: .top) { euclidDragHUD(rows).offset(y: -58) }` on the row
  VStack) — deliberately NOT anchored to whichever row is touched, so it sits in ONE consistent, finger-clear spot
  regardless of which of the 4 rows is being dragged, matching Paul's own "maybe sitting above the grid" steer.
  Four small arrow glyphs (▲▼◀▶) border the card on all 4 sides via `.overlay(alignment:)`, doubling as a visual
  reminder of what the gestures do (not just decoration). **PINCH → STEPS:** a `UIPinchGestureRecognizer` added
  to the SAME `EuclidGesturePad` view alongside the existing pan recognizer — spread = add steps, pinch-in =
  remove, routed through the EXACT same `onStepsDelta` the +/- tap glyphs already use (kept, not replaced — pinch
  is an additional way in, not a swap). Scale is converted to discrete integer steps LOGARITHMICALLY
  (`log(scale)/log(1.15)`, ~15%/step) rather than linearly, so pinching in and spreading out feel symmetric — a
  linear mapping would weight the two directions unevenly. **A REAL CRASH CAUGHT BEFORE SHIPPING, not after:**
  `UIPinchGestureRecognizer.scale` can approach 0 if both touches land on nearly the same point; `log(0) =
  -infinity`, and converting a non-finite Double to `Int` TRAPS in Swift — caught by reasoning through the edge
  case before testing, not by a crash log; fixed with `log(max(0.05, g.scale))`. **GESTURE COEXISTENCE:** pan
  (1-2 finger drag) and pinch now share one view — both recognizers get a delegate returning `true` from
  `shouldRecognizeSimultaneously`, lifting UIKit's own default "one gesture at a time per view" restriction. Not
  expected to conflict in practice (a genuine pinch has near-zero net translation; a 2-finger pan has near-zero
  scale change — the two gestures measure nearly orthogonal things) but this is reasoning, not a device-confirmed
  fact. UI-only (GridUI.swift), no test-target reach. **DEVICE-OWED, and this is the area most resistant to
  verification by reading code — real multi-touch arbitration only shows itself on a touchscreen:** whether pan
  and pinch genuinely coexist without one swallowing the other's touches; the HUD's exact vertical offset (-58pt)
  against the REAL surrounding panel chrome — it may overlap something above the EUCLID editor that isn't visible
  from the code alone, or get clipped if an enclosing container clips its own bounds; the pinch sensitivity
  (~15%/step) and pan sensitivity (~18pt/step) feel; confirm the HUD reads clearly as "LANE N" vs "ALL LANES" for
  the two drag modes.**
- **▶ EUCLID NOTE SELECT — trimmed to 1·2·3·4·TOP, one row instead of two (2026-10-01, on `main`; iOS builds;
  DEVICE eye owed). Paul: "Change the note control to only display 1, 2, 3, 4 and top." Was all 15
  `EuclidNoteSel` cases (ALL·N1…N8·LOW·HIGH·BOT2·TOP2·CYCLE·RANDOM) spread over two chip rows; now a single row of
  5 — `N1…N4` (labelled bare "1"…"4", not "N1"…"N4" — Paul's own wording) and `HIGH` (relabelled "TOP" for this
  control specifically — same case, same engine behaviour, just Paul's preferred word for it). The full enum is
  UNTOUCHED underneath (`euclidNoteSelShown` is a new, separate display-order list; nothing was removed from
  `EuclidNoteSel` itself) — an old doc already using ALL/N5…N8/LOW/BOT2/TOP2/CYCLE/RANDOM still resolves and plays
  exactly as before, it just won't highlight any of these 5 chips (an honest "none of these," not a wrong guess).
  **A GAP CAUGHT BEFORE SHIPPING, not after:** the EUCLID storefront card (same day) defaults a fresh row 0 to
  `euclidPick = .low` — `.low` isn't one of the 5 shown, so a brand-new EUCLID would have opened with NOTHING
  highlighted, reading as broken. Fixed in the chip row's own "is this selected" check (not by changing the
  default): `.low` and `.n1` resolve to the IDENTICAL pool rank (both strike index 0 — confirmed by re-reading
  `arpPick`'s fold, not assumed), so the row now treats `cur == .low` as matching the "1" chip — a freshly-created
  EUCLID now correctly shows "1" highlighted, with zero change to what's actually heard. The now-unused
  `noteSelCases` local (`euclidRow`) and the dead 9/6-slice comment were removed. The now-orphaned DIE control
  (only shown for CYCLE/RANDOM, neither reachable via these 5 chips anymore) is left as-is — still correctly shows
  for an OLD doc that has CYCLE/RANDOM set, just not reachable from a fresh pick. UI-only (GridUI.swift), no
  test-target reach. **DEVICE-OWED:** the single-row layout at real panel width with 5 chips instead of 2 rows of
  9+6 (likely reads calmer, worth confirming); the "1" chip correctly lighting for a freshly-created row.**
- **▶ EUCLID COMET BAR — gesture controls: 1-finger drag (this row) / 2-finger drag (all rows) / tap STEPS ±
  (2026-10-01, on `main`; iOS builds; DEVICE eye/feel owed — genuinely untestable off-device). Paul: "Left/right
  drag will move the offset. Up/down will increase or decrease the hits. A thin plus sign is on the left and minus
  sign is on the right to increase/decrease steps. Two finger drag up changes all lanes' hits. Two finger drag
  left/right changes offset on all lanes." The bar goes from purely decorative (`allowsHitTesting(false)`) to
  genuinely interactive — a deliberate reversal of the earlier "must not look selectable" brief; Paul's own
  explicit ask this time, not a contradiction to flag. **THE CORE PROBLEM:** SwiftUI's native `DragGesture` reports
  POSITION but never TOUCH COUNT — there's no built-in way to tell a 1-finger drag from a 2-finger drag on the same
  gesture. Solved with a real `UIPanGestureRecognizer` (`minimumNumberOfTouches: 1, maximumNumberOfTouches: 2`)
  bridged in via a new `EuclidGesturePad: UIViewRepresentable` — `numberOfTouches` is read ONCE, at `.began`, and
  LATCHED for the rest of that gesture, so a finger lifting or landing mid-drag can't flip which mode (per-row vs
  all-rows) the drag is in partway through. `GridUI.swift` already imports UIKit (pre-existing, unrelated to this
  change) — no new import/seam concern. **LAYOUT:** the comet bar is now a `ZStack` — the existing (unchanged)
  `Canvas` drawing underneath, the new gesture pad INSET 14pt each side, and the thin `+`/`−` STEPS glyphs as a
  THIRD sibling drawn on top in that reserved margin — SwiftUI hit-tests top-down, so the small glyphs claim their
  own bounds before the pad underneath ever sees those touches; no explicit exclusion-zone logic needed. **THE
  MAPPING**, all delta-based (relative nudges, not absolute-set, so a fast repeated drag/tap keeps compounding
  naturally): 1-finger horizontal → `Δrotate` (wraps mod 16, matching the existing ROTATE dial's own range) on THIS
  row only (`euclidLineEdit4`); 1-finger vertical → `Δhits` (clamped `0…max(2,steps)`, mirroring the existing HITS
  numPair's own clamp) on this row; the `+`/`−` glyphs → `Δsteps` (clamped 2…16, pulling hits down if steps shrinks
  below it — the exact same rule the existing STEPS numPair callback already applies); 2-finger horizontal/vertical
  → the SAME two deltas via a new `euclidAllRowsEdit` (applies the shared delta to EVERY row, each still clamping
  against its OWN steps/pulses independently, so a shared nudge can't push one row somewhere a DIFFERENT row's
  range wouldn't allow). Sensitivity: ~18pt/step on both axes — a first-pass, tunable constant, deliberately
  coarser than `NumPair`'s own 14pt scrub since this bar is small and a resting finger covers a good fraction of
  it. UI-only (GridUI.swift), no test-target reach. **DEVICE-OWED, and this is the one area I genuinely cannot
  verify by reading code — gesture-recognizer behavior only shows itself on a real touchscreen:** whether
  `numberOfTouches` reads reliably at `.began` in practice (a fast 2-finger touch-down isn't always perfectly
  simultaneous at the OS level); whether the UIKit pan gesture conflicts with any ENCLOSING SwiftUI ScrollView's
  own pan-to-scroll (if the processor panel scrolls, a vertical drag starting on this bar might fight the page
  instead of adjusting hits — untested, a real risk this specific bridge pattern is known to hit); whether the
  14pt margin is actually wide enough to reliably hit the `+`/`−` glyphs without also triggering the pad underneath;
  the 18pt/step feel in the hand.**
- **▶ EUCLID COMET BAR — the rest marker made legible, a perceived-not-literal position bug (2026-10-01, on `main`;
  iOS builds; DEVICE eye owed, audio unchecked — Paul: "I can't currently check audio"). Paul, on-device: "the
  position of the notes move, not just switch on and off" when toggling HITS/REST. Re-traced the draw math
  end-to-end (not re-asserted blind a second time) — `x = xFor(i+0.5)` is computed from the loop index `i` and `n`
  alone; `invert` only ever changes whether a given `i` counts as `hit`, never `x`. So every step's HORIZONTAL
  POSITION is provably fixed regardless of invert. **THE ACTUAL CAUSE, best diagnosis without being able to see
  the device:** the rest marker was a tiny (5pt), 16%-opacity HOLLOW ring sitting next to a hit dot that's much
  bigger and, after the same-day "more dramatic" pass, glows/flashes/rings brightly — that size+opacity gulf means
  the "off" state barely registered as present at all. Toggling invert then LOOKS like a note vanishing from one
  spot and a different one appearing elsewhere (relocation), when it's actually the same fixed 8 (or N) slots
  re-lighting a different subset. **FIX:** the rest marker is now a plainly visible FILLED dot at the SAME base
  radius a resting (non-flaring) hit dot settles to (7pt, up from 5pt) at 22% white opacity (up from 16%, and
  filled rather than a thin stroked outline) — same shape family as a hit, just dim, so the fixed slot grid reads
  clearly as persistent structure regardless of which subset is lit. **HONESTLY FLAGGED:** this is a perception fix
  for the most plausible cause found by re-deriving the math, not a confirmed root-cause match against what's
  actually on screen — if the dots still read as relocating after this, the bug is somewhere I haven't found by
  code-reading alone and needs a fresh look (a device screenshot/recording would resolve this far faster than
  another round of static analysis). Audio correctness is explicitly UNVERIFIED this pass (Paul can't currently
  check it) — this fix only addresses the VISUAL legibility, not any claim about what's actually heard.
  **DEVICE-OWED:** confirm the rest/hit distinction now reads as "the same slot, different brightness" rather than
  "different notes," and separately (once audio can be checked) that INVERT audibly plays the complementary N−K
  steps, not something else.**
- **▶ EUCLID EDITOR — a more dramatic hit flash, HITS FROM moved to the bottom, half-height number steppers
  (2026-10-01, on `main`; iOS builds; DEVICE eye owed). Three quick device-driven polish asks on the same-day comet
  bar. **(1) "The hits should be brighter, with effects, and more dramatic when it hits":** the flare was one glow
  layer decaying over the SAME 1.5-step window as the lingering afterglow — bright enough to read, but no sense of
  IMPACT at the instant of the strike. Added a second, much SHORTER `burst` window (0.35 steps, independent of the
  existing `recede` afterglow) layered on top: the dot visibly SWELLS (3.5→8pt radius) at the strike, a hot WHITE
  flash core blooms at its center (fades within the same short window), and a thin ring expands outward from the
  dot — three effects stacked, all fast-decaying, so the strike reads as a distinct "hit" moment rather than just a
  brighter glow. The lingering `recede`-based glow (Stage 2) is untouched underneath — still there for the trailing
  afterglow, just no longer the ONLY thing marking a hit. **(2) "Move fixed/pool to the bottom":** the `HITS FROM`
  FIXED|POOL seg (GridUI.swift, `case .euclid:`) moved from above the 4 rows to below them, just before the shared
  GRID/SPAN footer — a machine-wide toggle reads better sitting with the row stack it affects than ahead of it.
  **(3) "Halve the height of the number selectors":** `NumPair` (the ◀▶ nudge-pair used for HITS/OF/ROTATE/DIE)
  gained an opt-in `compact: Bool = false` — halves its height (42pt→21pt, arrows+value box) and trims its font
  (17/16pt→12pt) so the smaller pill stays legible; every OTHER caller across the whole file is untouched (default
  false), since `NumPair` is shared by dozens of unrelated processor editors and a global resize would have been a
  far bigger change than asked. All 4 `numPair` calls inside `euclidRow` now pass `compact: true`; nothing else
  does. UI-only (GridUI.swift), no test-target reach. **DEVICE-OWED:** the new burst effect's timing/scale at real
  panel size (0.35-step decay, the white-core peak, the ring's reach — all first-pass, tunable); the half-height
  steppers' legibility and touch-target size now that the tap/drag-scrub hit area is half as tall.**
- **▶ EUCLID DEFAULT — a fresh card opens on a steady 4-of-4 low-note pulse, not 5-of-8/ALL (2026-09-30, on `main`;
  iOS builds; DEVICE eye/ear owed). Paul: "default the euclid page to play a 4 by 4 on a single low note, on the
  first lane, and no notes on the additional rows." The storefront "EUCLID" card (`BuildPage.swift`'s `C(...)`
  list) previously applied NO preset at all (`C("EUCLID", …, .euclid)`, no trailing closure) — a brand-new card
  opened on the struct's bare defaults (5 pulses of 8 steps, PICK=ALL), no real starting point. Now applies
  `{ $0.euclidPulses = 4; $0.euclidSteps = 4; $0.euclidPick = .low }`, matching the same `apply:` convention every
  sibling card already uses for a sensible default (e.g. TUTTI COIN/AVOID CLASHES). **Rows 1-3 silent for free** —
  nothing here touches `euclidLines`, so the existing `euclidLinesForEditing()` pad (Stage 1 of the 2026-09-30
  redesign) still derives row 0 from these 3 flat fields and pads rows 1-3 with `pulses: 0`, exactly the idle-row
  behaviour already shipped — no new code needed for "no notes on the additional rows." UI-only (BuildPage.swift),
  no test-target reach. **DEVICE-OWED:** a freshly dragged-in EUCLID actually strikes only the lowest held note,
  on every one of 4 steps, with rows 2-4 visibly empty/silent in the new 4-row editor.**
- **▶ ARP EDITOR — revised same day: sliders stacked, VELOCITY now absolute 1…100 (2026-09-30, on `main`, `288ce7e`;
  macOS 1160 green incl. 3 rewritten, iOS builds; DEVICE eye/ear owed). Direct follow-up to the layout landed earlier
  the same day. Paul: (1) stack LENGTH/VELOCITY/VELOCITY TILT on top of each other, instead of side-by-side; (2)
  VELOCITY should IGNORE the input note's own velocity and use only what the control specifies; (3) the slider
  should run 1…100, not the old 0…2 relative scale. **LAYOUT:** the three now share ONE HStack slot (was three)
  as a `VStack(spacing: 8)`, top-to-bottom in the order Paul named them — matching the OCTAVE/OCT DIR stack's own
  spacing for visual consistency within the same row. **RENAMED `arpVelScale`→`arpVelocity` throughout** (MachineParams,
  SnapParams, `AutoParamField` + its 4 exhaustive functions, `SnapshotBuilder`'s resolve, the `effective*` helper,
  `arpPick`'s own parameter across all 3 overloads, GridUI's 5 LFO-editor switches) — not just a range change but a
  vocabulary fix, since "scale" no longer described what the field does. **ENGINE:** `arpPick` no longer reads
  `pool.velocity(note)` at all — `velocity` (the resolved 1…100 control value) IS the note's entire base, with
  VELOCITY TILT still shaping it further by pool rank on top (unchanged — a fixed base instead of the old scaled-
  input one). **TEST FALLOUT, traced not guessed:** 3 pre-existing RouterTests asserted the very invariant Paul just
  asked to reverse for ARP ("VELOCITY INHERITANCE — every processor takes its output velocity from the input
  source," dated 2026-08-09) — before rewriting their expected values, traced the EXACT fold path for `[ARP →
  HARMONIZE]` (`Router.applyStage`'s `.harmonize` case reads the ONE-NOTE pool `emitDriverNote` seeds from the
  driver's OWN resolved `(note, velocity)`, never the original chord — confirmed by reading, not assumed) to derive
  the correct new expected value (100, the VELOCITY default) for BOTH the dry note and the harmony voice, rather
  than guessing. Renamed + rewrote `testArpInheritsSourceVelocity`→`testArpUsesVelocityControlIgnoringSource`,
  `testChainInheritsSourceVelocityThroughHarmonize`→`testChainUsesArpVelocityControlThroughHarmonize`,
  `testAuditionInheritsSourceVelocity`→`testAuditionUsesVelocityControlIgnoringSource`.
  `testEuclidGeneratorInheritsSourceVelocity` (a different generator, unaffected — Paul scoped this to ARP only) is
  untouched, still green, still asserting the old invariant for euclid. **INTEGRATION NOTE:** this branch's own
  single commit landed a SECOND time this session one commit behind `origin/main` — another worktree's "ARP OCT
  DIRECTION" commit (below) had, in the interim, changed the EXACT SAME formula line (`let oct = octDown ? … :
  octIdx`) this commit's own velocity code sits directly beneath in `arpPick` — a real rebase conflict (adjacent,
  not overlapping, lines), resolved by hand: kept their new oct-direction formula verbatim + this commit's new
  velocity code verbatim, rebuilt + retested green on the combined tree before pushing. **JUDGMENT CALL, flagged:**
  Paul said "1 to 100," read literally as the direct value (not a 1–100 MAPPED onto 0–127) — so a VELOCITY of 100 is
  the ceiling, not "full MIDI velocity" (127); if 127 was actually meant, that's a one-line range change.
  **DEVICE-OWED:** the stacked trio's legibility in one column, VELOCITY audibly ignoring how hard the chord was
  played and only tracking the dial, and the oct-direction + velocity changes not interacting oddly in the same
  render pass.**
- **▶ EUCLID COMET BAR — a REAL glow, not a stack of flat circles (2026-09-30, on `main`; iOS builds; DEVICE eye
  owed). Paul, on-device: "the timing on the animation is great, but it doesn't look as good as it did in the
  preview html. Maybe it's missing the glow?" Correct diagnosis. The Stage 2 build (this same day) approximated a
  glow by layering hard-edged circles of falling opacity underneath each lit element — reads as flat concentric
  rings, not a soft halo, because nothing was ever actually BLURRED; the HTML mockup's look came entirely from CSS
  `box-shadow`/`filter: blur()`, a genuine gaussian blur with no equivalent in the first Canvas draft. **FIX:**
  `euclidCometBar` (GridUI.swift) now uses `ctx.drawLayer { … }` + `GraphicsContext.Filter.shadow`/`.blur` — Canvas's
  real counterpart to CSS box-shadow/blur — for every glowing element: a hit node's flare is now one dot inside a
  `.shadow(color:radius:)`-filtered layer (radius scales with `recede`, the same decay factor as before) instead of
  a second flat circle drawn underneath; the comet's trailing tail is now a blurred (`.blur(radius:3)`) gradient
  stroke instead of discrete hard dots; the comet head itself sits inside its own `.shadow(radius:9)` layer for a
  true glowing halo instead of a plain filled circle. The underlying per-node recede/age math (Stage 2) is
  untouched — only HOW each element is painted changed, not when/how bright. UI-only (GridUI.swift), no test-target
  reach — builds clean, nothing to run off-device for a pure Canvas-drawing change. **DEVICE-OWED:** confirm the
  glow now reads as intended at real panel size/brightness — the shadow radii (3–9pt) and the blur amount are
  first-pass values, tunable if they read too soft/too sharp on the actual screen.**
- **▶ ARP OCT DIRECTION — REDEFINED: DOWN now descends BELOW the held keys, symmetric with UP (2026-09-30, on
  `main`; iOS builds, macOS green incl. 2 updated; DEVICE ear owed). Paul noticed DOWN starts a full octave (or
  more) ABOVE the held keys rather than at them, and asked whether starting AT the held keys and descending was
  practical. It was — and it's a deliberate BEHAVIOUR CHANGE, not an addition (Paul: "I'm currently the only user
  so I don't mind behaviour changes. Go for it."). **OLD semantics:** DOWN opened at the TOP octave (`octaves-1`)
  and came DOWN TO the held register — it never sounded anything BELOW the held keys, only reversed which octave
  each lap of the walk landed in. **NEW semantics, symmetric with UP:** lap 0 always opens AT the held register
  (`octIdx 0 ⇒ oct 0`) for BOTH directions; UP ascends from there (`oct = +octIdx`), DOWN now descends BELOW it
  (`oct = -octIdx`) — `arpPick`'s one-line formula (Derivations.swift) simplified from `octDown ? (max(1,octaves)-
  1-octIdx) : octIdx` to `octDown ? -octIdx : octIdx`. **RANGE SAFETY, checked not assumed:** `arpPick` itself only
  ever guards the UNSHIFTED note against 0…127 before applying the octave offset; the actually-shifted
  `note + 12*oct` is range-checked at every one of the 6 call sites in Router.swift (either directly, or via a
  downstream `base + transpose` check the arp/hold/strum paths already share) — the EXACT same mechanism that
  already silently drops a note UP pushes above 127 now equally drops one DOWN pushes below 0, so going negative
  needed no new guard anywhere. +0 new tests — 2 EXISTING `DerivationsTests` updated to the new expected values
  (`testArpOctDirectionInvertsTheLaps`, `testArpOctaveSpanFullSequence`) rather than left asserting the old
  behaviour. **DEVICE-OWED:** an ARP with OCT DIR=DOWN and 2+ octaves actually sounds the held chord first, then
  descends into the register below it, rather than opening high.**
- **▶ ARP EDITOR — a full layout rework + two new fields, VELOCITY + VELOCITY TILT (2026-09-30, on `main`, `67fb646`;
  macOS 1155 green, iOS builds; DEVICE eye/ear owed). Paul specified the new layout precisely: ARP PATTERN's options
  into two equally-sized rows, SPEED to its right at matching height; OCTAVE + OCT DIR stacked one over the other, to
  the right of ARP FLOW, matching FLOW's height; then LENGTH, VELOCITY, VELOCITY TILT to the right of that, equal
  height among themselves — with VELOCITY and VELOCITY TILT named as NEW features, both wanting a ∿ LFO.
  **LAYOUT:** the 10-entry `arpPatternOptions` table (UP/DOWN/UP-DN/ALT LO/ALT HI/AS PLAYED/RANDOM/RND HI/RAND LO/
  RANDOM ONCE) splits into two 5-chip rows via `arpPatternRow`, reworked to take an explicit SLICE instead of always
  the whole table (its `sel` highlight is now `Int?`, not `?? 0` — a pattern belonging to the OTHER row no longer
  wrongly lights this row's first chip, a real bug the split would otherwise have introduced). Height match against
  SPEED is EXACT ARITHMETIC, not eyeballed: 2 rows×48pt + 1×6pt gap = 102, same as `arpSpeedGrid`'s 3 rows×32pt +
  2×3pt gap = 102. OCTAVES/OCT DIR now stack in one VStack beside FLOW's existing 3-item `segV` (each keeps its own
  label). LENGTH/VELOCITY/VELOCITY TILT are three side-by-side fields, naturally equal height since all three share
  the identical `slider`/`lfoSlider` → `FineSlider` (fixed 30pt) content underneath. **NEW ENGINE FIELDS:** `arpVelScale`
  (0…2, default 1 — a flat multiplier on the picked note's own velocity) and `arpVelTilt` (−1…1, default 0 — favours
  the top (+) or bottom (−) of the held pool). No spec for either existed, so both were modeled on established
  precedent rather than invented from nothing: `arpVelScale` mirrors HARMONIZE's `harmVelScale` (a plain velocity-
  scale multiplier); `arpVelTilt` reuses `Derivations.strumVelocity` VERBATIM (the exact formula STRUM's own `velTilt`
  and CHANCE's `chanceTilt` already established as this codebase's tilt convention), keyed on `rank = pos % count` —
  the SAME ascending-pool-rank index `arpPick` already computes to fetch the note itself (captured once, reused for
  the tilt — no second pool scan). For every pattern except AS PLAYED, `rank` is a true pitch-ascending rank (0=lowest);
  AS PLAYED reads press-order instead (`srcPlayed`, not `srcAscending`), so its "tilt" is by play-order there — an
  honest, disclosed minor difference for that one mode, not a second code path. Threaded through all THREE `arpPick`
  overloads (chanMask-based impl, the `filter:` forwarder, the `for cell:` convenience forwarder) with defaults
  (1, 0) that reproduce the exact prior velocity byte-for-byte (verified: `clampVel` is idempotent on an
  already-legal 1…127 velocity, and `strumVelocity`'s tilt=0 scale is exactly 1). `emitArpRow` resolves both via new
  `effectiveArpVelScale`/`effectiveArpVelTilt` (Snapshot.swift, mirroring `effectiveGate`) and passes them to BOTH
  the chain-driver and standalone `arpPick` call sites. **LFO:** both fields joined `AutoParamField` (the ONE enum
  shared by the per-param ∿ LFO AND the older render-time span-automation) — `settingAuto`/`autoValue`/`unitRange`
  gained the two cases, which is ALSO what makes them span-automation-ramp-able for free, unasked but harmless (same
  shared-enum consequence every prior LFO addition to this enum has had). GridUI's 5-switch LFO-editor recipe
  (`lfoLabelText`/`lfoEndpointControl`/`lfoFmt`/`lfoSeedFrom`/`lfoSetBase`) got matching cases each — caught the
  `lfoSeedFrom`/`lfoSetBase` DEFAULT branches fall back to `p.gate` before writing these in, which would have silently
  seeded/written the WRONG param (GATE, not VELOCITY) had either case been skipped. **`bipolarSlider` gained LFO
  support** (a new optional `lfo target:` param, default nil) — the FIRST bipolar field in the app to get a ∿ button;
  nil renders byte-identical to before (confirmed: `lfoLabelRow`'s own no-lfo branch uses the exact same Text/font/
  opacity bipolarSlider inlined previously), so STRUM's VOL TILT and CHANCE's FAVOUR — the only other callers — are
  unaffected. **CAUGHT BY THE COMPILER, not hand-checked (this session's own standing pattern):** adding the 2
  `AutoParamField` cases broke 2 EXHAUSTIVE switches in `Tests/EffectiveParamsTests.swift` (the 28-key recognition
  list and the 28-entry clamp-bounds table, both bumped to 30) — fixed once the build surfaced them. **A genuine
  self-caught bug pre-push:** the first pass only updated TWO of the three `arpPick` overloads with the new params;
  the THIRD (the `for cell:` convenience one `emitArpRow`'s standalone branch actually calls) was left unchanged,
  which the iOS build failed on immediately (`extra argument 'for' in call` — Swift's overload resolution tried to
  match the call against a different candidate once the intended one no longer matched) — caught by the real
  compiler, not assumed fixed. **INTEGRATION NOTE:** built and committed on a branch that started one commit behind
  `origin/main` (another worktree had just landed EUCLID redesign Stage 1, `481cafe`, unrelated fields/files);
  rebased cleanly (no conflicts — different processor, disjoint field names), rebuilt + retested green on the
  combined tree before pushing, per the standing multi-worktree workflow. **JUDGMENT CALLS, flagged not silent:**
  VELOCITY's 0…2 range/percentage display and VELOCITY TILT's pool-rank tilt basis are this session's own design
  choices (Paul asked for the features + LFO, not their exact semantics) — modeled closely on existing conventions,
  but unverified against what Paul actually pictured; the OCTAVE+OCT DIR stack's height-match against ARP FLOW is a
  best-effort spacing choice, NOT provably exact arithmetic like the PATTERN/SPEED pair — SwiftUI's own per-label
  text-line-height isn't something to hand-derive from source, so this one is real device-eye-owed, not just
  routine caution. **DEVICE-OWED, the whole feature:** the layout at real panel width (5 side-by-side slots in row 2
  is the most cramped row this card has ever had), VELOCITY audibly scaling louder/softer, VELOCITY TILT audibly
  favouring top/bottom notes across a real chord, and both ∿ LFOs sweeping smoothly.**
- **▶ EUCLID REDESIGN — Stage 2 (the UI): four always-visible rows, DIRECTION seg, the merged NOTE SELECT chips, a
  live comet-bar (2026-09-30, on `main`; iOS builds, macOS 1160 green; DEVICE eye owed — no test-target reach,
  GridUI-only, same as every prior playhead/widget change in this file). Completes the redesign Stage 1 shipped
  the model/engine for — planned via a two-round HTML mockup with Paul before any code (comet trail chosen over
  two other candidates; the final row layout ratified in a second round). **THE EDITOR:** `case .euclid:`
  (GridUI.swift) rebuilt entire — the old "single euclid OR a dynamic +ADD LINE stack up to 8" branch is gone;
  `ForEach(p.euclidLinesForEditing().enumerated())` always renders exactly 4 row blocks (the SAME shared helper
  Stage 1's SnapshotBuilder resolve calls, so the editor and the render path can never derive "what the 4 rows
  are" differently). Each row: line 1 = `HITS ◀K▶ OF ◀N▶` · `ROTATE ↻r` · a new `FWD|REV` seg bound to `reverse` ·
  the existing INVERT tap-pill; line 2 = the merged NOTE SELECT (two `euclidNoteSelChipRow`s, sliced from
  `EuclidNoteSel.allCases`'s own declared order — ALL·N1…N8 on row 1, LOW·HIGH·BOT2·TOP2·CYCLE·RANDOM on row 2 — so
  there's no second, separately-maintained grouping list to drift from the enum) to the left, the new comet-bar to
  the right; DIE's dial (kept, not dropped, from the pre-merge editor) reappears inline only when the row's
  resolved noteSel is CYCLE/RANDOM. New `euclidLineEdit4(idx:)` replaces the old `euclidLineEdit` (deleted, no
  callers left) — it seeds/pads to 4 via `euclidLinesForEditing()` before writing, so touching ANY of the 4 rows
  "promotes" the machine to a real 4-line array on first edit, same idiom the old "+ ADD LINE" button used, just
  automatic. Footer keeps GRID (rate) + SPAN (shared machine-wide, unchanged); the footer's ROTATE slot (already
  conditionally hidden in LINES mode pre-redesign) is now unconditionally empty (rotate lives on every row's own
  line 1); the standalone "PICK — for ALL-target lines" row is gone, folded into the per-row selector. **THE COMET
  BAR:** a new non-interactive `euclidCometBar` (`TimelineView` + `Canvas`, ~30fps) — reuses `euclidPhase`/
  `euclidReadIndex` (Derivations.swift, Stage 1), the SAME pure functions the real render path calls for its own
  step math, so the bar can never silently disagree with what's actually heard the way RATCHET PATTERN/DEST once
  did. A glowing dot travels the pattern continuously; each hit node flares and holds a brief decaying afterglow as
  the dot passes; rests stay a plain hollow ring — reads as decoration, never as a tappable grid (per Paul's "I
  don't want this to look selectable"). **TWO DELIBERATE DEVIATIONS FROM THE LITERAL APPROVED MOCKUP, flagged
  plainly rather than silently changed:** (1) NOT swing-warped — the mockup obviously couldn't show this either
  way; matches every OTHER pattern-processor's live sweep in this exact file (BURST/RATCHET/TUTTI/DEST's
  `StateMatrixClock`/`liveCol` also read a plain linear beat, only the real render path applies `musicalOf`) —
  threading swing into this ONE new widget would need a new stored property on `ProcessorBox` for a discrepancy
  that only shows at non-50 swing settings; scoped out rather than half-built. (2) the comet's direction of travel:
  the mockup showed BOTH the displayed hit pattern mirroring AND the comet visually reversing to run right-to-left
  under REV; built instead so screen position always shows the i-th step in PLAYBACK order (`euclidReadIndex`
  resolves which buffer index that is) and the comet ALWAYS travels left-to-right — steadier, more legible, and
  actually reads as "impressive" (Paul's own word for the brief) rather than as a glitch, which a direction-
  reversing comet risked once actually animated rather than sketched in static HTML. **DEVICE-OWED:** whether
  deviation (2) reads right in practice — reverting to a direction-flipping comet is a small, contained change if
  Paul prefers the literal mockup once he sees the real animation; the chip legibility at real panel width (up to
  15 options across 2 rows); the comet bar's height/proportions next to a 2-row chip stack; the flare/afterglow
  timing constants (0.02 threshold, 1.5-step decay window — all tunable, unverified off-device); confirm an old
  saved doc (flat single-euclid, or a pre-redesign 2-8-line doc) opens showing its content correctly across the 4
  rows with no data loss for the first 4 lines.**
- **▶ RECEIVER TOGGLES + DOOR PICKERS — the note-name/key/"no input" text shrunk 15pt→11pt (2026-09-30, on `main`,
  `ad48901`; iOS builds; DEVICE eye owed). Paul: reduce the size of the text showing notes on the receiver toggles
  and related instances. That readout (`buildReceiverSelectChip`'s `big` label — key ?? live notes ?? "no input")
  was rendering at `buildIOSelectChip`'s shared 15pt: fine for a single letter, but a short live-note string
  ("c e g") rarely needs `minimumScaleFactor`'s shrink-to-fit to avoid clipping, so it rendered near the full
  nominal size and read as too dominant for a 2-3 char label. **FIX:** `buildIOSelectChip` gained a `textSize:
  CGFloat = 15` param — the receiver-chip call site passes 11; `buildEmitterToggles`' call (the MIDI-OUT bus-letter
  chips) passes nothing, keeping its plain "A/B/C/D" at the original 15 — Paul scoped this note-display feature to
  receivers specifically in an earlier session ("not the separate MIDI-OUT emitter toggles"), so I left emitter
  toggles untouched here too. Matched the same 11pt directly on `ioChip` (GridUI.swift) — the shared sibling that
  gives ECHO's FROM, CHORDS' SCALE FROM, and AVOID's WHICH INPUT the identical note-display styling per the
  2026-09-29 receiver-door-picker audit — since its own doc comment already commits to "keep the two visually in
  sync by hand if the shared look ever changes." UI-only (BuildPage.swift/GridUI.swift), no test-target reach.
  **DEVICE-OWED:** legibility of the smaller text at real chip size, both for a short note label and for a longer
  one like a key name ("D MIXOLYDIAN") still relying on the auto-shrink floor underneath the new, smaller base.**
- **▶ BUILD UNDO — structural chain edits now ALWAYS get their own step (2026-09-29, on `main`, `f49363b`; iOS
  builds, macOS 1155 green; DEVICE-owed — no test-target reach, UI-state bookkeeping only). Paul: "I added two
  processors to the MIDI chain, then hit undo and both disappeared. Every user touch action should have a
  corresponding undo/redo step." **ROOT CAUSE, traced not guessed:** `buildApplyChain` is the SINGLE funnel every
  chain mutation goes through — add/remove/move/type-change/bypass-toggle AND per-param slider drags alike — and it
  unconditionally called `buildRecordUndo("chain")`. That coalesce key exists so a FineSlider's dozens-per-second
  `onChanged` ticks collapse into one undo step (confirmed by reading `FineSlider`'s `DragGesture.onChanged` — it
  really does call `set(v)`, and therefore `buildApplyChain`, on every tick) — but the SAME blanket key was applied
  to genuinely discrete, one-shot actions too. So "add processor A" pushed a checkpoint and set `buildUndoKey =
  "chain"`; "add processor B" right after saw that key already active and silently skipped recording — both adds
  shared ONE undo step, and a single undo dropped both at once, exactly Paul's report. **FIX:** `buildApplyChain`/
  `buildChainEditSlot` now take an explicit `coalesce` override (default `"chain"`, preserving the param-drag
  path). The five DISCRETE call sites — `buildChainAddCard` (ADD), `buildChainRemoveSlot` (DELETE, both the editor
  button and drag-to-trash), `buildChainMoveSlot` (drag-to-reorder — confirmed fired only once, from `.onEnded`,
  never per drag-frame, so forcing it fresh can't explode the stack), `buildChainSetType`, `buildChainToggleBypass`
  — now pass `coalesce: nil`, which `buildRecordUndo` treats as "always push, no coalescing," regardless of what
  `buildUndoKey` currently holds. **ALSO:** added a 0.6s SLIDING TIME WINDOW to "chain" coalescing specifically —
  the generic param-mutate path (`onEdit`, used by sliders AND plain discrete taps like a segmented MODE picker
  alike, since nothing at that boundary can tell them apart) still shares one key, so two genuinely separate
  "chain" edits could still merge if nothing else intervened between them. Now a same-key coalesce only continues
  if the last one was < 0.6s ago (refreshed on every continuation, so a slow multi-second drag still stays one
  step throughout); a tap that lands well after a drag has clearly ended gets its own step. **DELIBERATELY SCOPED
  to "chain" only** — checked `buildRecvEdit`'s own doc comment first ("coalesced into one 'recv' burst so a run of
  config tweaks is a single undo," an explicit, documented design choice from 2026-08-27) and left "recv"/
  "randomize"/"mutate" on their original untimed behaviour, so a deliberate multi-tap MIDI-config session still
  collapses to one undo exactly as designed — a blanket time window would have silently broken that. Verified
  every `buildApplyChain`/`buildChainEditSlot` call site by grep (4 total) before and after, confirming none were
  missed and no other caller needed the same treatment. **RESIDUAL, flagged not fixed:** two truly discrete param
  taps on DIFFERENT controls within the same open editor, performed within 0.6s of each other, can still coalesce
  into one step — an accepted, narrow edge case (see the comment on `buildRecordUndo`), not the reported bug.
  DEVICE-OWED: confirm two back-to-back ADD/DELETE/REORDER/BYPASS actions each undo independently, and that a
  normal slider drag still collapses to one undo step (not one per tick).**
- **▶ EUCLID REDESIGN — Stage 1 (model/engine): TARGET+PICK merged into one NOTE SELECT field, DIRECTION (FWD/REV),
  always-exactly-4-lines (2026-09-30, on `main`; iOS builds, macOS 1160 green incl. 5 new). Paul asked to redesign
  the EUCLID editor UI — planned via a two-round HTML mockup (three hit-bar candidates, comet trail chosen; then the
  final row layout) before any code, per the plan at `~/.claude/plans/velvet-foraging-curry.md`. This is the
  model/engine half; the UI half (Stage 2 — the new row layout, the comet-bar widget, the merged chip selector) is
  still to come. **THE MERGE:** `EuclidLine.target` (0=ALL/1-8=N1…N8, which chord note a line fires from) and `.pick`
  (ALL/CYCLE/LOW/HIGH/RANDOM, only meaningful for TARGET=ALL) collapse into ONE new `EuclidNoteSel` (String-raw enum,
  ALL·N1…N8·LOW·HIGH·BOT2·TOP2·CYCLE·RANDOM — BOT2/TOP2 ported from the sibling EUCLID MASK's own `MaskChordPick`).
  `target`/`pick` are KEPT on `EuclidLine` for decode compatibility (never read by the render path again); a new
  `noteSel: EuclidNoteSel?` is additive-Optional (the same CR-8 reasoning already recorded for `die`). **BOT2/TOP2
  needed a real engine change** — `strikeChord(onlyIndex:)` only ever strikes one pool rank or the whole chord;
  `runEuclidLine` now resolves a `noteSel` to either an `onlyIndex: Int?` or a `(lo,hi)` range, calling `strikeChord`
  once per index in the range when one applies — mirroring EUCLID MASK's own `maskChordPickRange` loop rather than
  inventing a second mechanism. **DIRECTION (FWD/REV):** a new `reverse: Bool?` on `EuclidLine`. REV mirrors
  (time-reverses) the K-of-N pattern by flipping the READ INDEX into the already-ROTATE-baked buffer
  (`euclidReadIndex(step,n,reverse) = reverse ? n-1-step : step`), NOT by rebuilding the buffer with a second
  rotation — verified algebraically that rotate-then-reverse and reverse-then-rotate are NOT the same pattern in
  general (they differ by a shift of 2×rotate mod n, coinciding only at rotate=0 or n/2), so this is a deliberate,
  tested composition order, locked by a worked-example `DerivationsTest` rather than left to chance. Every buffer
  read in `runEuclidLine` — the hit/rest test AND the `hitsUpTo` ordinal loop CYCLE/RANDOM use for their walk
  position — goes through the same `euclidReadIndex`, so a reversed line's pick-walk stays correct in PLAYBACK
  order, not buffer-storage order. **ALWAYS EXACTLY FOUR LINES** (the fixed-4-row redesign, replacing "start with
  one euclid, tap +ADD LINE up to 8"): `SnapshotBuilder`'s old `.prefix(8)` clamp is gone — `MachineParams.
  euclidLinesForEditing()` (Models.swift, shared by SnapshotBuilder AND the eventual Stage-2 editor, so the two
  can't independently derive this differently) always returns exactly 4, deriving row 0 from the flat single-euclid
  fields when untouched (rows 1-3 silent, `pulses: 0`) or padding/truncating a touched `euclidLines` array to 4 —
  **a deliberate, disclosed consequence: any existing saved session that used 5-8 lines loses lines 5-8 permanently**
  (Paul: "fixed at four always visible rows, please" — named here plainly, not silently absorbed). Router.swift's
  `.euclid` case dropped its `euclidLines.isEmpty ? flat : lines` branch entirely — always `for L in p.euclidLines`.
  **A MIGRATION SUBTLETY caught before it shipped wrong:** a pre-redesign line with `pick == nil` fell back to the
  MACHINE-WIDE global `euclidPick` (the old "PICK — for ALL-target lines" row) — a fallback `EuclidLine.
  noteSelResolved` can't see on its own (it only knows its own fields). Fixed by resolving this WITH the full
  context inside `euclidLinesForEditing()` itself (which has `self.euclidPick`), not left to the narrower per-line
  computed property — regression-tested (`testEuclidLineWithoutItsOwnPickFallsBackToTheOldMachineWideGlobal`).
  **TWO REAL BUGS CAUGHT BY THE TEST SUITE, not by inspection — this session's own standing rule, twice over:**
  (1) a first draft tried to make the render path's step computation and the eventual Stage-2 UI comet-bar share
  ONE formula (`euclidPhase`, a continuous phase-in-[0,n) function) — mathematically proven equivalent to the
  original exact-integer step math for real-number arithmetic, but in FLOATING POINT the continuous version's extra
  divide+floor+multiply round-trip introduced a rare off-by-one at tick boundaries that the original integer-only
  path never had. Caught by `testEuclidPulsesFromPoolTracksHeldCount` (an existing test, not a new one) going 9→54
  note-ons — traced with a throwaway debug print rather than re-guessing by hand, per this project's own standing
  technique. Fixed by reverting `runEuclidLine`'s own step math to the original exact Int64 formula and keeping
  `euclidPhase` as a SEPARATE, UI-only function (Stage 2) — a discrete hit/rest decision needs exact integer ticks;
  a comet's visual position tolerates float imprecision invisibly, and the two shouldn't share a code path just
  because they share a CONCEPT (the same rate/span/anchor reading). (2) even after that revert, the SAME test still
  failed the same way — traced (again via a debug print, not guessing) to a genuine interaction the redesign
  introduced: `iterateTicks` dedups via a `lastTick[row]` scalar SHARED across every line on a row (safe for one
  real line; a pre-existing, undisclosed limitation for 2+ real lines sharing a row across a render-window boundary
  — not introduced here, just newly exercised). Running all 4 lines unconditionally under `HITS FROM: POOL` (which
  overrides EVERY line's K to the held-note count, ignoring each line's own authored `pulses`) turned the 3
  always-present silent padding rows into 3 MORE real, identical lines competing for that shared dedup state across
  the ~24 render windows a 2-beat test spans. Fixed by skipping any line with `pulses <= 0` entirely (`for L in
  p.euclidLines where L.pulses > 0`) — an unused fixed row now stays silent regardless of POOL, matching the
  approved mockup's own "row 4 — 0 hits, no comet" idle-state language, and keeps genuinely-authored multi-line
  polyrhythms (2+ real lines, already supported pre-redesign) working exactly as before. **ALSO FIXED, found while
  testing:** the render-time SPAN-AUTOMATION system (`AutoParamField.euclidPulses/.euclidSteps/.euclidRot`,
  `SnapParams.settingAuto`) mutates the FLAT `euclidPulses`/`euclidSteps`/`euclidRot` fields per render window — but
  since Router.swift no longer reads those flat fields at all, an AUTO lane ramping EUCLID's hit count silently
  stopped reaching the render path. Fixed by mirroring `settingAuto`'s write onto `euclidLines[0]` (row 0 — the row
  the flat fields always fed) alongside the flat field, caught by the EXISTING
  `testRenderAutoPassSpanRampsHitsUpAcrossBars` test, not a new one. **TESTS:** +5 (a worked-example composition-
  order lock for REVERSE; BOT2/TOP2 strike two notes; REVERSE genuinely time-reverses the onset sequence, not just
  a cosmetic relabelling; always-exactly-4 resolution for both a flat doc and an old 2-line doc; the machine-wide
  PICK fallback). Every pre-existing EUCLID test (LINES polyrhythm/target, per-line PICK/DIE, POOL, SPAN, INVERT,
  CYCLE/RANDOM, chain-driver composition) passes UNCHANGED — confirming the redesign's migration path is genuinely
  byte-identical for every pre-existing document shape. No UI touched yet — GridUI.swift is next (Stage 2).
  **DEVICE-OWED (once Stage 2 ships):** none yet — this stage is pure engine/model, fully covered by the macOS test
  target, nothing device-only to verify until the UI lands.**
- **▶ SELECT GRID — a live scrolling piano roll on the auditioning cell (2026-09-29, on `main`; iOS builds, macOS
  1155 green; DEVICE eye owed). Follow-through on the PART ROW ROLL entry below: Paul asked for the SAME accuracy
  standard (true onset beats read live from the render engine, velocity reflected, "no shortcuts") on the SELECT
  grid's currently-auditioning cell — but with a DELIBERATELY different, explicitly-requested motion model: notes
  SCROLL right-to-left as they play, not PART's fixed-column fade-in-place. Also folded in a small earlier fix that
  hadn't been logged yet: `partRollFadeBeats` doubled 2.0→4.0 beats per a same-day follow-up ask ("increase the time
  for the fade"). **ROOT STATE, confirmed by tracing (not assumed):** the SELECT grid's existing roll is entirely
  STATIC — every present cell, including the selected/auditioning one, draws through `buildGridSelPianoRoll` →
  `buildOutputFace` → `roomsRibbonFace`, a one-shot `Canvas` render from an OFFLINE-simulated note array
  (`gridSelRollBars` → `Dice.runRecorder` against a fixed standard chord, not the cell's real live output). Its
  `playing`/`strikeIdx` params are dead — explicitly neutered in the 2026-09-08 "calm cells" rewrite ("kept for
  call-site compatibility but ignored"), confirmed via a targeted trace before building anything. So this was new
  code, not a matter of flipping an inert switch. **ENGINE:** none — reuses `Router.rowSoundingVoices()` verbatim,
  the same primitive the PART roll introduced, scoped to the ONE engine row the chain audition already pins to
  (the existing `buildChainAuditionRow`). **DATA:** a new reconciliation block in the existing `.onReceive
  (meterTimer)` (AudioUnitViewController.swift), a third sibling right after the PART ROW ROLL block, mirroring its
  exact diff/freeze/prune technique (poll → diff against last-seen held notes → freeze `heldToBeat` on release →
  prune once fully receded) but scoped to a single row via a new `meters.selectRollNotes: [PartRowRollNote]` (plain,
  non-`@State`, same reason as `partRollNotes` — the TimelineView-driven Canvas re-reads it on its own per-frame
  schedule, so a SwiftUI-invalidating write would be pure waste). Gated on `ddSolo` (`buildVoiceOwner == .chain`,
  the precise "is a SELECT cell genuinely the live voice" check) AND a selection present — NOT the `selGrey` UI
  proxy alone, so a selected-but-stopped cell correctly reports no live notes rather than a stale/wrong snapshot.
  **DRAWING:** new `buildSelectLiveRoll(tint:)` (BuildGridSelector.swift) — right edge = now, left edge =
  `selectRollWindowBeats` (new constant, 2.0 — a SELECT cell is one grid column, not a whole PART row, so
  meaningfully less horizontal room than PART's context; flagged as a tunable default, same as `partRollFadeBeats`
  itself was tuned live off device feedback this session) beats ago. A note's HEAD (onset, or `heldToBeat` once
  released) and TAIL (true onset beat) each map independently via `x = clamp(w×(1−age/window), 0, w)` — a
  STILL-SOUNDING note's head stays pinned at the right edge while its tail scrolls left as it's held (grows to fill
  the cell on a long hold, the scrolling analogue of PART's "head tracks the live position"); a RELEASED note's
  whole bar keeps scrolling left and exits off the left edge — the deliberate difference from PART (which freezes a
  released bar in place and only fades its opacity). Added a soft opacity fade as a bar's head nears the left edge
  (`edgeFade`) so the exit isn't an abrupt pop — the scrolling context's equivalent of PART's own recede factor, same
  "no shortcuts" rigor applied to a different problem. A minimum-visible-width floor mirrors `roomsRibbonFace`'s own
  `max(x0+2, x1×w)` — without it a very short/instantaneous strike computes a zero-width, invisible rect and
  silently never renders, exactly the kind of shortcut this task ruled out. No `musicalOf` swing-warp needed (unlike
  PART, which reconciles against a separate swing-warped playhead) — there's no second visual element on a SELECT
  cell to stay in sync with, so the raw true onset beat is the most direct, most accurate signal to draw from.
  Reuses `roomsRibbonFace`'s own thickness/opacity formulas (`2.0+vel×2.5` thickness, `0.4+0.5×vel` opacity) so the
  switch from the idle static ribbon to the live view doesn't jump in visual weight, and `rollLaneForPitch`
  (Derivations.swift) verbatim for the pitch→lane mapping. **WIRING:** in `buildGridSelCell`, `selGrey && ddSolo`
  now branches to the live roll instead of the static `buildGridSelPianoRoll` call; every other case (idle,
  selected-but-stopped, committed, or a non-SELECT caller of the same shared function) is byte-identical to before
  — a selected-but-stopped cell keeps its static offline preview rather than an empty live canvas, the natural
  low-risk fallback. Colour needed no new work: `rollTint` already resolves to `Color(white: 0.22)` (dark ink) for
  this state, correct as-is since `selGrey`'s background is the light `buildSelectGrey` — the opposite contrast
  problem from PART's dark cells, and already solved. Planned first (EnterPlanMode, one Explore pass confirming the
  static/dead-param state, a second targeted Explore pass locating the exact `meters.partRollNotes`/`roomsPart-
  NoteRoll` code to mirror precisely rather than re-derive from memory) before any code. UI-only, no
  `Router.swift`/engine change, no macOS test-target reach (GridUI-only, matching every prior playhead/roll fix this
  session). **DEVICE-OWED:** the scroll reads smooth and beat-locked, not jittery; a long-held note visibly fills
  the cell rather than looking stuck; the exit fade is soft, not a pop; `selectRollWindowBeats = 2.0` is legible at
  real cell size for typical chain content (arp density especially) — first tunable to revisit if too cramped or
  too sparse; the dark-ink colour still reads with enough contrast against the light `selGrey` face.**
- **▶ RECEIVER-DOOR PICKERS — a codebase-wide audit + unification with the main toggles (2026-09-29, on `main`,
  `dbf3fa3`; iOS builds; DEVICE eye owed). Paul: "please review everywhere in the code where another receiver
  toggle is used, for things like chord and echo. I want the styling and dynamic note info to be the same as on the
  main toggles." Audited every A/B/C/D-style picker across GridUI.swift/RackMatrix.swift and classified each as
  RECEIVER (MIDI-IN door reference, in scope) or EMITTER (MIDI-OUT bus reference, out of scope — Paul named
  "receiver" specifically): DEST's "EMITTER PER STEP", DEAL's "EMITTER 1/2", MUTE MATRIX's per-column mute row, TAP's
  "TO — where the copy exits", HOCKET's "LISTEN TO — the wire" (another ROW's OUTPUT, not an input door — "put it on
  a later row than what it listens to"), and the whole of RackMatrix.swift ("THE RACK — the emitter treatment
  matrix") are all EMITTER-side, untouched. Found exactly THREE genuine receiver-door pickers beyond the main
  toggles, each a hand-rolled or plain `seg()` control with none of the main toggles' styling or live-note behavior:
  **ECHO's "FROM"** (`echoInKeyReceivers`, a multi-select bitmask — which door(s) define "in key" for the pitch-step
  trail), **CHORDS' "SCALE FROM"** (`chordsScaleRef`, single-select + "—"/none — which door supplies the key; its own
  comment already said "the KEY is read from a RECEIVER set to SCALE" — this ALSO fixes the CHORD DOOR's own "KEY
  FROM" pop-up for free, since that door mounts this exact CHORDS processor editor, per the door's original
  design), and **AVOID's "WHICH INPUT"** (`avoidRefIndex`, single-select, shown only when `avoidRefKind == .door` —
  "another MIDI input's live notes" per its own comment). **THE REFACTOR:** `ProcessorBox` (GridUI.swift) is a
  SEPARATE `View` struct from `DiagView` (BuildPage.swift's main type) — it can't call `DiagView`'s own
  `buildIOSelectChip` method directly (no shared `self`). Rather than thread `DiagView`'s full state through
  `ProcessorBox` or risk touching the two already-shipped, heavily-used main toggles, extracted two NEW top-level
  free functions (GridUI.swift, beside `receiverGrey`): `ioChip(_:on:accent:action:)` — the bare visual core (text/
  background/border/tap), a deliberately smaller sibling of `buildIOSelectChip` that leaves out its chase-index
  "invite" animation and long-press "apply to every row" gesture (both `DiagView`-only `@State`, and both concepts
  that don't apply to a per-processor door reference — ECHO/CHORDS/AVOID aren't rows); and `noteClassLabel(_:)`, the
  shared lowercase/no-octave formatter, which `BuildPage.swift`'s own `liveNoteClassLabel` now calls too (was
  standalone duplicate logic, now one implementation). New `ProcessorBox.doorKeyLabels: [String?]` (mirrors the
  EXISTING `avoidInputNotes` pattern exactly — a per-door array, populated at the ONE real call site that already
  supplies `avoidInputNotes`, `buildSlotBox`'s `ProcessorBox(...)` — every OTHER `ProcessorBox` call site (tab
  strips, the chord-sequencer popup) falls back to its all-nil default, same as `avoidInputNotes` already does
  there, so this isn't a new gap). All three pickers now compute their chip label identically to the main toggles:
  `doorKeyLabels[i] ?? noteClassLabel(avoidInputNotes[i]) ?? "no input"`. CHORDS' "—" (none) option — no separate 5th
  widget; tapping the already-selected door deselects it, matching what the old 5-way seg offered with one fewer
  control. **FLAGGED, not fixed:** `buildIOSelectChip`'s own `top:` parameter is genuinely dead (its two-line design
  was flattened to one line back on 2026-08-30 and the parameter was never removed — confirmed while reading the
  function closely) — left alone as out-of-scope housekeeping, not touched by this pass. **DEVICE-OWED:** the three
  reworked editors' legibility/layout at real panel size, and that CHORDS' new deselect-by-re-tapping interaction
  reads as intentional rather than broken.**
- **▶ PART ROW ROLL — three device-reported fixes: note contrast, blinking→fading, and a REAL pre-existing playhead-
  jitter bug (2026-09-29, on `main`, `0eb862b`; iOS builds; DEVICE eye/ear owed). Paul, testing the new live piano
  roll: the note colour needs more contrast, the playhead jitters when stopped, and notes are blinking out rather
  than fading. **CONTRAST:** the note colour was the row's raw, unmixed hue — the SAME colour family as the cell's
  own background tint (`partFerryFill` mixes that identical hue into the dark ground), so at typical fade opacity
  the bars barely stood out. Now blends the hue 55% toward white (`mixHex(partFerryHue(r), 0xFFFFFF, 0.55)`) so
  notes read as bright marks over the darker, more saturated background — the same "notes pop white-ish over a
  coloured cell" language already used elsewhere in this grid. **BLINKING, ROOT CAUSE:** a released note's
  `heldToBeat` FREEZES at its release point, but the draw code only ever varied opacity by POSITION within the bar
  (distance from the frozen head) — never by how much REAL TIME had passed since release. So a released note held
  CONSTANT brightness frame after frame (nothing in the per-segment gradient depended on `live` once frozen), then
  vanished in a SINGLE FRAME once its age crossed `partRollFadeBeats` and the existing `guard` dropped it — a blink,
  not a fade. Fixed by adding the missing piece: a `recede` factor (`1 − (live − headBeatRaw) / partRollFadeBeats`,
  clamped 0…1) multiplied into every segment's opacity — continuously dims the WHOLE bar as time passes since
  release, reaching 0 exactly as the guard's cutoff arrives, so by the time a note is actually dropped it's already
  invisible. A still-sounding note (`heldToBeat == nil` ⇒ `headBeatRaw == live` always) keeps `recede == 1`,
  unaffected — this bug was specific to released notes. **PLAYHEAD JITTER — a genuine, pre-existing bug, not
  something new in the roll's own code, just made newly obvious by it:** traced `meters.syncBeat`
  (AudioUnitViewController.swift) — its own doc comment says "only HARD re-anchor on a genuine discontinuity...
  otherwise FREE-RUN... so 4Hz sampling jitter never shows," but its ONE call site was passing `playing: nd.playing`
  (the HOST's raw transport state) instead of `nd.effectivePlaying` (host OR free-run). During FREE-RUN (a ferry/
  part driving its own clock while the host transport is genuinely stopped — the normal way to audition a part
  without the host DAW running), the host is NEVER "playing" by definition, so `!playing` was PERMANENTLY true,
  defeating the dejitter guard entirely and hard-re-anchoring the beat on EVERY 4Hz poll — exactly the "~4Hz
  sawtooth" the original 2026-09-11 dejitter fix (`ef48264`) was built to kill, just scoped specifically to
  free-run playback (steady host-driven playback was never affected, which is why this went unnoticed until a
  new, low-motion-tolerant view — the roll — made the creep-then-snap pattern obvious). Fixed by passing
  `nd.effectivePlaying` instead — `nd.beat` was ALREADY the correct "effective" beat (per Kernel.swift's own
  comment), only this one boolean was reading the wrong field. **SECOND, RELATED BUG found in the same pass:** the
  `@State d` refresh trigger (`if nd.playing != d.playing || nd.tempo != d.tempo || nd.pass != d.pass { d = nd }`)
  never checked `effectivePlaying` — since `nd.playing` stays `false` throughout an ENTIRE free-run session by
  definition, `d.effectivePlaying` could go stale INDEFINITELY unless tempo/pass ALSO happened to change at the
  same moment, desyncing `roomsPartPlayhead`/`roomsPartNoteRoll`'s own visibility gate from the TRUE free-run state.
  Added `effectivePlaying` to the trigger condition. UI/telemetry-only changes — no Router/engine touch, no new
  tests (GridUI/AudioUnitViewController have no macOS test-target reach, same as every prior playhead fix in this
  file); iOS build green. **DEVICE-OWED:** the note colour actually reading with enough contrast; a held note
  visibly fading out smoothly rather than popping; and — the one most worth confirming carefully — the sweep/roll
  staying rock-steady during a FREE-RUN part (host transport stopped, a ferry playing on its own), not just during
  host-driven playback.**
- **▶ ECHO — a live in-key pitch-step via ABCD receiver toggles, replacing the confusing POOL mode (2026-09-29, on
  `main`, `d092d9b`; macOS 1151 green incl. 7 new, iOS builds; DEVICE ear/eye owed). Paul: each echo repeat should be
  able to step to the NEXT IN-KEY note (up if PITCH STEP is positive, down if negative — sign only, magnitude no
  longer matters in this mode) instead of a flat semitone amount, where "in key" is read from whichever of the 4
  receivers are toggled — and it must be genuinely LIVE ("I want it live, please"): a chord change on the referenced
  receiver(s) mid-tail bends the walk, each repeat chaining from the PREVIOUS repeat's actual landed pitch, never a
  fixed offset from the source note. Also: remove the old POOL pitch-step mode entirely ("I saw pool but didn't
  understand what it did") — replaced by ABCD multi-select toggles, not a single receiver picker. Planned carefully
  first (EnterPlanMode, 2 parallel Explore agents + 1 Plan-agent validation pass, re-entered plan mode after the user
  asked "is this clear instruction?" surfaced real ambiguity) before any code — the validation pass caught two real
  bugs pre-implementation: (1) a same-window multi-repeat staleness bug (`drainEchoTails` takes `let e =
  echoTails[i]` ONCE before its `for k in 1...e.repeats` loop — reading the walk cursor through `e` inside that loop
  would have two same-window repeats both read the same stale value instead of chaining), fixed by seeding a LOCAL
  `var` cursor once per tail per drain call, read/written through the loop directly, with the array write-back only
  feeding the NEXT render window's drain call; (2) inferring "in-key mode engaged" from `inKeyReceivers != 0` would
  have made "IN-KEY mode with zero receivers ticked" indistinguishable from "mode not engaged," silently falling
  back to flat semitones instead of the required "hold at last landed pitch" — fixed with an explicit `inKeyMode`
  flag on the tail, not an inferred one. **ROOT ENGINEERING PROBLEM: `EchoTail` was fully static once pushed**
  (every field written ONCE at `pushEchoTail` time; the only prior cross-window mutation was `active` flipping
  false on retirement) — going live meant adding the FIRST genuinely mutable per-tail field,
  `inKeyLast` (the walk cursor). Disclosed as a sanctioned, narrowly-scoped exception to the engine's derived-never-
  accumulated rule, same class as `riffDrunkPos` — but structurally SAFER than that precedent: it's per-tail (not
  per-cell/session-long), and provably exempt from the seek/loop replay concern DRUNK carries, because a tail cannot
  survive a beat discontinuity at all (`clearEchoTails` fires first) — and its reset is FREE, not a separate
  mechanism, since `pushEchoTail` always fully reconstructs the struct via a literal rather than in-place mutation,
  so a reused slot's `inKeyLast` silently defaults back to unset. New `nextInKeyNote` (Derivations.swift) always
  advances to a genuinely DIFFERENT note — unlike the existing `keyFilterNote` (AVOID's own primitive), which snaps
  to nearest-or-stays if the input is already in-key; the new function's whole point is that even an already-in-key
  note must still move. Live reads reuse `doorRefMask` (already proven safe to call from this exact render-window
  context by AVOID) unioned across whichever ABCD receivers are toggled, mirroring AVOID's own `.sounding` union.
  **SCOPE GAP FOUND DURING IMPLEMENTATION, inherited unchanged from the old POOL mode, not a new regression:** tracing
  `emitEchoColumn`/`isEchoTail` mid-implementation revealed THREE separate echo-tail registration call sites, not
  one — `registerEcho` (single-slot `[ECHO]` or an upstream-then-echo tail like `[HARMONIZE→ECHO]`), `pushEchoForNote`
  (a hold-chain shape like `[ECHO→HARMONIZE]`, echo NOT last), and `registerLengthChainEcho` (`[ECHO→…→LENGTH]`
  specifically). POOL mode's own `echoPoolMask` computation only ever existed in `registerEcho` — confirmed via grep
  before assuming — so IN-KEY mode, threaded the same way, inherits the identical scope: it works for ECHO standalone
  or as a chain's own tail, not for the other two shapes. CHAIN route is architecturally inapplicable to `registerEcho`
  regardless (nothing sits downstream of ECHO when it IS the tail) — so "IN-KEY × CHAIN route" was never a reachable
  combination to begin with, not a gap. Flagged here plainly rather than silently shipped. +1 DerivationsTest
  (strict-advance / cross-octave / empty-mask / dir-zero / range-exhaustion, mirroring `testScalePitchClassMask-
  AndKeyFilterDirections`'s style) +6 RouterTests (chained walk stays in the reference's pitch classes; genuinely
  live — a receiver's content changed BETWEEN repeats via a manual per-window `process()` loop, not the shared
  `run()` helper, which only takes one fixed pool for its whole run; empty-mask hold; zero-receivers hold, not a
  flat climb — caught a test-writing mistake of its own: holding also lands on note 60, so filtering `note != 60`
  to isolate "the repeats" from "the dry strike" silently emptied the result — fixed by checking event COUNT
  separately from note VALUE; same-window multi-repeat chaining, the direct regression test for bug (1) above, via
  one oversized `frameCount` so 3 repeats resolve inside a single `drainEchoTails` call; walking a harmonized
  upstream set through `registerEcho`'s own chain-composition branch). One existing test for the removed POOL mode
  deleted outright (`Tests/AcceptanceTests.swift`, nothing left to assert once the mechanism is gone — its
  `Accept.notesA` oracle also can't express a separate referenced receiver anyway); the `FuzzTests.swift` POOL
  randomizer now hammers the new mode instead, including the empty-mask "hold" edge case across all 16 receiver-
  mask combinations. Old saved sessions using POOL decode fine (Codable ignores the removed key) but now play flat
  semitones instead of a pool-stepped trail — a real, silent musical change on next load, expected given the
  removal request, named here rather than left implicit. Plan: `~/.claude/plans/velvet-foraging-curry.md`.
  **DEVICE-OWED:** the walk audibly following a changing chord on the referenced receiver(s) in real time; the
  empty-mask hold reading as a hold, not a dropped/stuck note; the new FROM row's chip legibility next to PITCH STEP.**
- **▶ RECEIVER STRIP — the top label now shows LIVE notes received, not the channel filter (2026-09-29, on `main`,
  `92ed1c8`; iOS builds; DEVICE eye owed). Paul: change the receiver toggles' labels to show the notes being
  received in realtime, but leave whichever one is set to KEY still showing the selected key. `buildReceiverControl`'s
  TOP button (the ENABLE toggle, `buildRecProminent`) previously showed `recChanLabel` — OMNI/CH n/CH ×k, the channel
  filter. Replaced with `recLiveLabel(i, rec)`: for a door in SCALE mode (the standing "key" reference doors like the
  D→SCALE door use throughout this rig) it shows the selected key ("D MIXOLYDIAN", the exact `\(names[root])
  \(type.label)` format the scale pop-up's own ACTIVE summary already uses, for consistency); every other door shows
  its currently-held/received pitches live, e.g. "C4 E4 G4" — reusing `recvHeldNotes` (`AudioUnitViewController.
  swift`), the SAME already-live per-door note feed that already drives the config-sheet REPLAY roll, the IN-piano
  truth-strip, and the AVOID piano — no new polling, no new engine plumbing, just a new reader of state that was
  already being kept current every render. Empty (nothing held) shows a plain "—" rather than going blank. Checked
  why SCALE needed the special case rather than falling through: `recvHeldNotes` for a scale door already reports
  ITS OWN resolved pool (per the AVOID-piano comment on that field: "armed/scale doors report their pool"), not a
  live performance — showing that as "notes received" would be misleading (a wall of 7+ pool notes, not what's
  actually playing), so the key name is the more honest realtime-ish readout for that one door type. Chose the check
  as `rec.doorModeResolved == .scale` (not hardcoded to a specific door letter) so it naturally covers however many
  doors are actually configured as scale references, not just an assumed one. Channel-filter info isn't lost, just
  relocated — it's still reachable via the spanner → MIXER sheet, same as before. Removed a now-stale doc-comment
  that described the old channel-caption behaviour and was left orphaned above the new function. UI-only (BuildPage.
  swift), no test-target reach, matching every prior GridUI/BuildPage-only fix in this file. **DEVICE-OWED:** legibility
  of a real chord's worth of note names at this button's actual size (`.minimumScaleFactor(0.6)` auto-shrinks, same
  as every other label on this button, but untested against 4+ simultaneous notes); confirm a CHORD-mode door (left
  on the live-notes branch, not special-cased like SCALE — Paul only named "key") reads sensibly showing its own
  resolved chord rather than looking broken.**
  **WRONG CONTROL — REVERTED + REDONE on the actual receiver TOGGLES, lowercase/no-octave (2026-09-29, on `main`,
  `da5f3b8`; iOS builds; DEVICE eye owed). Paul: "I actually intended this for the toggles, not the receivers
  themselves. Also, make them lowercase without the octave number." The entry above landed on
  `buildReceiverControl`'s big 4-button strip (the ENABLE/LATCH/OCT/S-M column) — fully reverted (`recLiveLabel`
  deleted, `recChanLabel` + its call site restored byte-for-byte). "The receiver toggles" are a DIFFERENT, smaller
  control: `buildReceiverSelectChip` (via the shared `buildIOSelectChip`), the per-row A/B/C/D door-picker chips
  under the machine box — these ALREADY had a "show the key instead of the letter" mechanism for a SCALE/CHORD door
  (`key`, via `receivers[i].scaleLabel`/`buildChordDoorLabel`, a top/big label swap so the letter survives as a small
  caption) — exactly the "leave one set to key" case, so that branch is UNTOUCHED. Added a new `live` branch using
  the SAME top/big swap: when a door has no key AND currently has held notes (`liveNoteClassLabel`, a new pitch-
  CLASS-only reader of the same `recvHeldNotes` feed — no octave digit, lowercased, e.g. "c e g", per Paul's literal
  ask), the big slot shows that instead of the plain letter; idle (nothing held, no key) still falls back to the
  plain A/B/C/D letter exactly as before — a chip is never left blank. Two held notes an octave apart collapse to the
  same letter twice (e.g. "c c") — an honest, undeduplicated consequence of dropping the octave, flagged not fixed
  (Paul didn't ask for dedup). MIDI-OUT emitter toggles (`buildEmitterToggles`, the sibling caller of the same shared
  chip) are UNTOUCHED — Paul named receiver toggles specifically. **DEVICE-OWED:** legibility of several lowercase
  letters in the chip's compact space, and whether a CHORD-mode door (still covered by the pre-existing `key` branch,
  unaffected by this pass) reads right alongside the new live-notes chips.**
  **"NO INPUT" ADDENDUM, same day (`a75ec6a`; iOS builds; DEVICE eye owed).** Paul: "this works well on the first
  receiver toggle. I also expect to see the notes or 'no input' appear on the other emitter toggles (the exception
  being scale)" — clarified via AskUserQuestion (2 corrections already landed on this exact feature this session, so
  asked rather than guessed a third time): he meant the other 3 RECEIVER chips (B/C/D), not the separate MIDI-OUT
  emitter toggles — "no input" is receiver-side language, which was the tell. ROOT ISSUE: the idle fallback was the
  PLAIN LETTER (byte-identical to the chip's own resting state), so a receiver with nothing currently held looked
  indistinguishable from "this feature doesn't apply here" — not a bug in the logic (every chip already ran the same
  code), just an invisible result. FIX: idle now shows literal `"no input"` (lowercase, matching the note-name
  convention) instead of falling back to the letter. Simplified the top/big swap while in there: since EVERY branch
  now fills the big slot with something (key · live notes · "no input"), the top caption is unconditionally the
  letter — the old `"MIDI IN"` fallback caption is dead code (no remaining case reaches it), removed. Scale/chord
  doors are UNCHANGED (still their own `key` branch, exactly the "exception being scale" Paul named).**
  **CHORD-DOOR FIX, same day (`eeafcda`; iOS builds; DEVICE eye owed). Paul: "it doesn't work on chord receiver
  toggles - it still shows 'chord'."** Self-inflicted: the `key` exception (the entry above's own "Scale/chord doors
  are UNCHANGED" line) wrongly carried CHORD doors along with SCALE ones — the ORIGINAL pre-existing code bundled
  `receivers[i].scaleLabel` and `buildChordDoorLabel` under one `key` value (both being "this door has a special
  identity" cases), and this feature's first pass never questioned that bundling. But Paul's own words, both times
  ("leave one set to key," "the exception being scale"), only ever named scale/key — never chord. A CHORD door was
  showing `buildChordDoorLabel`'s fixed `"A · CHRD"` string, which reads as "it still shows 'chord'." FIX: dropped
  `buildChordDoorLabel` from `buildReceiverSelectChip`'s `key` entirely (it's still used elsewhere — the tab-label
  call site at line ~211 — only THIS chip's use of it is gone) — a CHORD door now falls through to the same live-
  notes/"no input" branch as any plain input door. Its `recvHeldNotes` entry is that door's own resolved chord pool,
  live — a meaningful "what's sounding from here right now" readout, not a stand-in.**
- **▶ EUCLID MASK CHORD "not sounding" — INVESTIGATED, NOT REPRODUCIBLE off-device; +2 permanent regression tests
  (2026-09-29, on `main`, `10863ef`; macOS 1149 green incl. 2 new). Paul: a Euclid mask after an arp, GAPS=CHORD,
  7-of-8, wasn't sounding, "fails on every setting" — then gave the exact steps: the chain was ARP→VELOCITY, he added
  EUCLID MASK after it (still silent on CHORD), removed VELOCITY (still silent). Exhaustive engine-level
  investigation could NOT reproduce this: the CHORD stab mechanism (`chainScratch`/`composeChainSet`), `isModifierFoldable`/
  `chainDriverIndex`'s fold selection, `emitDriverNote`'s mask block, K/N/GAPS/ROTATE/CHORD PICK/SPAN/FILL/ACCENT LAYER
  param resolution, every `emitOneBus` suppression gate (mute/octave-clamp/RACK FENCE/CLAIM/solo/flood-governor/MONO,
  all confirmed off by default), and `openVoice` all check out clean by direct reading; Paul's TWO literal repro shapes
  were built and tested directly — `[ARP→EMPTY/bypassed→EUCLID MASK]` (the real post-removal shape; chain edits are
  POSITION-PRESERVING, `buildChainRemoveSlot` leaves a bypassed `.empty` passthrough and never shifts later slots) and
  `[ARP→VELOCITY→EUCLID MASK]` (his original, pre-removal chain) — both strike the chord correctly. The storefront
  "ADD PROCESSOR" card for EUCLID MASK applies no param preset (`apply: { _ in }`), so a freshly-added slot is
  identical to direct construction. **A real dead-code finding along the way, flagged not fixed:** `Router.
  auditionRender` — a separate, simpler render path for a press-and-hold single-cell preview — only ever previews a
  chain's HEAD slot (its own comment says so: "a full serial preview of the tail is a follow-up") and would have
  PERFECTLY explained this exact symptom (a downstream processor silently ignored) if it were reachable. It isn't:
  its sole trigger `MidiSparkAudioUnit.setAudition(col:row:)` and the `AuditionBox.target`/`.held` state it depends on
  are never written anywhere in the current codebase (grepped clean) — today's real preview mechanism instead parks
  the audition machine as a genuine playing cell (`BuildSceneLogic.composeSceneMeta`'s `auditionRow`) and renders it
  through the same full engine as any other cell, so this dead path isn't actually reachable from the UI. **Also
  flagged (minor, not what Paul described but a real discoverability trap):** a freshly-added EUCLID MASK defaults to
  K=N (fully open/pass-through — `mK = p.maskK ?? mN`), and the GAPS/ROTATE/CHORD PICK/CHORD OCT/LEN/VEL rows are all
  HIDDEN until K is manually lowered below N, so there's nothing to tap toward "chord mode" on a brand-new slot until
  HITS is touched first. +2 RouterTests locking in Paul's two repro shapes as permanent coverage
  (`testEuclidMaskChordFoldsAcrossAPositionPreservingEmptySlot`, `testEuclidMaskChordFoldsWithVelocityStillInTheChain`).
  **GENUINELY UNRESOLVED — asked Paul for the detail needed to keep chasing it:** whether he's checking via the
  press-and-hold/tap audition or by actually pressing PLAY on a scene; his CHORD PICK setting (ALL vs. a narrower
  pick could read as "nothing" if it's e.g. LOW/HIGH and he's listening for the whole chord); whether EUCLID MASK is
  the chain's last slot or anything follows it; any other processor anywhere else in the chain.**
  **BOTH FLAGGED ISSUES FIXED (2026-09-29, on `main`, `33d2266`; iOS builds). Paul confirmed he's not auditioning
  (real playback), it fails on every CHORD PICK mode, and EUCLID MASK is the chain's last slot, then asked me to fix
  the two issues found above. (1) `Router.auditionRender` and its whole "Phase 2" dead-preview cluster REMOVED at
  every entry point: `AudioUnitViewController.swift`'s `AuditionBox` class + `abox` @State (its `target`/`held`
  fields were written only to their own already-default values, never read anywhere); `MidiSparkAudioUnit.
  setAudition(col:row:)`/`clearAudition()`; and — found while removing these, same dead "Phase 2" era, same
  shape (zero UI callers) — `MidiSparkAudioUnit.setPreview`/`clearPreview` too. Deliberately did NOT chase the
  removal all the way down into `Kernel.swift`'s `auditionTarget`/`previewActive`/`suppressAuditionNotes` fields
  or `Router.process()`'s `audition:`/`preview:` parameters — those are live plumbing read by the render loop's
  own gates on every render (`auditionSuppressing: suppressAuditionNotes || previewActive || …`), and safely
  unwinding a load-bearing function signature deserves its own focused pass, not a rushed side-fix; they're now
  commented as permanently-dead-but-still-read, and Kernel.swift's own two setter methods that only these deleted
  callers used (`setAudition`/`setPreview`/`clearPreview`) are gone too since nothing calls them anymore. Net
  effect: this render path can no longer be reconnected from the UI by accident — it would need genuinely new code.
  (2) The K=N discoverability trap in the EUCLID MASK editor (GridUI.swift) — GAPS/ROTATE/PATTERN/CHANCE/the CHORD
  sub-fields are no longer hidden behind `if mK < mN`; they're always visible now, with a plain one-line hint
  ("K = N — every step hits, so GAPS/ROTATE/CHORD have nothing to act on yet") shown only when the mask is
  currently fully open. **A THIRD possibility raised, not yet code — a listening-window hypothesis, not a bug:**
  reconciling "7-of-8 fails, and so does every OTHER setting he tried" — K=7/N=8 leaves exactly ONE gap per 8-note
  cycle; if GAPS/CHORD PICK are being toggled and listened to for only a second or two each (very natural while
  dialling in a setting), the one gap-per-cycle may simply never be reached before moving on — which would equally
  explain "fails on every CHORD PICK mode" (the pick differentiator never gets a chance to be heard if the gap
  itself is never reached). Asked Paul to test a much denser mask (e.g. 4-of-8) over 2+ full cycles, and separately
  whether REST/TIE modes have ANY audible effect at all (drops/ties a note) with his current settings — the single
  most decisive remaining diagnostic: if REST/TIE do nothing either, the whole downstream fold isn't engaging (a
  bigger, different, and more findable bug than the CHORD stab specifically); if REST/TIE clearly work and only
  CHORD's replacement note is silent, that narrows the search to the stab's own emission call.**
- **▶ FERRY DRAG-DROP — silent ferry + un-stopped source audition FIXED, the source cell now commits (name+colour),
  +2 tests (2026-09-29, on `main`, `aada129`; macOS green incl. 2 new, iOS builds; DEVICE ear/eye owed). Paul reported
  three bugs dragging a SELECT cell onto a play ferry: the source cell kept playing, the target ferry stayed silent,
  the source cell never got marked/named. **ROOT CAUSE of the silent ferry — A REGRESSION FROM THIS SAME DAY'S
  EARLIER FIX** (the `1c902c6`-adjacent "only navigate to PART if already focused" change): `buildPublishScene`'s
  `input.ferryParts[t] = t == buildActiveFerry ? buildCaptureBenchPart() : buildFerryParts[t]` — an ACTIVE ferry is
  read LIVE off the editing "bench" @State, every OTHER ferry from its own stored `BuildPart`. The earlier fix set
  `buildActiveFerry = t` on a non-focused drop WITHOUT loading `t`'s data onto the bench — so the compositor kept
  reading whatever the PREVIOUSLY active ferry had left there, not the drop. Same shortcut skipped the chain-
  audition-stop (it only ran on the navigate-to-PART branch) — the un-stopped source cell was the SAME root cause,
  not a separate bug. **FIX:** `buildActivateFerry`/`buildReactivateFerry` gained a `navigate: Bool = true` param —
  the FULL activate flow (outgoing-ferry bench writeback, bench LOAD of the new ferry, the chain-audition stop) now
  ALWAYS runs; `navigate` gates ONLY the room switch + `roomsPartSetup()`. `buildPopulateFerry` calls through this
  properly instead of the hand-rolled `buildActiveFerry = t; buildPublishScene()` shortcut the earlier fix used.
  Traced the fix by hand against the exact `buildPublishScene` composition code before shipping (not assumed) —
  confirmed a non-focused drop now correctly bench-loads `t`, publishes with `t`'s real content, and separately
  writes back the OUTGOING ferry's live edits so IT keeps sounding right too. **SOURCE-CELL COMMIT:**
  `buildPopulateFerryFromSelect` now marks/names the SOURCE cell, mirroring the existing "EDIT = COMMIT" rule an
  in-place chain edit already applies (`buildApplyChain` — first name wins, the colour override always follows) —
  this never ran for drag-drop at all before, which is exactly why it "did this in some instances already" (only
  when a PRIOR edit had happened to commit the cell first). **TESTS:** extracted the two genuinely pure rules —
  which name wins (`BuildSceneLogic.ferryDropSourceName`) and whether to navigate
  (`ferryDropShouldNavigateToPart`) — into `BuildSceneLogic.swift`, `BuildPage.swift` now calls THROUGH them rather
  than duplicating the logic inline, +2 `BuildSceneLogicTests`. **HONESTLY FLAGGED, not swept under a test:** the
  actual bench/active-ferry sync bug lives entirely in SwiftUI `@State` glue (`buildLoadBenchPart`/
  `buildCaptureBenchPart` read/write ~20 `@State var`s directly) — this project's own architecture deliberately
  keeps that class of code OUT of the unit-test target (BuildPage.swift isn't in `MidiSparkTests`); traced it by
  hand instead of forcing an artificial pure-function extraction that wouldn't actually cover the real bug. **DEVICE-
  OWED:** drop onto a non-focused ferry → it should audibly start playing the dropped content immediately, the
  previously-focused ferry should keep sounding unaffected, the source SELECT cell should go quiet + show its name,
  and switching to PART later should show the newly-active ferry's part (not stale bench content).**
- **▶ PART GRID — a live per-row piano roll of what actually played, overlaid on the existing grid (2026-09-29, on
  `main`, `56868a9`; macOS 1145 green incl. 4 new, iOS builds; DEVICE eye/ear owed). Paul: each of the part grid's 4
  interior rows should show a LIVE piano roll of the notes it actually played — pitch vertically, time horizontally,
  riding the row's own existing sweeping playhead — accurate, no perceptible latency, fading at a FIXED trailing
  window behind the playhead (a rolling lookback from NOW, not from a held note's onset — its head stays bright at
  the playhead as long as it's held, its tail fades at a fixed distance regardless of hold length). Planned carefully
  first (10 ACs ratified in chat, then a formal EnterPlanMode pass with 2 parallel Explore agents + 1 Plan agent,
  self-reviewed against the ACs before implementing — 3 real gaps caught and fixed pre-code: velocity wasn't wired to
  any visual, an early draft cleared the roll on transport-stop which directly violated the no-abrupt-reset AC, and
  the ~33ms poll-bound "how fast can a note appear" honesty wasn't stated plainly). **SCOPE, confirmed via
  AskUserQuestion:** one roll PER ROW (not one combined roll for the whole part); it lives ON the existing grid as an
  overlay (not a new strip/page element — no layout/lattice change at all); a bar stays FIXED at its own grid column
  and fades in place (opacity only), a held note's head still extends forward with the live playhead. **ROOT DESIGN
  PROBLEM: the render engine had no per-voice onset TIME at all** — `Router.Voice` tracked active/note/vel/cellIndex/
  offSample but nothing about WHEN a voice opened. Fixed by adding `Voice.onBeat: Double`, stamped inside `openVoice`
  using the IDENTICAL formula the existing `focusNoteBeat` comet-trail already uses (`fBeatPos + Double(onSample −
  fWindowStart) × fBeatsPerSample`) — these are Router INSTANCE fields set once per render window, so no signature
  change was needed on `openVoice` or any of its 13 call sites. New `Router.rowSoundingVoices()` bucket-scans the
  128-voice pool ONCE by engine row (`cellIndex % Snap.rows`), returning every row's (note,vel,onBeat) — mirrors
  `cellSoundingVelSnapshot`'s existing "return the whole unscoped array" shape rather than threading a ferry/row
  param through 3 forwarding layers. Threaded through Kernel/MidiSparkAudioUnit as thin forwarders, polled on the
  **30fps `meterTimer`** (the OUT-piano's just-landed precedent from the day before — NOT the laggier 4Hz diagnostic
  timer), reconciled into a new `LiveTelemetry.partRollNotes` (plain reference-class field, not `@State`, matching
  `cellRoll`'s existing pattern so per-note writes don't force a body re-run). **THE SUBTLE BUG THE PLAN AGENT CAUGHT
  BEFORE ANY CODE WAS WRITTEN:** `onBeat` is captured RAW (un-swing-warped, matching `focusNoteBeat`), but the
  existing playhead (`roomsPartPlayhead`) runs its beat through `musicalOf` (the swing warp) before it becomes a
  pixel — comparing a raw note-beat against a musical playhead-beat directly would have silently drifted the bars off
  the white sweep line under any non-50 swing setting. Fixed by applying `musicalOf` to BOTH the live beat and every
  note's beat at draw time, never comparing raw-to-musical. **LOOP-COLUMN SELECTION EDGE CASE, also caught in
  planning:** a loop-column selection can map adjacent logical steps to non-adjacent physical columns
  (`BuildSceneLogic.loopColumnPlan`) — a naive single-rectangle bar would smear across skipped columns, so a held
  note's bar is decomposed into one segment per LOGICAL step, each positioned via the SAME `plan.physicalColumn`
  the playhead itself uses — this also gives the loop-seam CLIP (never wrap) for free, matching the fade
  clarification Paul gave. **KNOWN, STATED LIMITATION (not a bug):** detection depends on the ~30fps poll observing
  "what's active right now" — a note shorter than ~33ms, or repeated strikes closer together than that (a fast
  ratchet/burst can exceed it), can open and fully close BETWEEN two polls and never be observed at all, not merely
  delayed. No faster live-voice channel exists in this codebase today; flagged explicitly in the plan and here rather
  than discovered as a surprise later — device-verify against a real fast ratchet before calling this fully done.
  Also explicitly NOT clearing `partRollNotes` on the transport-stop edge (an early draft did — removed: it fought
  the no-abrupt-reset AC and was pure downside, since the overlay is already gate-hidden while stopped via the same
  `d.effectivePlaying` gate `roomsPartPlayhead` uses). Reused verbatim, not reinvented: `rollLaneForPitch`
  (pitch→lane, already used by the dead-but-still-populated `meters.cellRoll`/`buildNoteSweep` pathway) and
  `partFerryHue(row:)` (the exact colour already tinting the flat part cells this overlay sits on top of).
  **DELIBERATE, SCOPED EXCEPTION to "GRID REBUILD P2" (2026-09-08, "cells are calm, the ferry row carries the
  motion")** — the roll is a new overlay layer riding above the flat, unchanged part cells, not a reversion of that
  redesign; worth device-confirming it doesn't read as visually contradicting the calm-grid intent elsewhere. +4
  RouterTests (onset-beat accuracy on a SUSTAINED hold — an ARP's staccato notes were the first draft's mistake, all
  already gated off by the check point, caught by the test failing, not by inspection; row-bucketing across a real
  ferry boundary, row 0 vs. row 4; clears on release; the existing silent-claim-ghost exclusion pattern extended to
  the new method). One test-writing lesson recorded plainly: the first draft of the onset-beat test also asserted 3
  voices for a 3-note chord and failed at 6 — §7b's own two-cable-per-note copy (own bus + the ALL cable) means
  `rowSoundingVoices()`, a deliberately raw per-voice dump, legitimately reports 2 voices per logical note; the UI
  layer's `(pitch,onBeat)` dedup (not Router) is what collapses that back to one bar. **DEVICE-OWED:** the whole
  feature — no-perceptible-lag on strike, a held note's tail pinned at the 2-beat window while its head tracks the
  sweep, non-zero swing not drifting the bars off the white line, a loop-column selection not smearing a bar across
  skipped columns, velocity actually reading as thinner/dimmer for soft notes, and the fast-ratchet miss-limitation
  either not noticeable or worth a follow-up if it is. Plan: `~/.claude/plans/velvet-foraging-curry.md`.**
- **▶ FERRY DRAG-DROP — a SELECT-cell drop no longer force-navigates to the part grid unless the target ferry was
  already focused (2026-09-29, on `main`, `59f6bdb`; iOS builds; DEVICE eye owed). Paul: dropping a SELECT cell onto
  a play ferry shouldn't yank the view over to the part grid unless that ferry's own selector was already the active
  one — otherwise stay on whatever room you're in, but still let "the selected colour" (`buildActiveFerry`) follow
  the drop. ROOT CAUSE: `buildPopulateFerry`'s trailing `buildReactivateFerry(t)` was unconditional — it always
  called through to `buildActivateFerry(t)`, which (since the ferry is now populated) always takes the "load bench +
  `roomsRoom = .part`" branch, regardless of whether `t` was the ferry you were already looking at. **FIX:** capture
  `buildActiveFerry == t` right before that trailing call (nothing above it in the function touches `buildActiveFerry`,
  so it still reflects the PRE-drop focus) — already-focused → unchanged behaviour (`buildReactivateFerry`, full
  bench load + navigate); a DIFFERENT, non-focused ferry → populate + colour-swap runs exactly as before (untouched),
  the ferry starts playing in the BACKGROUND (consistent with the ferry-row-unification model, where every ON ferry
  already composes/plays independently of which one has focus), and only `buildActiveFerry = t` updates (+
  `buildPublishScene()` so the newly-armed play state actually takes effect) — no bench load, no room switch. Scoped
  to exactly the SELECT-cell→ferry drop path (`buildPopulateFerry`, the only caller of the old unconditional call);
  ferry→ferry drag-moves (`buildMoveFerry`) are untouched — Paul's ask named the SELECT-cell case specifically.
  UI-only, no test-target reach (GridUI/BuildPage, as always). **DEVICE-OWED:** dropping onto a non-focused ferry
  reads as "it populated and started playing, right where I was" rather than as a dead tap; the SELECT cell's border/
  play badge (the two things this session already wired to "the selected colour") pick up the new colour immediately.**
- **▶ RANDOMIZE/MUTATE — a REAL progress bar on both the machine panel and the part grid (2026-09-29, on `main`,
  `b7591af`; macOS green (full suite), iOS builds; DEVICE eye owed). Paul: show a progress bar while RANDOMIZE/MUTATE
  is in process, from either surface. **MACHINE PANEL:** already backgrounded since the 2026-09-13 tranche
  (`runOnLargeStack` + `buildMachineGenerating`), just showed an indeterminate circular `ProgressView()` — swapped for
  `ProgressView(value: buildMachineGenProgress)` (`.progressViewStyle(.linear)`). **PART GRID:** the row-creator's
  MUTATE/RANDOM/TRY-AGAIN (`roomsRowCreatorInline`/`buildRegenRow`) were STILL SYNCHRONOUS on the main thread — a
  gap explicitly flagged and left open in the 2026-09-13 tranche's own forward-plan ("Background the synchronous
  row-creator MUTATE/RANDOM"), never picked up until now. New shared `buildRowGenerate(row:random:base:)` — one
  guard (`buildRowGenRow`, keyed by row not a bare bool), one `runOnLargeStack` dispatch, one completion handler —
  replaces the three near-duplicate inline call sites; a new `roomsRowGeneratingInline` shows the bar in the SAME
  row footprint the creator/confirm buttons already use, wired into the part-grid's per-row switch (now a 4-way:
  generating → confirm → creator → cells) and into the drag-gesture guard (a generating row can't also take cell
  taps, matching the existing KEEP\|TRY-AGAIN row's own guard). **THE BAR IS REAL, NOT SIMULATED** — checked this
  before building anything: `Dice.fingerprint`/`evalRun` (which both `mutateChain`'s retry loop and `rollSimple`'s
  candidate loop call every iteration) run a genuine offline Router probe (`runRecorder`, 3 beats each) — a real,
  not-fake cost per attempt, confirmed by reading `runRecorder` directly rather than assumed from the loop shape
  alone. So `attempt/24` (mutateChain's hard cap) and `candidate/4` (rollSimple's) are honest proxies for work
  actually done, not a decorative timer. Threaded an optional `progress: ((Double) -> Void)? = nil` through BOTH
  pure functions (BuildSceneLogic.swift, Dice.swift — both Foundation-only, no UI dependency added; the callback
  itself hops to main via the caller, same pattern as the existing completion handler) — additive, every existing
  caller/test unaffected (confirmed, not assumed: ran the full macOS suite). **A real bug caught before it shipped,
  not after:** a first draft used `defer { progress?(...) }` per loop iteration for the "didn't finish yet" case —
  but the fast-path early return (`if !scored { progress?(1); return chain }`) would have fired its OWN 100% call
  and THEN the deferred per-attempt fraction on the way out (defer always runs on scope exit, including via
  return), landing the bar back below 100% instead of at it. Caught by tracing the actual control-flow order before
  shipping, not by a test (no test-target reach for this — see below) — rewritten with explicit calls at each exit
  point instead of `defer`, so every path reports its OWN final value exactly once. RANDOMIZE's rare cold-corpus
  fallback (`Dice.rollArchetype`, only reachable when the pregen corpus isn't warm yet) has no natural sub-steps to
  report — left as a small 0.08 head-start snapping to 1.0 on completion, honest about not knowing more than that,
  not worth over-engineering for a path that's usually instant anyway. UI-only for the wiring; the two engine
  signature changes have no test-target reach for the NEW behavior specifically (the callback itself isn't asserted
  by a test, only that existing callers/tests still pass unmodified) — DEVICE-OWED: the bar's legibility at both
  panel and row-creator size, and that rapid-fire RANDOMIZE/MUTATE taps (either surface) can't desync the guard from
  the visible state.**
- **▶ PROCESSOR EDITOR — the swap transition is now SLIDE + FADE, not a plain cross-fade (2026-09-29, on `main`,
  `7ad1775`; iOS builds; DEVICE eye owed). Follow-through on the 2026-09-28 cross-fade fix: Paul asked whether it'd
  landed (he couldn't see it), then for suggestions on feel — shown as an interactive mockup comparing candidates
  (opacity-only · slide+fade · scale+fade · flash · flash+slide) built from the shipped code's own actual gaps, not
  invented; he picked slide+fade. **THE TRANSITION:** `ProcessorBox`'s new `swapTransition` (GridUI.swift) — a small
  FIXED 14pt offset + opacity, `.asymmetric(insertion:removal:)`, NOT SwiftUI's built-in `.move(edge:)` (which travels
  the view's own full width — far too big a sweep at panel size for a subtle cue, caught before shipping by reasoning
  through what `.move` actually measures against, not assumed). Direction is `swapDirection: Int` (new `ProcessorBox`
  param, default +1): the incoming controls nudge in from the edge matching which way the user actually moved through
  the chain; the outgoing controls nudge out the opposite way. Duration bumped 0.18s→0.2s to match what read best in
  the mockup comparison (a touch more time for the added motion). **DIRECTION SOURCE:** `buildEditSlot` (0…7) already
  IS the chain's own left-to-right order — no new positional concept needed. A new `buildEditSlotDir` @State
  (AudioUnitViewController.swift) derives it via `.onChange(of: buildEditSlot)` (comparing against a remembered
  `buildEditSlotLast`), threaded into the ONE call site tied to the real chain editor (`buildSlotBox`'s own
  `ProcessorBox(...)` call, BuildPage.swift). Both surfaces Paul originally named — the MIDI-chain box grid
  (`buildProcBox`) and the tab strip above the panel (`buildProcCardTabs`/`buildProcTab`) — already write the SAME
  `buildEditSlot`, so both get the directional treatment for free, no separate wiring per surface. The OTHER
  `ProcessorBox` call site (the chord-sequencer popup, `buildChordSeqEditor` — a 4-slot radio with no real chain
  position) keeps the `swapDirection` default (+1) — still gets slide+fade, just not adaptively directional; not a
  regression (it had no transition beyond the shared cross-fade before either). **UNCHANGED, flagged again for
  clarity:** still fires ONLY on an actual TYPE change (the existing `.id(ft)` mechanism) — switching between two
  same-typed slots (e.g. two ARPs with different params) still shows nothing; that's the separately-flagged gap from
  the mockup's own "same-type switches" toggle, not addressed by this pass. UI-only, no test-target reach (GridUI, as
  always). **DEVICE-OWED:** the 14pt/0.2s feel at real panel size and normal tap cadence, and that rapid back-to-back
  swaps (slot→slot→slot) don't visually overlap or stutter.**
- **▶ FERRY DRAG-AND-DROP — a DEALT cell's transpose now bakes into the chain, not a machine field (2026-09-28/29, on
  `main`, `9272248`; iOS builds; DEVICE-ear owed). Paul asked me to investigate circumstances where dragging a SELECT-
  grid cell onto a play ferry changes its output. Traced the whole path (`buildFerryDrop` → `buildPopulateFerry-
  FromSelect` → `buildPopulateFerry` → `buildNewTabMachine`) against what the SELECT-grid audition actually plays
  (`buildGridSelLoadChain`, `composeSceneMeta`). **ROOT CAUSE:** a DEALT (tab 0, "RE-DEAL" bank) cell carries a per-
  archetype REGISTER transpose (`Dice.transposeFor`: bass −12, arp/sparkle +12, pad/wild ±12 — a full octave, not a
  rare amount). The SELECT-grid audition bakes this as a LEADING `.transpose` UTILITY PROCESSOR inserted at chain
  position 0 (`buildGridSelLoadChain`) — so it shifts the notes BEFORE the rest of the chain runs. `buildPopulateFerry`
  instead handed the same number to `buildNewTabMachine` as a MACHINE-LEVEL `transpose` field, which `Router.
  machineTranspose` applies AFTER the whole chain has already composed (added directly to the chain's already-composed
  OUTPUT — confirmed e.g. at the ECHO-tail sites, Router.swift ~2071/2100). Pre-chain vs. post-chain transpose is only
  mathematically identical for a chain that's pitch-shift-transparent throughout; it diverges the moment any stage's
  result depends on ABSOLUTE register rather than a relative offset (chiefly the hard 0–127 clamp, "out-of-range notes
  drop" — Router.swift:4366 — or a chain that layers its own further octave movement on top of the archetype's own
  ±12) — so the exact notes that come out could differ between what was previewed and what plays from the ferry, same
  chain, same transpose number. **SCOPE:** only an UNEDITED bank-0 DEALT cell — the moment any processor-card param is
  touched, `buildApplyChain`'s existing "EDIT = COMMIT" path (2026-09-12) bakes the chain into `buildGridSelOverride`
  WITH the transpose already inserted as a real chain slot, so both paths agree from then on. MY LIBRARY cells (tab 1)
  and cell-to-cell copies always carry transpose 0 (`buildGridSelChainAt`), so they were never affected. **TWO
  THEORIES CHECKED AND RULED OUT** (traced, not assumed): a receiver/emitter "sticky" mismatch — doesn't exist, both
  paths read `buildSelReceiver`/`buildDefaultEmitters` live and `buildPublishScene` re-resolves the audition's door on
  every edit; a stale/un-committed live edit — already covered by the 2026-09-12 EDIT = COMMIT fix. **FIX:**
  `buildPopulateFerry` now bakes `transpose` into `chain` the SAME way `buildGridSelLoadChain` does (a leading
  `ProcessorSlot(type: .transpose)`, clamped ±24, inserted at index 0) before calling `buildNewTabMachine` with no
  machine-level transpose — so the dropped ferry's chain sees exactly what the SELECT-grid preview's chain saw.
  `buildNewTabMachine`'s `transpose:` param/machine-level path is untouched (its only other caller already passes the
  default 0). UI-glue code (BuildPage.swift, not in the macOS test target) — no new unit test, matching every prior
  GridUI-only fix in this file. **DEVICE-OWED:** a BASS/ARP/SPARKLE/PAD/WILD DEALT cell with a register-sensitive chain
  (near the keyboard extremes, or with its own octave-shifting stage) actually sounding identical before/after the
  drop now.**
- **▶ ROOMS WORKBENCH — the machine column moved LEFT of the grid; its trash/verb-button flanks swapped (2026-09-28,
  on `main`, `1c902c6`; iOS builds; DEVICE-eye owed). Paul: move the whole right column (receiver toggles · machine ·
  emitter toggles) to the left instead of the right, and swap the LIBRARY/MUTATE/RANDOMIZE/CLEAR verb-button stack
  with the trash/row-rail flank around it. **PAGE LAYOUT:** `RoomsPage.roomsWorkbench`'s HStack order flipped —
  `chainPanel` (the receiver strip · machine box · emitter strip) now renders FIRST (1/3, LEFT), the active grid
  (SELECT or PART, 2/3) now RIGHT — was grid-left/chain-right since the 2026-09-08 workbench merge. **MACHINE-BOX
  FLANKS:** inside `roomsMachineStrip` (BuildPage.swift), the two flanks either side of the MIDI-chain block swapped
  — `buildChainButtonStack` (LIBRARY/MUTATE/RANDOMIZE/CLEAR) now LEFT, the `ZStack{roomsMachineRowRail (PART only) ·
  roomsChainTrash}` now RIGHT — in both the populated-chain branch and the faded empty-part-row placeholder branch, so
  the two stay visually consistent. **HIT-TEST FOLLOWED THE MOVE:** `buildProcBox`'s drag-to-delete gesture detected
  "over the trash" via `drag.location.x < -6` in the chain block's own "chainBlock" coordinate space (the trash sat at
  negative x, the LEFT flank) — now `drag.location.x > blockW + 6` (positive x past the block's own right edge,
  `blockW = w·2 + gap` computed locally from the per-box width already in scope), matching the trash's new RIGHT-flank
  position. The ferry-drag trash hit-test needed no change — `roomsChainTrash` registers its drop zone via real
  on-screen geometry (`FerryZoneKey`/`.named("rooms")`), so it tracks wherever the view actually renders. The chain's
  own IN/OUT velocity-meter overlay (`buildChainFlowOverlay`, left circle = input door, right circle = emitted output)
  is untouched — it reads MIDI flow direction through the chain, independent of which flank the buttons/trash occupy.
  **NOT TOUCHED:** the PART grid's own internal row-select rails (chevron rail left / numbered rail right, inside
  `roomsPartGrid` itself) — a separate, unrequested feature; only the machine-box's own flanks and the page-level
  grid↔machine order moved. **DEVICE-OWED:** the whole re-arranged layout on a real screen, and that dragging a chain
  box to the NOW-right-side trash still deletes it (the hit-test math is unit-untestable — GridUI has no test-target
  reach, same as every prior playhead/layout fix in this file).**
- **▶ ROOMS WORKBENCH — the left/right layout swap REVERTED (2026-09-29, on `main`, `28641fb`; iOS builds). Paul: back
  to the original layout. A clean `git revert` of `1c902c6` (same-day, "move the machine column to the left, swap its
  trash/verb-button flanks") — applied with no conflicts against this session's other BuildPage.swift edits (all in
  unrelated regions). Restores: `roomsWorkbench`'s top-level HStack back to GRID (2/3, LEFT) · MACHINE BOX (1/3,
  RIGHT); within the machine box, TRASH/row-rail flank LEFT · verb buttons (LIBRARY/MUTATE/CLEAR) flank RIGHT, for
  both the populated and the faded-empty-row layouts; the chain-box drag-to-delete hit-test back to `drag.location.x
  < -6` (was `> blockW + 6`). Net: `1c902c6` is now fully undone, nothing else changed.**
- **▶ PLAY FERRIES — M/S collapsed to a single SOLO button (2026-09-29, on `main`; iOS builds; DEVICE eye owed). Paul:
  replace the mute+solo pair under each play ferry with one "SOLO" button, same size. `roomsPlayFerry`'s `HStack { M;
  S }` (each half-width) is now one full-width `Text("SOLO")` calling `buildToggleFerrySolo(t)` — same amber-when-
  soloed styling the S button had, same overall footprint/height (`selH`, matching the selector row above it) the
  M+S pair used to fill together. **MUTE'S UI IS GONE, its plumbing ISN'T:** `buildToggleFerryMute`/
  `buildPlayColMute`/`buildFerryAudible`'s mute check, and the ferry-move carry-over that copies a source ferry's
  mute state onto its target, are all UNTOUCHED — a ferry can still end up muted (an old saved doc, a future code
  path) and `buildFerryAudible`/the silenced-dimming visual will still honor it correctly; there's just no button
  left to SET it. Scoped to exactly what was asked (a UI button, not a feature removal) — flagged in case Paul
  actually meant to drop mute everywhere, not just its ferry-row control.**
- **▶ EMITTER TOGGLES — zero emitters is now selectable, chase-pulses an invite when reached (2026-09-29, on `main`;
  iOS builds; DEVICE eye owed). Paul: let the MIDI-OUT A–D toggles go to nothing selected, and when they do, animate
  all four "in order" to invite a pick. **REACHING ZERO:** `buildToggleBus`/`buildToggleBusAll` (BuildPage.swift)
  each had a `if buses.isEmpty { buses = [bus] }` guard — "never leave a row with no output" — removed from both, so
  toggling off the last emitter now actually lands on an empty set instead of snapping back on. That alone wasn't
  enough: TWO resolvers upstream of the toggle also forced non-empty — `buildRowEmittersResolved` treated an
  explicitly-empty per-row override the SAME as no override at all (`if let own, !own.isEmpty { return own }; return
  buildDefaultEmitters` — an empty `own` fell through to the default) and `buildDefaultEmitters` itself collapsed
  `buildPartEmitters.isEmpty` to `[.a]`. Both changed to respect an explicit empty set as a real value — nil (never
  touched) is still the only thing that falls through to a default now. Safe precedent already existed: the
  fresh-cell `buildIONullPending` state already runs the engine at busMask 0 on purpose ("the fresh cell is SILENT
  until wired") — zero real emitters was already a proven-safe engine state, just not reachable through ordinary
  toggling before this. Checked every reader of both resolvers first (all either `.contains()` or pass the Set
  straight into `chainEmitters`/`p.emitters` — no force-unwraps assuming non-empty). **THE INVITE:** a NEW
  `emitterChaseLevel(date:index:count:)` — a cosine bump per toggle index, phase-offset by its position (0…3) over a
  ~1.2s lap, cubed to sharpen the peak so ONE toggle reads "lit" at a time as the brightness sweeps A→B→C→D — drives
  a new `chaseIndex: Int?` param on `buildIOSelectChip`, wired only from `buildEmitterToggles` when the resolved set
  is empty AND it isn't the separate (already-static) `buildIONullPending` invite. Deliberately a DIFFERENT, animated
  treatment from that existing static cyan keyline (Paul 2026-09-08 flattened THAT one from a breathe to a steady
  mark) — this is a distinct state (a normal, previously-wired cell the user emptied out) with its own fresh, explicit
  ask for motion, not a reversion of that earlier call. The MIDI-IN receiver chip (the OTHER `buildIOSelectChip`
  caller) is unaffected — `chaseIndex` defaults to nil there.**
- **▶ SELECT GRID — the play badge left-aligned + vertically centred (2026-09-29, on `main`, `2276dcb`; iOS builds;
  DEVICE eye owed). Paul: match `roomsPlayFerry`'s own icon placement. `buildGridSelCell`'s play badge (added
  2026-09-28) moved from `.frame(alignment: .bottomTrailing)` + a same-order `.padding(4)` — which padded OUTSIDE an
  already-full-size frame rather than insetting the icon, a minor pre-existing mis-order — to `.padding(.leading, 4)`
  THEN `.frame(width: w, height: h, alignment: .leading)`: pads the icon first, then places the padded icon at
  `.leading` (horizontal-leading + vertical-CENTER, SwiftUI's `Alignment.leading`), mirroring the ferry button's own
  `HStack { icon; …; Spacer() }` inside a full-bleed `.overlay` (left-hugging content, vertically centred by the
  overlay since the HStack's natural height is shorter than the button).**
- **▶ PROCESSOR EDITOR — the OUT piano: latency cut to ~30fps + a stop/restart freeze fix (2026-09-29, on `main`,
  `cf14cdc`; iOS builds; NEITHER symptom is off-device reproducible — DEVICE-owed, best-effort root cause). Paul: "is
  there a way to get rid of the latency on the piano that represents a processor's output? Also, the piano animation
  stops working when I stop then restart the host transport." **LATENCY:** `buildOutHeld`/`buildRiffDrunkPos`
  (`AudioUnitViewController.swift`) were polled inside the 4 Hz diagnostic `.onReceive(timer)` — a real, quantifiable
  250ms worst-case lag behind the actual audio. Moved both to the existing ~30fps `.onReceive(meterTimer)` (the SAME
  timer the emitter/receiver peak meters already use for "low latency", per its own standing comment) — cuts the
  worst case to ~33ms. `cellSoundingNotes`/`riffDrunkPosAt` are plain live reads (a `voices[]` scan / array index, no
  draining queue — confirmed in Router.swift before relying on it), so polling them 8× more often is safe, no
  double-consumption risk. **THE FREEZE:** root-caused by reading, not an empirical device trace (neither symptom is
  reproducible off-device) — flagged as best-effort. `buildTruthStrips` (the IN/OUT piano view) computed its OWN
  "is MIDI reaching this instance" flag (`proc`) inside a `TimelineView(paused: animationsPaused || !dynamic)`, where
  `dynamic` required `buildDisplayVoice == .part && d.effectivePlaying && (…playing…)` — the ONE paused-gate in the
  whole file keyed on transport/effectivePlaying-derived state (every other `TimelineView` pause condition is either
  app-visibility (`animationsPaused` alone) or a plain `!d.playing`, not this specific compound). A TimelineView
  paused by transport state is a plausible spot to wedge across a stop→restart cycle, since its OWN schedule is
  exactly the mechanism that would need to notice the restart to resume ticking — and this mechanism was BRAND NEW
  (shipped alongside the OUT piano itself, `25dc00f`, earlier the same day), never exercised against a stop/restart
  cycle before now. **FIX:** `proc` is now `buildOutProcessing`, a plain `@State` computed in the SAME 30fps poll as
  `buildOutHeld` (`buildProcessing(at:)`, unconditional on `dynamic`) — `buildTruthStrips` reads it directly, no
  TimelineView of its own anymore. A plain `@State` write always forces a re-render (no schedule to get stuck);
  same 30fps refresh rate as before (no responsiveness regression) — and CHAIN-audition mode now gets the same fast
  treatment `dynamic`'s part-only gate never gave it. UI-only, no test-target reach (GridUI, as always).
  **DEVICE-OWED, both fronts:** the latency actually reads as fixed: and — the one I can't fully stand behind without
  a device trace — that a stop→restart cycle no longer freezes the piano. If it still does, the next place to look is
  `buildTransportEdge`'s `buildHostHalted` guard (`if buildHostHalted { …; buildPublishScene() }` on resume) — three
  OTHER call sites (`buildSetFerryPlay`, `buildTogglePlayGrid`, `buildRequestWorkshopVoice`) can clear
  `buildHostHalted` to false WHILE the transport is still stopped, which would skip the resume republish entirely if
  one of them fires between a stop and the next start; ruled less likely only because it should affect audible
  playback too (not just this display), which Paul didn't report — flagging in case the piano fix alone doesn't hold.**
- **▶ SELECT GRID — the picked-cell recolour reverted; the selected colour moved to a border + a play badge (2026-09-28,
  on `main`, `cbb3bb2`; iOS builds; DEVICE eye owed). Paul: revert the 2026-09-27 change where a picked-but-uncommitted
  SELECT cell's notes wore the active ferry's colour — back to plain grey ink — and carry that "selected colour" on the
  cell's FRAME instead, plus a PLAY BADGE styled identically to the play-ferry buttons' own PLAY icon, including the
  same velocity-flash animation. `BuildGridSelector.swift`'s `buildGridSelCell`: `rollTint` for the `selGrey` case is
  back to the unconditional `Color(white: 0.22)` (no `buildActiveFerry` read); a new `selectedHue` (same
  `buildActiveFerry.map { Color(hex: buildFerryHex($0)) } ?? Color(white: 0.22)` expression the notes used to read) now
  colours the `sel` frame stroke (was plain black for `selGrey`) AND drives a new play badge — `flashingIcon("play.fill",
  …)` (the SAME shared helper `roomsPlayFerry`'s own running-ferry icon uses, incl. its real-time velocity flash via
  `buildFlashLevel`/`meters.cellHitVel`), fed the cell's own `buildChainAuditionRow` strike index, bottom-trailing corner,
  shown only for `selGrey`. **ENGINEERING NOTE:** `flashingIcon` was `private func` in `BuildPage.swift` — Swift's
  `private` is file-scoped, so a same-type call from a different file (`BuildGridSelector.swift`, both extend `DiagView`)
  wouldn't compile; opened it to `internal` (dropped `private`) since it's now a cross-file shared helper, no behaviour
  change for its existing caller. UI-only, no test-target reach (GridUI, as always). **DEVICE-OWED:** the badge's size/
  corner placement at real grid-cell dimensions, and whether the border-recolour reads clearly against the light
  `buildSelectGrey` face it sits on.**
- **▶ OUT PIANO — fixed showing nothing, TWO bugs found chasing one report (2026-09-28, on `main`, `2eea46c`; macOS
  1141 green, iOS builds; DEVICE-owed). Paul, on the piano-swap feature above: "it doesn't work, I'm seeing nothing
  output," then "never showing, whichever method I use to get to the processor" — confirmed via a ferry actually
  playing. **BUG 1 (real, but not the actual cause here):** `Router.auditionRender` (press-and-hold single-cell
  preview, transport stopped) never tagged its emitted voices with `currentCellIndex`/`currentMachineIndex` at
  all — every audition voice inherited whatever a PRIOR real scene render last left in those globals (or -1). SEAL
  comet/`cellSoundVel`/`cellNoteHead`/the new `cellSoundingNotes` all key off `voices[].cellIndex`, so an audition
  was invisible (or misattributed) to every one of them, not just the new piano — fixed with the same save/set/
  defer-restore idiom `emitColumnRatchetPattern` already uses for the identical need. **BUG 2, THE ACTUAL CAUSE:**
  `buildPartColumnNow` (reused for the new `buildOutputCellIndex`) and its two playhead call sites
  (`roomsPartPlayhead`, `roomsCardRowPlayhead`) + `buildTruthStrips`' own `dynamic` flag ALL gated on `d.playing` —
  which `Diag.swift` documents explicitly as "the HOST transport flag (raw)". A ferry playing via FREE-RUN (no host
  transport running) made all four think nothing was playing. `d.effectivePlaying` ("host OR free-run — the UI's
  'is anything really playing' tell") already exists for exactly this distinction; these four just never used it —
  fixed together so the visible part-grid playhead, the card-header row playhead, and the OUT piano can no longer
  disagree about whether a free-run-only ferry is "playing." **DEVICE-OWED:** confirm the OUT piano lights up during
  a free-run ferry AND host-transport playback, and that the part-grid/card-header playheads now sweep during
  free-run instead of sitting frozen (a pre-existing symptom of bug 2 that predates this piano feature entirely —
  may explain other "the playhead doesn't move" reports if any were ever filed against free-run specifically).**
- **▶ PROCESSOR EDITOR — a one-shot cross-fade when the shown type changes (2026-09-28, on `main`, `b36026d`; iOS
  builds; DEVICE-owed). Paul: picking a different chain box (ARP→RATCHET) swaps the controls with nothing marking
  that it happened. ROOT CAUSE: the controls panel carries NO type identity of its own — the old header (emblem ·
  name · BYPASS/DELETE/CANCEL/DONE) was removed entire on 2026-09-10 as too heavy; the only surviving "ARP" vs
  "RATCHET" signal is a small tab label in a horizontal scroll strip above the panel, easy to miss once your eye is
  in the controls. Paul picked the transition over reviving a header. **FIX:** `ProcessorBox.body`'s one call to
  `typeParams(ft)` gained `.id(ft)` (a type change is a fresh view identity, not an in-place diff) +
  `.transition(.opacity)` + `.animation(.easeInOut(duration: 0.18), value: ft)` — a brief cross-fade catches the
  MOMENT the controls change. Lives in the shared component (not BUILD-specific), so it applies everywhere
  `ProcessorBox` renders. Explicitly NOT the same class of thing as the looping/strobing chain-box focus indicator
  Paul ruled out on 2026-09-08 — this is one-shot, tied to a real state change, not a resting-state animation.
  **DEVICE-OWED:** whether 0.18s reads as "caught it" without feeling laggy when tapping quickly between boxes.**
- **▶ PROCESSOR GRIDS — missing/wrong live sweeps fixed across 6 processors; the sweep redesigned as a pulse glow
  (2026-09-28, on `main`, `dce2d9c`; macOS 1141 green, iOS builds; DEVICE-eye owed on the whole look). Paul: "the
  processors have grids and many of them don't show the sweep... one important example is riff," plus "I don't like
  the appearance of the current sweep" — asked for an audit + visual proposals first (an artifact mockup: column
  wash · needle · pulse glow · header tick, against the honest current baseline), then picked **pulse glow**, and
  separately said not to bother with MUTE MATRIX's own (correct, just 4Hz-choppy) sweep. **AUDIT, then FIX (each
  reusing the ENGINE'S OWN resolve formula directly — spot-checked in Router.swift/Derivations.swift line by line
  before writing the UI clock, this project's own standing rule, not re-derived from the UI's own comments):**
  **RIFF** had ZERO live-sync anywhere (rank matrix, OCT lane, ACCENT/TIE/SLIDE all raw/static) — now calls
  `riffStepAt` directly, the SAME pure function `Router.emitRiffRow` calls, across all 5 non-stateful direction
  modes; DRUNK initially shipped deliberately unlit (its true position is per-cell RENDER-THREAD state this UI layer
  has no access to) — **fixed same day, see the DRUNK addendum below.** **VELOCITY** (both its lanes), **BURST** pattern, **TUTTI** pattern, and
  **CHORDS** degree matrix all had a sweep, but it always read the generic scene grid clock despite each having its
  own independently configurable rate/span (CHORDS' own code comment says it outright: "a chord per rate-tick, not
  per grid column") — each now gets a bespoke `StateMatrixClock` matching its real engine math (VELOCITY mirrors
  RATCHET's exact `driverNoteRate`-unknown guard for its NOTE clock mode; BURST's ROTATE is NEGATED relative to
  every other processor's convention — confirmed by reading `burstSliceAt`'s `(i − rotate)`, not assumed). **MOD's
  STEPS lane — found only while implementing, NOT in the original audit** — same gap, fixed by factoring the exact
  period math `modLiveCC` already used into a shared `modPeriodBeatsUI`, so the lane and the existing live CC marker
  can't disagree. **THE VISUAL:** the old thin top-edge line + faint background bump is replaced everywhere by ONE
  shared `pulseGlowOverlay` (a breathing white stroke + glow, ~1.67Hz, independent of tempo) — always plain white,
  never a second hue, so it reads consistently over whichever colour a processor's own cells happen to be; threaded
  through `stateMatrixRadio`, `sliderLane` (which also gained the same `clock:`/`liveColOverride:` bespoke-clock
  capability `stateMatrixRadio` already had), `toggleLane`, and a new `riffToggleLane` live hook. A new shared
  `liveCol(from:at:)` factors the "clock → live column" arithmetic that was previously hand-duplicated across
  `stateMatrixRadio` and `sliderLane` into one function, so a bespoke clock fed to two different widgets (VELOCITY's
  lane + its BYPASS toggle) can't disagree by construction. UI-only — no engine/render change, no new tests (nothing
  NEW to test; the engine formulas being matched are already covered, this is display code with no test-target
  reach, same as every prior playhead fix in this file). **DEVICE-OWED:** the pulse-glow legibility/rate on a real
  screen, RIFF's 5 direction modes actually tracking what's heard, and BURST's negated-rotate sweep against a real
  ROTATE drag. **DRUNK ADDENDUM (2026-09-28, same day, `5cea4db`; macOS 1141 green, iOS builds): Paul asked what it'd
  take to cover DRUNK too.** Checked the actual mechanism before proposing anything: `LiveTelemetry.beatAnchor`
  (`AudioUnitViewController.swift`) RE-SYNCS to the host's real beat position on a transport edge — it does NOT reset
  to zero — so a UI-side replay of the walk from an inferred restart point would silently diverge from the true one
  after the very first tick (the seed hash is tick-EXACT; being one tick off sends the whole subsequent walk down an
  uncorrelated path). That ruled out faking it client-side, confirming the earlier "can't safely replay" call was
  right, not just cautious. **FIX: read the true value instead.** `Router.riffDrunkPosAt(cellIndex)` — a plain array
  read of the existing `riffDrunkPos` state, mirroring `cellSoundingNotes`'s exact shape (the SAME UI-poll precedent
  the OUTPUT-piano entry below this one just established) — threaded through Kernel/`MidiSparkAudioUnit` as
  `pollRiffDrunkPos`, polled in `AudioUnitViewController`'s existing `editorOpen` block at the SAME cadence and SAME
  `buildOutputCellIndex` as the OUTPUT piano, into a new `buildRiffDrunkPos` → `ProcessorBox.riffDrunkPosLive`.
  RIFF's live-sweep closure reads it directly for DRUNK instead of computing a step. **Honestly capped, not
  shortcut:** the indicator jumps between columns at the diagnostic poll rate (~4Hz) rather than sweeping — the same
  ceiling MUTE MATRIX hit — because DRUNK's position genuinely isn't a predictable function of wall-clock time, so
  there's nothing smoother to extrapolate. No new tests (a UI-poll passthrough, same class as `cellSoundingNotes`
  itself, which also shipped untested — no test-target reach). DEVICE-OWED: confirm the jump reads as "the true
  position, updating slower" rather than as broken. **VISUAL FOLLOW-UP, same day (`31c88a1`; iOS builds): Paul —
  "I need only the selected cell to animate, not the entire column. I also want a playhead on the header of the
  column."** The per-cell glow lit every row at the live column (a `stateMatrixRadio` matrix is radio-per-column, so
  every OTHER row's cell there is off, but it still glowed) — narrowed to `live && on`, so only the actually-
  selected/sounding cell animates; applied to `stateMatrixRadio`'s main rows, CLOCK's GLIDE `extraRowCell` (shares
  the same live-column highlight, so it follows the same rule), and RIFF's own rank matrix (POLY mode can still
  glow several ranks at once — correctly, since several genuinely sound together there). OCT/ACCENT/TIE/SLIDE and
  the `sliderLane`/`toggleLane` lanes are untouched: one row = one cell already, nothing to narrow. New
  `playheadHeaderRow`: a thin strip above the grid reusing the SAME `liveCol`/`date` the cell glow reads (so the
  two can never disagree), showing a small chevron at the live column — SNAPS exactly, no fractional glide, since a
  RANDOM/DRUNK-class jump has no meaningful in-between position to interpolate through. One shared function, wired
  into `stateMatrixRadio` (covers RATCHET PATTERN/DEST/CLOCK/KILL STEP/BURST/TUTTI/LENGTH/CHORDS at once) and
  RIFF's rank matrix. **CAUGHT BEFORE SHIPPING, not after:** the first build of this actually FAILED — a
  `.frame(maxWidth:, height:)` call mixed two incompatible SwiftUI `.frame` overloads (this codebase's own
  convention is two chained `.frame()` calls, not one combined call) — a stale-looking background-task notification
  claimed success while the real log said `BUILD FAILED`; caught by tailing the actual log instead of trusting the
  notification, fixed, rebuilt clean before pushing. DEVICE-OWED: the header chevron's legibility/size, and whether
  a POLY-mode multi-cell glow at one column still reads clearly now that MONO's is down to one.**
- **▶ PROCESSOR EDITOR — the OUT truth strip is now a second piano, not a scrolling roll (2026-09-28, on `main`,
  `25dc00f`; macOS 1140 green, iOS builds; DEVICE-owed). Paul: IN/OUT were mismatched widgets (IN a piano of held
  pitches, OUT a piano-ROLL of drifting recent onsets) for what's really the same idea; make OUT a second piano.
  The existing OUT feed (`buildOutRoll`, an onset-only ring with no note-off tracking) structurally can't answer
  "what's held right now" — fixed by reading the render engine's OWN voice pool instead of re-purposing the onset
  trail: new `Router.cellSoundingNotes(cellIndex:)`, a same-shape sibling to the existing `cellSoundingVelSnapshot()`
  — a snapshot scan of `voices[].cellIndex`/`.active` (already tracking genuine hold-duration for note-off
  bookkeeping; no new render-side state, just a new read of what's already there). Threaded through Kernel/
  MidiSparkAudioUnit as `pollCellSoundingNotes`, polled into a new `buildOutHeld` array on the SAME `editorOpen` gate
  and cadence as the existing OUT-roll poll. **Needed its own cell resolution:** the existing focus-cell mechanism
  (the chain-flow comets) only covers chain audition, not a part row's processor — so `buildOutputCellIndex(at:)`
  mirrors `buildProcessing(at:)`'s own chain/part/none switch exactly (same rung/column gating), returning the
  `Snap.cells` index instead of a bool, so the OUT piano and the existing "is this instance processing" gate can
  never disagree about which cell is live. `buildInKeyboard` renamed `buildKeyboardStrip` (now serves both IN and
  OUT, 4 call sites); `buildOutStrip`/`buildRollCanvas` deleted (their only caller) — `buildOutRoll`/`OutMark` kept,
  the Stage Eye's separate OUTPUT lane still uses them. **DEVICE-OWED:** confirm the OUT piano lights the right keys
  against real playback (chain audition AND a part row), and dims/empties correctly when the editor's instance isn't
  the one currently sounding.**
- **▶ PART GRID — the multi-select playhead now sweeps every active row, not just the lead (2026-09-28, on `main`,
  `9232edf`; iOS builds). Paul: with MULTI selected, the playhead "doesn't always sweep over active cells when more
  than one is selected in a column" — three rows selected somewhere on the part, only two ever shown. ROOT CAUSE: a
  documented v1 shortcut from when multi-select shipped (2026-09-27) — the per-cell highlight (dimming + the white
  selection ring) already correctly used `buildActiveRungs` for every active row, but BOTH playhead renderers
  (`roomsPartPlayhead`, the grid's own sweep, and `roomsCardRowPlayhead`, the card/rail row selectors' mini-sweep)
  still read only the column's single "lead" rung. Since the lead is whichever row was MOST RECENTLY toggled per
  column, different columns can easily land on different leads — so sweeping across several multi-selected columns
  shows only whichever rows happened to be lead somewhere, never the full set together, exactly the reported symptom.
  FIX: both now read the same `buildActiveRungs(c)` the highlight already relied on — `roomsPartPlayhead` draws one
  bar per active row at the column's sweep position (a `ForEach`, was a single conditional bar); `roomsCardRowPlayhead`
  lights row `n` whenever `buildActiveRungs(c).contains(n)`, not only `r == n`. DEVICE-eye owed, as always.**
- **▶ ARP — the embedded Euclid mask removed, superseded by the standalone processor (2026-09-28, on `main`,
  `2063381`; macOS 1146 green, iOS builds). The arp-only `arpMask*` controls (HITS K/N, GAPS REST/TIE/CHORD, ROTATE,
  the CHORD-gap stab's OCT/LEN/VEL) were fully superseded by the newer standalone EUCLID MASK processor (`mask*`,
  landed 2026-09-27/28), which gates ANY driver — including ARP, via `[ARP → EUCLID MASK]` — and has since grown
  well past parity (INVERT, SPAN, CHANCE, ACCENT LAYER, FILL, CHORD PICK, none of which the arp-embedded version
  ever had). Paul asked for the redundant original removed. The one capability lost is WALK/WAIT (the walk advancing
  only on hits instead of marching through rests) — already an accepted, disclosed trade-off from when the
  standalone processor was built (a downstream fold can't reach a driver's own phase-index the way an embedded mask
  could) — nothing new lost by this cleanup. Removed: the `MachineParams`/`SnapParams` fields, `SnapshotBuilder`'s
  resolve, the `ArpMaskWalk` enum (confirmed zero other users), the engine block in `emitArpRow`, the ARP editor's
  UI controls, and the `AutoParamField` LFO-target cases — Swift's own exhaustive switches caught every call site
  that needed a matching removal. Two tests genuinely covering capability the standalone processor ALSO has (the
  chord-gap stab's OCT/VEL/GATE independence) were PORTED to chain `[ARP → EUCLID MASK]` instead of deleted, passing
  unmodified on first run — confirming the standalone fold's chord-gap math matches the removed version exactly;
  tests covering only the arp-embedded wiring itself (including one exercising WAIT, which has no replacement) were
  removed outright. **FLAGGED, not fixed here:** the standalone EUCLID MASK processor has NO param-LFO targets
  registered anywhere, unlike the version it replaces (which exposed HITS/ROTATE/CHORD-OCT/CHORD-LEN to the `∿`
  modulation system) — a real capability gap, found while removing the old version, separate scope to restore.
  **LFO RESTORED (2026-09-28, `0b41225`; macOS 1147 green): Paul asked for the flagged gap fixed.** ROOT CAUSE of why
  this wasn't a one-line UI wire-up: `applyParamLFO` (the `∿` engine) resolves every non-`"arpRate"` target through
  `AutoParamField` — the SAME enum the removal above correctly stripped its old `arpMask*` cases from. So restoring
  the control needed NEW `AutoParamField` cases (`.maskK`/`.maskRotate`/`.maskChordGate`/`.maskChordOct`) pointing at
  the standalone processor's own fields, plus the five GridUI switches that seed/format/edit an LFO's FROM/TO value
  by target-name string (`lfoLabelText`/`lfoEndpointControl`/`lfoFmt`/`lfoSeedFrom`/`lfoSetBase`), plus `lfo:` wired
  into the four `field()` calls themselves. **Caught by the compiler, not a hand-check:** two more exhaustive
  switches in `Tests/EffectiveParamsTests.swift` locking `AutoParamField`'s key list and clamp bounds needed the
  same 4 cases — the build failed until both were extended, exactly the safety net exhaustive switches exist for.
  +1 RouterTest (`testEuclidMaskKLFOModulatesDensity`, restoring the coverage the removed
  `testArpMaskKLFOModulatesEuclidDensity` had, chained after an ARP driver on the standalone processor's own `maskK`).**
- **▶ CHAIN EDITOR — fixed a stale edit-slot showing an empty box's PASSGATE identity after a drag-reorder
  (2026-09-28, on `main`, `1585c28`; iOS builds, macOS 1147 green). Paul: "a pass gate processor sometimes shows
  when it's not part of the MIDI chain." Root-caused, not guessed: an empty/placeholder chain box is INTERNALLY
  represented as a bypassed PASSGATE slot (`buildPassthroughSlot`, `buildIsEmptySlot` — this is load-bearing
  plumbing, not incidental). `buildChainMoveSlot` (drag-to-reorder) vacates the DRAGGED-FROM box into exactly that
  placeholder, but never updated `buildEditSlot` — so if the user was editing the box they then dragged elsewhere,
  `buildEditSlot` kept pointing at the now-empty original position. The main processor panel's render guard
  (`roomsProcessorCardAt`) only checked array bounds, not emptiness — unlike every OTHER reader of a chain slot (the
  tab strip, the chain-box grid, the drag ghost), which already guard with `buildIsEmptySlot` — so the panel (and
  "the eye" diagnostic view, the same gap) showed that empty box's PASSGATE identity as if it were a real processor,
  purely because the user reordered a DIFFERENT (the moved) processor. **FIX:** `buildChainMoveSlot` now follows
  `buildEditSlot` to the moved processor's new position; added the missing `buildIsEmptySlot` guard to both
  previously-unguarded readers as defense in depth, matching the convention every other call site already follows.
  UI-only; DEVICE-eye owed to confirm the reorder-while-editing flow now keeps the right card open. **SEPARATE ASK,
  NOT YET ACTED ON:** Paul also asked to remove the PASSGATE processor entirely. Flagged back to him rather than
  done blind: PASSGATE is BOTH a user-facing storefront card (the "PASSES" card — pass-gated laps 1–4) AND the
  engine's internal "this chain slot is empty" sentinel (`buildPassthroughSlot`/`buildIsEmptySlot`, `isHoldTailChain`,
  `cellMode`'s pass-based silent/identity logic) AND a generic "identity hold" utility used throughout the test suite
  (~80 references in `RouterTests.swift` alone, most nothing to do with PASSGATE's own feature). Removing the
  user-facing card is a small, safe change; removing the TYPE itself would need a replacement sentinel mechanism and
  touch dozens of call sites plus most of the test suite — asked Paul which he actually means before touching either.**
- **▶ PASSGATE — REMOVED ENTIRELY, the whole type (2026-09-28, on branch `refactor/remove-passgate`, `2839240`; macOS
  1142 green, iOS builds). Direct follow-through on the entry above: Paul answered the three-way flag — "the whole
  type, engine included"; cut factory scene 9 from the sixteen, don't replace; delete test session T13 outright.
  **DECODE SAFETY:** `ProcessorType.passgate` → `.empty`, raw string `"PASSGATE"` KEPT — an old saved cell of that
  type still decodes, landing on `.empty`, now a plain inert passthrough (exactly right: the gating it used to do no
  longer exists to preserve). **DELETED, not renamed (the feature itself):** `MachineParams.passes` ·
  `SnapParams.passMask` / `effectivePassMask` · `cellMode`'s pass-mod-4 branch (`.empty` now just joins the
  always-`.identity` bucket; `cellMode`'s signature dropped its now-pointless `passMask`/`pass` params — 8 call
  sites in Router.swift/Kernel.swift simplified) · the GridUI "PLAY ON PASS" editor row + its self-clocked playhead
  (`livePass`/the dead `passHead` field, found and removed in passing) · the storefront "PASSES" card ·
  MacroAuthoring's dedicated PLAY-ON-PASS binding (folded into the existing bypass-only catch-all bucket every other
  discrete-param type already uses). **RENAMED (sentinel + generic-fixture uses, compiler-driven sweep across ~25
  files):** `buildPassthroughSlot`/`buildIsEmptySlot` and their AU-side/EditPage.swift/Dice.swift twins,
  `isHoldTailChain`'s tail-type list, ~20+ "give me an inert machine" test fixtures. Roster lists that used PASSGATE
  as one of several types to hammer/exclude (FuzzTests' type roster, ChaosDriver's edit-fuzz roster, Dice's factory-
  chain generator's "NO PASSGATE" exclusion, BuildSelfTest's no-stuck-notes roster) had the entry DROPPED rather than
  renamed — `.empty` isn't a real processor a user or generator would ever produce, so it doesn't belong in a "hammer
  every real type" list either. **SCOPE SURPRISE, caught mid-implementation, not pre-planned:** the plan assumed
  only scene 9 used the `pass()` scene-builder DSL helper; grep found THREE more call sites (UNDERTOW, THE LOOP THAT
  ISN'T, PACIFIC) — two used it only in its default all-open state (a plain sustain in musical terms, so converting
  to the new `thru()` helper — same helper, `.empty`-typed, no mask param since none exists anymore — is
  byte-identical), but PACIFIC's "wine" voice genuinely alternated every 2nd pass as a deliberate texture (documented
  in `factory-scenes.md`'s own COLOURS line). No replacement mechanism exists for that alternation now — `wine` was
  converted to a continuous sustain, an honest degradation flagged here and in the scene's own doc entry rather than
  silently absorbed. **ROUTERTESTS.SWIFT (~38 references across 36 functions) forked out** rather than swept blind —
  many asserted the pass-mod-4 gating mechanism as their actual subject, not just used PASSGATE as a fixture. Per-test
  triage: 2 DELETED (`testArpThenPassgateGatesPassZero`, `testPassgateGatesByPassInThePlayingPath` — nothing left to
  assert once the mechanism is gone); 13 SUBSTITUTED `.chance` at `probability: 1.0`/`0.0` for PASSGATE's open/closed
  states (verified exact, not seed-dependent, against `Derivations.chancePasses`'s own hard clamp at the
  probability extremes, before relying on it — not assumed); ~20 mechanical `.empty` renames incl. a shared
  `passgateMachine` fixture helper renamed `holdMachine`. **FACTORY SCENES renumbered 10-16→9-15** in both
  `SceneFactory.swift` (code) and `Docs/factory-scenes.md` (every cross-reference re-derived from the actual
  old→new mapping, not just the headers — caught ALT EGO's own device-test procedure in `Docs/test-procedures.md`
  still citing its OLD scene number 14, now 13, a real cross-doc drift that a header-only renumbering would have
  missed). `Docs/pending-tasks.md` and `Docs/manual/manual-skeleton.md` had their own PASSGATE mentions fixed
  (a stale future-task example list, a manual glossary entry for a feature that no longer exists). **FLAGGED, not
  touched:** `midispark-spec-v2.8.md`/`v3.0-delta.md` still describe PASSGATE's pass-mask behaviour in several
  places — treated as a separate, larger spec-contract editorial pass rather than surgery-by-the-way; `feature-
  status.md` is a self-described already-stale redirect notice, left alone; `status-log-archive.md`/`codebase-
  review-2026-08-16.md`/`router-design.md`/`migration-tree-routing.md` are established-historical and never
  retroactively edited by this project's own convention. **DEVICE-OWED:** confirm no chain anywhere still shows a
  "PASSES" card; an old saved doc with a real PASSGATE cell opens as a silent inert passthrough, not a factory-reset
  or a decode error; PACIFIC's wine sustaining continuously instead of alternating every 2nd pass reads as an
  acceptable finale-scene change, not a loss.**
- **▶ EUCLID MASK — CHORD PICK gains BOTTOM2/TOP2 (2026-09-28, on `main`, `9d38406`; macOS 1141 green incl. fuzz,
  iOS builds; DEVICE ear/eye owed). Paul: add bottom-two/top-two to CHORD PICK. Judgment call, flagged rather than
  asked: rather than extend the SHARED `EuclidPick` enum (also used by the standalone EUCLID driver's own PICK),
  introduced a DEDICATED `MaskChordPick` enum (ALL·LOW·HIGH·BOT2·TOP2·CYCLE·RANDOM) — BOT2/TOP2 strike a PAIR of
  notes, which the driver's own `strikeChord(onlyIndex:)` (one pool-rank at a time) can't express, so reusing the
  enum would have forced an unrelated change onto the driver for a feature Paul didn't ask to touch. Generalized the
  fold's single optional pick index into an INCLUSIVE RANGE (`lo...hi`) — ALL/LOW/HIGH/CYCLE/RANDOM are a range of
  one, BOT2/TOP2 a range of two, one application path for all seven. **CAUGHT WHILE WRITING THE FIX, not by a test:**
  the naive range construction (`max(0,lo)...min(count-1,hi)`) can build an INVALID `ClosedRange` (Swift traps on
  lower > upper) if `count` were ever 0 by the time the range is applied — guarded by checking `count > 0` BEFORE
  constructing the range, not just filtering after; pinned down with a dedicated regression test (BOT2/TOP2 against
  a single held note collapses to one note cleanly, not a crash) rather than left as an unverified guard. +2
  RouterTests. **DEVICE-OWED:** BOT2/TOP2 actually sounding like the intended voicing against a real chord.**
- **▶ RIFF — 6 playhead direction modes: FWD/REV/PENDULUM/PING-PONG/RANDOM/DRUNK (2026-09-28, on `main`, `92042df`;
  macOS 1146 green, iOS builds; DEVICE ear owed). Paul asked for an option to override how the RIFF playhead travels,
  giving precise worked examples for all 6. Found along the way: today's `RiffDir.pingpong` already matched the new
  spec's PENDULUM exactly (hand-verified — bounces, each end played once, cycle 2n−2, n=2 degenerates to FORWARD) —
  the same class of bug as RATCHET PATTERN/DEST/the ARP-rate LFO before it, a control whose name didn't describe its
  own behaviour. **Fixed for free, no migration:** `.pendulum` KEEPS the old `"PING-PONG"` raw value (old saves
  decode byte-identical; the editor now correctly labels them PENDULUM instead of the wrong PING-PONG); the
  genuinely-new bounce-TWICE mode gets a fresh raw value (`"PONG"`) as `.pingpong`; a `displayLabel` splits the
  UI-shown name from the persistence key so both read right. FORWARD/REVERSE/PENDULUM/PING-PONG/RANDOM are all pure
  functions of the existing `raw` tick index — no new state, SPAN re-anchor applies uniformly to all five; RANDOM
  reuses `splitmix64Mix` (the same primitive `ArpPattern.randomOnce` already uses) keyed by a new per-instance
  `riffDirSeed`. **DRUNK is the one genuinely stateful mode** (its own spec: "position carries across cycles") —
  runs against this project's "derived, never accumulated" invariant. Resolved by following the EXACT existing
  precedent for this class of state (DEAL/ALT's per-cell counters, `Router.swift` ~315) rather than inventing
  something new — disclosed, not waved through as pre-approved: the codebase's own architecture review
  (`Docs/codebase-review-2026-08-16.md`, finding A1) already flags that class of state as a known, UNDISCHARGED
  limitation (not replay-exact across a mid-phrase seek/loop), not a blessed exception — this is a deliberate third
  instance of an accepted trade-off, named honestly as such. Keyed on `tick`, NEVER `raw` (a design correction caught
  during planning, not shipped wrong first) — `raw` resets at every SPAN boundary, so keying off it would make the
  walk silently re-sync mid-cycle, contradicting "carries across cycles" outright; `tick` is monotonic and
  SPAN-oblivious by construction. Reset alongside DEAL/ALT on the transport-edge "fresh play" trigger, never on
  panic. A BIAS control (`-1...1`, 0 = neutral, the exact `chanceTilt`/`velTilt`/`bipolarSlider` convention) tilts the
  walk's −1/0/+1 weights via a squared tilt: bias=0 → uniform ⅓ each ("wanders evenly"); bias=+1 → 0%/20%/80%,
  forward-dominant but never deterministic ("Forward with stumbles", hand-verified both extremes before shipping).
  +6 RouterTests (literal n=8 sequences for PENDULUM/PING-PONG, the n=2 PENDULUM=FORWARD edge case, RANDOM seed-
  repeatability + range, DRUNK bounds/step-size across 4 seed·bias combos, DRUNK reset-on-transport-edge). One test
  explicitly NOT shipped rather than shipped vacuous: a SPAN-obliviousness regression guard for DRUNK never showed
  ANY span effect on ANY mode (including FORWARD) under the test harness's `forceColumn:0` bypass — a test-
  infrastructure interaction, not a code defect (the engine change was verified by direct reading, independently,
  twice), flagged inline at the deletion site rather than hidden. Plan: `~/.claude/plans/flickering-dazzling-floyd.md`.
  **TIE LOOKAHEAD FIX (2026-09-28, `04459d3`; macOS 1148 green): Paul asked to fix the disclosed TIE limitation
  above.** RIFF's TIE run always checked array-index `step+1` for "what plays next" — already wrong for REVERSE
  (whose true next step is `step-1`), meaningless once PENDULUM/PING-PONG/RANDOM/DRUNK made "next" stop being a
  fixed offset at all. FIX: factored the 5 non-DRUNK modes' step formula out of `emitRiffRow`'s inline switch into a
  pure `riffStepAt(dir:raw:steps:seed:)` (Derivations.swift) — used for BOTH the current tick's step and the TIE
  lookahead's `raw+1, raw+2, …`, so the two can never disagree (the RATCHET/DEST class of bug: a lookup and its
  lookahead drifting apart). DRUNK gets `riffDrunkPeek` — a NON-MUTATING simulation of the walk forward from its
  current position using the SAME pure per-tick `riffDrunkDelta`, exact (not a guess) since replaying the identical
  future tick indices later reproduces precisely what the real walk will do. Hand-verified against the exact REVERSE
  bug before writing the fix or the test: steps=4, tie on step 2 (REVERSE's true next step after step 3) — the old
  formula checked step 0 (untied, no extension), the new one correctly finds step 2 tied; FORWARD's formula is
  provably byte-identical (same arithmetic, `s ≡ raw (mod steps)` either way). +1 RouterTest
  (`testRiffTieRespectsReverseDirection`, asserting fewer note-ons with the tie painted on REVERSE's real next step
  vs. without it — would have failed under the pre-fix code). SLIDE's own `prevStep = step - 1` lookup (Router.swift,
  a few lines below TIE) has the EXACT same forward-adjacency assumption, in the other direction — noticed while
  fixing TIE, NOT fixed here (Paul asked specifically about TIE), flagged as a likely next ask.
  **SLIDE FIX (2026-09-28, `9561d16`; macOS 1149 green): Paul asked for the flagged SLIDE bug too.** The mirror image
  of the TIE fix: SLIDE's "was the PREVIOUS step a slide" check always looked at array-index `step-1` — already
  wrong for REVERSE (whose true previous step is `step+1`) — so a slide armed at one step could go un-cleared once
  the real next note struck, leaving portamento wrongly armed into a later, unrelated note. Non-DRUNK modes reuse
  `riffStepAt(raw-1)` — the identical pure formula one tick EARLIER, so it can't disagree with the current step by
  construction. DRUNK can't be algebraically un-walked (a reflected random walk isn't invertible from its current
  position alone, unlike TIE's forward case which could reuse `riffDrunkPeek`) — so its previous position is simply
  REMEMBERED instead: new `riffDrunkPrevPos` (Router.swift, beside `riffDrunkPos`), written by `riffDrunkStep` right
  before it moves, reset alongside the walk's other state on a fresh play. Hand-verified against the same REVERSE
  shape as the TIE fix before writing the test: steps=4, slide on step 1 — REVERSE's true next step (0) now
  correctly detects it and clears the portamento; the old lookup checked step 3, found nothing tied, left it armed.
  +1 RouterTest (`testRiffSlideRespectsReverseDirection`).**
- **▶ EUCLID MASK — INVERT, SPAN, ACCENT LAYER, FILL, PROBABILITY, CHORD PICK (2026-09-28, on `main`, `2a54d5d`;
  macOS 1140 green incl. fuzz, iOS builds; DEVICE ear/eye owed). Asked what else the design space supported; Paul
  picked six to build now, in the priority order agreed: INVERT + SPAN first (cheap, closed a real consistency gap),
  then ACCENT LAYER (pencilled in since 2026-09-15), then FILL, PROBABILITY, CHORD PICK. All six are additive-
  Optional fields on the SAME processor — no new chain position. **INVERT** mirrors the sibling EUCLID driver's own
  toggle exactly. **SPAN** re-anchors the K-of-N ordinal to 0 every N notes, sized by the DRIVER's own step (mirrors
  KILL STEP sizing its own span ladder by its own rate) — EUCLID MASK was the one pattern processor in the whole
  codebase (RIFF/EUCLID/RATCHET PATTERN/KILL STEP/CLOCK all already had this) that had shipped without it. **FILL**
  overrides the mask for a whole pass every N passes, reusing `pass` — already a parameter of `emitDriverNote`, the
  SAME authoritative lap counter PASSGATE gates on — no new counter needed. **PROBABILITY (CHANCE)** is an Elektron-
  style trig condition layered on the deterministic skeleton: it can only DEMOTE a hit to a gap, never promote a gap
  to a hit (seeded on the ordinal `g` alone, mirroring HUMANIZE's own inline `splitmix64Mix` idiom — replay-exact, no
  accumulated state), and is skipped entirely on a fill pass. **ACCENT LAYER** is a second, fully independent K/N/
  ROTATE test sharing the SAME `g` as the gate (so a SPAN re-anchor keeps both patterns' relative phase stable) —
  boosts velocity additively on its own hits, like RIFF's own ACCENT lane; K=N (off) by default, matching the gate's
  own no-op convention. **CHORD PICK** restricts a GAPS=CHORD stab to specific chord note(s) — reuses `EuclidPick`
  (ALL/CYCLE/LOW/HIGH/RANDOM) and mirrors the sibling EUCLID driver's own PICK resolution (down to the same RANDOM
  seed constant), keyed on "gaps before `g`" — derived from the ALREADY-TESTED `euclidMaskHitsBefore` via simple
  arithmetic (`g − hitsBefore(g)`), so no new pure function was needed. Ordering inside the fold, precisely: SPAN
  re-anchors `g` → INVERT flips the base pattern → FILL overrides everything for the pass → CHANCE can only demote a
  hit → GAP/HIT resolves as before (now PICK-aware) → ACCENT applies independently in the final emit loop, right
  where TIE's own gate-extension already lands. +6 RouterTests, one per feature, each an inequality/property
  (INVERT's output is the exact complement of the non-inverted run; SPAN < the pattern's own N changes the onset set
  vs FREE; an active ACCENT strictly raises peak velocity; FILL strictly increases note count over several passes;
  CHANCE never increases note count and is provably unreachable with the gate off; CHORD PICK's LOW/HIGH strike only
  one note per gap while ALL strikes the whole chord) + fuzz coverage hammering FILL/CHANCE against TIE/CHORD (the
  paths most likely to leak a stuck voice). Plan: `~/.claude/plans/stateless-tickling-flask.md`. **DEVICE-OWED:**
  CHANCE's feel at various probabilities, ACCENT audibly popping against the base hits, FILL reading as a turnaround
  not a glitch, CHORD PICK's CYCLE/RANDOM actually rotating through a real chord.**
- **▶ KILL STEP — MUTE + PAUSE step behaviors alongside the original DROP (2026-09-27, on `main`, `f35b595`; macOS
  1134 green incl. fuzz, iOS builds; DEVICE ear/eye owed). Direct follow-through on the reminder set the day EUCLID
  MASK landed: Paul asked to plan whether KILL STEP's one boolean ON/OFF row could grow MUTE ("the step advances but
  doesn't play") and PAUSE ("stops it advancing for a configurable number of steps"), and whether the idea works/is
  musical. Confirmed both — MUTE is the standard step-sequencer mute (a hole, pattern length unchanged); PAUSE has
  real precedent (Elektron trig-condition holds, Metropolix's PAUSE/TIE stage type) — then ratified two calls via
  AskUserQuestion: PAUSE freezes/holds (nothing new triggers; whatever's sounding just rings on — NOT a retrigger/
  stutter) and its hold length is ONE global setting, not per-step. **BUILT:** the boolean row becomes a 4-state
  `KillStepMode` (ON·MUTE·DROP·PAUSE) per step. DROP is the original mechanism, unchanged. MUTE counts exactly like
  ON for the TRANSFORM (the downstream clock advances through it normally) — its whole effect is a new per-note FOLD
  in `emitDriverNote`, the identical shape EUCLID MASK's REST just shipped with, keyed on the note's real onset
  against KILL STEP's own rate (`precedingKillStepMuted`, scanning `0..<driver` like `driverClockBeat` itself).
  **PAUSE broke the old one-line closed form** (`value = lap·steps + onIdx[n mod k]` assumed every real column maps
  to exactly one local step; a hold needs SEVERAL real columns to map to the SAME frozen value) — replaced with a
  small table PRECOMPUTED once per snapshot publish (`killStepResolveTable`, Derivations.swift), off the render
  thread entirely; `killStepPhase`/`killStepPhaseInverse` now do a cheap `table[n mod columnsPerLap]` lookup instead
  of deriving the cycle live. Proven byte-identical to the original formula whenever nothing is MUTE/PAUSE by
  rerouting all 5 pre-existing `killStepPhase` tests through the new table unchanged (same assertions, same
  results). The table is SHARED between `SnapshotBuilder`'s resolve and GridUI's live-playhead preview (one
  function, so the lit cell and the audible step can't drift apart — the standing RATCHET PATTERN/DEST lesson).
  `killStepEnabled: [Bool]?` stays as a decode-only migration source (true→ON, false→DROP), even though nothing had
  shipped with it device-verified yet — costs nothing to keep. **UI:** the boolean `toggleLane` row is replaced with
  `stateMatrixRadio` (the SAME one-of-N-per-column widget RATCHET PATTERN/DEST/LENGTH already use) — which gained a
  new optional `liveColOverride` closure (mirroring `toggleLane`'s own `live:` shape) so KILL STEP's playhead can
  still call `killStepPhase` directly instead of the widget's generic rotate-clock math (that generic math can't
  express a freeze — using it here would have been a real regression from yesterday's playhead fix). Added a PAUSE
  LEN control. **CAUGHT BY THE TEST SUITE, not guessed (this session's own standing rule):** a first draft's inverse
  round-trip test assumed exactness everywhere, mirroring the pre-existing sweep test's own doc comment — but PAUSE
  makes the forward map genuinely NON-INJECTIVE by design (every real column across a hold maps to the SAME frozen
  value, so a beat landing on the hold's 2nd/3rd column can only invert back to its 1st) — 64 failures, traced to
  the test's premise being wrong, not the implementation; fixed by replacing the blind sweep with the explicit
  "inverts to the first occurrence" case, the SAME policy the pre-existing DROP-gap test already modeled explicitly
  rather than swept. **FLAGGED, not built (scope, not a bug):** MUTE only has an effect when KILL STEP PRECEDES the
  driver it retimes (`[KILL STEP→ARP]`, its own generation) — in the OTHER existing KILL STEP shape
  (`[ARP→KILL STEP→DEST]`, retiming a downstream fold consumer's own clock) there's no note-generation event left at
  KILL STEP's own position to suppress, so MUTE is a no-op there; DROP/PAUSE work in both positions since they're
  pure time-transforms. +3 RouterTests (MUTE keeps timing but silences one note · PAUSE makes several consecutive
  arp ticks land on DEST's same emitter, mirroring `testKillStepTransformsDestsOwnRoutingClock`'s own technique ·
  the legacy `killStepEnabled` migration is byte-identical to authoring the equivalent `killStepMode` directly) + 4
  new DerivationsTests (MUTE counts like ON for timing · a hold freezes for its exact length · the inverse picks the
  first occurrence · all-columns-of-a-hold read the identical value) + fuzz coverage (hammers PAUSE especially, the
  one genuinely new way a driver's own tick search could misbehave). Plan: `~/.claude/plans/stateless-tickling-
  flask.md`. **DEVICE-OWED:** the 4-state matrix's legibility, MUTE actually leaving a clean silent hole vs. DROP's
  compaction, and PAUSE reading as a hold/breath rather than a glitch.**
- **▶ SELECT GRID — the picked cell now survives a trip through PART (2026-09-27, on `feature/ferry-row-
  unification`, `46c0b2d`; iOS builds; DEVICE eye owed). Paul: pick a SELECT cell → open PART → come back → wants the
  SAME cell still in focus. ROOT CAUSE: `roomsPartSetup` always calls `buildRoomsSetActiveSide` to focus a part row,
  which explicitly nils `buildGridSelSel` — the browse-cell pick and a ferry-row focus share ONE underlying value
  (`buildSelectSource`, "one thing active", the 2026-09-06 desync fix) — so every PART entry silently discarded
  whatever was picked on SELECT. FIX: new `buildGridSelLastPick` snapshots the outgoing pick (nil included, so a
  deliberate deselect before leaving isn't resurrected) the moment PART claims the slot; `roomsSelectSetup` restores
  it on a plain return (skipped when a playing part's cell is being carried over instead — `carryFromPart`, an
  existing, more relevant behaviour for that case). Restoring the pick also resumes its chain audition for free,
  since `roomsSyncVoice` already ties "a cell is selected" straight to "it's auditioning."**
- **▶ EUCLID MASK — the arp-only mask pulled into a standalone downstream processor (2026-09-27, on `main`, `d6bb40d`;
  macOS 1116 green incl. fuzz, iOS builds; DEVICE ear/eye owed). Paul asked whether the ARP EUCLID MASK feature
  (`arpMask*` — a K-of-N Bjorklund pattern with GAPS·WALK·ROTATE, baked inline into `emitArpRow`) could work as its
  own chain processor, usable downstream of ANY driver, not just ARP. Worked the architecture out live: GAP
  (REST·TIE·CHORD) + ROTATE fit the codebase's existing per-note downstream-FOLD seam (`isModifierFoldable` +
  `emitDriverNote`) — the same one SHIFT/HUMANIZE/VELOCITY/RATCHET's fold already use — so pulling them out reaches
  the WHOLE driver roster (ARP/RIFF/STRUM/RATCHET/EUCLID-as-driver/…) for free. WALK's WAIT mode does NOT fit that
  seam — it doesn't reshape a note it's handed, it overrides which note the driver picks in the first place (feeds
  `euclidMaskHitsBefore` into `arpPick`'s `phaseIndex`), a decision already made before any fold sees the note.
  Traced WAIT's actual mechanism to the SAME renumbering `killStepPhase` already does — it belongs to the OTHER
  existing seam, the upstream beat-transform family CLOCK/KILL STEP use (`driverClockBeat`), which would need the
  processor to sit BEFORE its target driver instead of after (the opposite position from GAP/CHORD/ROTATE). Paul:
  "I'm happy to drop wait as an option." **BUILT:** `ProcessorType.euclidMask` — not `isDriverType`, joins
  `isModifierFoldable`; a new fold block in `emitDriverNote` keyed on the note's ordinal against the upstream
  driver's own rate (mirroring VELOCITY's `driverStep`), reusing `euclidMaskHit`/`euclidMaskTieRun` unchanged; new
  `mask*` fields mirrored on BOTH `MachineParams` and `SnapParams` (+ the `SnapshotBuilder` resolve — missing this
  the first time round is what the macOS build caught immediately); a new GridUI editor (the ARP mask block minus
  WALK); a DYNAMICS storefront card; `cellMode` classifies it `.identity` (same bucket as VELOCITY/DEST/CLOCK/KILL
  STEP — verified via `applyStage`'s `default:` fallthrough, not assumed). ARP's own embedded `arpMask*`
  fields/editor are UNTOUCHED — this is additive, not a migration. +7 RouterTests (REST drops gap notes · TIE
  extends the gate across gaps, not just count · CHORD stabs the gap with more note-ons · ROTATE changes WHICH
  ticks gate, not the count · K=N is byte-identical to the arp alone · folds onto RIFF too, proving it's
  driver-agnostic · a lone instance is a no-op exactly like an empty chain, guarding the AVOID-class "silently
  emits nothing standalone" bug) + fuzz coverage (hammers the CHORD note-injection path especially, the most likely
  place to leak a stuck voice). **CAUGHT DURING THE BUILD (own dead-code survey, not guessed):** `MacroAuthoring.
  swift`'s per-processor macro-bindable-params switch is exhaustive via a big bundled catch-all case
  (`case .octave, .transpose, …, .killStep:`) that a naive grep for `"case .killStep"` misses (killStep isn't the
  FIRST case in that line) — cost one extra build round-trip; added `.euclidMask` to the same bucket (its config is
  per-step/discrete, not a simple macro-foldable scalar, matching KILL STEP's own reasoning). **PLAN:**
  `~/.claude/plans/stateless-tickling-flask.md`. **DEFERRED (Paul 2026-09-27, logged in `Docs/pending-tasks.md` +
  a memory file):** once this is device-verified, raise whether KILL STEP itself should gain selectable
  disabled-step behaviors (DROP/MUTE/PAUSE) instead of one fixed behavior — a direct spin-off of this same
  conversation. **DEVICE-OWED:** the new card's editor legibility, GAP=CHORD actually sounding right downstream of
  a non-ARP driver (e.g. `[RIFF→EUCLID MASK]`), TIE's extended-gate feel, ROTATE's control.**
- **▶ SELECT GRID — picked-cell notes wear the selected ferry's colour (2026-09-27, on `feature/ferry-row-
  unification`, `504416f`; iOS builds; DEVICE eye owed). Paul: the picked-but-uncommitted SELECT cell's face was
  inverting (a bright background with dark-grey notes) — wants the notes coloured instead. `buildGridSelCell`'s
  `rollTint` (BuildGridSelector.swift) now reads `buildFerryHex(buildActiveFerry)` — the SAME "selected colour" the
  ferry-row selector glow already uses (`roomsPlayFerry`'s header-bar emanation) — instead of `Color(white: 0.22)`,
  when the cell is picked (`selGrey`). Live: tapping a DIFFERENT, unselected ferry's own selector (`buildActivateFerry`)
  re-points `buildActiveFerry`, so the notes recolour with it at once. Unaffected: picking a different SELECT cell or
  deselecting falls out of the `sel`/`selGrey` branch entirely, reverting to the plain grey face exactly as before —
  and a COMMITTED (named) cell's roll stays white on its own machine-hue background, untouched (it was never
  "inverted" to begin with). DEVICE-OWED: legibility of a ferry hue as ink against the still-unchanged bright
  `buildSelectGrey` card background — Paul asked only to recolour the notes, not the card, so that pairing is
  unverified off-device.**
- **▶ FERRY ROW UNIFICATION — Stage 1: dead-code removal (2026-09-27, on `feature/ferry-row-unification`, `f689649`;
  macOS 1109 green, iOS builds). Paul: background ferries should play polyphonically, not the mono reduction
  `buildFlattenFerry` forces on them today — and questioned why the engine has a shared rows-0-7 concept at all.
  Ratified target (plan `flickering-dazzling-floyd.md`): 8 ferries × 4 dedicated engine rows each, always live, no
  active/background distinction, plus a per-ferry SINGLE/MULTI row-select toggle. Stage 1 clears the ground: deleted
  three confirmed-dead layers, each traced to zero live producers before removal — the pre-ferry "PIECE" deployed-
  arrangement grid (`performCells`/`buildPerformPart`, only ever written by snapshot/undo restore; no live gesture
  reaches it since the Room enum dropped to SELECT/PART only), the superseded independent play-cell grid
  (`playCells`/`playSel`), and the tap mute/solo/alt bitmask cluster (`tapMuteMask`/`soloCellMask`/`tapAltMask`,
  structurally capped at 64 bits `col*8+row` and traced end-to-end — `applyTapOverlay` has zero callers, and the one
  theoretical solo-mask path is defensively zeroed by `buildPublishScene`'s own `clearMachineSolo()` every publish).
  `soloEmitterMask`/the live emitter-strip SOLO buttons are untouched — confirmed a separate, live feature despite
  sharing call sites. Ported 5 BuildSceneLogicTests that used `performCells` as scaffolding for the still-live
  chain-audition-fallback logic to use `stagingCells` instead, rather than losing that coverage.
  **STAGE 2 — widen the row axis (2026-09-27, `0901d9b`; macOS 1109 green, iOS builds):** `Snap.ferries=8`/
  `rowsPerFerry=4`/`ferryRowBase(t)=t×rowsPerFerry` land as the PERMANENT per-ferry addressing, replacing
  `playLayerRowBase`; `BuildPart`'s row storage shrinks 8→4 to match the already-4-row `roomsPartGrid` UI. Caught by
  testing, not guessed: naively relocating a background ferry's mono row from `8+t` to `ferryRowBase(t)` collides
  with the still-untouched STAGING write path at `ferryRowBase(0)=row 0` — `testPlayGridComposesStartedColumnsAs-
  ContinuousVoices` failed asserting row 0 empty when ferry 0's background content now legitimately lived there.
  FIX: a TRANSITIONAL `Snap.stagingRowBase = ferries×rowsPerFerry` (32) reserved past every ferry's block, where the
  still-live staging pass parks until Stage 3 unifies the composer — `Snap.rows` is 36 for this stage only, settling
  to 32 once Stage 3 deletes the reservation.
  **STAGE 3 — one composer loop, every ferry alike (2026-09-27, `0233d34`; macOS 1116 green, iOS builds):**
  `composeSceneMeta` no longer distinguishes an active bench ferry from a background one — every ON+audible ferry
  composes from its own `BuildPart` into its own dedicated `ferryRowBase(t)` block, every publish; `buildPublishScene`
  captures the active ferry fresh from live @State (`buildCaptureBenchPart`, already used for this — verified it
  already carries every field the unified composer needs: rate/length/loopCols/receiver/emitters/rowReceiver/
  rowEmitters) and reads every other ferry's stored part directly. **This is the structural change that actually
  makes background polyphony possible** — a background ferry's content no longer gets flattened to one machine per
  column before it can play. Traced before relying on it: `buildStagingPlaying` turned out to be LITERALLY
  `buildPlayColOn[buildActiveFerry] ?? false` — the active ferry was already using the same on/off boolean as every
  background ferry, so the two gates unify with zero special-casing. Deleted `buildFlattenFerry` + the `playCol*`
  flattened-representation fields entirely, plus — found via a zero-caller trace, not guessed — a SELECT-page
  per-column I/O editor that was already dead behind a permanently-nil stub (its own comment had already flagged
  "returns with the Stage 3 unified ferry composer"), and the transitional `Snap.stagingRowBase` Stage 2 introduced
  (`Snap.rows` settles back to 32). **DELIBERATE BEHAVIOUR UNIFICATION, flagged not buried:** a machine-less cell was
  a silent "unset" on the staging grid but a passthrough live wire on the old flattened background path; onto one
  code path, one rule — kept the staging rule (silent) for every ferry, matching "no active/background distinction."
  DEVICE-AUDIBLE if a background ferry ever relied on that passthrough.
  **STAGE 4 — multi-select authoring, FEATURE COMPLETE (2026-09-27, `a71523d`; macOS 1126 green incl. 10 new, iOS
  builds; DEVICE eye/ear owed on the whole feature). `BuildPart` gains `stagingMulti` (a per-column 4-bit mask) +
  `selMulti`; `BuildSceneLogic.activeRungs(sel,multi,c)` is the plural sibling of `selectedRung` — the "POLY-PREP"
  seam a 2026-09-14 session set up for exactly this ("only these two bodies change — every caller already asks
  here"). `composeSceneMeta`'s per-ferry loop iterates every active rung instead of one; a ferry's own `selMulti`
  gates whether its mask is even consulted, so flipping back to SINGLE can't leave a stale mask sounding rows it
  shouldn't (a real fix, not automatic — required threading `selMulti` into the engine read, not just the UI).
  `partGridTap` gained a multi-aware toggle branch (XOR a row's bit rather than exclusive-overwrite); the lead
  (which row anchors the playhead/focus) follows the most recently toggled row, reassigning to a survivor if the
  lead itself is toggled off. UI: a SINGLE|MULTI `launchInline` in the ferry settings tab, same shape as CHOKE.
  Two v1 defaults from the plan, applied not re-litigated: the row-bulk-select rail REPLACES a column's active set
  rather than adding to it; the part-grid playhead sweep stays lead-row-only even in MULTI (a per-row sweep is a
  visual follow-up, not gated on anything audio). **Found in passing:** `buildPartGridDrag`'s row bound was still
  hardcoded to 8, a stale leftover from Stage 2's shrink to 4 (no observable bug — the touch coordinate space was
  already sized correctly — but wrong on its face, fixed); `buildFerryFlashIndices` + the emitter-strip playing-
  colour band both iterated the lead only, generalized to every active rung so a multi-row ferry's flash/tint
  doesn't under-represent what's actually sounding. Byte-identical for any ferry left in SINGLE (the default).
  **THE WHOLE ARC (Stages 1-4, one session):** replaced the old model — rows 0-7 shared by whichever ferry sat on
  the bench + a dead pre-ferry "PIECE" arrangement grid, rows 8-15 one mono row per background ferry via
  `buildFlattenFerry` — with 8 ferries × 4 dedicated engine rows each, always live, no active/background
  distinction, plus per-ferry SINGLE/MULTI row selection. Paul's own diagnosis ("why do we have rows 1 to 8 anyway
  — sounds like a byproduct of an older model") was confirmed exactly right: `buildPerformPart` had zero live
  writers, and the part-editing UI had already quietly shrunk to 4 rows (2026-09-08) without the engine following
  suit. Plan: a session-local plan file (not checked in) validated by a dedicated research pass before any code
  moved — closed two real open risks (a `col*8+row` UInt64 tap-mask cluster confirmed fully dead end-to-end; the
  `Snap.rows`/`Snap.cells` call-site audit across Router/Kernel/SnapshotBuilder found almost everything already
  symbolic, not hardcoded) before Stage 1 touched a single file. **DEVICE-OWED, the whole arc:** a backgrounded
  ferry with 2+ rows populated actually sounds both machines together; the SINGLE|MULTI toggle feel; no stuck notes
  across ferry activate/deactivate/mute while multi-row content plays in the background.**
- **▶ FERRY COLOUR SWAP — closes the "invents a third colour" gap (2026-09-27, on `main`, `1c2d3b7`; iOS
  builds, macOS 1123 green; DEVICE eye owed). Paul described the intended model for select→ferry colour (pick a
  colour via a selector → the SELECT cell shows it → dragging it onto a ferry lands verbatim, regardless of that
  ferry's own predetermined colour → a clash swaps the two slots' colours, never invents a new one → the SELECT
  cell and the ferry can never disagree) and confirmed it should ALSO hold when the clash is against an
  ALREADY-POPULATED ferry, not just an empty placeholder — the one case the 2026-09-12/13 ferry drag-and-drop work
  didn't cover (`buildPopulateFerry`'s "FERRY HUE UNIQUENESS" block fell back to `buildDistinctHue()` there,
  silently diverging from the SELECT cell that fed it — the exact class of bug the whole ferry-colour-review
  session flagged as still-open). FIX: `BuildSceneLogic.ferryColourDisplacement` dropped its `empty` filter — it
  now matches ANY other ferry currently wearing the incoming colour, populated or not; `buildPopulateFerry` applies
  the swap by recolouring the OTHER ferry's `.ferryHue` (+ mirroring into its own `machineHueOverride`, so its
  machine box can't fall out of step with its own ferry swatch) when populated, or its `ferryHueAlloc` placeholder
  when empty — `buildDistinctHue()` is never called on this path anymore, so the dropped cell's colour always lands
  verbatim at the target. Rewrote `testFerryColourDisplacement` to the new signature (no more `empty:` array) and
  flipped its last assertion (a populated clash is now chosen for the swap, not rejected). **RESIDUAL, flagged not
  fixed:** the DISPLACED ferry's colour change doesn't propagate to any SELECT-grid cell that may have committed
  with that OLD colour — there's no persisted link from a ferry back to whichever cell(s) seeded it (colour capture
  on SELECT is already one-shot-at-commit by design, per the 2026-09-12 model, not a live binding); closing that
  fully would need a new bond and is out of scope for this fix. Also NOT touched: the broader Refactor 2
  (`Docs/PLAN-ferry-colour-unification.md`) — one accessor across all ~12 hue-reading surfaces — which is a
  separate, larger, still-open decision.**
- **▶ CLOCK — GLIDE "elastic landing", in sync whether or not a step glides (2026-09-26, on `main`, on fix/clock-
  glide-sync; macOS 1120 green incl. fuzz, iOS builds; DEVICE ear owed). Paul: "when it lands on a target, whether
  it got there with or without glide, it should be in sync." Confirmed real: a plain linear GLIDE ramp only
  contributes its own AVERAGE of (from,to) over the column, strictly less than `to` when accelerating — so it
  banks LESS local time than SET reaching the same target, and that shortfall carries forward unchanged for the
  rest of the SPAN window (already provable via the existing `testClockDrawnGlideRowSoftensTheColumnTransition`).
  Asked Paul to pick a resolution (a monotone ramp can't avoid the shortfall — a calculus fact, not a bug); he
  picked **elastic landing**: `clockDrawnGlideShape` splits a glide column into two straight-rate segments — a
  short "kick" from `from` toward a computed peak `P`, then a longer ease from `P` back onto `to` — chosen so the
  TWO SEGMENTS' combined area always equals `to × rateBeats` exactly, same as SET. `P = to + f×(to−from)`; f
  defaults to a symmetric 0.5 for any accelerating (or mild decelerating) glide, shrinking (5% floor) only for a
  STEEP deceleration where a full-size overshoot would otherwise drive `P` negative (local time running backward —
  the exact class of bug WAVE's old depth clamp existed to prevent; no ladder rung pair near that floor in
  practice, only extreme multi-rung jumps like ×4→÷4 engage it). `clockDrawnColumnAdvance` (new, replaces 3
  copy-pasted closures) now returns `to × rateBeats` for a GLIDE column too — the fix itself, shared by
  `clockDrawnPhase`, its inverse, and `clockDrawnDriftPerLap` so they can't disagree; the drift readout now only
  ever reports a lane genuinely authored to run fast/slow on average, never an artefact of glide-vs-SET choice.
  **BUG CAUGHT MID-BUILD:** a first draft generalised `P` for the adaptive-f case but left the within-column
  quadratic denominators hard-coded to `/T` (only correct when f is exactly 0.5) — `testClockDrawnPhaseInverse-
  RoundTrips` failed on the extreme ×4→÷4 all-glide case; traced with a throwaway Swift script rather than
  re-guessing by hand (this session's own standing rule), fixed to `/(2×half)`/`/(2×rest)`. Rewrote the 4 affected
  DerivationsTests with fresh values pulled from the actual function (never re-hand-derived blind) + added
  `testClockDrawnGlideFullColumnAlwaysMatchesSetAtTheSameTarget` (sweeps the whole 9-rung ratio ladder both ways —
  81 pairs — asserting zero drift AND a never-negative peak) as the standing regression guard. 1120 macOS tests
  green incl. all 8 fuzz scenarios; RouterTests' existing glide-softening test still holds (GLIDE is still visibly
  later than SET WITHIN the ramp, converging to exactly the same phase once it lands). **NEXT:** device ear-check —
  confirm a glide into a target no longer leaves the rest of the pattern audibly later than a same-target SET would.**
- **▶ CLOCK — GLIDE "elastic landing" NARROWED to accelerating glides only (2026-09-27, on `main`, on fix/clock-
  glide-decel-safe; macOS 1122 green incl. fuzz, iOS builds; DEVICE ear owed). SUPERSEDES the entry above the same
  day it landed — Paul actually tried it and reported two device symptoms: "weird behaviour… appears to change the
  velocity two cells after a jump to another tempo when glide is set on the jump only," and "hiccups… a stutter"
  with columns 1–4 all SET+glide to ×1 (column 8 at ×2, so the whole run decelerates ×2→×1 across 4 columns via the
  SPAN-coalescing rule). Traced BOTH with a throwaway script rather than guessing: for a DECELERATING glide (e.g.
  ×2→×1), the elastic curve's cumulative local time runs UP TO 16% AHEAD of a same-target SET for most of the
  column before snapping back to exact parity only at the very end — the mechanism is a hard calculus asymmetry, not
  a tuning knob: an ACCELERATING glide's elastic curve can be PROVEN to stay ≤ a same-target SET throughout the
  whole column (verified both analytically and by sweep-testing the full ratio ladder), so it can never make a
  downstream driver/fold-consumer discover an early/extra tick — but a DECELERATING glide's zero-drift correction
  necessarily requires the opposite: dipping BELOW the (slower) target first, which means racing AHEAD of a
  same-target SET before catching back down. That "ahead of schedule, then catch down" motion is exactly what reads
  as a stutter, and it compounds badly across the coalesced 4-column run (four such wobbles in series). **FIX:**
  `clockDrawnGlideAdvance`/`FullAdvance`/`AdvanceInverse` now branch on `to >= from` — ACCELERATING keeps the full
  elastic "in sync" treatment (now with NO adaptive-f floor needed at all, since `P = to + 0.5×(to−from) ≥ to > 0`
  unconditionally when accelerating — the floor only ever existed to protect decelerating overshoots, which no
  longer take this branch); DECELERATING falls back to the plain single straight-line ramp — this feature's
  ORIGINAL shape, honest/non-zero-average, exactly what shipped before the "in sync" work began. Re-verified with
  the same throwaway-script technique: the 4-column ×2→×1 span now shows a PERFECTLY MONOTONIC, smoothly
  decreasing rate in every column (no dip-then-recover) — confirmed against the actual function's own numeric
  output, not re-derived by hand. **`clockDrawnGlideShape` simplified** (the adaptive split-fraction tuple is gone —
  always exactly `T/2` now, so it returns a scalar peak, not a tuple) — a direct consequence of decel no longer
  needing it. **TESTS:** rewrote `testClockDrawnGlideFullColumnAlwaysMatchesSetAtTheSameTarget` (accel → matches
  SET exactly; decel → the honest average, an explicit different expectation) + `testClockDrawnGlideOfDifferingTargetsIsUnaffectedBySpanLogic`
  (mixes an accelerating run with a trailing decelerating column — GLIDE now agrees with SET through the
  acceleration and explicitly diverges at the deceleration, asserted both ways) + added
  `testClockDrawnAcceleratingGlideNeverRunsAheadOfSet` (sweeps the whole ladder × a beat range, the standing
  regression guard for the safety property the whole fix rests on). 1122 macOS tests green incl. fuzz; the two
  pre-existing RouterTests (`…SetAndGlideProduceDifferentFoldResults` on a DECEL [×4,×1] pair, `…SoftensTheColumn
  Transition` on an ACCEL [×1,×4] pair) both still pass unchanged, confirming each already happened to sit on the
  side of this asymmetry it needed to. **HONEST REMAINING GAP (flagged, not a bug):** decelerating glides are back
  to the ORIGINAL "not perfectly in sync" behaviour Paul first complained about — eliminating that drift there is
  mathematically impossible without reintroducing the exact overshoot artefact just removed (proven, not a
  limitation of this implementation specifically). The `clockDrawnDriftPerLap` readout still exists precisely for
  this case. **NEXT:** device ear-check on both fronts — confirm the 4-column decel run now feels like one smooth
  slowdown (no stutter), and confirm an ACCELERATING jump still lands cleanly in sync as before.**
- **▶ KILL STEP — a new TIME processor, sibling to CLOCK (2026-09-26, on `main`, `b1e7a19`; macOS 1121 green, iOS
  builds; DEVICE ear/eye owed). A row of ON/OFF steps (variable count, default 8) + its own RATE + SPAN: a disabled
  step is skipped, everything downstream jumps past it, enabled steps repeat to fill the pass (4-of-8 → the first
  half plays twice; 3-of-8 → a 3-cycle rotates against the bar) — `lapColumn`'s ephemeral LAP algorithm, AUTHORED
  per-cell. Reached the WHOLE generator roster CLOCK's own widening earned this session FOR FREE, by generalizing
  the three functions that type-check `.clock` (`Router.driverClockBeat`/…Inverse/`clockTransformedBeat`) to also
  detect `.killStep` — no new call sites; composes with CLOCK too. New pure `killStepPhase`/`Inverse`: a DISCRETE
  remap (real gaps in local time, unlike CLOCK's continuous warp) — monotonic in the real column count so the
  shared tick-search machinery still works; all-disabled falls back to all-enabled; a beat landing in a gap snaps
  FORWARD to the next enabled repeat. Model additive-Optional (`killStepCount`/`Enabled`/`Rate`/`SpanN`); UI =
  STEPS + a `toggleLane` row + an ArpRate seg + `frameSpan`; self-names "N/total". Tested (Derivations + Router,
  mirroring the CLOCK+DEST tests) + fuzz roster. **NEXT:** device ear/eye pass.**
- **▶ CLOCK — driver retiming WIDENED to the whole generator roster (2026-09-26, on `main`, `e5e00cd`; macOS 1112
  green, iOS builds; DEVICE ear owed). Paul's repro after the RATE-removal pass above: "euclid isn't effected by
  tempo changes, neither is ratchet — put a 1-step grid on speed, change it, put a euclid or ratchet pattern after
  it" — and asked "shouldn't all downstream processors read an upstream clock, defaulting to real time if none is
  present?", then "do the lot please." Stages 1–3 (this file, earlier entries) only wired `iterateTicks` — shared
  by ARP/RIFF/RATCHET-ALL — to the clock-transform params; every OTHER self-clocked generator computed its own
  onset/gate math directly and never read an upstream CLOCK at all: EUCLID's own `iterateTicks` call site (the
  params just weren't threaded through, even though the shared walker already supported it), HOCKET (same), BURST
  (`layBurst`), CASCADE, DRONE, SHIFT, HUMANIZE, WEAVE (both its EUCLID sub-mode and its LADDER/HARMONIC/DRAWN
  sub-mode), and RATCHET's PATTERN and COIN modes (`emitRatchetModal`) — three distinct code shapes across the
  roster, none reachable by extending `iterateTicks` alone. **NEW shared helpers** `clockLocalAnchor`/
  `clockDriverTiming` (Router.swift, beside `driverClockBeat`/`driverClockBeatInverse`) factor the pattern every
  one of these needed: shift a real anchor forward into LOCAL (retimed) time once per driver, then for each
  sub-strike invert the local onset+off pair back to real time INDEPENDENTLY — a duration can never be inverted
  directly under a non-uniform DRAWN transform, only points can, so a note's real gate length is always the real
  difference of two separately-inverted points. Both helpers are no-ops when `chainDriver < 0` (plain, non-CLOCK-
  prefixed chains stay byte-identical). **THE SOVEREIGN LAW held throughout the widening**: RATCHET-COIN's per-step
  chance decision (`rtcCoinFires(step:...)`) still reads the REAL column index — only its sub-strike SCHEDULING
  reads the transformed local beat; column-membership never moves. **TEST FIX**: `testClockDrawnDoesNotReachEuclid`
  asserted the OLD gap as correct behaviour (a deliberate scope-boundary lock at the time) — renamed/rewritten to
  `testClockDrawnRetimesEuclidToo`, asserting ×1 is a no-op and ×3 packs meaningfully more pulses into the same
  real window (an inequality, not a hand-derived count — this session's standing rule, hit twice already by trusting
  un-traced hand derivations). **NEXT**: device ear-check, as with every CLOCK change this session — confirm EUCLID
  and RATCHET (Paul's literal repro) now audibly retime, alongside the rest of the newly-wired roster.**
- **▶ CLOCK — RATE removed (a column IS a grid step) · GLIDE merged into one grid widget · the playhead now actually
  tracks the grid · GLIDE SPANS a multi-step run instead of flatlining (2026-09-26, on `main`, `f8eb2fd`; iOS
  builds, macOS 1112 green incl. fuzz; DEVICE ear/eye owed). Four fixes from one device-driven thread, none of them
  the driver-retiming feature itself — all about the grid's OWN feel now that it's built. **(1) RATE REMOVED**
  ("what's the point of rate when we have a speed-per-step grid? I think we'd lose nothing"): `clockDrawnRate`/
  `clockDrawnRateBeats` deleted from Models/Snapshot/SnapshotBuilder; every `rateBeats:` call site in
  `clockTransformedBeat`/`driverClockBeat`/`driverClockBeatInverse` now passes `S` (the cell's own grid step) — a
  clock column IS a grid column, no independent dial. **(2) GLIDE MERGED INTO THE GRID** ("should be part of the
  same grid control so it all lines up"): the old `toggleLane` GLIDE row was a SEPARATE full-width widget with no
  leading label offset, so its columns didn't align with the ratio matrix's (which reserves a 64pt header column) —
  a real geometry bug, not just a look. `stateMatrixRadio` gained an optional `extraRowHeader`/`extraRowCell` pair
  (any other caller omits them, unaffected) so GLIDE now renders as one more row INSIDE the same widget, sharing
  identical column geometry AND the same live-column highlight. **(3) THE PLAYHEAD NOW TRACKS THE REAL CLOCK**
  ("it doesn't line up with what I'm hearing at all"): the CLOCK editor never passed a `clock:` argument to
  `stateMatrixRadio` at all, so it fell through to the generic whole-grid `liveStep` column — unrelated to CLOCK's
  own steps/rate/SPAN. Now constructs its own `StateMatrixClock` (`rate: gridStepBeats` — the SAME S as (1), so the
  UI and the engine are provably the same clock — `steps:`/`span:` from the lane's own STEPS/SPAN controls) and
  passes it through. **(4) GLIDE SPANS** (caught mid-fix, against a worked example Paul gave: "three glides in a
  row, all on a distinct speed — should ramp up over three steps"): the ORIGINAL glide math ramped from a column's
  IMMEDIATE PREDECESSOR's landed value to its own target, each column independently — so three consecutive columns
  all targeting ×2 would reach ×2 after the FIRST column (1→2) then sit FLAT for the other two (2→2 has no slope
  to inherit). Root-caused live in conversation (a segment whose two ends are numerically equal can't produce a
  climb no matter how it's read) rather than guessed at. Fix: new `clockDrawnGlideEndpoints` coalesces a run of
  CONSECUTIVE glide columns that all target the SAME ratio into one SPAN, and gives a column its own linear-
  interpolated slice of the whole span's ramp (three ×2-glides after a ×1 now climb ~1.33→~1.67→2.0, reaching the
  target only at the end of the third column). A run of DIFFERING consecutive targets (1→2→3→2, each a genuinely
  new value) forms spans of length 1 throughout, reducing EXACTLY to the original one-column formula — confirmed
  unaffected, not just assumed. Threaded into `clockDrawnPhase`, its inverse, and the drift readout (all three had
  their own local `columnAdvance`/`(from,to)` lookup — now all three call the one shared span function, so they
  can't independently drift out of sync). **THE TESTING, honestly recorded because it went sideways more than
  once:** two hand-written span-math tests had OFF-BY-ONE column-boundary errors on the first draft (mapped a beat
  to the wrong column — e.g. asserting col1's midpoint at beat 0.5 when col0 occupies [0,1) and col1 occupies
  [1,2)) — caught by the actual test run disagreeing with the hand derivation, not by a second read-through; fixed
  by recomputing from the column boundaries directly rather than trusting the first arithmetic pass twice. Separately,
  three Router-level integration tests went from passing to failing to passing again as RATE's removal changed what
  S actually is: a bare, un-held test cell only ever ticks during ITS OWN grid column's real-time span `[0, S)` —
  fine for a single-step CLOCK lane (whose own real-time width is also just `S`, so it never needs to look further),
  but a MULTI-step lane now needs `steps × S` of real time to show its later columns, which a bare cell's own
  natural column window can't reach on its own. Pinning the scene's `stepRate` to force a convenient S was tried
  first and made it WORSE (it also changes how many ticks the driver's own generation fits per column, an
  unrelated engine behaviour, breaking a DIFFERENT assumption); the actual fix was `forceColumn: 0` (the existing
  PLAY-THIS-CELL mechanism, newly threaded through the `run()` test helper), which bypasses the column-lap gate so
  real time keeps advancing past the cell's own column regardless of grid width. **NEXT:** device ear/eye pass on
  the merged grid + corrected playhead + the real 3-step glide feel, as always.**
- **▶ CLOCK — FIXED and WAVE modes REMOVED ENTIRE; CLOCK is now always the one grid (2026-09-26, on `main`,
  `5a857df`; iOS builds, macOS 1110 green incl. fuzz; DEVICE ear owed). SUPERSEDES the same-day "driver retiming,
  REBUILT against DRAWN" entry below — that pass was STILL INCOMPLETE, caught by Paul directly: "tell me what I
  asked you to do that you haven't done." He'd said "remove everything you've done on clock because it's wrong,
  and complete it to this specification" — I only removed the driver-retiming layer added that same session (the
  FIXED-only `driverClockBeat`/Inverse pair + the global GLIDE toggle), and left FIXED mode, WAVE mode, and the
  three-way mode picker completely untouched, even though I'd built FIXED and WAVE earlier in the SAME session and
  neither matches Paul's spec ("a grid with a variable number of steps, each step a mutually exclusive speed, and
  another row on the same grid for glide" — one mechanism, not a choice of three). The root cause, named plainly
  when Paul asked why this keeps happening: resolving ambiguous instructions toward whatever's already loaded in
  recent context (today's narrow addition) instead of re-checking the literal instruction against the FULL current
  codebase. **REMOVED, completely, this pass:** `ClockMode` enum + the `clockMode` field entirely (CLOCK has no
  mode now — DRAWN's grid IS the whole feature); FIXED's `clockRatio`/`clockOffset` + `clockFixedPhase`; WAVE's
  `ClockWaveShape`/`clockShape`/`clockDepth` + `clockWavePhase`; the mode-picker `seg` + both branches in the
  GridUI editor; the FIXED/WAVE storefront cards (CLOCK/CLOCK WAVE/CLOCK DRAWN → one "CLOCK" card); `clockTransformedBeat`
  (the Stage 1–3 downstream-fold function) collapsed from a 3-way mode switch to unconditionally applying the DRAWN
  transform; `driverClockBeat`/`driverClockBeatInverse` dropped their now-meaningless `clockMode == .drawn` guard
  (every `.clock` slot IS the grid). KEPT: `clockRatioLadder`/`clockRatioLabels` (DRAWN's per-column picks still
  index into it) and `clockSpanN` (DRAWN's own SPAN control — was shared with WAVE, now DRAWN-only). **TESTS:**
  removed the whole FIXED/WAVE pure-function test cluster in DerivationsTests (ratio/offset math, composition,
  WAVE re-landing, monotonicity — the properties DRAWN's own tests already cover for the grid that ships); rewrote
  6 RouterTests (the RATCHET-fold flagship test, the two-CLOCK composition test, and the DEST/VELOCITY/TUTTI/MOD
  Stage-3 tests) from FIXED-mode clock construction to a shared `drawnClock(ratioIndex:)` helper — a single-step,
  all-SET DRAWN lane, algebraically identical to a FIXED ratio (`clockDrawnPhase` collapses to `beat×ratio` for one
  constant column, independent of steps/rate) — deleted the now-pointless `testClockDrawnWithOneConstantColumnMatchesFixedAtThatRatio`
  (its whole point was proving DRAWN reduces to FIXED; nothing left to compare against); trimmed
  `testClockParamsResolveAndClamp` to only the DRAWN `clockDrawnSteps` clamp (the `clockDepth`/`clockRatio` clamps
  it tested are gone with the fields); simplified `applyRandomClock`'s fuzz randomizer to DRAWN-only fields. Net
  −7 tests (1117→1110) — FIXED/WAVE tests removed outright rather than converted, since there's no FIXED/WAVE
  behavior left to test. **NEXT:** the one grid is now unconditionally what CLOCK is — no follow-up mode work
  planned; revisit only if Paul asks for a second control paradigm alongside it.**
- **▶ CLOCK — driver retiming, REBUILT against Paul's own grid (DRAWN, not FIXED) (2026-09-26, on `main`, `790fb39`;
  iOS builds, macOS 1117 green incl. fuzz; DEVICE ear owed). SUPERSEDES the same-day "driver retiming (FIXED only) +
  a GLIDE row" entry below — that build was WRONG and was entirely removed, not kept alongside this one. The story,
  for the record (a real misunderstanding, not a euphemism): Paul tested `[CLOCK→ARP]`, heard nothing, and said "the
  clock control will override the transport for everything downstream" — I read "grid" (from his own words, "we
  have a grid with x2, x3, etc, as we see now") as FIXED mode's simple ×2/×3 seg-picker (a literal reading of what's
  labelled on that row) and built driver retiming + a brand-new global GLIDE toggle for THAT mode. Paul's actual,
  much more specific follow-up spec — "a grid with a variable number of steps, each step a mutually exclusive
  speed, and another row on the same grid for glide" — describes something else entirely: DRAWN mode, which
  ALREADY EXISTED (built in an earlier stage of this same feature, well before this driver-retiming conversation) —
  variable steps (`clockDrawnSteps`, 1–32), a per-column mutually-exclusive ratio matrix (`clockDrawnRatios`), and
  an existing per-column GLIDE row (`clockDrawnGlide`) directly beneath it. So the FIXED-mode work retimed the wrong
  mode, and the new GLIDE toggle duplicated — badly, as a single global switch instead of a per-step row — a
  mechanism DRAWN already had. Paul caught this ("the grid that appears on drawn still doesn't do anything… it
  feels like you're not being straight with me") and, once the mismatch was confirmed back to him in plain language,
  said to remove all of it and build to the real spec. **REMOVED, completely:** `driverClockBeat`/
  `driverClockBeatInverse`'s FIXED-mode bodies, `clockFixedPhaseInverse`, `resolveGlideRatio` + its 3 backing arrays
  (`clockPrevRatio`/`clockTargetRatio`/`clockChangeBeat` — a whole "remember across renders" exception that turned
  out to be unnecessary), `clockRatioGlide`/`clockRatioGlideTime(Beats)` on `MachineParams`/`SnapParams` + their
  resolve lines + their FIXED-mode UI row + the `buildProcLabel` "~" suffix. **REBUILT for DRAWN instead:**
  `driverClockBeat`/`driverClockBeatInverse` now walk ONLY `.drawn` slots, calling the EXISTING `clockDrawnPhase`
  (which gained an `originOverride` param, default nil ⇒ byte-identical for its Stage 1–3 fold-consumer callers) and
  a new `clockDrawnPhaseInverse` (Derivations.swift) — SET columns invert linearly, GLIDE columns invert the
  closed-form quadratic (the antiderivative of a linear rate ramp) via the quadratic formula's `+` root, proven the
  only valid one in-range since a column's own rate is always positive throughout its span (monotonic, one root).
  Both closed-form — a bounded O(steps) walk to find the column, then one algebraic solve, no iteration — so DRAWN's
  own GLIDE needed NO new cross-render memory at all (unlike the FIXED attempt's now-deleted `resolveGlideRatio`):
  a column's ramp is purely a function of its own position, stateless by construction. `iterateTicks` threads
  `cycleBeats` + an `originRef` (the window's real start, pinned once per tick search so every slot's own SPAN-
  origin and every discovered tick agree) instead of the old `nowBeat`. Same 3 call sites (`emitArpRow`,
  `emitRiffRow`, `emitRatchetRow`'s ALL-mode branch), same sovereign-law shape (search in LOCAL time, invert to REAL
  immediately on discovery, only note-selection stays local). **TESTS:** rewrote the 4 FIXED-mode RouterTests as
  DRAWN-mode equivalents (`testClockDrawnRetimesArpsOwnGeneration`/`…RiffAndRatchetAllOwnGeneration`/
  `…DoesNotReachEuclid`/`…GlideRowSoftensTheColumnTransition` — a single-step all-SET DRAWN lane is algebraically
  identical to FIXED's linear math, so the doubling/no-op assertions carry over unchanged in spirit; the GLIDE test
  is new — hand-derived a 2-step ×1→×4 lane, SET reaches the ARP's next tick at real beat 1.125 vs GLIDE's 1.333,
  asserted comparatively per this session's standing "don't hard-code the exact sample, the discontinuity's own
  quantization isn't the property under test" rule); replaced `clockFixedPhaseInverse`'s round-trip test with
  `clockDrawnPhaseInverse`'s (5 ratio/glide/lane-shape cases × 3 origins × a beat sweep). Full suite + all 8 fuzz
  scenarios stay green. **NEXT:** FIXED/WAVE driver retiming stay explicitly unbuilt — Paul's spec describes DRAWN's
  grid specifically, not a mode choice; revisit only if asked. Device ear owed, as always.**
- **▶ HOUSEKEEPING — dead-code sweep + 3 test-coverage gaps (2026-09-26, on `main`, `7fcac1e`; iOS builds, macOS 1112
  green). Three parallel read-only surveys (dead code · missing tests · refactor/efficiency) over the whole codebase,
  every finding independently re-verified before acting (per this file's own standing pattern). **DEAD CODE (6, all
  pre-existing, unrelated to CLOCK):** `buildCreateMachine` + its stale doc comment, `buildHeaderFill` + the `BuildFill`
  enum it was the sole consumer of, `partRollCamera` + its function-specific doc (the SECTION 1 header above it
  describes still-live code and was kept), three unused colour aliases (`buildRed`/`stagingCyan`/`ladderGreen`).
  **TESTS (closing the 2 load-bearing gaps CLOCK Stage 1–3 left behind):** `SnapshotBuilder`'s WHOLE `clock*` resolve/
  clamp block had ZERO coverage — including the one safety-critical clamp (`clockDepth ≤ 0.95`, the monotonicity
  ceiling keeping WAVE's local time from running backward; a regression there wouldn't fail anywhere else in the
  suite) — +`testClockParamsResolveAndClamp`. `clockDrawnPhase`'s SPAN re-anchor branch (`periodBeats > 0`) was also
  untested (every existing test only exercises FREE) — +`testClockDrawnPhaseReAnchorsAtEverySpanBoundary`. Plus a
  minor `loopColumnPlan` out-of-range-clamp test. **REFACTOR survey: nothing actionable** — no render-path allocations
  in the CLOCK code, one flagged-but-not-urgent pre-existing duplication (`emitColumnMod`/`emitFreeMod`'s parallel
  loops), no stale comments, no bugs.**
- **▶ CLOCK — a placeable pattern-clock transform, Stage 1 (2026-09-26, on `main`, `4afe9dd`; iOS builds, macOS 1098
  green; DEVICE ear/eye owed). Design-partner spec (`AcceptanceCriteria-clock-processor`, ratified via the
  `_dear_claude_code/` channel), planned first (`~/.claude/plans/whimsical-wibbling-walrus.md`): a chain stage where
  everything downstream ticks to a transformed local time and everything upstream keeps the part's — polymeter,
  rubato, stutter-time as an ordinary chain citizen. `[EUCLID→CLOCK 3:2→RATCHET]` = hemiola; `[ARP→CLOCK ÷2→ECHO]` =
  half-time trails. **THE SOVEREIGN LAW, mechanically:** CLOCK never touches windows/columns/spans'-own-extents/the
  reel/boundary-deferred switching — only a downstream FOLD consumer's OWN internal step/rate math reads the
  transformed beat. Two pure functions (`Derivations.swift`): `clockFixedPhase` (beat×ratio+offset) and
  `clockWavePhase` (a zero-mean closed-form wobble around ×1 — SINE or TRIANGLE, both hand-verified to re-land
  EXACTLY in phase at every SPAN boundary, any depth); `depth` clamped <1 at resolve (`SnapshotBuilder`) so
  dphase/dbeat never goes non-positive (local time must never run backward, or a downstream fold's note-ordering
  breaks). **THE ENGINEERING:** `emitDriverNote`'s fold consumers (RATCHET/SPLIT/AVOID/GLIDE/VELOCITY/RECORDER) each
  do their OWN independent backward-scan for "the first/last slot of type X after the driver" — no single sequential
  pipeline to slot into. New `Router.clockTransformedBeat(cell,from:to:atBeat:S:cycleBeats:)` composes every CLOCK
  stage strictly between two slot indices (multiple CLOCKs multiply, in chain order) — wired into exactly ONE
  flagship consumer this stage, RATCHET's fold, matching the spec's own headline example. Every other self-clocked
  consumer (DEST/VELOCITY/MOD/EUCLID/TUTTI/BURST/CASCADE/WEAVE/RIFF) is an explicit Stage-3+ follow-on, not built
  blind — mirrors this session's own SPAN-LADDER staged rollout. **SCOPING CALL flagged to design (not blocking):**
  CLOCK-before-a-driver (transforming a driver's OWN generation cadence, e.g. `[CLOCK→ARP]`) is OUT of v1 — it needs
  inverting the phase function back to real time to schedule ticks, no closed form for WAVE; v1 = CLOCK strictly
  between a driver and a downstream fold consumer, matching both of the spec's given examples. Model:
  `ProcessorType.clock` + `ClockMode`(FIXED|WAVE) + `ClockWaveShape`(SINE|TRIANGLE only — SQUARE is discontinuous, S&H
  isn't periodic/deterministic the way re-landing needs) + the 9-rung ratio ladder (×4…÷4, dotted/triplet deferred
  per the spec). UI reuses only existing widgets (seg/numPair/slider/frameSpan); self-names the slot ("CLOCK ×2" /
  "CLOCK WAVE") via `buildProcLabel`; two TIME-group storefront cards. +6 DerivationsTests (fixed math, multiplicative
  composition, ×1/depth-0 no-ops, WAVE re-landing at every span boundary for both shapes/several depths/periods,
  monotonicity at the clamp ceiling) +2 RouterTests (the RATCHET fold genuinely reads the transformed beat — caught +
  fixed a test-design pitfall along the way: column 0 is invariant under any pure ratio scaling, so a first-draft
  test picked it as the "special" column and couldn't distinguish a working transform from a no-op; an RTCDEBUG trace
  confirmed the transform itself was correct throughout; two-CLOCK composition matches the product ratio regardless
  of stage order). **STAGE 2 — DRAWN mode landed same day (`e528b94`; iOS builds, macOS 1105 green):** a hand-
  authored per-column ratio LANE — `ClockMode` gains `.drawn`; `clockDrawnRatios`/`clockDrawnGlide`/`clockDrawnSteps`/
  `clockDrawnRate` (Models.swift, MachineParams) resolve ONCE at `SnapshotBuilder` time via `clockDrawnResolveRatios`
  (empty/−1 "CARRY" columns hold the PREVIOUS explicit ratio, wrapping around the lane if the whole thing is empty —
  a pure carry-forward scan, never re-mapped on the render side) into fully-resolved `SnapParams` arrays. Two more
  pure functions (`Derivations.swift`): `clockDrawnPhase` (per-column SET = snap to the column's ratio immediately ·
  GLIDE = linearly ramp FROM the previous column's landed ratio TO this one, a quadratic phase accumulation within
  that column — factored via `fullLaps × lapAdvance + partial + current` so it stays O(steps) and exact no matter how
  many laps have elapsed, never a per-lap summation) and `clockDrawnDriftPerLap` (the lane's own net beats gained/
  lost per lap against real grid time — an honesty readout, not a correction). SPAN's FREE (0) end is a genuine mode
  here (the lane just laps forever from absolute beat 0) — `spanLadderBeats` has no "0 = free" sentinel of its own
  (n≤1 means ONE COLUMN), so `Router.clockTransformedBeat`'s DRAWN branch guards `clockSpanN > 0` explicitly before
  calling it, mirroring the same idiom RATCHET PATTERN/DEST already use for their own free-run spans (caught before
  it shipped — DRAWN's UI passes `frameSpan(free: true)`, unlike WAVE's `free: false`, since WAVE's period can never
  sensibly be zero but DRAWN's can). UI: STEPS/RATE/a `stateMatrixRadio` ratio-per-column matrix (a "···" CARRY rung
  above the 9 ratio rungs) + a `toggleLane` GLIDE row + SPAN + the drift-readout `Text`, reusing only pre-existing
  widgets per the spec; a "CLOCK DRAWN" storefront card. +5 DerivationsTests (carry-forward/wrap/empty-lane fallback,
  all-×1 no-op, SET-vs-GLIDE hand-verified exact values, the drift readout cross-checked against the phase function's
  own lap advance, exactness across 50 simulated laps) +2 RouterTests (a single constant-ratio DRAWN column reduces
  EXACTLY to FIXED at that ratio — an equivalence check, not a hand-derived count, so it can't hit the column-0-style
  invariance trap again · SET vs GLIDE genuinely fold differently, hand-verified via a fresh RTCDEBUG trace after the
  first draft's parameters coincidentally produced the SAME strike total for both — the same lesson twice now: never
  trust a hand-derived beat/column mapping without an empirical trace first). Also caught pre-merge: a `toggleLane`
  call with two named arguments in the wrong order (Swift requires labelled arguments in declaration order) — would
  have failed only the iOS build, not the macOS unit-test target (GridUI.swift isn't in that target), so it's a
  standing reminder that this codebase's off-device verification needs BOTH passes, not just the faster one.
  **STAGE 3 — DEST/VELOCITY/TUTTI/MOD (`4da7446`; iOS builds, macOS 1109 green):** threads `clockTransformedBeat`
  into every self-clocked consumer that's ARCHITECTURALLY REACHABLE under the current fold model. **DEST + VELOCITY**
  ride `emitDriverNote`'s fold exactly like RATCHET's Stage-1 wiring (`clockFrom = driver + 1`) — `chopMask`/
  `emitChop` gained an optional `clockFrom`/`cycleBeats` pair (default −1/0, byte-identical at every other of the
  now-16 call sites that don't pass it); VELOCITY's slot index is now captured during the forward scan (it only had
  its params before). **TUTTI** rides `applyStage`'s generic dispatch (it's note-transparent, not pulled into its
  own explicit branch like RATCHET/VELOCITY) — `applyStage` gained the SAME optional `clockFrom`/`atSlot` pair,
  read by its ONE self-clocked case (`.tutti`) only; every other mode (ARP/CHANCE/HARMONIZE/…) ignores them
  entirely. **MOD is the odd one out — it has NO driver at all** (`emitColumnMod`/`emitFreeMod` scan every MOD slot
  in a cell unconditionally, column-gated or not), so it threads from CHAIN-START (`from: 0`) instead of driver-
  relative — the first departure from the driver-relative framing all of Stages 1–3 used until now, since "down-
  stream of a driver" simply doesn't apply to a processor whose whole point is speaking regardless of what's driving
  notes. Only the shape-READ beat is transformed; the real sample-time a CC is actually sent at (and `entryBeat`,
  the STRIKE envelope's re-trigger reference, which lives in real column-space) are both untouched — the sovereign
  law again. **BLOCKED, not attempted:** EUCLID/BURST/CASCADE/WEAVE/RIFF are `isDriverType` themselves —
  `chainDriverIndex` always makes the LAST one the chain's own driver (confirmed by re-reading its scan: only
  driver-type slots enter the `lastDriver`/`lastNonFold` tracking at all), so they never reach a downstream-fold
  position under this architecture regardless of chain order — `[ARP→EUCLID]` makes EUCLID the driver (re-pooling
  from the ARP's output via `composeChainSet`), not a folded consumer reading ARP's per-tick beat. Retiming these
  five needs the SAME phase-inversion problem Stage 1 scoped out (no closed-form inverse for WAVE or DRAWN) — not
  a threading exercise like this stage, a genuine open design question. +4 RouterTests, one `[ARP→CLOCK→X]` pair
  per consumer, each hand-verified via a fresh RTCDEBUG-style trace before asserting (two of the four — TUTTI and
  VELOCITY — looked wrong on first run: every note emits on BOTH its own cable and the shared ALL cable per §7b, so
  an unfiltered/vel-filtered count silently doubled; fixed by filtering to one cable, not a bug in the wiring — the
  THIRD time this session an apparent CLOCK bug turned out to be a test-counting artefact once traced, not an engine
  fault). **NEXT:** the CLOCK-before-a-driver scoping question is still open, going to design via the outbox — until
  it lands, EUCLID/BURST/CASCADE/WEAVE/RIFF stay untouched by CLOCK; this closes out the reachable half of the
  Stage-3 roster.**
- **▶ PART GRID — LOOP-COLUMN BUTTONS, order-preserving (2026-09-26, on `main`, `8530379`; iOS builds, macOS 1090
  green; DEVICE eye/ear owed). Paul: toggle buttons on the part grid's bottom rail restricting playback to a chosen
  subset of columns, played in the order they were ADDED (not left-to-right) — both the part-grid playhead and the
  play-ferry button's playhead must reflect it. Planned first (`~/.claude/plans/whimsical-wibbling-walrus.md`), then
  built to the approved plan. The bottom rail already existed as a placeholder for exactly this (`roomsGridFooter`,
  "PART = column-loop buttons, not wired" — drew empty boxes); the existing engine lap primitive (`Derivations.
  lapColumn`) is bitmask-based (always ascending order) and driven by a UIKit hold-gesture belonging to the retired
  GRID tab — unreachable from BUILD and unable to express "added order" anyway. **DESIGN:** resequence at scene-
  composition time rather than teach the real-time render engine a new ordered-lap concept — ONE pure primitive,
  `BuildSceneLogic.loopColumnPlan(loopCols:length:)`, maps a logical step (0..<count) to the real part column to
  read from / draw at (identity map when unused, byte-identical). BOTH audio paths — `composeSceneMeta`'s staging
  block (the active ferry) and `buildFlattenFerry` (background ferries, already a live per-publish derivation since
  the ferry-purity fix above) — and BOTH playheads (`roomsPartPlayhead`/`roomsCardRowPlayhead` for the part grid,
  `roomsCellPlayhead`'s new `steps:` param for the ferry button) call the SAME function, so the lit cell and what
  plays can never disagree (this session's standing lesson: RATCHET PATTERN → DEST → the ferry-rate fix → this).
  `BuildPart.loopCols: [Int]?` (ordered, nil/empty ⇒ play the whole part) round-trips through `buildLoadBenchPart`/
  `buildCaptureBenchPart` + the undo `BuildSnapshot`, exactly like `rate`/`length`; `buildTogglePartLoopColumn`
  APPENDS on select (added-order — re-adding a removed column goes to the END, not its old position). New
  `roomsPartLoopFooter` (a "repeat" SF Symbol per column, same size/shell as the placeholder) replaces the call at
  the PART site only — the SELECT-page footer + `roomsGridFooter` itself are untouched. **ADJACENT BUG FOLDED IN:**
  `roomsCellPlayhead`'s bar length was hardcoded to `Snap.cols` (8) even for a 16-step part — a 16-step ferry's
  button already swept 2× too fast regardless of looping; now takes the caller's real effective step count. +5
  `BuildSceneLogicTests` (loopColumnPlan identity/added-order/out-of-range-fallback; composeScene plays the selected
  columns in added order, not sorted; an empty selection composes byte-identical to today).**
- **▶ PLAY FERRIES — the background playback line is now a LIVE DERIVATION, not a cache (2026-09-26, on `main`,
  `80c1dc4`; iOS builds, macOS 1085 green; DEVICE eye/ear owed). Follow-up to the ferry-playhead rate fix, prompted by
  Paul's own mental model of the feature: "every play ferry is a part grid, only the selected one is visible" —
  TRUE of the storage (`buildFerryParts`, one `BuildPart` per ferry) but NOT of playback. The active ferry's staging
  sequencer already recomposes from the live bench every publish (pure); every OTHER on-air ferry played from
  `buildPlayColSteps/Rate/Len/StepRecv/StepEmit` — a snapshot `buildFlattenFerry` only refreshed at specific event
  boundaries (a ferry goes on / stops being active). Any edit to a background ferry's stored `BuildPart` between
  those events (its rate, its I/O, a drag-and-drop overwrite) left the cached line stale until the next transition —
  the same root cause as the rate-playhead bug, generalised. FIX: `buildPublishScene` now re-derives every ON,
  non-active ferry's flattened line from `buildFerryParts[t]` (the one source of truth) on EVERY publish, before
  those arrays are read into the scene `Input` — giving background ferries the same "always live" treatment the
  active ferry already had, just collapsed to the ONE hidden play-layer row each background ferry is allocated
  (`Snap.playLayerRowBase` — a genuine engine constraint: poly background playback isn't built, so a background
  ferry's whole grid must reduce to a mono line regardless). The persisted `@State` shape and the existing event-
  triggered `buildFlattenFerry` calls are untouched (now harmless belt-and-braces) — this closes the staleness GAP
  between those events rather than replacing the mechanism. Should also fix any other background-ferry field (I/O,
  chain) that could have gone stale the same way, not just rate — device-owed to confirm.**
- **▶ PLAY FERRY PLAYHEAD — now follows the cell's own PER-PART RATE (2026-09-26, on `main`, `c6f0f5a`; iOS builds,
  macOS 1085 green; DEVICE eye owed). Paul: changing a ferry's RATE updates the part-grid playhead at once but the
  play-ferry BUTTON's own playhead kept sweeping at the original rate. ROOT CAUSE: `roomsCellPlayhead` (the sweep
  drawn on every ferry's PLAY button) was hardcoded to the scene-default `stepBeats`, never reading PER-PART CLOCK at
  all — unlike `roomsPartPlayhead` (the part grid's own sweep), which already reads `buildPartRate` live. FIX:
  `roomsCellPlayhead` takes an optional `rate: StepRate?` (nil ⇒ `stepBeats`, byte-identical elsewhere — its only
  caller is the ferry button); `roomsPlayFerry` passes the ferry's TRUE rate — the live `buildPartRate` for the
  ACTIVE (bench-open) ferry (matches `roomsPartPlayhead` exactly, updates the instant the RATE menu changes) or the
  stored `buildPlayColRate[t]` for a background ferry (refreshed whenever that ferry stops being active).**
- **▶ ARP-RATE LFO — the ladder is now TEMPO-SORTED, not declaration-block order (2026-09-26, on `main`, `04b7807`;
  iOS builds, macOS 1085 green; DEVICE ear owed). Paul: "the LFO on the arp rate seems to miss out dotted and triplets
  even when I include them in the selection. It jumps right past them" — and pointed at the RATCHET PATTERN saga as
  the model for diagnosing it. ROOT CAUSE (same shape as the RATCHET/DEST bugs — a ladder/clock whose position axis
  didn't correspond to the real musical quantity it claimed to): `arpRateAllowedLadder(ignore:)` returned the kept
  rate indices in ArpRate's DECLARATION-BLOCK order (all 6 normal · all 6 dotted · all 6 triplet). But a dotted/
  triplet rate musically falls BETWEEN two adjacent normal rates (1/4T=0.667 beats and 1/8D=0.75 beats both sit
  between 1/8=0.5 and 1/4=1.0). Since FROM defaults to the arp's own base rate, the common sweep is between two
  NORMAL rates — and because both endpoints sat in the same contiguous ladder block, `applyParamLFO`'s linear FROM→TO
  interpolation over ladder POSITIONS never crossed into the dotted/triplet block, even with those families fully
  "included" (inclusion only ever affected which VALUES could exist in the set, never where they SAT in position-
  space). **FIX:** the ladder is now sorted by ACTUAL DURATION (`.beats`, slow→fast) instead of declaration block —
  ladder position is a true proxy for musical position, so any included rate that tempo-wise falls between the two
  endpoints is genuinely visited. `nearestLadderPos` + the interpolation math untouched, only the ladder's order.
  +1 regression test (`testArpRateLFOSweepBetweenNormalRatesCrossesIncludedDottedAndTriplet`, reproduces the exact
  reported symptom: 1/8→1/4 must cross 1/4T and 1/8D) + `testArpRateIgnoreLadderAndSnap` updated to the new order.**
- **▶ DEST MATRIX — NONE emitter + its own free-running RATE, the RATCHET-PATTERN-class fix (2026-09-26, on `main`,
  `0104c95`; iOS builds, macOS 1084 green incl. fuzz; DEVICE ear/eye owed). Paul's report on DEST (§5 routing-class,
  built 2026-08-22): zero emitters should be selectable, it needs a rate control, and "the visuals for which cell is
  lit up has nothing to do with what I hear" — he named RATCHET PATTERN's development as the precedent for how to
  read + fix this. ROOT CAUSE (same shape as RATCHET's pre-v6 bug): DEST indexed its 8-slot matrix via `chopSlice(m,
  columnBeats: S)` — an 8-way subdivision of the CELL'S OWN column, tied to whatever was driving notes through it —
  while the EDITOR matrix lit the unrelated DEFAULT grid-column clock (one column per whole bar step, ~8× slower).
  Two different clocks: the lit cell never corresponded to the emitter actually heard. FIX (mirrors RATCHET PATTERN
  v6/v7's self-clocked model): DEST now runs its OWN free-running clock — `destRate: ArpRate?` (nil ⇒ 1/8) →
  `destRateBeats`; `Router.chopMask`'s DEST branch computes `sl = floor(m ÷ destRateBeats) mod 8` (absolute beat,
  decoupled from the column/driver) instead of `chopSlice`; CHOP's own chopSlice branch is UNTOUCHED (that's a
  distinct, intentional per-column feature). The editor matrix (`GridUI` `.dest` case) extrapolates the IDENTICAL
  formula per animation frame via `StateMatrixClock` (RATCHET PATTERN's own mechanism — never the ~4 Hz poll, which
  aliases a fast rate into a jump), so the lit cell and the audible route are now always the same clock. **NONE**:
  `destSlices` gains `−1` (silence this step, no emitter) alongside 0=A…3=D — the matrix shows a 5th "·" column; a
  NONE slice yields mask 0, which every existing chopMask consumer already handles safely (no voice opens, no stuck
  note — the same path MUTE=0 already proved). FuzzTests' DEST randomizer widened to hit NONE + a random RATE. 2
  pre-existing RouterTests (`testDestMatrixHocketsTheArpAcrossEmitters`/`testMuteMatrixComposesOverDest`) still pass
  unchanged under the new clock. DEVICE-owed: the editor RATE control feel, the NONE "·" column, and confirming the
  playhead now visibly tracks what's heard.**
- **▶ RECORDER — a new looper-in-a-chain processor, stages 0–4 (2026-09-18, on `main` `87934e5`…`09d690a`; iOS builds,
  macOS 1084 green incl. fuzz; DEVICE ear owed). Paul ratified a spec (`AcceptanceCriteria-recorder.md`) then greenlit the
  build; done in tested stages while he's away (no device checks). A `ProcessorType.recorder` that records the upstream
  chain output over N steps/passes and plays it back — TRANSPARENT while recording (captured in the driver fold, GLIDE-
  style), a DRIVER while playing back (a per-window `emitColumnRecorder` pass, echo-ring class). Built: the full surface
  (editor + TIME storefront card + persisted config); the engine for a DRIVER-fed recorder — GRAIN passes|steps · LENGTH
  1…32 · ARM on-play|after-N · MODE **LOOP · FREEZE(held/repeat) · CANON** · MIX replace|layer · CAPTURE **once|refresh** ;
  and the persistence READ/CLEAR half (a persisted/authored `recEvents` = paired notes {beat·note·vel·gate} seeds the loop
  directly — a stored-clip player; CLEAR resumes live recording). The phase is a pure fn of the pass/step number → a
  committed loop is replay-exact; only the live capture window isn't seek-exact (accepted, TURNS/DEAL class). No stuck
  notes (fuzz across every edge + all modes; `testRecorder*` in RouterTests). **DEFERRED (device-ear owed on the feel):**
  the live-capture→document **SAVE drain** (render→main, so a session-recorded loop persists to disk — the crash-prone
  boundary, wants host verification); **standalone/hold-fed** recorder REPLACE-suppress (no driver ⇒ the hold layers);
  **FREEZE-HELD** true legato (v1 re-pulses per loop); **HOLD**'s momentary grab (needs a control signal). Per-cell render
  state (recNoteCap=96) reset on every flush edge (scene/panic drop the loop; transport/latch/freeze keep it).**
- **▶ THE 2026-09-14→16 ARC — RANDOM ONCE · per-param ∿ LFO (+ redesign) · MOD rework · RIFF additions · DEAL · card-grey ·
  sliders · housekeeping (all on `main`; iOS builds, macOS 1116 green; DEVICE eye/ear owed on the UI). A run of Paul's asks.
  (1) **RANDOM ONCE arp pattern** (`cd65b3e`) — `ArpPattern.randomOnce`, a per-pool shuffle from a PERSISTED `arpSeed`
  (`splitmix64Mix(asc+seed) % span`), replay-exact; PATTERN→"ARP PATTERN", FLOW→"ARP FLOW". (2) **PROCESSOR-CARD PLAY-GREY is
  POSITIONAL, not sounding** (`44fe3d9`/`bbeeaac`/`26a361c`/`6ac926c`, earlier per-cell `5592eab`/`8521d86`) — the card dims when
  the machine can't receive MIDI in the current column, read from `buildProcessingNow` (fixed the flashing: was gated on
  live SOUND, which flickered). (3) **ARP euclid GAPS=CHORD stab controls** (OCTAVE·LENGTH·VELOCITY) + LFO on HITS/ROTATE/CHANCE
  (`605c74f`/`a244ff2`/`dbc4abc`). (4) **THE PER-PARAM ∿ LFO** (`0a516a2`→`d4de554`) — a mod button beside a param label. Stage 1
  engine + Stage 2 UI, THEN a REDESIGN: `ParamLFO { target, shape (WAVE), period/stepSpan (DURATION), to }` sweeps the base
  param → TO over a DURATION (GRID STEPS · FIXED SUBDIVISION); **FROM ≡ the base param — two views of one value** (editing either
  updates both, seeded on open, kept on REMOVE); DEPTH/PHASE/QUANTIZE + `paramLFOValue` all REMOVED. Arp RATE is special-cased
  (`applyParamLFO` sweeps the rate ladder) with **INCLUDE-family toggles** (NORMAL/DOTTED/TRIPLETS via `rateIgnore`). Engine
  `applyParamLFO`; editor `lfoEditor`. (5) **SLIDERS chunkier/grabbier** (`4d12f40`, `FineSlider` track 5→9pt · thumb 16→28pt).
  (6) **HOUSEKEEPING** (`a3d57b2`) — CHORDS **8→16 fix** (`chordsDegreesResolved`/`applyChords` now size the degree matrix + rotate
  to the matrix WIDTH — a 16-wide progression was truncated to 8), Dice fillRole fix, dead `paramLFOValue` removed, stale
  "128 cells"→256 comments. (7) **MOD editor → the arp-LFO anatomy** (`383ca9c`) — reworked to FROM/TO + DURATION [GRID STEPS ·
  FIXED SUBDIVISION] + WAVE (was MIN/MAX; engine still stores `modMin`/`modMax`, only the labels/editor changed) + a live CC
  marker + `modStepSpanN` (grid-steps duration via `spanLadderBeats`). (8) **RIFF gate-length + DIRECTION** (`9afa57c`) —
  a gate-length control (with ∿ LFO) + `RiffDir` FWD/REV/PING-PONG step reorder + a roomier RATE grid + SPAN on its own line.
  (9) **NEW `DEAL` processor** (`ce1f54a`) — a simple OUTPUT dealer (ROUTING group): OVERRIDE the cell's emitters and deal N1
  notes to emitter 1 then N2 to emitter 2 (repeat, defaults 1/1). Note-transparent (`cellMode .deal = .identity`); reuses the
  TURNS moment-counter idiom in `emitArtic` with per-cell counters (reset on every transport/scene/panic edge → no stuck notes);
  DEAL mode = **OVER TIME** (per strike) · **WITHIN CHORD** (per note-in-moment) · **EVERY NOTE** (per note-on). +Router/fuzz
  tests. v1 flag (like TURNS): the deal position isn't replay-exact across a mid-phrase seek/loop; WITHIN CHORD after a mono
  driver sits at position 0. DEVICE-owed: every ∿ button + the MOD/RIFF/DEAL editors + DEAL splitting across two synths audibly.**
- **▶ FERRY DRAG-AND-DROP — long-press copy/seed RETIRED; SELECT-cell-is-a-part; colour inherit + reallocation; housekeeping
  (2026-09-12, on `main`, `7f1bd88`…`6852381` + the housekeeping commit; iOS builds, macOS 1086→1090 green; DEVICE eye owed).
  Paul reworked how a SELECT cell reaches a play ferry. **COPY GESTURE RETIRED:** the play-ferry + right side-rail LONG-PRESS
  copy/seed (and the rising-fill/commit-bloom animation) are GONE. **DRAG-AND-DROP (`947d866`)** in a shared `"rooms"`
  coordinate space (custom finger-track + FerryZoneKey drop-zone frames + floating ghost — `.onDrag` doesn't survive the AU
  host): a **SELECT cell → play ferry** populates it; a **ferry → ferry** MOVES (overwrites target, vacates source, carries
  play/mute/solo); a **ferry → the machine-box trash** deletes it (the trash now reveals on a ferry drag too). Ferry
  spring-momentary play is kept; the side-rail is tap-to-select only. **SELECT-CELL = A PART WITH ONE ROW + INHERIT
  (`6852381`):** dragging a SELECT cell makes the ferry INHERIT the cell's **name** (committed hash, else a short chain
  hash), **colour** (`ferryHue`), and **settings** (chain) — not a fresh positional part hue. **COLOUR REALLOCATION:** a cell
  dropped on a populated ferry of a DIFFERENT colour whose incoming colour is currently allocated to an EMPTY ferry → that
  empty ferry is re-allocated the DISPLACED colour (`buildFerryHueAlloc`, consulted by `buildFerryHex` for empty slots,
  persisted in `BuildPlayGridData.ferryHueAlloc`, additive-Optional). **SELECT-CELL FACE (`7f1bd88`/`d186888`):** the SELECT
  cell keeps its piano-roll face UNTIL it's committed (named), then the name replaces the roll; committed cells persist with
  the session (`gridSelChains`/`Hues`/`Names`) + no auto-revert; the ferry settings tab takes the cell's name.
  **HOUSEKEEPING (this pass):** extracted the pure ferry-drop cores to `BuildSceneLogic` (`FerryDragSource`/`FerryDropZone`
  enums + `ferryZoneAt` + `ferryColourDisplacement`) so they reach the test target (+4 BuildSceneLogicTests: ferryHueAlloc &
  gridSel* round-trips, zone hit-test, reallocation); DRY'd the ferry activate path (`buildReactivateFerry`); removed the
  now-dead copy/stamp cluster (`buildGridSelStampSweep`/`Pressing`/`Fire`/`Commit`/`CanStamp`, `roomsStampFire`, +
  `roomsAssignPlayColumn`/`roomsFlattenPartToPlay`/`roomsStampSourceIO` — the retired play-column ferry — + 5 dead @State).
  **FLAGGED:** `buildArchivePartToPlay`/`buildSelectPlayColumn`/`buildPlayFerryRow` are now orphaned too (a deeper retired
  play-column cluster — left for a dedicated dead-code pass, they touch part-grid persistence). DEVICE-owed: the whole drag
  feel (ghost, hovered-ferry cyan ring, trash reveal), the inherited name/colour read, the reallocation on a real palette.**
- **▶ COLOUR → MACHINE — the concept renamed (2026-09-09, on branch `feature/machine-rename`; macOS 1085 green, iOS builds;
  awaiting merge). Paul: the `Colour` object no longer means "a sound colour the user picks" — it is a MIDI treatment/machine
  (a processor `type` + `MachineParams`/`templateChain` + identity), carrying zero routing (that's on `Cell`) and zero stored
  colour (the display **hue** is *derived* from `machineID`). The code had drifted to "machine" in newer UI (`buildMachine*`,
  RackMatrix), so there were two words for one thing. Full rename across `AUExtension/*.swift` + `Tests/*.swift`:
  `Colour`→`Machine`, `SnapColour`→`SnapMachine`, `ColourParams`→`MachineParams`, `colourID`→`machineID`,
  `PluginState.colours`→`machines`, `colourIDs`→`machineIDs`, `buildColourReg`→`buildMachineReg`, the enum case
  `.allColour`→`.allMachine`, etc. The genuine HUE helpers took hue names not machine: `colourColor`→`machineHue`,
  `colourHexes`→`machineHexes`, `colourHueOverride`→`machineHueOverride`, `emitterColour`→`emitterHue` (overloads the
  existing `emitterHue(Set<Bus>)`), `markColour`→`markHue`, `buildEmitterPlayingColours`→`buildEmitterPlayingHues`;
  `buildColourMachine`/`buildWriteColourMachine`→`buildMachineSlots`/`buildWriteMachineSlots` (avoid `MachineMachine`).
  **KEPT unchanged (data, not names):** the palette id string VALUES `"gold".."slate"` + ephemeral `"b<n>"`/`"gsAud"` (they
  anchor the default hue palette); AU param addresses (numeric, invariant 5); position/role palettes (`playHexes`,
  `partRowHexes`, `emitterHexes`, `receiverHues`); the prose adjectives `coloured`/`colourless` (genuinely about hue). The
  British spelling isolated the project token from SwiftUI's `Color` (no 'u'), so a substring sweep was safe. **NOTHING
  SHIPPED → on-disk Codable keys moved with the field names (synthesized), so pre-rename saved sessions factory-reset — Paul
  accepted this, no migration written.** Plan: `Docs/PLAN-machine-rename.md`. Pure rename, no behaviour change; device pass
  only to confirm UI strings read "machine". NOTE: this status log's OLDER entries below still say "Colour" (history, not
  revised). FLAGGED FOLLOW-UP: the wider `Docs/*.md` corpus (specs/manual/factory-scenes) still says "colour" — a separate
  vocabulary pass if wanted; the test FILE names (`ColourTypeSwitchTests.swift` etc.) keep their filenames (symbols inside
  renamed; a file rename would need xcodegen).**
- **▶ MOD finishing — FREE/LFO cell + QUANTIZE + PHASE + EXTERN SCALE (2026-09-09, on `main`, merge of `feature/mod-finishing`;
  iOS builds, macOS 1085 green incl. fuzz; DEVICE ear owed). Launch-critical MOD polish (MOD already FUNCTIONED — all 5 sources
  SHAPE/FOLLOW/STEPS/STRIKE/EXTERN + MIN/MAX + SPAN + CC/CHAIN targets, tested; Paul's pick = FREE/LFO + refinements, NOT the
  tactile fader or ownership pin). **FREE / THE LFO CELL (§16):** `modFree` — a MOD slot speaks EVERY window regardless of the
  playhead → the grid becomes a mod-matrix (a modulation-only cell beside music cells). `emitFreeMod` scans all cells once/window
  (beat-derived, replay-safe, block-invariant; active-column FREE slots skipped in emitColumnMod → no double-emit; NO
  leave-disposition — a flush stops it; CC targets only, a FREE chain-target has no active column to fold into — v1). **QUANTIZE
  (§14①):** `modQuantize` snaps the output to N levels (pure `modQuantizeValue`, both emit paths). **PHASE (§14②):** `modPhase`
  0–360° on the SHAPE wave (quadrature sines). **EXTERN SCALE (§6):** `modExternMode` RE-EMIT|SCALE — the incoming CC scales the
  SHAPE's depth ("rhythm from us, amount from the wheel"). Model (additive-Optional) + builder + engine + UI chips (SPEAK ON
  PLAYHEAD|FREE · QUANTIZE · PHASE · EXTERN MODE). **DEFERRED with reason: FOLLOW averaging WINDOW** — a true time-average needs
  pool/event HISTORY accumulated across renders (violates invariant 2, derived-never-accumulated); wants a sanctioned state
  exception (a design call), so v1 FOLLOW stays instantaneous — flagged for Paul. +2 tests (FREE cell speaks off the playhead ·
  QUANTIZE snaps to the level set). Spec `AcceptanceCriteria-mod-finishing.md`. DEVICE-owed: the CC feel (LFO cell · EXTERN SCALE
  with a real wheel · QUANTIZE steppiness). **Launch trio DONE: RATCHET (P1 fix) · RIFF (CAPTURE) · MOD (finishing).**
- **▶ RIFF CAPTURE §2 — "play a line in", the RIFF headline (2026-09-09, on `main`, merge of `feature/riff-capture`; iOS
  builds, macOS 1083 green incl. fuzz; DEVICE ear/eye owed). Paul's launch-critical RIFF finishing (the stencil engine §1/§5
  was already solid + tested). CAPTURE: LATCH a chord (the FRAME) → arm → play the line on the SAME door → keep. The line is
  recorded AS RANKS against the frame → it FOLLOWS every chord after (zero pitches stored). **PURE (tested):**
  `riffCaptureRank(pitch,frame)` = inverse of `riffResolve` (nearest rank+oct, round-trips a frame note; passing tone snaps) +
  `riffCaptureStencil(events,frame,steps,rateBeats,startBeat)` = quantize the (beat,pitch) take onto the step grid → MONO
  riffRanks/riffOct, unplayed steps REST, a take past one loop truncated. **KERNEL:** ephemeral capture state (never persisted,
  like auditionTarget) — arm snapshots the door's held/latched chord as the frame + starts a ring; `handleIncoming` DIVERTS the
  capture door's live line into the ring (never touches the pool → the frame can't shift); disarm drains on the main thread
  (record-on-render / convert-on-main, the reel pattern → no stuck notes). **AU:** `armRiffCapture`/`cancelRiffCapture`/
  `commitRiffCapture(colourID:)` (drain → `riffCaptureStencil` → write riffRanks/riffOct onto the colour's RIFF slot). **UI:** a
  CAPTURE row on the RIFF editor (◉ PLAY A LINE IN · ● RECORDING—TAP TO KEEP · CANCEL). **v1 SCOPE (Paul-confirmed): HELD frame +
  MONO line** — FOLLOWING (§4 re-voicing / pool-timeline) · POLY (chord capture) · §3 generator are flagged fast-follows. +1
  RouterTest (capture→playback→FOLLOW-a-new-chord) + 2 DerivationsTests (round-trip incl. octave · quantize/rest/truncate).
  Spec `AcceptanceCriteria-riff-capture.md`. **DEVICE-owed caveats:** capture needs a RUNNING CLOCK (host/free-run — beat-quantized,
  so stopped lands all on step 0); LATCH-first (a physically-held chord on the same OMNI door pollutes the take); the recorder +
  arm gesture aren't unit-testable (live MIDI in) — the pure conversion + playback are locked, the feel is Paul's to verify.
  NEXT launch-critical: MOD (the CC-stage sources).**
- **▶ RATCHET PATTERN standalone = PASS-THROUGH + unselect-to-mute (2026-09-09, on `main`, merge of `fix/ratchet-passthrough`;
  iOS builds, macOS 1080 green incl. fuzz; DEVICE EAR OWED). Paul's priority-1 fix. A lone (SINGLE-SLOT) RATCHET PATTERN cell
  is now a PROCESSOR of the input, NOT a self-clocked generator: it PASSES the held chord through, and its OWN clock
  (rtcRate·STEPS·SPAN·rotate) only decides the per-column treatment — **count 1 = sustain (rate-INDEPENDENT legato hold) · 2…8 =
  ratchet N over the column's slot · 0 = OFF/mute**. No input → silence. Fixes "a short chord stab plays for each step" (the old
  standalone `emitRatchetModal .pattern` GENERATED a note per column-tick regardless of input) + adds unselect-to-mute (both
  confirmed by Paul; the OFF state REVERSES the earlier "no rest-as-silence" ruling — he now wants it). **ENGINE:** a per-window
  subsystem `emitColumnRatchetPattern` (called before the pool guard, like emitColumnMod/Glide) — a STATELESS diff-reconcile
  modelled on `reconcileBypass`, owning IMMORTAL `rtcHold` voices (a new `Voice` tag, EXCLUDED from the grid hold-reconcile;
  `allNotesOff` closes them on every transport/scene edge → no stuck notes). PASS sustains keyed on (wire,bus,colour) so a ROW of
  same-colour cells sustains SEAMLESSLY (adopt across cells); RATCHET columns window-scan staccato sub-strikes (`ratchetStrikeAt`).
  `emitRatchetModal .pattern` returns early for single-slot cells (the subsystem owns them); the `[ARP→RATCHET PATTERN]` per-note
  FOLD is unchanged + gains OFF=mute (drops the driven note). Builder clamp `1→0` so OFF survives; the matrix editor gains a `0/·`
  OFF state. **KEY BUG caught in test (not device):** first read the ratchet params from `colour.a` — wrong for a chain cell whose
  colour is a passgate; the resolved slot is `cell.proc`. **v1 SCOPE:** single-slot standalone only (a `[RATCHET PATTERN → X]`
  chain keeps the old generator — flagged follow-up). +2 tests (RouterTests rate-independence/ratchet-adds/OFF-mutes/no-input;
  DerivationsTests rewritten from the retired self-clock test). Spec `AcceptanceCriteria-ratchet-passthrough.md`. Part of the
  launch-set work (`PLAN-stream-unification.md`, on branch `feature/grid-rebuild`): RATCHET was Paul's P1; RIFF + MOD are the next
  launch-critical finishing targets, all well-tested processors ship, only hocket + weave shelved.**
- **▶ THE 2026-09-08 WORKBENCH BATCH — VELOCITY processor · grid footers · PLAY-FERRIES-ARE-PARTS · add-a-row · a
  housekeeping sweep (all on `main`, pushed; iOS builds, macOS suite green; DEVICE eye/ear owed on the UI). (1) VELOCITY
  (`ProcessorType.velocity`, `76f2027`) — a per-step velocity SEQUENCER, a note-transparent DYNAMICS MODIFIER folded in
  `emitDriverNote` (velLane/velPass/velSteps/velRate/velSpanN/velClock; `velLaneStep` pure): downstream of a driver it
  sets each note's velocity from a per-step lane, TIME clock (own RATE grid) or NOTE clock (one column per note), SPAN
  re-anchor, per-step PASSTHROUGH. Editor drag-across sliders + drag-paint bypass row (`fix/velocity-lane-drag`), euclid
  brush dropped (`cd8f803`). SCALE compressor MODE deferred. (2) GRID FOOTERS (`f81b6ae`+`b700af8`) — a placeholder row
  flush under both grids, 2/3 ferry height, interior-body width (SELECT=pages · PART=column-loop; NOT wired). (3)
  **PLAY-FERRIES-ARE-PARTS** (spec `AcceptanceCriteria-play-ferries-as-parts.md`; Phases 1–3 `c21a7d3`…`ffb9bc0`, merge
  `b4f18d3`) — each of the 8 play ferries IS a full `BuildPart` (`buildFerryParts`/`buildActiveFerry`, persisted via
  `BuildPlayGridData.parts` + `partsResolved` migration). The ferry row is the SOLE navigation (SELECT|PART toggle
  retired): a populated ferry's SELECTOR opens its part on the bench, an empty ferry → the SELECT browser; long-press an
  empty ferry on SELECT seeds a part from the selected chain **[SUPERSEDED 2026-09-12 — the long-press seed/copy is RETIRED;
  populate a ferry by DRAGGING a SELECT cell onto it (see the top FERRY DRAG-AND-DROP entry)]**; CLEAR frees a ferry (empties the part → the ferry clears →
  SELECT). Playback: the ACTIVE (on-bench) ferry plays via the STAGING step-sequencer (visible sweep, per-column selected
  rung, live edits); BACKGROUND on-ferries via the play-layer flatten — up to 8 at once. Seed fills the whole first row;
  extending a part to 16 tiles the pattern. Retired the SELECT-backed play cells / hand-authored passes / cursor. STILL
  LEFT (flagged): an entangled dead-code cluster (`buildPlayCells`/`buildPlaySel`/`buildSelectMode`/… + the `.play`/`.reel`
  room subtree) for a dedicated device-verified pass. (4) ADD-A-ROW (`buildRowCreatorMenu`, `e2ebf76`) — selecting an
  EMPTY part row turns the machine-box interior into a fixed-footprint menu: DUPLICATE/MUTATE per populated row · RANDOMIZE
  · CREATE NEW · PICK FROM LIBRARY, each minting a colour onto the row. (5) HOUSEKEEPING (5-agent survey, every finding
  re-verified) — the emitter strip now maps the active ferry whenever it's ON + background ferries from their flatten
  steps (was blank on some passes); the per-cell SOUNDING gate now covers all 256 cells (the 128-bit lo/hi gate that
  dropped a 16-wide part's cols 8–15 is RETIRED — the UI derives the gate from the 256-wide `cellSoundVel > 0`); +CR-8
  decode-tolerant `init(from:)` for `Colour`/`ProcessorSlot`/`SceneState`/`Receiver` (a future non-Optional field can no
  longer factory-reset an older doc; +round-trip tests); composeScene occ scans the full 16-wide part; +VELOCITY TIME/SPAN
  RouterTests. DEVICE-owed: the whole ferry UI + the strip + VELOCITY ear.**
- **▶ RATCHET PATTERN v6 — SELF-CLOCKED PASS-THROUGH, ✅ DEVICE-VERIFIED (2026-09-07, on `main`, `6db4ae6` engine + `c6fcbb4`
  playhead; iOS builds, macOS 1072 green). SUPERSEDES Model B (v5) below. Paul's final ruling: "Ratchet pattern is NOT a driver.
  It receives MIDI, passes it through, unless the current column is active in which case it ratchets it the specified number of
  times" + "should have its OWN clock, and any notes passed through should ratchet or not based on the timing of the ratchet
  pattern processor." So Model B's per-arp-NOTE ordinal (`g=floor(m/driverStep)`) was WRONG — a fast arp hit the ratchet every
  step or two, decoupled from the ratchet's own rhythm. **ENGINE (`emitDriverNote` PATTERN fold):** the ARP still drives; a note
  passing through reads whichever column the ratchet's OWN-RATE playhead is on AT THE NOTE'S TIME — `col = floor(localBeat ÷
  rtcRate) mod STEPS` (+ rtcRotate; SPAN re-anchors via `spanLadderBeats`/`columnStart`). `1` = pass through untouched · `2…8` =
  ratchet N over the ratchet's OWN rate slot (spacing `rtcRate ÷ N`, via the ECHO ring). NEVER silent (no rest — Paul rejected
  rest-as-silence twice). So two 1/8 notes inside one 1/4 ratchet column BOTH read that column and both ratchet. **PLAYHEAD
  (`stateMatrixRadio` + `StateMatrixClock`):** the matrix highlight was aliasing to a 1↔5 jump on 1/8 — I'd fed it the ~4 Hz
  polled `d.beat`, and sampling an ~8 Hz sweep at 4 Hz is below Nyquist → jumps of STEPS÷2. FIX: the ratchet matrix playhead now
  runs in a `TimelineView` that EXTRAPOLATES the beat per frame (`meters.beatAnchor + elapsed×tempo/60` — the app's standard
  pattern), `col = floor(beat÷rtcRate) mod STEPS`, sweeping all STEPS smoothly at RATE. `ProcessorBox` carries the beat-anchor
  trio; other matrix callers still light the global grid column (`liveStep`). Test renamed `testRatchetPatternRatchetsOnActive
  Columns` (all-1 == bare arp · all-3 > all-pass). **PROCESS LESSON (Paul, hard):** I burned his time going in circles by iterating
  on the VISUAL playhead blind (I can't see/hear the device) and by implementing from my own synthesis / reviewer notes instead of
  his literal words (twice reverted rest-as-silence + a driver rewrite mid-flight). The engine is unit-testable off-device (trust
  that); the playhead is cosmetic — when reporting, SEPARATE "does it sound right" (engine, chase with tests) from "does the light
  track" (cosmetic). v1 flags still open: burst sub-strikes ~0.6 staccato; COIN fold velFactor 1.0; the visual runs FREE (no SPAN
  re-anchor / gated on `d.playing` not free-run).**
- **▶ RATCHET PATTERN v5 (Model B) — a PER-ARP-NOTE fold + adversarial-review fixes (2026-09-07, on `main`; iOS builds, macOS
  1067+ green incl. fuzz; DEVICE ear owed). Paul: v4 "isn't very good" → a thorough adversarial sweep. VERDICT: v4's self-
  clocked driver RE-CLOCKED the arp onto its own RATE grid (point-sampling "what note is the arp on now" per tick), throwing
  away the arp's rhythm — the opposite of "process the input in front of it" / "ratchet both of the 1/8 notes." (WHY A can't
  ratchet two: a RATE tick samples ONCE, so the second 1/8 note falls between ticks, unseen.) Paul chose **Model B**: downstream
  of a driver the PATTERN ratchet FOLDS — the ARP drives, and each arp note reads the NEXT matrix column (by its tick ordinal
  `g=floor(m/driverStep)`, +rtcRotate, mod STEPS): **0 = REST (drop) · 1 = passthrough (the note at its own on/off) · 2–8 =
  ratchet** (re-fire N over the gap to the next arp note, spacing driverStep÷N, via the ECHO ring). So both 1/8 notes get their
  own column. ENGINE: `isRatchetFoldable` includes PATTERN again → `chainDriverIndex` makes the ARP the driver + the ratchet
  foldable; `emitDriverNote` gained the PATTERN branch (foldBurst/foldRest by column). STANDALONE (no driver) keeps the v4 self-
  clocked `emitRatchetModal` (RATE playhead) — now honouring 0=rest too. **REVIEW FIXES:** B1 ROTATE was clamped mod-8 in the
  builder (dead past col 8) → mod-32; B4 rtcSlices clamped 1…8 dropped authored RESTS (Dice/preset `0`s became passthrough) →
  clamp 0…8; matrix gained the **· (rest)** option (0,1,2…8). Tests: [ARP→RATCHET PATTERN] all-1 plays the arp · all-3 > all-1 ·
  all-rest silent; standalone/self-clock + rate tests kept. **STILL FLAGGED (device-eye):** B2 the matrix PLAYHEAD highlight is
  the GLOBAL grid column (`liveStep`), not the ratchet's per-arp-note position — so the visible sweep still won't match; needs a
  per-cell liveStep feed (not wired). B3 a ratcheted sub-strike is ~0.6-staccato (not the note's own length). RATE only drives
  standalone now (the arp's rate drives in a chain). The tick-ordinal advances per arp TICK (a masked/rested arp step skips a
  column). NOTE: Diag.swift/Kernel.swift were the partner instance's HOLD work — untouched; I committed only my 4 files.**
- **▶ RATCHET PATTERN v4 — the step MATRIX restored (self-clocked, per-column counts) (2026-09-07, on `main`; iOS builds, macOS
  1067+ green incl. fuzz; DEVICE ear owed). Paul: "I was wrong to say ditch the numbers" — bring the grid back, without the
  euclid control, self-clocked like RIFF with a defined step count; each column, when the playhead reaches it, decides
  passthrough or how many to ratchet. So v3's bare RATE+STEPS is replaced by: a STEP MATRIX of **STEPS columns (1–32)**, each a
  COUNT (**1 = passthrough · 2–8 = ratchet**); the playhead sweeps the columns at **RATE** (its own clock, RIFF-shaped),
  **SPAN** re-anchors (FREE = free-run). ENGINE (`emitRatchetModal` PATTERN): window-scan RATE ticks over the absolute beat;
  `col = (localTick + rtcRotate) mod STEPS` (localTick re-anchored by SPAN); `count = rtcSlices[col]`; subdivide that column's
  RATE slot into `count` staccato sub-strikes (count 1 = one hit). Feeds the upstream note (re-clocks the arp) → spreads across
  render blocks, free-runs independent of the grid. `rtcSlices` widened to 32 (builder pads/clamps 1…8); `rtcSteps` = the matrix
  length. UI: the `stateMatrixRadio` count matrix is back (`steps: rtcSteps`, options 1–8, **eFill:false** = euclid brush
  removed, drag-to-rotate kept) + a STEPS numPair; the matrix column cap raised 16→32; RATE/SPAN in the frame footer. Tests:
  per-column-count (all-4 > all-1) + the self-clock rate tests; retired the v3 span-window test. **v1 FLAGS (device-eye):** 32
  columns × 8 option-rows is cramped; a HOLD driver combo (`[DRONE→RATCHET PATTERN]`) still won't re-clock (drone rides
  emitColumnHolds); SPAN re-anchors the phase (no rests — every column fires its count).**
- **▶ HOUSEKEEPING SWEEP + the session's HOLD/colour/diagnostic fixes (2026-09-07, on `main`, PUSHED; iOS builds, macOS 1072
  green +5). Five parallel read-only survey agents (engine bug-hunt · pure-core · test-gap · docs · dead-code), every finding
  re-verified before acting. **ENGINE (`1c20892`):** Finding 1 (HIGH) — the Kernel's reel + free-run edge `router.allNotesOff`
  calls run OUTSIDE `Router.process()` (no transport edge) and couldn't reach the private `flushGlide`/`flushMod`, so a closed
  glide anchor left a dangling `glideVoices[]` slot → a reused voice wrong-closed on resume (spurious note-off). New
  `Router.externalFlush(box:atSample:out:includeBypass:)` = allNotesOff + flushGlide + flushMod; the 4 reel/free-run edges route
  through it. Finding 2 (MED) — a chatty source's incoming CC120/123 was still FORWARDED to the synth when NO latch was armed
  (silencing the grid's own sustained output while our refcount held it); `suppressAllOff` now also fires when
  `ignoreAllNotesOff`. **DEAD CODE (`6ad51cf`):** removed `buildIsDark` + `rtcSliceAt` (grep-verified zero-ref, 2026-08-16
  orphans) + the now-dead `holdReleasing` var (orphaned by the HOLD mirror-and-freeze rewrite). **TESTS (`a6e35f4`, +5):**
  `passLen` clamp + `mutateCount` range/seed; SHIFT-fold DELAYS onsets + HUMANIZE-fold replay-safe-and-perturbs (the old test
  only checked note COUNT, so an identity-regression fold would've passed) + a lone fold-ratchet still DRIVES. **KEPT + flagged
  (not removed):** `holdCaptureDecision`+`HoldCapture` (dead in prod since the HOLD rewrite but still test-documented — pending
  HOLD device-verification, may be needed if mirror-and-freeze is reverted); `hasDuplicateVoices` (reserved I3 hook); the
  dead-but-tested pure cluster (`laneValue`/`voiceLeadTowardPrevious`/`peakHoldLevel`/`triggerMark`/`poolStep` array-wrapper).
  **FLAGGED for a careful pass (not done — see pending-tasks):** decode-safety hardening — `Colour`/`SceneState`/`Receiver` are
  the three central persisted types and still lack a decode-tolerant `init(from:)`, so ADDING any non-Optional field to them =
  a whole-doc factory reset (CR-8 class; `Cell` already got the fix). Finding 3 (MED, deferred) — under `ignoreAllNotesOff` the
  live pool isn't cleared on a transport stop, so a CC123-only source re-sequences dead notes next play (the sustained-input
  case self-clears on real release; a stop-edge reset would break free-run-on-host-stop, so not fixed blind). This session's
  earlier landings are folded in here: **HOLD MIRROR-AND-FREEZE (`4549d2e`)** — the frozen HOLD pool now tracks the live chord
  when the admitted set is non-empty + freezes the last chord when it goes silent (replaced the detect-replace
  `holdCaptureDecision`; the invariant "never empty while input present"); **DERIVE-FROM-POSITION colour (`693ab8f`)** —
  `buildSelHue` derives `partPosHue(row)` for a focused ferry/part row so every machine surface shows the row's true position
  colour (`buildMachineHue` simplified); **cog HEALTH PLAY + SND (`90cc1dc`)** — the HOLD-silence bisect readout. All the HOLD/
  colour/diagnostic items are DEVICE-owed (the Kernel + UI aren't unit-tested).**
- **▶ HUMANIZE / SHIFT reclassified as per-note MODIFIERS (2026-09-06, on `main`; iOS builds, macOS 1067 green incl. fuzz;
  DEVICE ear owed; engine-only). Paul flagged these were miscategorized as DRIVERS (they re-pooled the chord on their own grid
  in a chain, discarding the upstream rhythm). Now, downstream of a real driver they FOLD — jitter/push each driven note IN
  PLACE, keeping the driver's rhythm: `[ARP→HUMANIZE]` humanizes the arp's notes (seeded per-note timing + velocity jitter,
  replay-safe by seed = column·note·index); `[ARP→SHIFT]` pushes each arp note late. MECHANISM (mirrors the ratchet-COIN-fold):
  they stay in `isDriverType` (so STANDALONE / as the ONLY driver they still GENERATE via emitGeneratorRow), but a new
  `isModifierFoldable` (shift/humanize) makes `chainDriverIndex` skip them when a real driver precedes it → the upstream drives
  and `emitDriverNote` records the downstream SHIFT/HUMANIZE (like `lenP`) and applies the per-note timing offset (on/off shift
  together, length preserved, clamped to the window like NUDGE/POCKET) + velocity scale at the final emit. So `[ARP→SHIFT]` /
  `[ARP→HUMANIZE]` emit the SAME note count as the arp (one modified note per arp note, not a re-pool). +1 RouterTest (fold ==
  arp count · standalone still generates). **v1 LIMITS (flagged):** applies on the tick-driver fold (arp/ratchet/strum/euclid/
  burst/cascade/weave/riff/hocket); a HOLD driver combo (e.g. `[DRONE→HUMANIZE]`) doesn't jitter (drone rides emitColumnHolds,
  not emitDriverNote); SHIFT still overlaps the NUDGE utility (both per-note timing — left as-is); a late push is clamped to the
  block edge like NUDGE. UI/storefront copy still calls them generators (a copy nicety, not wired — flagged).**
- **▶ RATCHET PATTERN v3 — a SELF-CLOCKED ratchet (RATE·STEPS·SPAN, RIFF-shaped) (2026-09-06, on `main`; iOS builds, macOS 1066
  green incl. fuzz; DEVICE ear owed). SUPERSEDES the fold v1/v2 below. After a long design thread Paul redefined RATCHET
  PATTERN away from a per-note fold: it now has its OWN clock like RIFF. THE BUG that triggered this: the fold indexed the
  pattern on the ratchet's rate grid, which drifted from the visible grid columns (scene step ≠ ratchet rate) → cells fired
  "every couple of steps," not once per playhead column. Paul's ruling: **RATE = the ratchet's own tick clock (replaces the
  global grid for this proc) · STEPS (1–32) = strikes per SPAN window · SPAN (like RIFF) = the window it fills then rests;
  FREE = a seamless STEPS×RATE loop (steady stream).** Each tick re-fires the upstream note (the arp's current note). Removed:
  the per-cell number matrix + euclid/rotate controls. **ENGINE:** PATTERN is a DRIVER again (not a fold) — `isRatchetFoldable`
  reverted to COIN-only, `emitDriverNote` fold reverted to COIN-only. `emitRatchetModal`'s PATTERN branch rewritten to a
  SELF-CLOCKED, absolute-beat window-scan (spreads across render blocks, free-runs independent of the grid): anchors at
  `period = SPAN>0 ? spanLadderBeats : rate×steps`, fires `steps` strikes at `rate` from each anchor then rests. New model
  field `rtcSteps` (ColourParams + SnapParams + builder; `rtcSlices`/`rtcRotate`/`rtcSpan` now decode-only). **UI:** PATTERN
  editor = STEPS numPair (1–32) + the frame footer's GRID(=RATE) · SPAN (ROTATE dropped), no matrix. **TESTS:** rewrote the two
  ratchet-PATTERN tests to the self-clock (faster RATE = more strikes; SPAN window w/ small STEPS < free-run) + the Derivations
  density test; retired the CELL|ROW slice test. **v1 LIMITS/FLAGS (device-ear owed):** STEPS is audible mainly via SPAN
  (with SPAN FREE every tick fires, so STEPS just sets the seamless loop length — flagged to Paul, accepted); the ratchet
  re-clock replaces the arp's note LENGTHS with RATE-staccato strikes (Paul embraced the re-clock); each strike ~0.6-staccato;
  the frameRow ROTATE slot is now an EmptyView (possible layout gap — device-eye). The COIN pass-through fold (rtcFold) is
  unchanged + still spreads via the echo ring.**
- **▶ RATCHET PATTERN fold v2 — AUDIBLE ratchet via the echo ring, REST dropped, matrix 1–8 (2026-09-06, on `main`; iOS builds,
  macOS 1066 green incl. fuzz; DEVICE ear owed). SUPERSEDES the same-day "true REST = silence" fold below (two mis-reads
  corrected). Paul: (1) REST should be pass-through, not silence — so DROP rest entirely, matrix = **1,2,3,4,5,6,7,8** (1 =
  plain/untouched · 2–8 = ratchet); (2) `[ARP 1/8 → RATCHET PATTERN 1/8]` with a 2/3/4 slice gave only "slightly shorter length,
  not ratcheting." ROOT CAUSE of (2): the fold bursted each arp note over its own SHORT GATE (`offOut−onSample`) → sub-strikes
  crammed into a near-inaudible flam; and a per-tick fold can't spread strikes across audio blocks (the engine emits note-ONs
  immediately, only note-OFFs defer). RATIFIED MODEL: the ratchet's RATE = a pattern LENS (which count each arp note reads);
  the count N = re-fire that arp note (its OWN pitch + length) N times spaced over the gap to the NEXT arp note (spacing =
  driverStep÷N); RATE never touches length; long notes' copies OVERLAP (engine re-articulates same-pitch, no stuck notes).
  IMPL: `emitDriverNote` emits strike 0 (the note at its own length) then registers N−1 copies as **ECHO-ring tails**
  (`pushEchoTail`, feedDelay 1 · decay from BURST-FADE · gateBeats = note length) — reusing the proven cross-block, no-stuck,
  flood-governed, replay-safe drain. `driverStep = Snap.arpRateBeats[driver.rateIndex]`. COIN fold now spreads the same way.
  Standalone/driver PATTERN path: REST removed (`count = max(1,min(8,raw))`, window-scans as before). Matrix → `[1…8]` +
  `rtcSliceAt`/set default 1; `rtcSlices` default `[2,1,2,1…]`. Tests updated (all-1 == arp alone · 2/4-per-step > arp; dropped
  the silence assertions). **v1 LIMITS (flagged):** `driverStep` uses the driver's nominal rate (exact for a uniform arp;
  approximate for variable-spacing drivers); a downstream ECHO echoes only strike 0, not the ratchet copies; N−1 tails/arp-note
  can hit the 256-tail ring / 48-per-beat flood cap under extreme settings (copies drop, no stuck notes). DEVICE ear owed.**
- **▶ RATCHET PATTERN — a downstream PER-NOTE FOLD + a true REST (2026-09-06, on `main`; iOS builds, macOS 1066 green incl.
  fuzz; DEVICE ear owed). Paul: `[ARP → RATCHET PATTERN]` altered notes on rest + made short arp notes long. ROOT CAUSE:
  RATCHET PATTERN, as the LAST driver, BECAME the chain driver and RE-POOLED the arp — a chain driver reads only the upstream
  NOTE POOL (via composeChainSet), never its rhythm/lengths — so it discarded the arp's 1/8 timing + note-lengths and played
  its own grid (long notes, firing on the arp's rests); and a "·"/0 pattern slice was coded as ONE PLAIN HIT, never silence.
  Paul's model (ratified): PATTERN should PROCESS the upstream input per-note — ratchet each arp note IN PLACE. FIX (generalises
  the 2026-09-06 COIN `rtcFold`): `isRatchetFold`→`isRatchetFoldable` now true for PATTERN too (always) — so `chainDriverIndex`
  (rewritten: last non-foldable driver, else the last driver so a lone/`[HARMONIZE→RATCHET PATTERN]` ratchet still DRIVES)
  skips a PATTERN ratchet when a real driver precedes it → the ARP keeps rhythm + lengths and `emitDriverNote` folds the
  pattern onto each driven note: slice REST (0/·) DROPS the note (+ its echoes, like LENGTH MUTE), 1 = pass through, 2/3/4 =
  burst its own [on,off] span (ramp = BURST FADE). Fold slice = the pattern's own RATE grid at the note's time (`floor(m/rate)`
  + rotate). **TRUE REST (Paul's ruling, changes existing patterns):** 0/· is now SILENCE in BOTH the fold AND the
  standalone/driver path (`emitRatchetModal`: `if raw<=0 { continue }`), and the PATTERN matrix gained a **1 = plain** state
  (was `[0,2,3,4]` → now `[0,1,2,3,4]`, `·`=REST). +1 RouterTest (all-1 == arp alone · all-REST = silence · all-2 bursts ·
  standalone all-REST silent) + updated the DerivationsTest that had encoded 0=plain. **v1 LIMITS (flagged):** the fold samples
  the pattern on its RATE grid (Paul's "1/4" example), not the SPAN-ladder/CELL|ROW span (that still shapes the standalone
  driver path); the matrix has no per-slice velocity; two PATTERN ratchets after one driver → only the first folds. DEVICE ear
  owed. NOTE: default rtcSlices `[2,0,2,0…]` now reads as roll-2/REST (was roll-2/plain).**
- **▶ RECEIVER STRIP — velocity indicator stripped back to a simple bar (2026-09-06, on `main`, `40dd3bd`; iOS builds; UI-only,
  DEVICE eye owed). Paul: strip the receiver strips right back to a simple velocity indicator + controller "as it was before",
  keeping the MIDI-accuracy fixes. Removed the two fader accretions in `buildReceiverFader` (BuildPage.swift): the per-machine
  FEED COLOURS (`buildReceiverFeedColours` — bands tinted by the cells the door feeds; DELETED, receiver-only, unused) and the
  chord/key-aware meter treatment (`buildMeterBands(faded:true)` energy-waist + `buildMeterNoFeedBand` grey shimmer). The fader
  is again ONE flat bar — cyan for the metered/held velocity, pink while dragging the override. KEPT (the accuracy fixes):
  `recvHeld` sustained-while-held level, the 30 Hz attack flash (`meters.receiverPeak`), the latch-velocity read, and drag-to-
  override (`setReceiverVel`). Strip BUTTONS unchanged (CH/ENABLE, LATCH mode, OCT, S/M — Paul chose "meter only" scope, not the
  mode-button or bare-fader options). `buildMeterBands`/`MeterBand`/`buildMeterNoFeedBand` KEPT (the EMITTER fader still uses them
  via `buildEmitterPlayingColours`). **TWO-INSTANCE NOTE:** BuildPage.swift had the other instance's uncommitted work; I staged
  ONLY my 3 hunks (`git apply --cached` of an isolated patch) and FF-pushed to main, leaving their work untouched in the tree.**
- **▶ IGNORE INCOMING ALL-NOTES-OFF — the sustained-chord "empty pass" fix (2026-09-06, on `main`, merge `27304e1`; iOS builds,
  macOS 1065 green; DEVICE ear owed). Paul: a third-party app feeding SUSTAINED chords dropped out for most of a pass even
  WITHOUT hold — a synth on the same source held it fine. ROOT CAUSE (confirmed via Paul's MIDI monitor): the source floods
  **CC120 (All Sound Off) + CC123 (All Notes Off) on all 16 channels** around each chord (loop/phrase/transport resets are
  common), and `Kernel.handleIncoming` wiped the ENTIRE live input pool on the first CC120/123 (`pool.reset()`), CHANNEL-
  AGNOSTIC — so it nuked even a channel-filtered door, and since the burst shares the chord's render block (all Time:0), the
  just-arrived chord was erased before the grid read it → silent pass. (The 2026-08-31 fix already spared the FROZEN/HOLD
  pool from this; the LIVE pool was still wiped, which is why HOLD only partly rescued it + why the HOLD `.replace`-thinning
  bit on top.) FIX (Paul chose toggle, default ignore): document-level `PluginState.ignoreAllNotesOff` (additive-Optional,
  resolved DEFAULT TRUE = ignore) → `SnapshotBox.ignoreAllNotesOff` → Kernel guard `… && !ignoreAllNotesOff` on the pool
  reset. Real note-offs still release notes; host/transport panic + the a8 stuck-note nets still flush. Cog **INPUT** section
  toggle ("IGNORE ALL-NOTES-OFF"). +1 SnapshotBuilder test (resolver default TRUE + box carry; explicit false honors). DEVICE
  ear owed (Kernel isn't unit-tested). FLAG: default flips existing docs to ignore — intended (a MIDI processor re-sequences
  input, so a source's routine reset shouldn't clear it); turn it OFF per project if a source uses CC123 as its only release.**
- **▶ RATCHET COIN "PASS-THROUGH" — a downstream per-note ratchet fold (2026-09-06, on `main`; iOS builds, macOS 1064 +
  fuzz green; DEVICE ear owed). Paul: "[ARP → ratchet] that plays through most notes but hits particular notes with a
  ratchet, by probability — pass through when NOT ratcheting." The existing `[ARP → RATCHET]` makes RATCHET the DRIVER
  (it's the last driver → re-pools the arp), and it gates every note ~60%, so it can't pass notes through untouched. NEW
  opt-in `rtcFold` (COIN-only): a fold-ratchet is NOT counted as the chain driver (`chainDriverIndex` skips
  `isRatchetFold`), so the UPSTREAM driver (the ARP) keeps its rhythm + note lengths; a new `downstreamRatchetFoldIndex`
  fold in `emitDriverNote` decides ONCE per driver note (seeded on its column step → replay-safe, gap/quota reuse the COIN
  scan): COIN fires → REPLACE the note with a burst subdividing its OWN [on,off] span (`rtcCoinCount`/`rtcCoinSize` +
  `ratchetVelocity` ramp); else emit it UNCHANGED (true passthrough). The ratchet slot is note-transparent in the set fold.
  Additive-Optional `ColourParams.rtcFold` (synthesized-Codable safe) → `SnapParams.rtcFold` → builder copy; UI = a
  RATCHET-DRIVES | PASS · RATCHET CHOSEN seg on the COIN editor. +1 RouterTest (chance 0 = byte-count-identical to the arp
  alone = passthrough · chance 1 = every note bursts) + fuzz randomizes `rtcFold` (~200s chaos, no stuck notes). **v1
  LIMITS (flagged):** the COIN chance is evaluated on the SCENE-step grid (one decision per column) — for a clean per-note
  chance, run the arp at the column rate; a sub-column-fast arp shares a column's decision. ODDS-FROM-VELOCITY isn't wired
  in fold mode (velFactor 1.0). The burst sub-strikes are ~60% staccato (a ratchet roll), not the note's own length.**
- **▶ CELL CONSTELLATION v2 — the device-feedback rework (2026-09-05, on branch `fix/cell-constellation-v2`; iOS builds; UI-only,
    DEVICE eye owed). v1 (`c7ad7f4`) failed on device: constellations appeared ONLY on SELECT, part/play cells lost their notes,
    the part cell colour didn't match the selector + looked faded, and the playing cell didn't animate. ROOT CAUSE: v1 only
    converted the LIVE-DRIFT face (`buildNoteSweep`), which draws only while notes are ACTUALLY sounding → idle cells blank;
    SELECT used the always-visible OFFLINE roll. **FIX — one unified always-visible face `buildOutputFace(bars,tint,playing)`:**
    every cell (SELECT · PART · PLAY · ferries · row selectors) now draws its EXPECTED-OUTPUT constellation from the offline
    rolls, static when idle, with a beat-locked PLAYHEAD sweep + dot-glow when playing. `buildGridSelPianoRoll` +
    `buildGridSelDriftFace` delegate to it; `roomsPartCell` + `roomsPlayFerry` use it (replacing the idle-blank `buildNoteSweep`).
    Rolls: PART = the existing per-row `buildGridSelRowRoll`; PLAY = a new per-column `buildPlayColRoll` (`buildComputePlayColRolls`);
    both recomputed in `buildPublishScene` so they stay current. **PART colour = the row's MACHINE hue** (not v1's separate
    fixed-position palette — "row 7 always yellow" = its yellow machine), drawn DARK + SATURATED + FLAT (`partCellFill`/`Frame`
    via `buildBaseHex`) so it MATCHES the selector and isn't faded. **[SUPERSEDED 2026-09-06 (`4966de5`/`693ab8f`): PART +
    ferry colour REVERTED to FIXED-BY-ROW-POSITION (`partRowHexes` via `partPos*`) per design-cell-language decision 4 — the
    machine-hue `partCellFill`/`buildBaseHex` recipe now serves ONLY the PLAY ferry; `partRowHexes` is the LIVE token.]** **drawConstellation tuned:** smaller dots, stronger sigil
    lines, + the `playhead` param (bright sweep line + dots brighten as crossed). **DEVICE-OWED / flags:** still can't verify the
    look; the `isEditedRow` black breathe (an edit invite) is a possible "faded row" Paul saw — flagged, removable; v1's
    `partRowHexes` token is now unused (harmless); the face is the EXPECTED-output constellation animating (not literal live
    strikes) — if Paul wants actual live-strike drift back it's a follow-up overlay.**
    **v3 device fixes (same day): the playing/selected cell now SCROLLS the constellation (two beat-offset copies, seamless
    loop) instead of a playhead — the NEW playheads were removed (`drawConstellation` playhead param gone; existing
    roomsPartPlayhead/roomsCellPlayhead untouched); SELECT scrolls on mere selection (was gated on live MIDI); the part cell
    is DARKER (`partCellFill` mix 0.24, `partCellFrame` 0.48 — was 0.52/bright-0.85) + the PART-PAGE ferries now wear the same
    dark fill/frame (gated `roomsRoom == .part`; the PLAY grid keeps its dusk blends) to kill the "still bright" look.**
    **v4 device fixes (same day): the scroll now runs ONLY while `d.effectivePlaying` (host or free-run advancing) → STATIC
    when the transport is stopped (v3 free-ran off wall-clock → skipping, esp. when stopped) and beat-locked/in-sync when
    playing. + THE STARS BLINK on a live strike: `buildOutputFace` gained `strikeIdx` (part `[idx]` · play `buildPlayColSweep-
    Indices(t)` · select `buildChainAuditionRow`); the timeline runs only when scrolling OR the strike feed (`buildCellRoll`)
    is non-empty, so a cell with no MIDI in never blinks; `drawConstellation` boosts a dot's size+opacity when a recent strike
    (age<0.3s) matches its pitch lane. DEVICE eye owed (blink delay ≤ the 4Hz poll; boost/decay constants tunable).**
    **v5 ANIMATION REWRITE (Paul: "worth rewriting completely?" — yes). The v2–v4 face fought itself: offline sigil + beat-
    EXTRAPOLATED scroll (jittered, ran when stopped) + offline↔live blink MATCH (missed/doubled). REWRITTEN around ONE source,
    the LIVE strike feed (`buildCellRoll`): idle/stopped → the STATIC expected-output sigil (no timeline → no jitter); notes
    SOUNDING → each real strike is a bright STAR at its true pitch drifting left + fading (in sync by construction, ONE star per
    note → no misses/doubles), over the dimmed sigil. The beat-scroll + the lane-matching blink are GONE. Also fixed the
    LONG-STANDING blank-then-redraw flash — the roll caches (`buildGridSelCellRoll`/`RowRoll`/`buildPlayColRoll`) no longer
    eager-`= [:]`-clear before the async refill (kept until the new dict swaps in atomically). And the PART grid is DEEPER dark
    (`partCellFill` mix 0.16, `partCellFrame` 0.34 over the ground — was 0.24/0.48) to kill the "primary as fuck" look. FLAG: I
    read "the side grid" as the PART grid (SELECT is already grey) — if a different grid is meant, redirect; the resting sigil
    is still the bright EMITTER colour (per the ratified design) — if THAT reads too primary, dimming it is the next lever.**
    **v6 (Paul corrected the model): the CONSTELLATION ITSELF scrolls + its OWN notes light — NOT a static sigil with a
    separate note layer drifting over it (v5 was wrong). `buildOutputFace`: when the live strike feed is non-empty (MIDI
    flowing → static otherwise, incl. stopped), the whole sigil (dots + path) scrolls right→left beat-locked (two beat-offset
    copies, seamless loop) and `drawConstellation(phase:)` LIGHTS each dot as the scroll carries it to the play line (x≈phase)
    — deterministic, in sync, no matching. The v5 drifting-live-stars-over-static-sigil is gone. **v7: the flash sat at the
    LEFT edge (x=0) + the wrap copy off the RIGHT edge → "flash on both edges, off-screen, disconnected." Moved the PLAY-POINT
    to ~28% from the left (`translate (0.28 − phase + k)·w`, k∈{−1,0,1}) so a note reaches it EXACTLY when it sounds → the flash
    is on-screen + singular (wrap copies fall fully off-screen); the glow is symmetric (`d = min(f, 1−f)`) so its peak lands on
    the beat. **v8 (the REAL disconnect — "dots flash on the beat but not on the note"): in v6/v7 the dots were ALWAYS the
    OFFLINE render (`gridSelRollBars` → `Dice.runRecorder` against the fixed standard chord `[60,64,67]`) on ALL THREE grids;
    the live strike feed was only an on/off "is it playing" gate. So the sigil showed a DIFFERENT chord's output — right beat
    grid, wrong pitches/sequence. FIX: `buildOutputFace` now — IDLE → the static offline blueprint (the identity at rest, no
    sound to contradict); PLAYING → the ACTUAL EMITTED NOTES from the live strike feed (`buildCellRoll`), a dot per real note
    at its real pitch, drifting right→left, brightest as it sounds (the buildNoteSweep model). The dots ARE the notes you hear
    → correspondence by construction, no offline↔live matching. Removed the scroll/`phase` machinery + `drawConstellation`'s
    phase param. All three grids route through `buildOutputFace`; the offline rolls survive only as the idle blueprint.**
    **v9 (the SELECT→part FERRY brought into line — it had never migrated to the part-cell look): the right-rail ferry
    (`roomsSideChip`, `part: false`) violated the spec 6 ways — a machine wash that brightened on play, the REJECTED two-layer
    note model (`buildGridSelDriftFace` static blueprint + a separate `buildNoteSweep` over it, dimmed 0.45–0.55), an emitter
    GLOW on play, a ground fill that didn't match the part cell, and a bright-on-play machine frame. FIX (part:false only, the
    part-grid rail untouched): flat `partCellFill(buildRowColour(n))` ground + `partCellFrame` frame (white ring when active,
    never a hue-brighten) + ONE `buildOutputFace(strikeIdx:)` (blueprint at rest → live emitted notes when auditioning) + the
    glow/wash/dimming/two-layer all removed. Ground now routes through `partCellFill(buildRowColour(n))` = the SAME recipe as
    the part cell, so the two read identical AND the position-vs-machine-hue colour choice (#6, ~~PARKED for Paul~~ RESOLVED
    2026-09-06 `4966de5`/`693ab8f`: FIXED-BY-POSITION via `partPos*`/`partRowHexes` — the derive-from-position model) is a
    one-place change in `partCellFill`.**
    **BUGFIX (2026-09-06, macOS 1063+2 green): re-selecting (TAPPING) a populated SELECT→part ferry made the machine box/chain/
    play-button colour fall to light GREY. Root cause: `buildGridSelAimRow`→`buildGridSelLoadChain` sets `buildSelID = gsAud`
    (the transient audition), and `machineBinding`'s `grey = onSelectPage && selID == gsAud` fired even though a real coloured
    ferry was the active source (the STAMP path dodged it by focusing the row's real colour via `buildTapColourTab`, so it was
    inconsistent — "often"). `colourHueOverride[gsAud]` already holds the ferry's hex, so the only defect was `isGrey`. FIX:
    `machineBinding` gains `activeFerry` (= `buildGridSelStampSourceRow != nil`); `grey = … && !activeFerry`. A ferry keeps its
    colour; a plain gsAud cell audition still greys. +2 assertions in `testMachineBindingResolvesFerryAuditionAndGrey`.**
    **MODEL REFACTOR (2026-09-06, Paul: "should be in the model, not an if statement"; macOS 1063 green, iOS builds): the
    ferry-vs-cell identity was two mutually-exclusive `Int?` @State (`buildGridSelSel` / `buildGridSelStampSourceRow`) kept in
    sync BY HAND across ~13 paired assignments + inferred via ~16 `!= nil` checks — a desync risk, and why the ferry could
    render grey (the resolver couldn't tell a ferry from a cell). Now ONE model value: `BuildSceneLogic.SelectSource` enum
    (`.none/.browseCell(Int)/.ferryRow(Int)`, pure/testable) as the single `@State buildSelectSource`; the two old fields are
    COMPUTED projections over it (`nonmutating set`, a nil-write clears only its OWN case) so every existing read/write site
    compiles unchanged AND exclusivity is now a TYPE GUARANTEE (can't be both). `machineBinding` drops the `activeFerry` bool
    for `source: SelectSource` — grey ⇔ the audition is loaded AND `!source.isFerry`, derived from the one value. Test updated
    to the `source:` signature + SelectSource projection assertions.**
- **▶ CELL DESIGN LANGUAGE — the CONSTELLATION face + three-grid differentiation (2026-09-05, on branch `feature/cell-
    constellation`; iOS builds; UI-only, DEVICE eye owed on the WHOLE look). Ratified with Paul over a mockup
    (`claude.ai/code/artifact/2b727eeb…`, spec `Docs/design-cell-language.md`). ONE idea: every cell paints its output as a
    CONSTELLATION (a dot per note, radius ∝ velocity, at x=time/y=pitch, joined by a faint sigil path); the three grids differ
    only by COLOUR + MOTION. **RENDERER:** new shared `drawConstellation(ctx,size,points,tint)` (Canvas; faint x-ordered path +
    velocity-sized dots) replaces the note-BAR drawing in `buildNoteSweep` (the live drift, PART+PLAY) and `buildGridSelPianoRoll`
    (the offline SELECT roll). **SELECT = monochrome blueprint:** the constellation in grey ink (tint from `buildGridSelCell`),
    a STABLE sigil with a sweeping PLAYHEAD when auditioning (replaces the old scrolling-notes); selected cell = the INVERSE
    (light stage, dark sigil) — inverse is SELECT-only. **PART = dark colour + bright notes:** `roomsGridCellBody` gained
    `flatFill`/`flatFrame`; `roomsPartCell` passes a DARK, FLAT, FIXED-ROW colour (`partRowFill`/`partRowFrame` from a new
    8-hue `partRowHexes` token — row identity by POSITION, not machine) + a row-colour frame; the constellation rides on top in
    the bright EMITTER colour (kept). The emitter/part separation is by LIGHTNESS (dark ground · bright marks), the fix for
    their overlapping hues. AUTO ramp is the one allowed exception. **PLAY = blended (unchanged look):** keeps the dusk washes +
    per-cell playhead + PLAYING glow; only the note FORM becomes constellation dots. **RATIFIED (Paul):** constellation face ·
    keep current emitter colours (dark cell makes them pop; NOT lightened globally) · velocity kept (dot size) · fixed-by-row
    palette (any distinct set) · inverse = SELECT-only · Part keeps live drift. **DEVICE-OWED / flags:** the entire look is
    unverifiable off-device (dot sizes, path opacity, drift feel, the 8 row hues, dark-cell saturation — all tunable constants);
    `buildGridSelDriftFace` (the row-selector fingerprints) still draws BARS — a consistency follow-up; empty part cells stay
    blank (row colour on populated cells only); the SELECT playhead-sweep is a behaviour change from the old note-scroll.**
- **▶ PROMOTE = ARCHIVE-THE-PART-GRID-then-CLEAR (Paul changed his mind; 2026-09-05, on branch `feature/promote-archive-restore`;
    iOS builds; UI-only, DEVICE eye/ear owed). SUPERSEDES the same-day "PROMOTE = MOVE / remove the source row" below. Paul:
    "if promoted to the playgrid FROM the part grid, store the status on the WHOLE part grid with the new play grid cell so it
    can be restored later (restore currently unimplemented)." Rulings (AskUserQuestion): the grid is CLEARED after archiving;
    the null-I/O pulse (the other half) STAYS. **IMPL (`BuildPage.swift` + `AudioUnitViewController.swift`):** dropped
    `buildRemovePartRow`; added `BuildPartSnapshot` (a value-copy of the whole part grid — stagingCells/stagingSel/rowReceiver/
    rowEmitters/rowChain/rowShade/rowUnder/deletedRows/partLen/partRate/partCast/selReceiver/partEmitters), `@State
    buildPlayColPartSnapshot: [Int: BuildPartSnapshot]` (keyed by play COLUMN), `buildCapturePartSnapshot()` +
    `buildClearPartGrid()` (clears every row + resets the per-row/part state) + `buildArchivePartToPlay(t)` (snapshot → store →
    clear). Both promote paths call it: `roomsFlattenPartToPlay` (a PART promote — always) and `roomsAssignPlayColumn` (a
    SELECT-cell ferry — only when the source is a part row, `buildGridSelStampSourceRow != nil`; a library-sourced ferry leaves
    the grid alone). The null-I/O pulse (B2, `buildPartJustPromoted`→`buildIONullPending`) is unchanged. **RESTORE is NOT built**
    — the snapshot is captured + stored only. **FLAGGED:** the store is IN-MEMORY (`@State`), so it does NOT survive save/load
    yet — persisting it (with the play grid's `BuildPlayGridData`) lands with the restore feature; keyed per play COLUMN (per-cell
    keying possible if wanted); a cell-ferry from a part row now also archives+clears the WHOLE grid (device-check that breadth).**
- **▶ PROMOTE = MOVE (remove the source part row) + FRESH-CELL NULL-I/O PULSE (2026-09-05, on branch
    `feature/promote-remove-row`; iOS builds; UI-only, DEVICE eye/ear owed). Paul: "when a cell or part is promoted to the play
    ferries, remove the row it was promoted from from the part grid; when a part is promoted and a new cell is selected/created
    on the select grid, the emitter+receiver toggles are set to null and all 8 controls PULSE invitingly." **B1 PROMOTE = MOVE
    (`BuildPage.swift`):** a new `buildRemovePartRow(r)` (clears the row's cells via `buildSetRow(r,nil)` + nils per-row I/O +
    de-selects any column rungs pointing at it). `roomsAssignPlayColumn` (a SELECT-cell ferry) captures `buildGridSelStampSourceRow`
    BEFORE `buildSelectPlayColumn` clears it, then removes it (nil source = a library cell → nothing removed). `roomsFlattenPartToPlay`
    (a PART promote) removes the DISTINCT rows the part was made of (the rungs across the flattened columns — Paul's ruling:
    "the rows it was made of", not the whole grid). **B2 FRESH-CELL NULL PULSE:** `roomsFlattenPartToPlay` arms
    `buildPartJustPromoted`; the NEXT select-grid cell tap (`buildGridSelTapCell`) consumes it → `buildIONullPending = true`.
    While pending: all 8 I/O chips render OFF + a breathing cyan keyline (`buildIOSelectChip` gained a `pulse` param using the
    house `stagingPulseFraction`/TimelineView idiom), and `buildDefaultEmitters` returns [] → busMask 0 → the cell is SILENT
    (Paul's ruling: "silent until wired"). The invitation clears on the FIRST I/O edit (`buildSelectDoor`/`buildToggleBus` +
    the two ALL variants clear the flag; the emitter setters build from EMPTY on the first pick, not the [.a] default).
    **JUDGMENT CALL / flagged mismatch:** Paul chose "silent until you pick BOTH a receiver AND an emitter"; v1 clears the
    whole invitation on the FIRST I/O touch (the existing fresh-row-flash idiom), so picking a receiver first un-silences on
    the default emitter A. A strict silent-until-BOTH gate would need a true-null receiver (buildSelReceiver = −1, risk of
    index crashes) + decoupling silence from display — a device-tunable follow-up. Whole feature is UI, DEVICE eye/ear owed.**
- **▶ SPAN AUTOMATION PHASE 2 — render-time ×N passes + STEP|SMOOTH, LANDED (2026-09-05, on `main`, `50159b8`+merge
    `c6ab8fb`; iOS builds, macOS suite green). Completes the parked Phase 2 (Paul: "all of phase 2 except cc dominance").
    A part-AUTO lane spans multiple bars (×2/×4/×8 passes) and/or ramps SMOOTHLY, overriding one SCALAR proc param FROM
    the beat instead of the compile-time bake. `AutoLane.spanPasses`/`smooth` (decode-tolerant) → `AutoParamField` (24
    scalar targets) + `SnapParams.settingAuto` (value-copy, clamps mirror applyProcessorValues) + `ColourAuto` in
    `SnapshotBox.renderAuto` (builder populates for an ACTIVE ×N/SMOOTH lane; STEP/default spans stay the Phase-1 bake) →
    `Router.applyRenderAuto` at emitTickRow + emitColumnHolds (STEP = integer column rank endpoint-inclusive; SMOOTH =
    continuous sawtooth). UI (`autoSpanColumn`): ×N live + MUTUALLY EXCLUSIVE with the 1–8 step ladder + a STEP|SMOOTH
    row (SMOOTH continuous-only; ×N/SMOOTH greyed for nested params that can't reach the render engine). +6 RouterTests +
    AutoParamField/settingAuto-clamp tests. **NOTE (two-instance collision):** the BuildPage (autoSpanColumn) + AU
    (setBuildAuto) halves were swept into the scale-pools commit `4ba091a`, briefly breaking main; `50159b8` added the
    model/engine/tests to make it whole. **v1 LIMITS (flagged):** SMOOTH sampled per render window (block-start, like
    applyInternalMods — deterministic per schedule, not block-size-invariant) · scalar-only render surface · per-part-
    clock/16-wide parts use the SCENE beat for the pass math (exact for uniform 8-wide). **CC-prominence PARKED** (Paul's
    carve-out; design elaborated 2026-09-05 — see pending-tasks + PLAN §11). DEVICE-eye owed on the ×N/SMOOTH UI.**
- **▶ THE CHORD DOOR = a chord SEQUENCER — re-architected to REUSE the CHORDS processor (2026-09-05, on branch
    `feature/chord-door-sequencer`; iOS builds, macOS 1057 green; DEVICE eye/ear owed). Paul: "the same chord sequencer that
    appears in the sequencer, identical controls; future processor dev must reflect on the door; 4 interesting default chord
    sequences; D as the chord door's key source; chord mode default on receiver C." SUPERSEDES the 2026-09-04 single-chord
    `ChordPool` door (fe708c7) — that model is gone (its stale JSON key decodes away harmlessly). **THE SHARING (the "future
    dev reflects" contract — three shared surfaces):** ① CONFIG = `ColourParams` — `Receiver.chordSeqs: [ColourParams]?` (4;
    only `chords*` fields used) + `activeChord`; a future `chords*` field appears on the door for free. ② EDITOR = the
    processor's own `ProcessorBox` — the pop-up MOUNTS it (slotMode, `showSlotChrome:false`, `plainTitle`) bound to the active
    instance's ColourParams, so the controls are LITERALLY identical (MODE·SCALE-FROM·degree MATRIX·VOICING·SPREAD·RATE·STEPS·
    WALK); `onEdit` persists via `setReceiverChordSeq`. ③ ENGINE = one pure `chordSeqNotes(beat,p,keyRoot,keyTones,followNote)`
    (Derivations) — the Router's CHORDS stage was REFACTORED to call it (behaviour-identical; all existing CHORDS RouterTests
    green) AND the Kernel door-fill calls it. `SnapshotBuilder.applyChords` (the ColourParams→SnapParams chords copy) is also
    shared between the cell build + the door build. **TIME-VARYING POOL:** the builder puts each chord door's active config into
    the box (`receiverChordsParams: [SnapParams?]`); the Kernel walks the progression per render on `renderBeatPos` (host/free-
    run), keyed by the SCALE-FROM door (`chordsScaleRef` → `receiverScaleRoot/Type`), and fills the latch pool (beat-derived,
    replay-safe). The builder bakes NO static chord pool (`receiverPianoNotes` empty for a chord door; piano bit still set so
    the Kernel fills it live). **DEFAULT RIG (makeInit):** D → SCALE door (existing A mixolydian); C → CHORD door; C's 4
    instances = `Receiver.defaultChordSeqs` (AXIS I–V–vi–IV · 50s I–vi–IV–V · JAZZ ii7–V7–I7–vi7 · PACHELBEL, all KEY FROM D).
    **UI:** strip CHORD button opens `buildReceiverChordPopup` (mounts the editor); door-sheet "EDIT CHORD SEQUENCER ▸"
    launcher; slot RADIO (SEQ 1–4); strip/tab label "A · CHRD" (`buildChordDoorLabel`). **+5 tests** (chordSeqNotes pattern/
    walk/follow/rest/loop · box carries the config + no static pool · radio switches the box config · chordSeqs decode-tolerant
    incl. the stale `chordPools` key ignored · the default rig wires C→D). **JUDGMENT CALLS (Paul-answered + flagged):** RADIO
    switch confirmed; time-varying autonomous confirmed; FOLLOW on a door sits on the tonic (no play-along trigger wired, v1);
    free-run interaction device-owed; no matrix playhead in the door editor yet (liveStep −1). Spec: `Docs/SPEC-four-scale-
    pools.md` (CHORD section rewritten). **BUGFIX (2026-09-05, `Kernel.swift`): the CHORD door never self-armed → silent by
    default (Paul: "can't arm it"). `computeEffectiveLatchMask` only self-armed a piano/scale door when `pianoNotes[i]` was
    non-empty, but a chord door's pool is TIME-VARYING so its pianoNotes is ALWAYS [] → its bit never entered the latch mask.
    FIX: a chord door (`chordDoorParams[i] != nil`) self-arms unconditionally (being a chord door IS reason to arm, like a
    scale door with notes). Kernel-only, device-verified.**
- **▶ THE CHORD DOOR — a new latch/key/hold-class door mode (2026-09-04, on branch `feature/chord-door`; iOS builds, macOS
    1057 green +5; DEVICE eye/ear owed). Paul's spec: a new `DoorMode.chord`, a SIBLING of the scale door — FOUR instances
    radio-switched from a strip pop-up, each a DIATONIC CHORD generated (CHORDS-processor primitives) from a referenced SCALE
    door, output as the receiver's pool. **MODEL (`Models.swift`):** `ChordPool {source·degree·voicing·spread·baseOct}` +
    `Receiver.chordPools`/`activeChord` (additive-Optional; nil ⇒ four defaults, no legacy migration — new mode).
    `latchPianoResolved` true for `.chord` (rides the KEYS pipeline: self-arm · EXCLUDE · play-along). **ENGINE:** pure
    `chordDoorNotes(root,tones,degree,voicing,spread,baseOct)` (Derivations, wraps the existing `diatonicChord`); the
    SnapshotBuilder's piano-notes map gained a `.chord` branch that resolves the SOURCE scale door (root+scale from
    `recvsForPool`, C-major fallback if the source isn't a SCALE door) → `receiverPianoNotes`. A CHORD door's
    `receiverScaleRoot` stays −1 (it's not a scale door; the CHORDS PROCESSOR reads scale only from scale doors). No render/
    Kernel change (rides SCALE's pipeline). **AU:** `setReceiverActiveChord` + slot setters (source/degree/voicing/spread/
    baseOct) via `editReceiverChordSlot` (materializes the 4 pools). `setDoorMode` .chord case. **UI (`BuildPage.swift`):** the
    strip CHORD button opens `buildReceiverChordPopup` (twin of the scale pop-up, in `roomsSharedOverlays`, gated on
    `buildChordPopupDoor`); `buildChordPoolEditor` = a 4-slot RADIO (each names its chord via quality-aware `degreeLabel`) over
    KEY-FROM(▸·A–D scale doors, non-scale dimmed) · DEGREE(I–VII) · VOICING · SPREAD · OCT + a live note-name readout; the
    MIDI-IN door sheet's CHORD row is an "EDIT 4 CHORDS ▸" launcher; strip label "CHORD"; the mode radio auto-lists it
    (DoorMode.allCases); tab/chip name themselves ("A · V7", `buildChordDoorLabel`). **+5 tests** (builder generates the right
    chord from a referenced scale door · no-source→C major · radio switches the chord · decode-tolerance/default · the pure
    `chordDoorNotes` anchoring). **DECISIONS (Paul-implied, flagged):** each instance = ONE standing chord (no PATTERN/FOLLOW/
    WALK — the 4 instances + hand-switching ARE the progression); KEY FROM references a SCALE door (C-major fallback). Spec:
    `Docs/SPEC-four-scale-pools.md` (CHORD section). DEVICE-OWED: the live radio switch (heard), pop-up legibility, the
    self-arm amber caveat (shared with SCALE). NOTE: built on the two-instance feature-branch workflow — merge+push routine.**
- **▶ FOUR SCALE POOLS PER SCALE DOOR — model + migration + the switch/config pop-up (2026-09-04, on `main`, UNCOMMITTED;
    iOS builds, macOS 1046 green +5; DEVICE eye/ear owed — UI + the live switch). Paul's spec (he chose RADIO + config-in-the-
    pop-up via AskUserQuestion): a SCALE door now holds FOUR configurable scale pools and switches between them LIVE via a
    pop-up on the strip SCALE button (RADIO — exactly one active). **MODEL (`Models.swift`, the load-bearing/elegant part):**
    new `ScalePool { root·type·baseOct·octaves }` (Codable/Equatable, defaults = the legacy single-scale defaults) +
    `Receiver.scalePools: [ScalePool]?` / `activeScale: Int?` (both additive-Optional). The FOUR existing resolvers
    (`scaleRootResolved`/`scaleTypeResolved`/`scaleBaseOctResolved`/`scaleOctavesResolved`) were RE-POINTED at the ACTIVE pool
    (`activePool` = `scalePoolsResolved[activeScaleResolved]`) — so the whole render pipeline (builder/box/kernel/CHORDS) is
    UNTOUCHED; switching the radio just republishes the box with the new active scale. `scalePoolsResolved` MIGRATES a legacy
    door (scalePools nil ⇒ pool 0 = the legacy single scale, pools 1–3 default, active = 0) → BYTE-IDENTICAL for old docs; a
    stray `activeScale` with no `scalePools` is ignored (guard). **AU (`MidiSparkAudioUnit.swift`):** slot-aware setters
    (`setReceiverScaleSlot{Root,Type,BaseOct,Octaves}`) + `setReceiverActiveScale` (the live radio) via a
    `editReceiverScaleSlot` that materializes the 4 concrete pools before mutating; the 4 legacy flat setters now DELEGATE to
    the active slot (no divergent path). **UI (`BuildPage.swift`):** the strip SCALE button (`buildReceiverLatchButton`) now
    OPENS the pop-up for a SCALE door (other modes keep arming — SCALE self-arms via the derived pool, so nothing to toggle);
    the MIDI-IN door sheet's scale row became a LAUNCHER (active-scale summary + "EDIT 4 SCALE POOLS ▸") to the same pop-up;
    `buildReceiverScalePopup` = a top-aligned card (like MIDI INPUTS, in `roomsSharedOverlays`, gated on `buildScalePopupDoor`)
    wrapping the shared `buildScalePoolEditor` = a 4-slot RADIO row (each names its scale, tap = switch active LIVE via
    `buildRecvEdit`) over the ROOT/SCALE/RANGE/EXCLUDE editor for the active slot. **+5 tests** (SnapshotBuilderTests: legacy→pool-0
    byte-identity + stray-active guard · radio switches the resolved scale · pad/clamp · decode-tolerance round-trip · the
    builder pool switches the fed derived set). **EXTENSIBILITY:** the pop-up shell is built to host a future CHORD variant
    ("later show as chord selected — to be defined"). Spec: `Docs/SPEC-four-scale-pools.md`. **DEVICE-OWED / judgment calls:**
    the SCALE button's amber "engaged" visual still reads off the MANUAL latchMask (a SCALE door self-arms, so it may look
    un-engaged though it's feeding — pre-existing, flagged) · the strip button label stays "SCALE" (doesn't show which slot is
    live — a nice-to-have) · editing a slot requires making it active first (radio model) · pop-up sizing/legibility.**
- **▶ SPAN-ONLY PART AUTOMATION + the AUTO-section batch (2026-09-04, on `main`, `7bd06ea`…`97038c7`; iOS builds,
  macOS 1041 green; DEVICE-eye owed — UI-heavy). Reworked the part-page AUTO band + rebuilt the automation MODEL to
  span-only, per the ratified plan `Docs/PLAN-span-automation.md`. **THE AUTO-SECTION UI (`7bd06ea`+`bb5d8d8`):** the
  panel below the tabs is TWO COLUMNS (left ~30%… wait, left ~80% MACHINE/PARAM/SWEEP · right 30% the SPAN ladder);
  SWEEP endpoints render the control APPROPRIATE to the param kind (continuous→slider · toggle→ON/OFF · option→cycle ·
  stepper→◀n▶ · mask→raw); a STATE row draws the live FROM→TO ramp + a playhead; the row headers + tabs wear the
  SELECTED machine colour; the edited row PULSES a black face over the static colour; every automation cell shows an
  "AUTO N" label. **SPAN-ONLY MODEL (`ad9fb75`, the keystone):** an AUTO lane is now ONE contiguous FROM→TO span that
  TILES across the row (replaces the punch-arbitrary-`cells` extent). `AutoLane` gained `spanStart`/`spanLen` (additive-
  Optional; legacy `cells`/`span` retained for decode + MIGRATED on load — a cells range → a span). `applyAuto` tiles
  the ramp (`rank = (col−start) mod len` → the existing linear `autoRamp`); a cell before the start is untouched;
  default (start 0, len = partWidth) = one sweep across the whole part; `partWidth` threaded through composeScene.Input;
  byte-identical when no lane armed. **UI:** arming a lane applies a default whole-part span IMMEDIATELY (audible at
  once — the fix for "armed a lane, heard nothing"); a DRAG on the part grid DRAWS the span (press=start, release=end,
  live; `buildPartDragAnchor`); `partGridTap` lost its punch case (span-draw is UI-side); the 1–8 ladder sets the
  length, ×2/×4/×8 (passes) are GREYED (Phase 2 = render-time). Retired `buildAutoToggle`/`buildAutoArmedParam`.
  **FOLLOW-UP (`97038c7`):** fixed 3 leftover `cells`-reading sites the switch broke — the tab "has-content" dot,
  CLEAR (now resets the span), and `buildCaptureAuto` (was pruning span-only lanes from the save). **DECISIONS (Paul):**
  span TILES · DRAG to draw · ×N deferred · 1-D per row. +11 tests (span tile/offset/default/no-lane byte-identity/
  round-trip/legacy-cells migration; partGridTap updated). **OPEN:** [Phase 2 LANDED 2026-09-05 — see the top entry] · device-eye ·
  2 small UI calls (highlight tiles the whole row vs first span; 1-D drag on any row) · minor dead-code (legacy
  `span`/`cells` fields). Plan: `Docs/PLAN-span-automation.md` (marked BUILT) + `Docs/PLAN-span-automation-phase2.md`.**
- **▶ PART PAGE POLISH BATCH — piano-roll rebuilt OFFLINE + a run of device-driven fixes (2026-09-04, on `main`,
  `5f70c7d`…`0254c3a`; iOS builds, macOS 1032 green; ALL device-eye/ear owed — the whole batch is UI). A long
  device-driven thread with Paul. **THE PART PIANO ROLL, rebuilt to an OFFLINE deterministic feed (`5f70c7d`):**
  the live-capture roll lagged one cycle (the "audio up / notation down octave" report) + was unreliable; replaced
  with `renderOfflinePartRoll(box:pool:latched:latchMask:cyc:)` (Emission.swift, Foundation-only, unit-tested) — runs
  the REAL Router over the current box for ONE pass against a CLONE of the live/latched pools (`NotePool.clone()`),
  so the roll is the part's exact output with NO lag + no audio-thread dependence. `Kernel.offlinePartRoll` +
  AU forwarder + a VC recompute gated by a `partRollSig` (held notes · selection · rate · `buildPartRollGen`,
  bumped by buildPublishScene); the live PartTap capture is retired. Router tags each emitted note with its cell
  index (`markCell`) + display hue (`markColour`) so the roll filters to the SELECTED rung per column. **THE ROLL
  LOOK (`0d20d1c`…`2bc89d3`, after several wrong turns — the bars were ~2px tall, too small to render two colours):
  notes = the EMITTER colour (a note reflecting ALL its cell's selected emitters as stacked horizontal bands); the
  CELL is a BORDER-only box around each column's section (the cell's colour). Readable fixed bar height.** **PLAY
  BUTTON (`bbe4d65`):** the machine play-button playhead now animates ONLY while the HOST transport runs (`d.playing`),
  never free-run/auto-engage — added `diag.effectivePlaying`; fixes the "strobes/jiggles when stopped" report (it was
  wall-clock-extrapolating a frozen beat). **8 PLAY FERRIES (`cd8726e`):** the part-page ferry row is ALWAYS 8 (the
  play layer), not `cols` — a 16-wide part no longer draws 16 ferries indexing the 8-slot play layer out of range.
  **PART-GRID SELECTION (`8dbe8cb`):** unpopulated cells are selectable again — the AUTO-lane PUNCH mode had been
  swallowing every non-punch tap; PUNCH now intercepts only its own cells and everything else (empty included) falls
  through. Extracted the decision to pure `BuildSceneLogic.partGridTap` + 5 locking tests. **LAYOUT + AUTO POLISH
  (`bec319f`…`0254c3a`):** the AUTO footer slide-up is retired — the piano roll is FIXED at two play-grid cells and
  the AUTO controls are ALWAYS visible below it to the page bottom (tabs top-anchored); the AUTO row headers +
  tabs wear the SELECTED machine colour; when a lane is armed non-selected part cells go HOLLOW (face → background,
  border kept); the SELECTED rung is ALWAYS a white outline drawn on top (never recoloured, faded only slightly under
  a lane); the FOCUSED number-rail chip INVERTS (solid machine-colour fill + alpha number). +1 side-rail fix
  (`6ddeb36`, the part rail is a simple selector, no longer follows the sequencer). Plan: `Docs/PLAN-part-piano-roll.md`.**
- **▶ OVERNIGHT BATCH — 7 queued jobs (2026-09-03, on `main`, `9010ca1`…`64330ae`; iOS builds, macOS 1023 green incl.
  fuzz; part-roll/AVOID-seg DEVICE-owed). Paul: "queue ten high-value jobs that don't need my involvement." Landed the
  safe, off-device-verifiable ones; flagged the two needing his semantic ruling. **Job 1 (`9010ca1`)** Info.plist — all
  four orientations + dropped `UIRequiresFullScreen` (clears the two Xcode deprecation warnings Paul flagged; project.yml
  → regen App/Info.plist; AU UI is host-sized so inert for the plugin). **Job 2 (`36834d1`)** decode-tolerant
  `AutoLane`/`PartAutoColour` — the newest persisted types were synthesized-Codable with non-Optional fields; partAuto is
  a PluginState dict, so a future field would throw → whole-session reset (CR-8 class). Added the tolerant inits + 2 tests.
  **Job 3 (`7b93b2e`)** THREE read-only bug-hunt agents (AUTO bake · 16-step · CHORDS · AVOID · macro fold · part-roll) —
  NO stuck-note/determinism bugs; fixed 4 confirmed: (a) **PartRollDeck render↔main RACE** — render wrote cur/last while
  the 4 Hz poll read them (violates the value-copy invariant, garbles the roll) → double-buffered publish (render writes
  the inactive of two flat buffers + flips a scalar; roll() snapshots the active by value); (b) **AUTO lane default →
  BYPASS** for the ~12 types w/o a curated autoPrimaryKey (params.first is always bypass) → falls back to the first
  NON-bypass param; (c) **CHORDS WALK froze after 64 rate-ticks** (free-running step, clamped) → loops mod 64; (d) an
  unguarded receiverRangeLo read. +3 tests. **Job 4 (`0abf896`)** dead-code + refactors — removed the inert ladder/old-EDIT
  tap machinery (armLadderRung/ladderPending/ladderBlink/playCellOnly/setEditSolo/editSelTargets — grep-proven inert, the
  old-UI triggers are deleted; syncSingleModeActivation stays live for LADDER presets) + dead `chordsModeResolved`; added a
  `posMod` helper, hoisted RATCHET's legal-repeats literal, fixed a DEBUG cell-coord (i/8→i/Snap.rows). **Job 9 (`dfb46c9`)**
  fuzz the 16-WIDE multi-clock path (was only ≤8-col) — ~30% of docs now widen to maxCols + loop >8 → non-uniform; all 8
  fuzz scenarios green. **Job 7 (`64330ae`)** AVOID §G "EVERYTHING OUT" (ratified) — `AvoidRefKind.soundingOut` = all
  emitter output minus this cell's own buses (self-exclude by bus); avoidRefMask gains ownBusMask (threaded ×3). +1
  RouterTest + fuzz allCases. **FLAGGED for Paul (in pending-tasks): job 5** (16-wide ROW-span procs — polymeter-every-8
  vs full-span, a v1 SEMANTIC), **job 6** (CHORDS invert-toward-previous — voice-leading is path-dependent vs the replay-
  exact rule), and the deferred perf/cosmetic items (CHORDS render-path alloc; 16-wide sounding/solo mask widening; the
  editMode/EditPageMode residue; the AVOID §G editor seg + OUTPUT-ref piano). Job 8 (coverage) folded — the AUTO/macro/
  16-step surfaces were already test-thorough.**
- **▶ 16-STEP GRID — the §E flip, DONE (2026-09-02, on `main`, Stage A `bf6ccaa` + Stage B `e696f07`; iOS builds, macOS
  1015 green; the part-grid UI is DEVICE-EYE owed). Paul: "the 16 step grid." A part's grid can now be 8 OR 16 columns.
  **STAGE A (engine substrate, byte-identical):** the safe framing — `Snap.cols` STAYS 8 (the DEFAULT/uniform BAR width;
  ALL cycle math, ROW-span, and the uniform fast-path key on it → the default part is UNTOUCHED), and a new `Snap.maxCols`
  = 16 is the ALLOCATION ceiling. `Snap.cells` = maxCols·rows (128→256); SceneState.empty + SnapshotBuilder allocate/scan
  maxCols; the per-row loop-length CLAMP widens to maxCols (a part loops 16), the UNSET fallback stays Snap.cols=8. So a
  16-wide part is NON-uniform → the proven, fuzzed MULTI-CLOCK per-row path (cycR = Lr·Sr) plays its 16 columns; an
  8-wide part stays uniform-fast, byte-identical. Router emission/index guards + topCell wrap → maxCols (≤7 identical).
  **STAGE B (authoring):** BuildPart.stagingCells/stagingSel + BuildSceneSnapshot.performCells/Chain + the @State mirrors
  are 16-wide (old 8-col saves decode short + are padded — `Snap.padCols`; `buildNormalizeStaging` normalizes to 16×8,
  was 8×8-TRUNCATING); composeScene builds staging+perform across maxCols (play grid stays 8 columns, each a ≤16-step
  pass via passLen→maxCols); `reconcileStagingSel` → 16; `roomsPartGrid` renders `buildPartCols` (= buildPartLen 1…16,
  nil⇒8) columns (cells shrink); a NEW header STEPS **8 | 16** control sets the part width (`buildSetPartLen` →
  stagingLen → rowLength). Drift feedback (buildNoteSweep) covers 16 for free (Snap.cells=256). **+2 tests** (a 16-wide
  part composes col 12 + row loops 16; the ramp/clamp updated); 4 pre-existing 8-assumption tests re-pointed (rowLen
  clamp 1…16, swap out-of-range past 16×16, 2 reconcile counts). **FLAGGED (device/deferred):** ROW-span processors
  (tutti/length) use the 8-wide bar → in a 16-wide part they repeat every 8 columns (polymeter, not full-span — a v1
  semantic); the old-grid cellSounding/tap/solo masks aren't widened (rooms uses the Snap.cells drift feed, not them);
  the piano-roll mock doesn't scale to 16; the STEPS control placement + 16-col legibility are device-eye owed.**
- **▶ PART AUTOMATION — the AUTO lanes now PLAY + persist (2026-09-02, on `main`, `b7d82e5`+`8d2837a`; iOS builds, macOS
  1014 green; the band is DEVICE-EYE owed). The part-page AUTO band became AUDIBLE. Per colour, FIVE lanes + NONE; ONE
  active lane (per-colour `activeLane`, −1=NONE). Paul's 4 rulings: per-param SUB-RANGE · one active lane per colour ·
  low→high column-order single sweep · extent = the colour's own cells. **MODEL:** `AutoLane`/`PartAutoColour` moved to
  BuildModel.swift (Foundation-only, Codable, in the test target); `PluginState.partAuto` (additive-Optional, keyed by
  colourID). **ENGINE BAKE:** `BuildSceneLogic` gained the pure core (autoPrimaryKey/autoResolvedParamKey/autoSubRange/
  autoRamp/applyAuto) + composeScene folds the active lane onto each part cell via `applyProcessorValues` — a cell in the
  extent gets its param set to the ramped sub-range value (rank/(count−1), column→row). Baked at BUILD time → the render
  is unchanged (invariant 1), like the macro/M2 fold. Byte-identical when no lane armed. **LIVE:** selecting a lane /
  editing / punching a cell republishes (buildPublishScene). Persistence rides the play-grid pattern (pending/consume +
  buildPersistTick). **HEADER:** NONE (left) · AUTO 1–5 (span) · CLEAR (separate, right); select = enable. **+4 tests**
  (ramp across the extent, NONE = base untouched, sub-range/ramp endpoints, doc round-trip). Plan:
  `Docs/PLAN-part-automation.md`. DEFERRED (P4, if wanted): configurable BEFORE/AFTER + a RATE/curve within the extent.
  Macros are SHELVED to v2 (the AUTO flow replaces them). DEVICE-OWED: the whole band + the punch-on-grid feel.**
- **▶ MACRO AUTOMATION M1+M2 — the engine foundation (2026-09-01, on `main`, `2aa17ed`+`f157ef8`; iOS builds, macOS 999 green;
  engine-only, no UI yet). The ratified macro-automation build (§K settled) begins with its two ENGINE increments — the parts
  that build+test off-device with confidence; M3–M6 (the 4-tab part-page band) are the device-owed UI remainder. **M1 (model
  tidy, `2aa17ed`):** the LIVE bank is now SIXTEEN in TWO species — 8 SLIDER (0–7) + 8 TOGGLE (8–15); the 8 TIMELINE macros
  (16–23) are RETIRED (§K3). Decode-safe by construction: a doc that stored the old 24-bank still DECODES whole (the Codable
  `macros` array is untouched → encode round-trips), but only the first 16 RESOLVE (`PluginState.macroBankCount`), so a retired
  timeline's offset simply stops applying — no crash, no factory-reset; byte-identical for any doc that used 0–15. `SnapshotBox.
  macroValues` 24→16; the AU setter guards narrowed `0..<24`→`0..<macroBankCount` (REQUIRED — they do `d.macros = d.macrosResolved`
  (now 16) then index, so a 24-guard would trap). **M2 (the per-cell value store, `f157ef8`) — the ONLY real engine change:**
  `MacroCellValue { col·row·macro·value }` + `PluginState.macroCellValues` (sparse, additive-Optional). Today a macro has ONE
  global value; PUNCH/SPAN need the DRIVING value to vary per cell. The builder folds `override[macro] ?? global` per cell —
  NO SnapCell field, NO render change (macros already bake into `sc.procs` at BUILD time → the fold is builder-side; the render
  still reads only the baked box, invariant 1). The macro's TARGETS stay shared; only the value is per-cell. Byte-identical when
  the store is empty/nil; persistence FREE (the field is on PluginState → fullState). **+6 tests** (M1: bank-is-16-two-species,
  short/over-long pad-truncate, the 24-doc decode-safe retirement, builder mirrors 16; M2: per-cell override shifts one cell not
  its neighbour, empty-store byte-identity, round-trip + old-doc-nil). **NEXT: M3–M6 — the 4-tab band (BIND · PLAY · PUNCH ·
  SPAN) as the bottom HALF of the PART grid (interior −50% height; ferry/▲▼/STOP unchanged), PART-PAGE-ONLY. Device-owed UI over
  the proven M1/M2 fold — held for Paul's device eye (band chrome / tab collapse / STOP placement have real interpretation room).**
- **Older entries (2026-09-01 and before) archived to `Docs/status-log-archive.md`** — moved out
  2026-09-26 to keep this file inside the context char limit; nothing was deleted, just relocated.
  Read that file for build history predating the entries above; `Docs/pending-tasks.md` stays the
  forward checklist.

## Style
- Swift, no external deps beyond apple/swift-atomics (SPM, already in project.yml).
- Comments cite spec sections (e.g. `// §3.2: stepped fields quantize`). Keep doing this —
  the spec is the contract, and drift between code and spec is the project's main risk.
