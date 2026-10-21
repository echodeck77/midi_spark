# Working with Claude on FourStep

Not general advice — the rituals this exact codebase has proven work, and the failure modes it's
hit more than once. Companion to CLAUDE.md: that file is the short brief Claude re-reads every
session; this is the fuller "how we actually work" reference, read on demand (linked from
CLAUDE.md's Scope section).

A browsable version of this page lives at
[the published artifact](https://claude.ai/code/artifact/986ce131-65a4-4c53-ac83-81bad2d48513) —
this file is the durable copy; update this one, the artifact is a rendering of it, not the
source of truth.

## The loop

Every well-run feature in this project's history follows the same six beats. Skipping one is the
single best predictor of rework in the status log.

1. **Plan** — enter plan mode for anything non-trivial. Don't start editing on an ambiguous ask.
2. **Research in parallel** — Explore agents cover the engine, the UI, and precedent at once, not
   sequentially in the main thread.
3. **Ratify** — ambiguous specs get confirmed before code, not interpreted silently.
4. **Build** — engine logic lives in `Derivations.swift` / `Router.swift` so it reaches the test
   target.
5. **Verify, split** — tests prove the engine; nothing proves the UI except an iPad. Say so.
6. **Ship** — commit → merge → push the moment it's green. Log device debt in one place.

## Read the literal spec text, not your own summary of it

When a spec or ferry arrives as a written message, go back to the raw text — not a plan file's
paraphrase of it, and not memory of "what I built." A paraphrase is lossy by construction; the
exact wording often carries a placement, a colour, or a scope boundary that a summary quietly
drops.

Confirmed pattern, repeatedly: self-audits that re-read a ferry's raw transcript text against the
shipped code have found five to ten concrete shortfalls each time — missing UI elements, wrong
placements, colours applied from a prior ferry instead of the current one — none of which a
second read of the *plan file* would have caught, because the plan file was the thing that
dropped them in the first place.

## One formula, read by both the engine and the display

The single most repeated bug class in this codebase is a UI indicator — a playhead, a
highlighted cell, a live sweep — computing its own version of "what step is this right now"
instead of calling the exact function the audio engine uses to decide what sounds. The two
drift, the light stops matching the sound, and it reads as random until someone traces it back to
two formulas instead of one.

- If a UI element claims to represent live engine state, it should call a function the engine
  itself calls — never re-derive an equivalent one.
- When fixing this class of bug, trace with a real, disposable debug trace before re-guessing by
  hand. Hand-derived beat/column arithmetic in this codebase has been wrong often enough that
  it's no longer trusted without one.

## Name judgment calls; don't silently resolve them

Every reply should open with the bottom line, then explicitly flag anywhere an interpretation was
made on an ambiguous instruction, or a value (a size, an opacity, a colour) was picked without a
literal spec to match. Stating it costs one sentence; finding out later it was wrong costs a
round trip and a rebuild.

## Know what's actually tested before claiming "done"

The split here is sharp and permanent, not a gap to eventually close: pure engine logic in
`Router.swift` / `Derivations.swift` reaches the macOS unit-test target and should be fully
covered before anything ships. SwiftUI view code (`EuclideousPage.swift`, `EuclidLaneUI.swift`,
and every other GridUI/BuildPage file) has **zero** test-target reach — a green build proves it
compiles, nothing more. For that half, a passing suite is not evidence of correctness; an iPad is
the only check that exists.

## The extension's main-thread stack is nearly full in a DEBUG build

The AU extension's main thread has a **1 MB** stack, and `EuclideousPage`'s eager view-construction chain (`body` → `pageBody` → `laneCard` → `tabContent` → a tab's builder → its sliders) fills almost
all of it in the debug build Paul runs from Xcode: every `some View` a function returns is a stack temporary, an `EuclideousSlider` is ~4 KB (it holds two `EuclidLine`s) and each opaque wrapper
around it is another dynamic 4 KB allocation. It has crashed twice at launch with "Thread stack size exceeded" (2026-10-13 type-metadata decode; 2026-10-21 the DYNAMICS row's third slider) and no
test or compile check can see it (release builds have none of these temporaries). Rules: **build every new leaf view (a slider, a row, an editor's section) in its own function that returns
`AnyView`**, so closures only hold 8-byte values and each leaf's temporaries die on return (`rhythmUpperZone` and `dynamicsEditor` are the pattern); never put several sliders in one
`@ViewBuilder` closure; and after a UI change compare frame sizes against the previous build with `Scripts/debug-frame-sizes.py <MidiSparkAU.debug.dylib> 'EuclideousPage\.(rhythm|tabContent|laneCard)'`
(static bytes + dynamic-allocation count per function; a worst-case path should sit well under the baseline). A UI ferry is not done until Paul has launched the page in a debug build.

## Running only Euclideous-relevant tests (fast inner loop, not a shipping gate)

`MidiSparkTests` is ~1,750 tests across 27 files; the full run takes ~9 minutes. Most of that
suite (the Acceptance* files, Rooms/Scenes/Macros/Build-workshop/Dice/Fuzz/ReelDeck/MidiFile/
PresetStore) exercises the Machine/ProcessorSlot/chain-based 8x8-State processor roster or
product-agnostic infra that Euclideous's `EuclidLine`/`runEuclidLine` path never touches.
`Scripts/classify_euclideous_tests.py` scans `Tests/*.swift` and sorts every test function into
"Euclideous/FourStep-relevant" vs "8x8-State-only / skippable," and `Scripts/run-
euclideous-tests.sh` runs only the relevant ~500 — about 1.5-2 minutes instead of 9.

**Regenerate, don't hand-maintain.** Run the script; don't copy its output into a frozen list —
test files change often enough that a stored list silently rots. `python3 Scripts/
classify_euclideous_tests.py` prints the human-readable breakdown; `--xctest` prints the raw
`MidiSparkTests/Class/method` lines the shell wrapper feeds to `-only-testing:`.

**The name collisions this exists to catch** (the reason naive `grep -i eucl` over the test
files is wrong): `ProcessorType.euclid`/`euclidPulses`/`euclidPick`/`EuclidDir`/`EuclidNoteSel`/
`EuclidPick` are the STANDALONE 8x8-State EUCLID generator in the processor roster — unrelated to
the Euclideous page despite the name. `ProcessorType.riff`/`EUCLIDMASK` collide the same way.
Each exclusion in the script's regex was found by reading an actual misclassified test, not
guessed — see the comments at the top of the file before changing the pattern.

**A genuine surprise worth knowing before trusting a "state-only" tag at a glance:** `EuclidLine`/
`runEuclidLine` are NOT Euclideous-exclusive. The 8x8-State EUCLID processor itself grew a
"Stage 3" multi-line upgrade (`ProcessorParams.euclidLines: [EuclidLine]?`, `Machine(type:
.euclid)` + `c.paramsA.euclidLines = [...]`) that reuses the IDENTICAL `EuclidLine` struct and
`runEuclidLine` function the standalone Euclideous page's `PluginState.euclideousLines` runs on.
A test built entirely through the `Machine`/chain embedding (`testEuclidLineUseRiff...` in
RouterTests) still exercises the one shared engine core — the script's "both" bucket (dual
signal: Euclideous-exclusive AND 8x8-State-processor) is deliberately kept IN the relevant set for
exactly this reason, not excluded as 8x8-State noise.

**Where the fast subset stops being safe to trust alone:** it's an inner-loop aid for Euclideous-
scoped logic (EuclidLine fields, `runEuclidLine`, the FX tab, the lanes grid, restart chains,
riff walk). It is NOT a substitute for the full suite's "Tests green" row in the Definition of
Done table below — truly cross-cutting shared primitives (swing, clock, the parameter address
table, snapshot publish, note-off refcounting) are ridden by every row including Euclideous's, and
a regression there can hide behind a test whose body never mentions "euclid" or "riff" at all.
Run the full suite before commit → merge → push, same as always.

## Device-verification debt is a list, not a feeling buried in prose

Keep it in `Docs/euclideous-device-verification-debt.md` — one line per open item, filed under
the subsystem it belongs to. Delete the line the moment it's confirmed. A list that only ever
grows has stopped doing its job.

## CLAUDE.md is a brief, not a diary

The file Claude re-reads every session should stay short enough to actually load and re-read
every session. History belongs in a separate, append-only file read on demand
(`Docs/euclideous-status-log.md`), not inside the file re-read on every turn. Update CLAUDE.md's
"current state" paragraph only when the real architecture changes, not on every individual fix.

## Using the toolset deliberately, not reflexively

- **Plan Mode** before any multi-file or ambiguous build — not for a one-line fix.
- **Parallel research forks** when a question has independent sub-parts whose noisy intermediate
  output doesn't need to live in the main conversation.
- **AskUserQuestion** for a real fork in the road that changes what gets built — a second host
  target vs. a reskinned existing one, a destructive vs. non-destructive migration — not for
  anything reversible or guessable.
- **Memory files** hold durable facts about how Paul likes to work and what's been corrected
  before — project facts belong in `Docs/`, derivable from the repo itself.
- **The two-worktree workflow** is a hard rule, not a suggestion — commit, merge, and push from
  your own worktree the moment work is green; never check out another instance's branch or leave
  finished work parked.

## Definition of done, for a FourStep feature

| Check | What it means here |
|---|---|
| Builds | iOS build clean via the pinned `DEVELOPER_DIR` xcodebuild command — read the actual log, don't trust a background-task notification. |
| Tests green | Full macOS `MidiSparkTests` run, pinned `-derivedDataPath`, for anything touching Router/Derivations/Models/Snapshot. |
| Audited against the raw spec | Re-read the literal ratified text once more before calling it complete, not just the plan file. |
| Device debt logged | Every UI claim that can't be confirmed here gets exactly one line in the debt checklist. |
| Shipped | Committed, merged to `main`, pushed — not left on a local branch "pending review." |
