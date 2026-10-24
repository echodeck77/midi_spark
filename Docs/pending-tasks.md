# MidiSpark — PENDING TASKS (forward checklist)

_The canonical "what's left" list. CLAUDE.md's "Current status" is the backward log (what LANDED, with commit
refs); THIS file is forward-looking (what's open). Keep them from overlapping: when a task lands, tick it here
AND add its commit line to CLAUDE.md status. Terse by design — detail lives in the spec (`midispark-spec-v3.0-
delta.md`, esp. §10) and the `Docs/design-*.md` ferries. Last synced: 2026-09-17._

## ★ FOURFOLD — CHORDS GRID: four progression tabs, borrowed chords, chord colours, playhead, pool strip (2026-10-24; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the new "CHORDS GRID" lines in `Docs/euclideous-device-verification-debt.md`.
- [ ] DECIDE (Paul): confirmed mid-build — §4.4's queue-to-next-column-boundary switch was dropped for immediate/manual switching only; say if you'd rather have the sample-accurate queued version after all (it would need a new Kernel-level mechanism, modelled on the RANDOM MODE ferry's apply-at-a-beat plumbing).
- [ ] DECIDE (Paul): the 5 non-heptatonic scales (major/minor pentatonic, blues, whole-tone, chromatic) have no scale-stepped third, so the borrowed-row picker (§3.2) falls back to the MAJOR-key table for all of them — say if minor pentatonic/blues specifically should read as the minor table instead.
- [ ] (noted) `EuclideousChordsPopupMetrics.labelW`/title-row/steps-rate-row heights are reasoned estimates, not measured (Derivations.swift can't do real text measurement) — device-owed, listed above.
- [ ] (noted) Fourfold-only: this does NOT touch `AUExtension/`'s own single-grid CHORDS popup (8x8 State is frozen/on hold) — the two popups now have genuinely different feature sets, not just different line numbers.

## ★ EUCLIDEOUS — RHYTHM gesture predictability: OFFSET per-step, TILT fixed + unified with HITS (2026-10-24; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "GESTURE PREDICTABILITY" lines in `Docs/euclideous-device-verification-debt.md` — the live TILT thumb's reset-to-centre feel is the one part of this ferry with no concrete mock.
- [ ] DECIDE (Paul): a lane locked then edited on EITHER HITS or TILT now shows the dashed "differs from L" frame on BOTH tiles (the stored `customHits` array alone can't say which gesture moved it) — a disclosed trade-off, not a bug; say if a single-control attribution (even if occasionally wrong) would read better on-device.
- [ ] DECIDE (Paul): Fourfold's own engine copy (`Fourfold/Engine`) was NOT touched — this fix lives only in `AUExtension/`. Port it to Fourfold too if the standalone product should feel the same way.
- [x] RESOLVED, found only by running the suite (not anticipated by the plan): two LANE LOCK cross-contamination bugs in `euclideousLockChangedControls`'s new HITS/TILT attribution — a plain legacy TILT-field edit on a still-pure lane spuriously showed as a `.hits` change (the resolved-pattern comparison folds in tilt bias), and a plain STEPS change spuriously showed as one too (the resolved array's own length changes with STEPS) — both fixed by guarding the shared-attribution clause on `pulses`/`steps`/`tilt`/`tiltIsFine` all still agreeing with L first.
- [ ] (noted) `euclideousOffsetDetent` (OFFSET's own now-unused detent) was deleted outright, not left as dead code — unlike the decode-tolerant model fields it supported, it was pure UI-touch-mapping code with zero persistence implication.

## ★ REEL USABILITY REVIEW (2026-10-24) — against Paul's intent: replay any MIDI from the START OF THE SESSION onward, and export SEVERAL passes of the things they like
Method: read `FourfoldReel.swift` / `ReelDeck` / the Kernel's reel code, then drove the real app (iPad A16 simulator, landscape): 45 s and 75 s of play (the first open, SAVE with nothing selected, tap a pass, EXTEND, pick an output, SAVE) and a 225 s run at 299 BPM so the history ring wrapped. Pictures: `build/uit/reel-*.png` (regenerate by re-running a UI test that taps the REEL icon). Not heard: nothing here judges audio or the real share sheet.
- [ ] REEL-1 (blocks the intent): only the LAST 64 passes are kept (`ReelDeck.histCount`, a ring). A pass is 16 beats by default (`1 PASS = 16 BEATS`), so the tape holds ≈ 8½ minutes at 120 BPM (3½ at 299). Seen: at pass 71 the first pass shown was 8 — passes 1–7 were gone, and nothing on screen says so (the sidebar text still says "the whole history"). Fix direction: a variable-length store (a real pass holds a few hundred events, the 8,192-event slot is a worst-case ceiling — 64 slots × 8,192 × 16 B = 8 MB is why the count is small) so the whole session, or an hour, fits; plus a visible "older passes dropped" mark.
- [ ] REEL-2 (blocks the intent): the tape STOPS recording while the reel is open or a pass is replaying (`reelFrozen`), and a pass interrupted that way is never filed — so reviewing material punches an invisible hole in the session, and pass numbers carry on as if nothing happened.
- [ ] REEL-3 (blocks the intent): replay is "loop ONE pass", not "play from here onwards": tapping a pass starts it phase-locked to the global 16-beat cycle, i.e. MID-pass (seen: playhead at 70 % three seconds after the tap — impossible from a start), it replaces the live output, and a selected RANGE has no replay at all (the range roll is a static picture; the code says "no replay yet"). Wanted: PLAY FROM HERE (start of the pass, continue through the following passes to now), LOOP RANGE, and a visible play / stop / restart in the reel.
- [ ] REEL-4 (blocks the intent): export is ONE contiguous range grown a pass at a time with the EXTEND chevrons (twenty passes = twenty taps), concatenated into one file per output. "The things I liked" are scattered, so the user must repeat select → SAVE each time — and see REEL-5. Wanted: drag / two-tap range select, and a KEEP flag (a star the user can press WHILE playing, so a liked bar is marked in the moment and the browser can show only the kept ones).
- [ ] REEL-5 (data loss): every export is named `Fourfold-All.mid` / `Fourfold-A.mid` … whatever was exported. Seen: pass 8 then pass 9 → ONE file in `Documents/Reel exports` (the second overwrote the first), and both show as "Fourfold-A" in the share sheet. (My Documents change, `release hygiene`, turned a temp-file quirk into silent overwrites of saved files.) Fix: `Fourfold passes 8–9 · A · 16-52.mid` (range, output, time).
- [ ] REEL-6 (dead button): SAVE looks live but does NOTHING, with no message, when (a) no pass is selected (first open), and (b) the chosen output has no notes — everything routes to A by default, so tapping B and SAVE does nothing. Both seen. Disable it with a one-line reason, or say "nothing on B in these passes".
- [ ] REEL-7: passes are only numbered — no bars or clock time ("pass 8 = bars 29–32"), no preview in the cell (every cell is the same grey), so finding the bit you liked means tapping them one by one; REMOVE DUPLICATES is the only help (in the 9-pass run nearly all passes were identical). Wanted: bar/time labels, a mini pitch contour or density mark per cell.
- [ ] REEL-8: the roll's four rows are MAIN OUT A–D, but the page's identity is lanes 1–4 (colours); with the default routing every lane is on A, so B–D are empty and the four lanes are indistinguishable (notes are grey). Export "stems" are per output, not per lane. Wanted: lane colours on the notes and per-lane stems.
- [ ] REEL-9: the export lane toggle is a whole-row tap with an 8 pt checkbox and no hint that two lanes make two files; selected-but-empty lanes are not flagged (see REEL-6).
- [ ] REEL-10: landscape-only — a portrait view shows "ROTATE TO LANDSCAPE" and nothing else; inside AUM the plug-in window is not something the user can rotate, so the reel is a dead end there.
- [ ] REEL-11: ZERO accessibility labels in the reel (`grep accessibility FourfoldReel.swift` = 0): the pass cells, EXTEND / PAGE, the lane toggles are plain shapes with gestures — VoiceOver can neither read nor operate it, and the page audit never covered it.
- [ ] REEL-12 (smaller): the export's tempo header is the CURRENT tempo, not the tempo each pass was played at (a session whose tempo moved exports old passes under the new one); REMOVE DUPLICATES hides passes but a range that spans them still exports them; the tape is not saved, so an app relaunch loses the whole session; "session start" is not defined or marked.
- [x] WORKS WELL (keep): the 8×8 "passes above, outputs below" layout is clear; tap-to-audition is immediate; the piano roll with a sweeping playhead and velocity as opacity is readable; the concatenated roll for a range is a good preview of what SAVE will write; big touch targets; stuck notes are handled on exit (CR-5).
- [ ] DECIDE (Paul): how much history is "the session" — everything since launch, or the last N minutes/hours? Should replay REPLACE the live output (today) or play over it? Is a pass the right unit at all (16 beats from beat 0 splits phrases that start mid-pass) or should the reel record a continuous tape and let you pick bars?

## ★ RELEASE SETTINGS (found missing 2026-10-24; DONE the same day, branch `feature/release-hygiene`) — Step 5 hygiene
- [x] DONE: PRIVACY MANIFESTS — `Fourfold/App/PrivacyInfo.xcprivacy` and `Fourfold/AU/PrivacyInfo.xcprivacy` (no tracking, no collected data; `UserDefaults` CA92.1 — saved tempo, PULSE level, session key, `@AppStorage` — and system boot time 35F9.1 — `mach_absolute_time` / `systemUptime` for audio timestamps and animation clocks). Checked the code for the other required-reason categories (file timestamps, disk space, active keyboards): none used. Verified the file lands at the root of BOTH built bundles and lints; NOT yet validated by App Store Connect (that happens at the first upload).
- [x] DONE: `ITSAppUsesNonExemptEncryption: false`, `LSApplicationCategoryType: public.app-category.music` (app).
- [x] DONE: the app and the AU extension share ONE version — `MARKETING_VERSION` 0.1.0 and `CURRENT_PROJECT_VERSION` 1 in `project.yml` (both plists read them, so they cannot disagree; checked in the built bundles). **Before EVERY upload run `sh Scripts/bump-build.sh`** (or `… 12` to set it, `… show` to read it); the 0.1.0 itself is edited by hand when a release deserves a new one.
- [x] DONE: DOCUMENTS FOLDER exposed (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`): in the standalone app saved presets live in `Documents/Presets` (presets saved earlier in Application Support are moved across once — tested) and reel MIDI exports in `Documents/Reel exports`, both visible in the Files app under Fourfold. Verified in the simulator container. Release dSYMs: the project's Release configuration is already `dwarf-with-dsym`.
- [x] DONE: BLUETOOTH MIDI — `NSBluetoothAlwaysUsageDescription` and a button in the standalone app's transport bar that opens Apple's own pairing screen (`CABTMIDICentralViewController`); a paired device is just another CoreMIDI source and the app already reconnects on every MIDI setup change. Tap-tested that the screen opens and closes; real pairing needs a device and a Bluetooth MIDI controller.
- [ ] CHECK on a device: (a) Files app > On My iPad > Fourfold shows `Presets` and `Reel exports`; (b) pair a Bluetooth MIDI controller from the new button and play it into the MIDI IN source; (c) does BLE MIDI keep working with the app in the background? — I did NOT add the `bluetooth-central` background mode (App Review wants it justified); add it only if (c) fails.
- [ ] NOTES: presets saved from an AUM instance live in the EXTENSION's own container and are never visible in Files or to the standalone app (no App Group — as before, only now it matters because the app's are exposed); the preset file extension is still `.8x8` (8x8 State's), which is now visible in Files — rename to `.fourfold` before release if you want (the browser would need to read both for a while); `LSSupportsOpeningDocumentsInPlace` is set without any registered document type, so tapping a preset in Files does not open it in Fourfold (it is for the folder's visibility only).
- [ ] FIRST DEVICE CHECK for the iOS 15 minimum is line 1.6 in `Docs/euclideous-device-verification-debt.md`.

## ★ POST-RELEASE: turn Ableton Link back on (parked 2026-10-24 at Paul's request)
- [ ] AFTER RELEASE: `sh Scripts/link-switch.sh on` (fetches LinkKit, un-comments the `#LINK ` lines in `project.yml`, regenerates the project; `off` reverses it), then: get Apple's restricted `com.apple.developer.networking.multicast` entitlement approved for the Fourfold App ID (developer.apple.com — Paul's own step), run the whole "ABLETON LINK" list in `Docs/euclideous-device-verification-debt.md` on a real iPad with a real peer, and commit with the project in the ON state. The Swift side is already there, behind `#if FOURFOLD_LINK` (`FourfoldEngine`, `FourfoldAppModel`, `FourfoldAppView`, `FourfoldLinkSettingsView`). Built and compiled in both states 2026-10-24; never run on a device.

## ★ FOURFOLD — SIMULATOR PASS (2026-10-24): what the standalone app made testable (`Scripts/fourfold-harness/soak.sh`, `screenshots.sh`)
- [x] SOAK PASSED: 10 minutes of the REAL app under random abuse (MIDI in, PLAY/STOP ×82, tempo, 48 preset loads, HOLD/LATCH, note source, lane edits, solo, ALL NOTES OFF): 6,004 note-ons / 6,004 note-offs, 41 stops all clean (every key OFF), nothing sounded while stopped, longest note 6.9 s. The checker is proven able to fail: `soak.sh 75 7 40` (drops every 40th note-off) reports FAIL and names the stuck notes. Re-run after any engine/transport change; the simulator's timing is not the iPad's.
- [x] FIXED 2026-10-24 (branch `fix/mini-legibility`; verified by re-shooting every iPad and looking at mini portrait + landscape, base iPad portrait + landscape, Air 11 landscape) — the three iPad-MINI defects. **Cause of (1):** the TILT tile's end captions (EARLY / LATE) sit on an opaque backing that, when the tile is shorter than 36.7 pt (mini portrait ≈ 31–34 pt), erased the label and value ink — so `EuclideousRhythmGeometry.endLabelsFloor` is now 37 and the captions drop below it (the base iPad's tile is taller, so nothing changes there). **(2):** the octave stepper's centre was 32–35.5 pt against the 36.9 pt "OCT +1" needs; `euclideousMixOctaveCaption(cellW:)` now answers `.full` / `.tight` (2 pt spacing, tracking 0.02) / `.none` — the NUMBER never truncates; mini portrait drops the caption, mini landscape shows the tight one. **(3):** the RHYTHM tab shows "RHY 5/16" (`ViewThatFits`) when "RHYTHM 5/16" will not fit, instead of cutting the count. Tests: `testTheEndCaptionsDropOutBeforeTheirBackingCanErasetheLabelRow`, `testTheOctaveCaptionShortensThenDropsBeforeTheNumberEverTruncates`, `testEveryShippedIPadKeepsTheOctaveNumberAndItsCaption`.
- [ ] DECIDE (Paul): (a) the "RHY" abbreviation reverses CLARITY PASS spec 2.3's "tail-truncate, count goes before the label" — say if you would rather lose the count than the word; (b) on a short tile the EARLY / LATE captions are gone entirely (mini portrait and landscape) — the slider still reads "TILT … 0%"; if you want the captions back on the mini the tile would have to grow ~6 pt; (c) the OCT caption is absent on mini portrait (the pad has no room for it beside a legible number).
- [ ] (noted, NOT fixed) mini landscape only: the STEPS caption is not shown (the "16" sits right under the "+" button), and "OF 16" under the big hit number has the fader's edge line through it — both still legible, neither was one of the three asked for.
- [ ] STILL NOT LOOKED AT: the other five iPads' tab / popup / sheet pictures (the A16's `5-*.png` set was looked at: LISTEN, FX, NOTES, settings), the upside-down shots, and Pro 11 / Pro 13 / Air 11 / Air 13 in portrait. Regenerate with `sh Scripts/fourfold-harness/screenshots.sh` (now also takes the 12 `5-*` screens).
- [x] DONE 2026-10-24 (branch `feature/sim-tests-2`, status log "SIMULATOR PASS 2"): the render-thread ALLOCATION AUDIT (`CONFIG=Release sh Scripts/fourfold-harness/run.sh --alloc`) — it FAILED at first (≈14 allocations per render window, 1.86 M over the 21 documents; invariant 3 had never been measured) and now PASSES at zero across 26 scenarios after the fixes in `Fourfold/Engine` (golden identical). ASan+UBSan over the unit suite: clean. TSan on the live app: the soak passes, 13 racing sites reported (next item). Tap tests (18), random-input tests (2) and Apple's accessibility audit (20 screens) all pass on the base iPad and the iPad mini; tap tests + audits pass on the 13" Pro (Pro 11 / Air 11 / Air 13 not run). `sh Scripts/fourfold-harness/ui-tests.sh [ipad-filter]` runs them (≈40 min per iPad with the random-input tests).
- [ ] DECIDE (Paul): the TSan findings — the UI-poll / render-thread side channel (the NOTE VIEW ring's 14 arrays, the riff cursor / mask-position arrays) and the Kernel's one-way flags (`euclideousSoloLive`, `euclideousLockLive`, `euclideousAllNotesOffRequested`, `flushRequested`, `freeRunEnabled`, `EuclideousPendingRollSlots`) are plain vars shared between threads. Nothing corrupts memory or the sound (fixed-size storage, aligned words), but they are formally races; a UI-held array copy can force a copy-on-write ALLOCATION on the render thread (what the allocation audit cannot see, it has no UI); a one-shot request flag can in theory be lost; a pending roll can in theory be seen half-updated. Recommended fix: relaxed atomics (swift-atomics is already in) for the scalars and a seqlock/atomic-head ring over pointer-backed storage for the arrays — a design change to the telemetry channel, no sound change; the golden + `--alloc` + TSan soak are the checks. Say if you want it.
- [ ] DECIDE (Paul): the 8x8 State engine copy (`AUExtension/Router.swift` etc.) still has every allocation the audit found in Fourfold's (LISTEN order, KEY sort, per-hit arrays, tilt, echo, escaping callbacks, chord generator) — 8x8 is on hold and frozen, so nothing was touched; if 8x8 ever ships, port `Fourfold/Engine`'s fixes (the audit harness compiles Fourfold only).
- [ ] DECIDE (Paul), ACCESSIBILITY — the audit's design-level findings (all allow-listed in `FourfoldAuditAllowList` with these reasons): **CONTRAST** ~130 distinct labels (secondary text in mid greys, 8–11 pt, on dark tints and the 42 % dims) below Apple's threshold; **HIT AREA** ~90 elements under 44 pt (the LANES 16-cell grid, the riff grid's rank labels, the key popup's note letters, the rails, the step-count caption); **DYNAMIC TYPE** every font is fixed-size by design (182 issues, not in the routine run). A "bigger text" mode and 44 pt targets would change the layout of the whole page; decide whether Fourfold targets accessibility at that level before the App Store.
- [ ] FIX / DECIDE (Paul), TRUNCATED TEXT seen in the base-iPad portrait pictures (`build/screens/iPad--A16/5-lane-listen.png`, `5-fx.png`): the LISTEN tab's PITCH row captions "ITS LINE, I…" and "MUTE ON ITS…" (and "ITS OWN RIFF" fills its cell), the LISTEN help line "Starts as an exact copy. Rhythm and Riff pause while…", and the FX tab's instruction line "TAP: ON/OFF · DRAG ALONG: PAINT · DRAG UP/DOWN: VALUE · DOUBLE-TAP:…" — words are cut; on the iPad MINI (`iPad-mini--A17-Pro/5-lane-listen.png`, `5-lane-riff.png`) all four PITCH captions are cut ("ITS OWN R…", "ITS NOTE…", "ITS LINE,…", "MUTE ON I…") and the RIFF tab's "Invert melody" reads "Invert m…", and the RIFF tab drops its WALK strip there (no room — by design). These are spec'd strings (the LISTEN spec's own captions): shorten, allow two lines, or accept? Not changed.
- [ ] FIX / DECIDE (Paul), STOPPED = NO NOTE NAMES (seen in every `--fresh` picture): until the transport has played, the riff grid's rank labels and the whole NOTES tab show "–" instead of note names, and VoiceOver reads "Rank 3, no note", because the pool is filled by the render thread and the standalone app's STOP runs no windows (AUM's free-run hid this in the extension). Editing still works; but the first screen a new user sees looks unfinished. Fix idea: derive the KEY / CHORDS pool in the UI (the pure functions already exist) when the engine is not running. Not changed — it touches where the pool comes from.
- [ ] (noted) VoiceOver: the riff grid's 64 cells now have labels and an activation, the settings sheet's tabs/close button and the preset browser's controls are named buttons — real VoiceOver behaviour (order, how "Step 3, E♭3, off" reads, how long swiping through 64 cells takes) is device-owed (`Docs/euclideous-device-verification-debt.md`).

## ★ FOURFOLD — ADVERSARIAL REVIEW of Steps 1–4 (2026-10-24, run at Paul's request; measured, not recalled)
- [x] DONE 2026-10-24 (branch `feature/restore-tests`): tests for all 23 live functions below restored or rewritten against the live functions (20 baseline tests brought back — about half had to be rewritten because the retired function they also called is gone — plus 5 new tests for functions no baseline test named); every one is back to its pre-trim line coverage; overall coverage 94.0% (was 93.3% after the trim, 95.4% before); `Router.soloSilenced` and 62 other private symbols that nothing in their own file referenced were deleted (my finder `reach.py` matches names across files, so a same-named symbol elsewhere had kept them alive — a per-file check (`privdead.py`, kept in the session scratchpad, not in the repo) now catches private symbols per file; internal-scope name collisions are still possible). Original finding: TESTS LOST WITH THE TRIM: the plan's own acceptance check ("compare the coverage list before/after") was never run until now. Result (FourfoldTests with coverage, pre-trim `4b1f08c` vs `main`): overall 95.4% → 93.3%; Emission 97 → 83, Models 93 → 88; **137 surviving functions lost 466 lines of coverage; 129 functions that were covered now have none.** ≥14 of those are called by the Fourfold UI/app — the pure functions that are the ONLY check on UI behaviour: `euclideousStripHitsPhrase` (strip VoiceOver text), `euclideousChainRhythmMarkBeats`/`…MelodyMarkBeats` (LANES restart marks), `euclideousFXHit` (FX tab tap hit-test), `euclideousLockCountdown` (lock badge), `euclideousStripColumnLook` (CLARITY PASS column fills), `euclideousLapHitSteps`, `euclideousToggleLitPosition` (NOTES keys), `euclideousStripAppendLive`, `euclideousMixPadWriteIfEnabled`/`…ResetIfEnabled` (MIX pad writes), `euclideousMixGateStep`, `euclideousLockRandomIdleCaption`, `spanLadderBeats`. Cause: `prune.py` deleted whole tests when one helper they called stopped compiling. FIX: re-add a test for each (the functions are unchanged); rerun the before/after comparison (`covcmp.py` method in the status log) until no live function is at zero.
- [x] DONE 2026-10-24: 9 deleted (claim ×3, receivers ×2, muted cell, chop, mono, drone — all concepts Fourfold's engine no longer has) and `testDisabledEmitterIsSilentOnItsCableAndAll` re-pointed at real Euclid lanes with a control case; `testPanicBlasts…` kept (its CC checks are real) but note `Kernel.panic()` has no caller in Fourfold, so that path is unreachable in production. Original finding: VACUOUS TESTS: ~11 `RouterTests` build non-Euclid (ARP etc.) cells that Fourfold's engine no longer plays and assert "nothing sounded" — they pass without checking anything (read and confirmed: `testMutedClaimantStillReservesItsPitches`; unread candidates: `testMutedClaimantReservesShortNotesAcrossCells`, `testMultiClaimLeakZeroStillFullySuppresses`, `testMutedReceiverSilencesItsSubscribers`, `testDisabledReceiverNotArmedIsSilent`, `testDisabledEmitterIsSilentOnItsCableAndAll`, `testChopMuteMaskSilencesEveryNote`, `testMonoLeavesNoStuckNotes`, `testMutedCellEmitsNothing`, `testSingleColumnLapReleaseClosesDrone`, `testPanicBlasts…`). Delete them or re-point them at a Euclid lane. Also ≈110 of the 1,070 tests have names about 8x8-only concepts (MigrationTests 40, RouterTests 21, DerivationsTests 15, SnapshotBuilderTests 12, EffectiveParamsTests 9) — they exist because `Models.swift` still carries the 8x8 document.
- [x] DONE 2026-10-24: exports are now `Fourfold-All.mid` / `Fourfold-<A–D>.mid`, and the hang log and console prefixes say Fourfold (the one-colour reel question stays open). Original finding: REEL NAMES: reel exports are still `MidiSpark-All.mid` / `MidiSpark-<A–D>.mid` (`Fourfold/Engine/Kernel.swift`) although the plan says `Fourfold-*.mid`; the stuck-note hang log still says "MidiSpark STUCK-NOTE" (`FourfoldRootView.swift`). The reel colours a note by its machine's hue and Fourfold has ONE machine, so every note is probably one colour (DECIDE already logged above).
- [ ] TRIM NOT FINISHED (claimed "most of (C)" in the plan — overstated): `Models.swift` still has ≈630 lines of 8x8 document (`Receiver` 193, `SceneState` 90, `OnConfig` 80, `Machine` 70, `Cell` 67, `Row8Cell` 54, `Macro` 42), all 32 `ProcessorType` cases, `Kernel` still owns four `DoorRing`s, and ~68 engine functions kept alive only by never-taken branches have zero coverage (`Router.clockTransformedBeat` 32 lines, `killStepPhase`, glide/bend reset, `refreshOverrides`…). Plan item (D) (Fourfold's own decode-only layers) is untouched. True size change: the pre-trim copy was 30.6k engine lines (not 26.3k as the docs say) → 20.6k now (−33%); tests 30.6k → 18.8k lines.
- [ ] "ONE RULE" FUNCTIONS WITH NO CALLER (pre-existing, found by the trim): `euclideousLaneIsDimmed`, `euclideousStripAccessibilityValue`, `euclideousStripDrawsAsHit`, `euclideousLockRandomAllowsRolls`, `euclideousSoloSilencedLanes` were documented as the single rule shared by drawing and tests but nothing in production called them; I deleted them AND their drift-guard tests (e.g. "the display dim equals the sound for every hit"). The page decides the same things inline (`soloSilenced` etc.), so the recurring UI-vs-engine drift risk is now unguarded. Decide: rewire the page to call a pure function and restore the guard, or accept the inline version.
- [ ] NEVER RUN: the `.appex` has never been loaded by a host (the app and the harness both instantiate `FourfoldAudioUnit` directly), neither product has run on a device, the 1 MB main-stack budget (`Scripts/debug-frame-sizes.py`) was not re-measured after Step 2, and the golden oracle (21 documents, regression-only) has no MIDI input / host stop-start / HOLD-LATCH / reel / lock. Steps 1–3 also edited 8x8 State's own files (moved code out of `GridUI`, `MidiSparkAudioUnit`, `PresetBrowser`, `PresetStore`; optional parameters on `EuclideousPage`/`EuclideousSettingsSheet`): its 2,114 tests pass, but 8x8 State has not been re-checked on the iPad. `MidiSparkTests` also still compiles `Fourfold/Engine/FourfoldCompose.swift` (a hidden two-way coupling).
- [ ] UNEXPLAINED: in a clean checkout of `4b1f08c`, `testRenderAutoPassSpanRampsHitsUpAcrossBars` and `testRenderAutoSmoothLanePlaysAndLeavesNothingSounding` FAILED under coverage although Step 4b was reported green (both tests were deleted later with the render-auto feature). Probably a stale-artefact/ordering effect in my 4b run; not investigated.

## ★ FOURFOLD — STEP 4 engine copy-and-trim (2026-10-24; `Docs/euclideous-status-log.md`, plan in `Docs/standalone-plan.md`)
- [ ] DEVICE: see the "Fourfold Step 4" line in `Docs/euclideous-device-verification-debt.md` (an ear pass: MIDI in, host start/stop, HOLD/LATCH, lane lock, reel, a mute mid-hold).
- [ ] TRIM, left: `Models.swift` (3.3k) still holds the 8x8 document (scenes of many cells, `Receiver` doors, `Row8Cell`, macros, factory scenes, migrations); `Derivations.swift` (8.1k) still has helpers the Fourfold UI never reaches; Fourfold's own retired / decode-only layers (plan item D). Method: delete by reachability (callers) then compile; prune only tests of things the copy no longer has — and audit `prune.py`'s removed TEST HELPERS (a removed helper silently takes every test that used it).
- [ ] LOOK (Step 5, accessibility): `euclideousStripAccessibilityValue`, `euclideousStripMuteLook`, `euclideousStripDrawsAsHit`, `euclideousLaneIsDimmed`, `euclideousLapStartOrdinal` were documented as shared "one rule" functions but had no production caller (before the trim, too) — check the lane strip's VoiceOver value and the dim rule are wired where they should be.
- [ ] DECIDE (Paul): `Scripts/classify_euclideous_tests.py` is only the 8x8 fast-run selector now; keep for 8x8 or retire.

## ★ EUCLIDEOUS — LISTEN REBUILT: canon-style LISTEN tab — COPY/FILL rhythm, SHADOW/ECHO/AVOID pitch, borrowed tabs pause whole (2026-10-23; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the new "LISTEN REBUILT" lines in `Docs/euclideous-device-verification-debt.md`.
- [ ] DECIDE (Paul): DUCK/ACCENT (the old LEVEL row) is retired outright with no replacement — a migrated old document that used either loses that velocity behaviour entirely, not just its UI slot.
- [ ] DECIDE (Paul): AVOID+ANY's migration (no exact cell given for it) → the lane's own stored specific partner if one exists, else the lowest-numbered other lane.
- [x] RESOLVED by an adversarial review against the raw ferry text (2026-10-23): the paused-card overlay's wording/colours/sizes WERE given literally (§7.2) — my first build guessed instead of reading the raw text, and got the title colour, the explanatory sentence (no live hit/gap counts), the button height, and the card's fill/padding/border all wrong. All now match §7.2 exactly; still device-owed for how it actually looks/reads on the iPad.
- [x] RESOLVED, same review: two real engine bugs found and fixed — DELAY never implemented §3.6's transport-start silence (it just rotated the buffer, so the grace period sounded wrapped-around content); §3.5's "the follower's own RESTART chains are not read while borrowing" was violated, and fixing that naively (force off) regressed an existing test, because §3.5 also wants the follower resynced to the SOURCE's restart points — now reads the source's chain instead of its own. The §7.1 "← n" mark was also coloured as the follower's own lane, not the source's; the OCTAVE/INTERVAL clamp changed pitch class instead of shifting by whole octaves; the DELAY/FEEL steppers' tap targets were 16pt against the spec's 44pt minimum; a disabled FOLLOW chip had a fill where the spec wants none. See `Docs/euclideous-status-log.md`'s own entry for the full list and the new tests (incl. the spec's own §11.8 ECHO+DELAY worked example, never built as a test the first time — the gap that let the DELAY bug ship).
- [ ] DECIDE (Paul): the header's "← n" override (your own clarifying decision, named for RHYTHM/RIFF) was extended to NOTES too, since NOTES always pauses alongside RIFF under SHADOW/ECHO — say if NOTES should instead keep showing nothing.
- [ ] DECIDE (Paul): a paused tab's VoiceOver label now says "Rhythm, paused, following lane n, 4 of 8 hits" / "Riff, paused, following lane n" — invented wording, no literal spec text available to match against.
- [ ] (noted) `euclideousListenFollowerPosition` was built per spec §9.5 (a beat-based "which step now" function) but the engine ended up reading a simpler direct buffer-remap instead — the function exists and is tested but has no caller.
- [ ] (noted) the old FOLLOW-multiplier rate grid, the lane-card strip's SHADOW-only dim, and two riff-arrow-visibility checks were all found still reading the pre-rebuild fields during an audit, not called out by the original plan — all fixed to the new resolved model (see the status-log entry's own "also found and fixed" paragraph for the full list).
- [ ] (noted) `EuclideousLock.swift`'s `listenFollowMult` lock-field capture is now permanently inert (nothing in the UI can set `listenFollowMult` any more) — left in place rather than deleted, to keep this ferry's footprint to the LISTEN tab itself; a candidate for a future cleanup pass.

## ★ EUCLIDEOUS — FOURFOLD REEL LINK: the tape icon in the header, the pass browser over the page (2026-10-23; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "FOURFOLD REEL LINK" lines in `Docs/euclideous-device-verification-debt.md`.
- [ ] DECIDE (Paul): the REEL icon widened UTILITIES by 44, so layout A (one-row header) needs a view ≥ 1133.86 wide (was 1089.86); an iPad mini 6 at its full 1133 pt is 0.86 pt short. Trim a metric (key pill 120 → 118?) or accept the two-row header below that.
- [ ] DECIDE (Paul): the tape records only while the HOST transport plays; Fourfold's KEEP PLAYING free-run (host stopped) is not recorded. Fix = run the free-run clock block before the reel block in `Kernel` (shared render path).
- [ ] DECIDE (Paul): the pass browser is landscape-only (rotate prompt in portrait); notes are coloured by machine hue not Euclid lane colour; exports are named `MidiSpark-*.mid`; no Fourfold "restore lanes" for a pass (RESTORE SETUP is hidden there).
- [ ] DECIDE (Paul): `ReelDeck.histCap` is 8192 events/pass (8 MB). The worst case the Euclideous flood budget allows (160 note-ons a beat per output, ×2 offs, ×2 cable-0 copies) is still past it.

## ★ EUCLIDEOUS — FX REVIEW FIXES: ratchet strikes, cap, flood budget, NOTE pass, RATCH SHAPE (2026-10-23; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "FX REVIEW FIXES" lines in `Docs/euclideous-device-verification-debt.md` (first: launch the DEBUG build — the FX panel's strip gained a branch).
- [ ] DECIDE (Paul): NOTE counts a LAP under a melody chain of exactly [1] and a riff cycle (from the melody origin) otherwise — the old LOCK rule, now a property of the chain. It makes NOTE move on a fresh [1] lane (it was inert there) and keeps migrated LOCK lanes sounding as they did; the cost is a second meaning of "pass" the NOTE row's bubble ("NOTE +1 A PASS") does not name. One line (`euclideousFXNotePass`) to flip.
- [ ] DECIDE (Paul): the RATCH strike cap is now a 10 ms time floor at the host tempo (it was 1/128 of the scene's grid bar). The mask RATCHET shares it, so a mask RATCHET range that the old cap held down at the default 1/2 scene step now plays in full. `euclideousRatchetMinSlotSeconds`.
- [ ] DECIDE (Paul): Euclideous strikes have their own flood budget (160 a beat per output, a separate counter; the 8×8 engine keeps 48). A strike beyond it is still dropped and counted in HEALTH — nothing on the Euclideous page shows the drops.
- [ ] DECIDE (Paul): RATCH SHAPE's numbers — ACCENT 100 % then 65 %, FADE 100 % → 45 %, RAMP 45 % → 100 % — are my picks (`euclideousRatchetAccentRest`, `euclideousRatchetRampFloor`); the stepper sits on the RATCH row beside the lane buttons (the description line there is gone to make room).
- [ ] (noted) NOT built (item 6, by your ask): more than 4 strikes, per-strike on/off masks. The roll mirror draws the strikes' spacing and gates, not their velocities.

## ★ EUCLIDEOUS — FLOORS: the page's size-diagnostic flags become real fallbacks on 5 tabs (2026-10-23; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "FLOORS ferry" lines in `Docs/euclideous-device-verification-debt.md` — every new compact-floor number is my own pick and needs a real-iPad look.
- [ ] (noted) the WALK strip (RIFF tab) and the hint row (FX tab) disappear entirely below their own trigger rather than resizing — say if either should stay visible at the cost of its neighbours shrinking further instead.
- [ ] (noted) Options 2–5 of the original scale-down investigation (size-class-aware layouts, a real `.minimumScaleFactor` escape hatch, `supportedViewConfigurations`, an AU host-size renegotiation) were not pursued — this ferry is Option 1 (fair-share + drop-decorative-only) only; revisit if fair-share alone proves insufficient on device.

## ★ EUCLIDEOUS — CLARITY PASS: beat-shaded step columns, tab glyphs, MIX lane panels (2026-10-23; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "CLARITY PASS" lines in `Docs/euclideous-device-verification-debt.md` (first: launch the DEBUG build — the tab row's and MIX's leaves changed).
- [ ] DECIDE (Paul): the 2 pt "leftover rule" under a short last group (7 steps in fours, etc.) was not named by the spec and stays, repositioned from the new even columns. The shading now shows the short group too, so the rule is redundant — drop it if you agree.
- [ ] DECIDE (Paul): the 24 pt VEL strip is gone (its label and value moved), so the pad's plot spans the whole pad (`velStripW` = 0) and the puck's travel changed with it (x 7 … cellW−7). The spec said only "give that width back".
- [ ] DECIDE (Paul): the panels' spacing makes every pad 6 pt narrower and 12 shorter (landscape 87.17 × 81.5 → 81.17 × 69.5), so the MIX legibility floors moved by the same amount (84 / 76 / 60 → 79 / 64 / 48; the width floor is 1 pt over the pure shift because "OCT +1" measures 37 pt) and the OCT stepper's buttons went 24 → 21 wide ("OCT +1" truncated to "OCT …" at the new width — found in a scratch render).
- [ ] DECIDE (Paul): the pad readouts cannot sit as "VEL 100" / "GATE 90%" at ≈ 81 pt (they need ≈ 90 pt of text); by your ruling the words yield by width — at the reference width the pad shows "VEL 100" / "90%".
- [x] RESOLVED by the LISTEN REBUILT ferry below (2026-10-23): LISTEN is now genuinely one shared source lane, not three independent rows — this item described the model that ferry replaced.
- [ ] DECIDE (Paul): the readability pass's 1.5 pt 70 % hit border is gone and its floor bar stays on hits only (a gap is a rest grey + a ring, no bar); an OFF pad is now inert (it used to grey and still edit) — the OCT stepper under an off NOTES pad still edits AND still sets the notes switch on — which re-enables the pad only if a note is selected (a layer is on only with the switch on AND a note selected; a new lane has none lit, so every NOTES pad starts OFF and its gate / velocity cannot be pre-set until a note is selected on the NOTES tab).
- [ ] (noted) "RHYTHM 10/16" … "16/16" measures 87.6 pt (11 pt heavy mono, the label's tracking, the count's none; real-font measurement) against an 87.2 pt tab landscape-unlocked (88.8 portrait), so a two-digit hits count loses its last digit landscape; on a locked lane (77.7 / 79.2) even "5/16" (80.8) truncates. The spec says truncate the count, never shrink, so it stays. A FOLLOW lane's count is the pattern it plays (its partner's steps and hits), not its own sliders. The spec's 4.2 wording was already true (the pad's label names the lane and layer).

## ★ EUCLIDEOUS — RESTART TILES: the MELODY tile counts riff notes, the editor shows the tiles, rests stay dashed (2026-10-22; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "RESTART TILES" lines in `Docs/euclideous-device-verification-debt.md` (first: launch the DEBUG build).
- [ ] DECIDE (Paul): STRIDE above 1 can leave some notes never reached (FWD LEN 8 STRIDE 2 visits 4). The MELODY track still has LEN cells — visited ones first in walk order, then the never-visited ones (dashed ghosts under a melody chain, plain unlit under FREE). Say if you'd rather the track show only the visited notes.
- [ ] DECIDE (Paul): the restart editor's sections start at y 38.67 / 119.33 at the reference card's 208-high editor (the ferry's 36 / 114 hold at a height of 200); the flexible gaps share the leftover height equally, as they always did, now through `euclideousRestartEditorLayout`.
- [ ] DECIDE (Paul): REPEAT-on-rest strikes the REPEATED note's cell, which needed a new display-only NOTE VIEW field (`cellColumn`); the riff panel's arrow still flares the hit's own rest column.
- [ ] (noted) RAND / DRUNK cannot reach the Euclideous row, so the "light as played, clear when all reached" fallback is not built — only the column-order, no-ghost cell order is.

## ★ EUCLIDEOUS — RHYTHM POLISH: prominent HITS, continuous OFFSET / TILT, FLIP HITS, sweeping restart tiles (2026-10-22; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "RHYTHM POLISH" lines in `Docs/euclideous-device-verification-debt.md` (first: launch the DEBUG build).
- [ ] DECIDE (Paul): TILT is not continuous at 0 — tilt 0 plays the Euclid positions {0,3,6}; any tilt ≠ 0 blends from the even spread {0,3.5,7}, so the first step off 0 jumps (the 3 % detent hides the first 3 %). Blending from the real Euclid positions instead is a one-function change (`euclidTiltPatternFine`) and would make it continuous — but it changes the shape of every tilted pattern, so not done unasked.
- [ ] DECIDE (Paul): unrounded TILT is OPT-IN per lane (`tiltFine`, set by the new slider) so existing sessions sound as before. A lane you never touch keeps today's rounded TILT forever; say if you'd rather it flipped for everyone (a sound change for any stored `tilt ≠ 0`).
- [ ] DECIDE (Paul): the HITS caption colours — the rule "75 % toward #F2F4F7" gives L1 #F2CDD0 (not the spec's #F7C1C1, which the rule cannot produce), L2 #CCE7F6, L3 #F2E7C9, L4 #D9EDD6. Say if you want #F7C1C1 for L1 literally (and how L2–L4 should then derive).
- [ ] DECIDE (Paul): the HITS hero's block height uses box heights (36 + 2 + 10), not measured font heights; "tabular" = monospaced digits.
- [ ] DECIDE (Paul): with a fractional OFFSET, BKW / PING-PONG put each hit in the box its START TIME falls in, which can be one box from where the integer pattern shows it; the unreached-step 42 % dim the ferry cites as existing is not in the code and was not added.
- [ ] (noted) a 3-link chain ("2·1·1 PASS") truncates the tile label to "MELODY RE…" at 160.75 pt; the tiles' timer is the flash's (not the comet strip's, which is private).

## ★ EUCLIDEOUS — LANE LOCK: a padlock in the header; a locked lane snaps back on a quantised grid line (2026-10-21/22; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "LANE LOCK" lines in `Docs/euclideous-device-verification-debt.md` (first: launch the DEBUG build and open lock mode).
- [ ] DECIDE (Paul): the required BRAND width pushes the output rings off the lane gutter at the 1190 reference (they pin flush against BRAND, 17.19 pt right of centre; 10.86 pt in portrait). Accept, or shorten BRAND's wordmark / hide it in layout A?
- [ ] DECIDE (Paul): the lock's landing is tick-exact (the hit ON the line plays L); RANDOM MODE's landing is still window-granular with a 150 ms margin (0.3 beat at 120 BPM). The new segment runner is generic — move random mode onto it (a small follow-up), or leave it?
- [ ] DECIDE (Paul): a stopped page puts a deviated, un-touched locked lane straight back (spec 6.5), so editing a locked lane with the transport stopped never "sticks" past the lift.
- [ ] DECIDE (Paul): the count-down's latency margin is 60 ms (`EuclideousLockMargin`); the render thread itself uses none — it checks "an edit is on its way" exactly (believed for at most 1 s). An edit made within tens of ms of a line can still be taken by the snap (it "snaps anyway", as asked).
- [ ] DECIDE (Paul): bar 1 = the host's beat 0 (AUM's own bar numbering is not read); a mid-song time-signature change shifts the grid.
- [ ] DECIDE (Paul): the comet bar's drags count as lock-field controls (they write the same fields); the lock card's RIFF row reads "RIFF OFF" when the riff is off (the spec gives no off text).
- [ ] (noted) VoiceOver ", will snap back" is on sliders, STEPS, the riff/notes steppers and buttons, the riff direction row and the restart tiles; the rate/feel cells, RHYTHM direction cells, riff card, notes keys and strip still need it.
- [ ] (noted) lane copy/paste, host automation of lane fields and MIDI learn of lane fields do not exist, so spec 3.4 / 6.7 hold by construction; the revision funnel (`setEuclideousLines`) would cover a future writer.
- [ ] (noted) `LaneLockTests` + the thirteen `RouterTests.testLock…` take ~2 min between them at buffer 64 (the scoped suite is slower for it).

## ★ EUCLIDEOUS — RANDOM MODE: the dice, THROW/TWEAK/BACK/KEEP, the hold, finish+undo (2026-10-21; `Docs/euclideous-status-log.md`)
- [x] Adversarial review (2026-10-22) + all 24 confirmed findings fixed — see the status log's own
      "RANDOM MODE adversarial-review fix ferry" entry for the full list (the stuck-hold bug, zero hold
      test coverage, the tab-resync gap, the simplified §4 pictures, caption/button bugs, and the
      Array→fixed-size-struct data-race fix). Device items from that pass are their own new subsection in
      `Docs/euclideous-device-verification-debt.md`.
- [ ] DEVICE: see the "RANDOM MODE" lines in `Docs/euclideous-device-verification-debt.md`.
- [ ] DECIDE (Paul): the 150 ms landing-margin constant (before a bar/beat line) is a judgment call with no spec number behind it — retune once heard.
- [ ] DECIDE (Paul): the hold has no minimum-duration threshold (switches from touch-down itself), unlike the 0.3 s hold used elsewhere on this page (output rings, SOLO) — confirm a bare touch-down was actually intended, not a hold timer.
- [ ] DECIDE (Paul): §7.3's return highlight is simplified to a ring fade + "KEPT · UNDO TO GO BACK" tag, not the full per-control glow the spec also names (the comet strip; HITS/STEPS/OFFSET; the direction row/EVERY/HIT·STEP/ON REST/SHIFT/STRIDE/WALK strip; the key row/PLAYS·RESTS/CHANCE/PLAY AS). Worth the follow-up pass, or is the simplified version enough?
- [ ] DECIDE (Paul): TWEAK's glyph is `waveform.path` (an SF Symbol approximation), not a custom one-period-sine path as literally specced ("one period, round caps, 2.2 pt stroke") — build the custom path, or keep the symbol?
- [ ] Not built: rolling the riff panel/MIX/LANES/FX, a throw-history, rolling LISTEN — all explicitly out of scope per the ferry text, noted here only so they're not mistaken for an oversight.

## ★ EUCLIDEOUS — LANE SOLO: the step-count box becomes a SOLO button (2026-10-21; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "Lane SOLO" lines in `Docs/euclideous-device-verification-debt.md` (first: launch the DEBUG build).
- [ ] DECIDE (Paul): §5.4 wants solo "within one buffer" but §4.2 says "the same path as the main-out mask"; that path publishes a snapshot one main run-loop turn after the touch, then the next window reads it (a few audio blocks; the build is ≈ 1.7 ms). A dedicated atomic the Router reads would be one buffer but is a second path — say if the hold feels late.
- [ ] DECIDE (Paul): preset load resets solo for factory presets but a USER preset restores the latch it was saved with (it mirrors main-out). Force solo to 0 on every preset load?
- [ ] DECIDE (Paul): while an output-ring TRACE is held the whole lane card (SOLO button too) sits at the trace's 42 % — the ferry says the button never dims.
- [ ] DECIDE (Paul): in a shared riff-grid cell only the silenced lane's stop / number dim (the blend snaps instead of easing); a ring quarter eases.
- [ ] (noted) the 0.15 s ease the ferry cites for the silent-lane look did not exist; built, and the LANES-mute dims on the touched surfaces now ease too.
- [ ] (noted) AU parameter / MIDI learn for solo is trivial to add (new stable address beside the macro bank); out of scope.
- [ ] (noted) the pulse feed shows a strike made just before a solo decaying on its own — nothing new is made.

## ★ EUCLIDEOUS — RHYTHM tab fixes: restart-engine edges, STEPS, layout fallbacks, accessibility (2026-10-21; `Docs/euclideous-status-log.md`)
- [x] FIXED §3.3: `euclideousPassIndex`/`euclideousPassStart` were missing `+ eps` on two of their three
  floor/round formulas (a beat landing exactly on a cycle or segment boundary could round into the wrong
  pass) — both now match the spec's stated formulas.
- [x] FIXED §4: the AUTO-lane automation ramp wrote `steps`/`pulses`/`rotate` straight to row 0 without
  nil-ing `hitsRequested`/`offsetRequested`, so a later manual HITS/OFFSET edit could resurface a stale
  pre-ramp request; the long-press-revert now restores those two fields too, for the same reason.
- [x] FIXED §5: the restart editor had a hard `height >= 192` gate with no fallback — below that it drew
  nothing. Now a pure `euclideousRestartEditorFallback(height:)` drops the timeline under 156pt and the
  hint line under 128pt, same progressive-degradation shape as the DYNAMICS editor. Touch areas widened
  (`.contentShape` only, drawn size unchanged): MIX OUT button and the picker/editor close buttons all now
  24pt tall.
- [x] FIXED §6: restart editor's close button reads "Close restarts" (was "Close the restart editor"); the
  STEPS value-box's VoiceOver swipe no longer shares `commitSteps`'s drag-only `firstWriteDone` coalescing —
  every swipe now calls `onCommit(true)` directly, so each is its own undo step.
- [x] CONFIRMED, not bugs (read against current code, not the spec's own framing): §3.1 ping-pong already
  doubles the lap length; §3.4 lap starts are independent of the rhythm origin by construction; §3.5 the
  riff ordinal still counts across rhythm restarts when melody is FREE; §3.7 bar length already comes from
  the host's live time-signature, not a hardcoded 4; §3.2 a restart mid-step floors to the containing tick
  (the engine's only resolution — same convention as the pre-existing legacy re-anchor, not a new rounding);
  §3.6 ping-pong's duplicate-visit-at-the-turn is deliberate, documented, pre-existing, and untouched by this
  ferry (confirmed by diff: none of this ferry's changes touch `euclidReadIndex`/`euclidCycleLen`).
- [ ] DEVICE: see the "RHYTHM tab fixes" lines in `Docs/euclideous-device-verification-debt.md`.
- [ ] (noted, a second independent audit's own finding, confirmed — no contradiction with the above) no test
  covers `euclideousRhythmChainChangesNothing` itself, a dotted/non-bar-dividing restart-link length, or
  `barBeats` sourced from a non-4/4 host time signature — a coverage gap, not a known bug.

## ★ EUCLIDEOUS — RHYTHM DYNAMICS: REMOVED (2026-10-21; `Docs/euclideous-status-log.md`)
- [x] Paul asked for the DYNAMICS button and functionality to be removed; it is gone (row, editor, engine, model fields, tests). A session saved while it existed still loads — the five stored keys are ignored. Nothing open here.

## ★ EUCLIDEOUS — header HOLD/LATCH: source-detour reset fix + CHORDS/KEY guard fix (2026-10-21; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "Header: output rings... HOLD/LATCH" lines in `Docs/euclideous-device-verification-debt.md`.
- [x] `euclideousChordsActive` → `euclideousGeneratedSourceActive` (Router.swift:3448) now reads the page-level
  `euclideousNoteSourceResolved` instead of each lane's legacy per-lane field, and covers KEY as well as CHORDS — fixed,
  tested (`testEuclideousChordsAndKeyPlayWithGenuinelyNothingHeldAnywhere`), landed `edaaa09`.

## ★ EUCLIDEOUS — RIFF GRID review (2026-10-21; `Docs/euclideous-status-log.md`)
- [x] FIXED: an arrow (and the lane card's riff thumbnail highlight / spoken "now on step") on a lane that is not running — PLAY off or 0 HITS (a transport stop already cleared them). DEVICE: see the "Riff grid" lines in `Docs/euclideous-device-verification-debt.md`.
- [ ] DECIDE (Paul): the note names / cells show what is WRITTEN, not what sounds (per-lane INV and TRANS, MIX riff OCT and FX NOTE are invisible there); the lit name on a strike uses the engine's rank (after INV / MIRROR / LEAP) while the arrow sits on the written row. Show the sounding rank on the grid, or leave it.
- [ ] DECIDE (Paul): LANES-tab playheads/roll for a STOPPED lane (they run on the transport alone), and a running lane with NO OUTPUT / MAIN OUT OFF (arrow + playhead move, nothing can sound) — should they follow the same "running" rule?
- [ ] DECIDE (Paul): the rails — keep as they are, make "played" vs "not played" easier to tell apart (16% vs 8% alpha), or drop the always-played full-length rails; a 0-hit lane's rail reads "all played" (§7.6 fallback).
- [ ] DECIDE (Paul): the riff tab's playing-triangle (always on the selected tab) adds nothing; remove or keep.
- [ ] (noted) a lane re-enabled mid-run has no arrow until its first hit lands; the engine still keeps a stopped lane's last riff step (only the UI hides it) — resetting it when the lane stops would be the engine-side alternative.

## ★ EUCLIDEOUS — LANE STRIP: the riff contour over the notes keys, in place of the comet (2026-10-21; `Docs/euclideous-status-log.md`)
- [x] Readability pass (2026-10-22, ratified by Paul from a screen-recording review): rhythm = lane
      colour (24%-fill/70%-border hit columns + a solid floor bar), riff = the white chips (nudged up),
      notes = the key row (untouched) — see the status log's "LANE STRIP readability ferry" entry. Device
      items are their own new subsection in `Docs/euclideous-device-verification-debt.md`.
- [ ] DEVICE: see the "Lane strip" lines in `Docs/euclideous-device-verification-debt.md`.
- [ ] DECIDE (Paul): the chip/cell colours are the riff grid's real composites (#DCDCDD note cell, #28292D empty cell — `EuclideousStripPalette`, one place), not the ferry's #DFE3EA / #24262C; the current chip is the light chip with the ARROW's own gradient (lane @ 95% → 55%) over it, not "lane100 → × 0.86" (which is not what the arrow draws). Say if you want the mock's numbers instead.
- [ ] DECIDE (Paul): the label floors (12 chip / 16 key) bite only on small cards — columns at 8 / 12 / 16 steps are 25.6 / 16.0 / 11.2 on a 10.2" iPad landscape, 30.4 / 19.2 / 13.6 on 11", 37.5 / 23.9 / 17.1 on 12.9" (the ferry's "≈ 13 wide" chip is the 12.9"'s), so at 16 steps chips carry no label below ≈ 345 pt cards and keys none until 12 steps; lower the floors or leave it.
- [ ] DECIDE (Paul): a FOLLOW lane lost its partner-coloured cells (the strip's cells are plain); the count box's dot still names the partner. A SHADOW lane shows no chips and the existing partner band over the key row. The pattern-miss outline and the hand-edited notch went with the tiles. Say if any should come back.
- [ ] DECIDE (Paul): key labels use the pool name without the lane's OCT (as the NOTES keys and the riff grid do), so with MIX OCT ≠ 0 the label is one or two octaves off what sounds. Chips use the WRITTEN rank (the arrow's rule); the LANES roll bars use the sounding rank — with INV / TRANS set the two contours differ.
- [ ] DECIDE (Paul): the strip's key glow is shadow radius 5 (CSS blur 10 ≈ half); the NOTES tab's key uses radius 10. One constant each if you want them equal.
- [ ] (noted) the footers' prediction ignored ADVANCE EVERY (`euclideousRiffCyclePrediction`); fixed in this ferry (`every:` → `euclideousRiffColumn`), with a footer-vs-engine test at EVERY 1-4.
- [ ] (noted) PING-PONG (a rhythm direction) shows the sweep the playhead is on (two legs); FWD / BKW one leg. The footers' prediction is still oblivious to a RHYTHM restart inside the lap and to LISTEN WITH / GAPS dropping a hit — the strip inherits both.
- [ ] (noted) a poll-uncorroborated moment (the arrow's static seat, at most one hit) shows no current chip; the strip's pass switches when the page body re-runs, as the footers always did.
- [ ] (noted) the per-body strip plan costs ≈ 1.3 ms a lane in a debug build at its worst (WHEN one-sided + CHANCE counting up to 1023 hits per key); a memo keyed on the lane's inputs is the obvious next step if the body shows up in a profile.

## ★ EUCLIDEOUS — PULSE: strikes that show velocity; riff rests are gaps (2026-10-21; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "PULSE" lines in `Docs/euclideous-device-verification-debt.md`.
- [x] (superseded by the LANE STRIP ferry, 2026-10-21) the comet-bar "riff off ⇒ the notes pulse it" rule: the strip lights the chip for a riff strike and the key for a notes strike, separately — `euclideousPulseStrikeVelocity` is gone.
- [ ] DECIDE (Paul): an FX-tied hit stays a NORMAL tile with no pulse (a gap is only a riff rest under SKIP/TIE); a REPEAT hit that finds no earlier note to repeat likewise (the footers show it as a rest hit, the engine plays nothing).
- [ ] DECIDE (Paul): strikes can lag the dot by up to ~50 ms (the NOTE VIEW poll is 30 Hz). If it shows, poll it at 60 Hz (the rate of an existing poll only).
- [ ] (noted) the BUILD-page EUCLID editor's comet bar (no feed) keeps the old geometric flare; the step-based ring/arrow flare functions are gone.
- [ ] RECOMMEND (Paul to say): `euclideousStrikeEvent` (@State on `DiagView`) is now read only by the NOTES keys (for the struck pitches); every strike batch re-evaluates the WHOLE page body (pre-existing since the header ferry, up to 30×/s). Storing the pitches on the feed's strike and dropping that @State would remove it — an unmeasured main-thread win, not done here.

## ★ EUCLIDEOUS — NOTES TAB: keys, WHEN, PLAY AS, CHANCE, RECEIVED; FILL leaves ON REST (2026-10-20; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "NOTES tab" lines in `Docs/euclideous-device-verification-debt.md` — the key sizes, the picker, ROLL/RUN by ear, the tied-rest strike, one old SKIP/TIE session and one old FILL session.
- [ ] DECIDE (Paul): TOP 2 kept its PAIR (the ferry's single-note design assumed one note): lower note + "+" on the key, "2–3" as its place number, two places in CYCLE/BOUNCE/BUILD/SPLIT. Say if it should become a single note (and whether an old TOP-2 lane then gets TOP added to keep its sound).
- [ ] DECIDE (Paul): with nothing held the keys show an en dash like the riff grid (the ferry said rank numbers 1–8).
- [ ] (noted) `addPitch` holds 9 pitches; a ten-key lit order plus the riff note and mask CHORD extras can pass it (first lit wins).
- [ ] (noted) the hidden NOTES controls (`notesOctaveTopRow`, `notesVelBar`, the per-note chips, `euclideousOctaveTrough`, `euclideousHighPickRanks`) are kept, unreferenced; `noteOctShifts`/`notesVelOffset` are decodable but no longer sound / are no longer set.

## ★ EUCLIDEOUS — RIFF PANEL: compact tabs, blended arrows, lane rails (2026-10-19; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "Riff panel" lines in `Docs/euclideous-device-verification-debt.md`, and the two DEBUG size lines (root `safeAreaInsets` / page `bottomInset`) — they settle whether the 9pt bottom gap was an inset.
- [ ] DECIDE (Paul): the one-lane arrow fill is the comet tile's own (lane colour 95% → 55% alpha) because source differs from the mock; it reads paler at the bottom on the light cells. Switch to the mock's lane100 → × 0.86 (`EuclideousArrowStyle`)?
- [ ] DECIDE (Paul): the tab number is 9pt (source) not 10pt; the playing triangle (not in today's row) is drawn on the active tab in ink. Say if either should change.
- [ ] DECIDE (Paul): the arrow now JUMPS to the latest hit's cell (no flight, no PEND/PING flip). Say if you want the 80ms glide back.
- [ ] (noted) ferry text §7.2's rail example contradicts its own "runs of three or more read as a range" — built the rule ("plays columns 1 and 3 to 8").
- [ ] (noted) the riff tab row's accessibility labels are unchanged ("Riff 2, editing"); there is no spoken "playing".
- [ ] (SHELVED, per Paul 2026-10-19) the LOOPER (2026-10-16) and LOOP SLOTS (2026-10-16): no looper is planned. Neither is built; `riffLoopRowH` and its budget are gone.

## ★ EUCLIDEOUS — PAGE LAYOUT: six equal boxes in both orientations (2026-10-19; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: see the "Page layout" lines in `Docs/euclideous-device-verification-debt.md` — above all the portrait fit (the 885 check) and the 9pt bottom margin.
- [ ] (noted) the other overlays in DiagView's root ZStack (cog page, presets, …) can be widened by the 8×8 workbench the same way the page was — not touched (8×8 is on hold).

## ★ EUCLIDEOUS — LEGATO removed from the XY pad / a lane's gate (2026-10-19; `Docs/euclideous-status-log.md`)
- [ ] DEVICE: the pad's far-right edge reads GATE 99% and every hit re-strikes (set the red/yellow lane to the far right: all hits sound); an older session that had a lane at 100% now loads at 99%.
- [x] ~~DECIDE: the FX tab's GATE row still has 100 = LEGATO~~ — DONE (Paul 2026-10-20: "remove 100=legato"): the row tops out at 95 (its step is 5; `EuclideousFX.gateMax`), a stored 100 loads as 95, and every LEG /
      LEGATO label is gone (strip, mark, bubble, VoiceOver). DEVICE: the GATE row's top cell reads 95; an older session with a GATE 100 cell now plays it at 95 and a repeated pitch re-strikes.
- [ ] (noted) the shared slider-label function and the engine's per-pitch legato code remain, but NOTHING the UI or a document can set reaches them any more (lane gate ≤ 99, FX GATE ≤ 95) — only tests that build
      lines / FX cells directly do. Deleting the engine's legato path is possible but is a bigger engine change with its own tests; say if you want it gone.

## ★ EUCLIDEOUS — FIX: a hit on a chord change read the previous chord (2026-10-19; found from Paul's video of the yellow lane's silent step 5)
The CHORDS pool is now resolved at each tick's own beat, not once per window at its start (`Docs/euclideous-status-log.md`).
- [ ] DEVICE: see the "CHORDS source" lines in `Docs/euclideous-device-verification-debt.md`.
- [ ] DECIDE (Paul): under GATE 100 a hit whose pitch equals the held one still carries on as one note (by design — "legato"), so step 3 of that lane is silent while the chord is unchanged.
      If you want a new HIT to re-trigger even on the same pitch, that is a different rule (a "retrigger on same pitch" option) — say if you want it.
- [ ] (noted) `chordSeqNotes` allocates arrays on the render thread every window (pre-existing); worth a pass to make the CHORDS pool allocation-free.

## ★ EUCLIDEOUS — "RIFF tab rebuilt: OCT goes, a WALK strip, ADVANCE EVERY and REPEAT on rests" — SHIPPED
(2026-10-19; LANDED on `feat/riff-tab-walk-advance-repeat`, macOS suite green throughout, iOS builds clean) —
the RIFF tab's OCT row is gone (MIX's stepper is the only riffOctave control now); a new WALK strip shows the
columns the lane's walk reads with a live ring; ADVANCE EVERY (1-4) moves the walk once every N hits/steps;
REPEAT is a 4th ON REST choice (plays the nearest earlier non-rest column's note again); NUDGE is relabelled
SHIFT; INV moved into the direction row. All 20 factory presets confirmed unaffected (EVERY defaults to 1,
nothing uses REPEAT) except ties the TIE lookahead's new, longer bound now catches — disclosed, not a
regression. Full story, including the §14 report (file:line audit findings, the layout discrepancy, REPEAT's
cost, what's device-owed), in `Docs/euclideous-status-log.md`.
- [ ] DEVICE: see `Docs/euclideous-device-verification-debt.md`'s "RIFF tab rebuilt / WALK strip" section —
      the strip at real size in all four lane colours, the 55.3pt mini-grid and its 32% dims, the ring's live
      feel, EVERY sounding like held groups, REPEAT sounding like the riff's previous note, a long PING tie.
- [x] ~~`euclideousListenPartnerNoteAt` (LISTEN/SHADOW, LISTEN/AVOID) computed the partner's riff ordinal the OLD way~~ — FIXED (Paul 2026-10-20: "fix the bug you found"). It ignored ADVANCE EVERY, the restart chains and the
      melody origin and read the retired LOCK flag; it now asks the same chain core + `euclideousRiffColumn` the Router uses, so a SHADOW lane sounds what its partner sounds (6 new Router tests; 4 + the two multi-link-chain
      ones failed on the old code). DEVICE (by ear): a SHADOW lane (unison, FOLLOW) of a partner with EVERY 2 / a restart chain plays the same notes as the partner. STILL NOT FOLLOWED, disclosed: a partner that is itself
      FOLLOWing a third lane (its pattern is its own here), the partner's WITH/GAPS strike filter, and its ON REST modes (a hit on a rest — REPEAT/TIE/FILL included — leaves the shadow resting, per §6's own rule).
- [ ] (accepted) the ON REST row's 4 buttons are each their own VoiceOver element, not grouped under one "On a
      rest in the riff" container label (§9.5's own ask) — would need restructuring the row's hit-testing.
- [x] ~~the §7 readout/never-play functions recompute on every SwiftUI body evaluation rather than being memoised~~ — DONE (2026-10-20): `EuclideousRiffReadoutCache`, one slot per lane keyed on every input;
      the lane card's mini-grid, the WALK strip and the riff panel's rails now share one computation per edit (tested). The readout's two internal passes remain (see the adversarial follow-up).
- [ ] (accepted) §7.8/test 14-15's fuller worked-example matrix (chain-based Q, the over-budget and
      longest-readout cases) is implemented per the literal formulas but verified against only 2 of ~14
      examples, for time — not exhaustively diffed.
- [x] ~~opacity multiplied on a never-played WALK-strip cell of a riff-off lane (≈0.176 instead of the
      spec's own "the dims don't multiply" 42%)~~ — FIXED (adversarial review, below).
- [x] ~~§11 tests 5, 6, 10 (TIE+EVERY, the long PING tie, REPEAT's own NOTE VIEW telemetry) were unwritten~~
      — ADDED (adversarial review, below).

### Adversarial review follow-up (2026-10-19; `fix/riff-walk-adversarial-review`) — remaining open items
- [ ] §3.2's readout text-shortening fallback ("drop 'LINES UP' first, then truncate before the amber part,
      which stays whole") is unimplemented — the strip's header just `.lineLimit(1)`s the full string, so the
      amber "N NEVER PLAY" part isn't protected at the ferry's own 41-char worst case.
- [ ] `riffModesRow` was deleted outright rather than hidden (§0.3's own "hide, don't delete, report anything
      you delete") — never disclosed in the original report. Low risk (fully superseded, no persisted state)
      but worth a one-line acknowledgment or restoring it as dead code, your call.
- [ ] `euclideousRiffReadout` still does two full passes internally (builds `F`/`playedColumns`, then re-walks every tick again for `neverPlayWalkSteps`). The recompute-per-body half of this is FIXED
      (cached per lane on its inputs, 2026-10-20); collapsing the two passes would only speed up the recompute that now happens once per edit — do it only if dragging HITS/STEPS hitches on-device.
- [ ] §11 tests 9 (REPEAT+FX), 13 (REPEAT+lit notes), 17 (the ring's ADV HIT vs ADV STEP behaviour), 19
      (SHIFT's full LEN 8→4→8 walkthrough), 20 (decode-clamp boundary values 0/9/12) remain unwritten.

## ★ EUCLIDEOUS — "RHYTHM tab rebuilt, outputs move to MIX, restart chains become the one restart model" — SHIPPED
(2026-10-19; LANDED on `feat/rhythm-tab-restart-chains`, macOS suite green throughout, iOS builds clean) — two
declarative restart chains per lane (RHYTHM in bars, MELODY in passes) replace the LANES GRID's masked model as
the ONE live restart decision; LOCK is retired (a melody chain of [1] does what it did); the RHYTHM tab drops
VEL/GATE/the OUT circles, gains a STEPS stepper+picker and HITS/OFFSET memory, and a restart-tiles editor; the
LANES panel is mute-only now (no RESTART sub-tab); OUT A–D moved into MIX, which shrank OCT to 24pt and grew a
20pt OUT row under each pad; the header's output ring now targets MIX (its OUT buttons, or the MIX tab chip)
instead of the RHYTHM tab. All 20 factory presets confirmed unaffected (none used any old restart field). Full
story, including the §17 report (what the old models re-anchored, the migration-inexact edge case, every
judgment call), in `Docs/euclideous-status-log.md`.
- [ ] DEVICE: see `Docs/euclideous-device-verification-debt.md`'s "RHYTHM tab rebuilt / restart chains" section —
      the STEPS stepper's drag-vs-tap feel, the picker's preview bars, the restart tiles/editor's small type and
      timeline, TILT's EARLY/LATE, MIX at padH 76, the dashed OUT button, the pulse/trace rings on MIX.
- [ ] DECIDE (Paul): the restart editor's focus-on-open/back-on-close VoiceOver behaviour (§13.5) isn't wired —
      every control is individually labeled/hinted, but explicit focus transfer is unimplemented. Worth a follow-up?
- [ ] DECIDE (Paul): one synthetic old-model test case (`resetSteps=2` over `LEN=5`, a 10-mark true period) migrates
      "not exact" and falls back to FREE — not a real preset, but confirms the ≤4-link chain model is a genuine,
      disclosed narrowing of what the old masked grid could express. Any real document likely to hit this shape?
- [ ] (accepted) the restart editor's chain-row button positions are computed proportionally from the real panel
      width rather than reproducing the ferry's own literal absolute reference pixels — consistent with how the
      rest of this page already scales.
- [ ] (accepted) the editor's timeline "current bar/pass" ring updates on the page's own existing re-render cadence
      (piggybacking on other TimelineViews already driving it), not a dedicated new timer — may lag slightly in a
      frame where nothing else on the page is animating.

## ★ EUCLIDEOUS — "FX tab (six fixed effect rows on the riff's steps)" — SHIPPED (2026-10-18; LANDED on `feature/fx-tab`, macOS 1701 green, iOS builds clean)
— a third tab FX after MIX and LANES: RATCH · GATE · TIE · VEL · NOTE · CC over the riff's eight columns, per-row lane sets, one decision function
(`euclideousFXApply`) that the Router, the TIE lookahead, the LANES roll and the flash all call. Every cell starts empty, so old sessions and
all 20 presets sound as before. LANDSCAPE ONLY. Full story in `Docs/euclideous-status-log.md`.
- [ ] DEVICE: see `Docs/euclideous-device-verification-debt.md`'s "FX tab" section (touch feel, axis lock, double-tap window, column alignment, RATCH / GATE 100
      / TIE / NOTE / CC by ear and on a MIDI monitor, flash, strip text fit, VoiceOver).
- [ ] DECIDE (Paul): PORTRAIT FX is NOT built — the spec's own stop condition: the portrait sequencer panel sits BESIDE the riff grid (so its columns can't
      line up under it) and is 248pt tall (< 273). The tab is hidden there. Give portrait a stacked layout + more height, or accept landscape-only?
- [ ] DECIDE (Paul): today's legato reconcile closed a held pitch that the NEXT hit re-struck at hit+10 ms — after the new note-on in stream order. I changed it
      to close at the hit's own sample (spec §4.2). Reachable today only with mixed per-layer gates or a gate edit mid-play; the 20-preset golden is unmoved. OK?
- [ ] DECIDE (Paul): FX GATE sets the effective gate of EVERY pitch in the hit (riff, lit notes, CHORD extras), and FX VEL sets the riff note to v and each lit
      note to v + (NOTES VEL − VEL) — the spec speaks of one lane GATE/VELOCITY, while the MIX ferry gave each layer its own. This is my reading; say if the lit
      notes should keep their own gate / ignore VEL.
- [ ] DECIDE (Paul): `drainEchoTails` could drop a deferred strike that landed exactly on a render-window boundary (the mask RATCHET and ECHO share it). Fixed by
      making the windows tile exactly — shared engine code, so it also changes 8×8 State's ECHO in that rare case (only ever to play a strike that was dropped).
- [ ] (accepted) the beat-width cap on RATCH uses the SCENE GRID's `cyc` (stepRate × columns), not the lane or the host bar — it only lowers n at slow grid rates.
- [ ] (accepted) `sampleOf` truncates, so an event exactly on a sample boundary can land one sample either side depending on its window (pre-existing, engine-wide).
- [ ] (accepted) an FX edit made between a TIE's triggering hit and the tied hit is invisible to the lookahead (spec §5.6): one extra strike or gap at that moment.
- [ ] (accepted) the flash draws only the later of two hits in one poll (`strikeEvents` keeps the latest per lane); TIE cells and BASE sends never flash.
- [ ] (accepted) the §15 determinism test (buffer 64 / 256 / 1024 + a transport restart) compares event-for-event within ONE SAMPLE, not bit-identical: `sampleOf` truncates a
      beat-derived sample, so an event exactly on a sample boundary can land one sample either side depending on its window — engine-wide, not FX. Rounding there would move every golden.
- [ ] (accepted) the flash's outer glow is a 10pt shadow cast from the 2pt ring; the spec's "2pt spread" has no SwiftUI equivalent — judge it on device.
- [ ] (small) RATCH ticks use a 4pt GAP between 2.5pt ticks ("4 apart" read as a gap), "RIFF" is right-aligned over the note-label column, and the double-tap
      window runs lift → touch-down. Say if any should differ.

## ★ EUCLIDEOUS — "LANES panel rebuilt as a per-lane mute grid with a live roll, plus separate rhythm and melody restart rows" — SHIPPED
(2026-10-18; LANDED on `feature/lanes-grid`, macOS green, iOS builds clean) — the LANES tab is four lane blocks of 16 cells, each on its own cell
size, with MUTE and RESTART sub-tabs, a roll of the lane's hits, a playhead per lane, and separate RHYTHM / MELODY restart marks. The old ON /
RATE / LEN, per-lane RESET boxes and the ring beside LANES are gone (hidden, not deleted; old fields stay decodable and are never written). One
per-tick core drives the Router, the TIE/gap lookahead, the walk-tag mirror, the comet, the footer baseline and the roll. Full story in
`Docs/euclideous-status-log.md`.
- [ ] DEVICE: see `Docs/euclideous-device-verification-debt.md`'s "LANES tab" section (tap/paint feel at 20 × 24 / 20 × 50, roll legibility,
      playhead vs sound, the 2pt-gap jump, legend fit, restart independence by ear, boundary close, the muted lane's card, VoiceOver).
- [ ] DECIDE (Paul): a NEW instance now has NO restarts (spec §1.3/§9.1) — it used to restart the riff every bar (`resetSteps = 1` for a fresh
      document). Right? (A never-edited saved session changes the same way; the 20 presets don't.)
- [ ] DECIDE (Paul): the migration picks the NEAREST unit to the old step, which is only exact when a lane's lap is a bar fraction; a lane with an odd
      lap (e.g. 3-of-5 @ 1/8) migrates to the nearest unit and sounds different. Fine, or hand-fix those in a one-off pass?
- [ ] DECIDE (Paul): a plain NOTE-mode CYCLE/RANDOM pick still counts from the RHYTHM origin — should a MELODY restart reset it too?
- [ ] DECIDE (Paul): portrait panels are 248pt tall, so the lane blocks shrink to ≈37pt (the spec's budget is 50pt) — give portrait more height, or accept?
- [ ] DECIDE (Paul): the roll cannot draw SHADOW lanes (pitch from the partner), an AVOID-muted pick or a FILL hit on a rank axis — they draw as rests. OK?
- [ ] (LEN ∤ 16 seam) a pre-feature LEN of 3/5/6/7 gets one short run at the 16-cell seam — accepted as inherent to a 16-cell window.
- (The "TAP = RESTART" hint DECIDE below is moot: the hold-RESET gesture it belonged to is gone.)

## ★ EUCLIDEOUS — "MIX tab (gate, velocity and octave for every layer)" — SHIPPED (2026-10-18; LANDED on `feature/mix-tab`, macOS
green, iOS builds clean) — the sequencer panel opens on MIX: eight XY pads (gate × velocity) + OCT steppers, per-pitch gate and per-layer
legato in the engine, `notesGate`/`notesVelocity`, per-touch undo. Also fixed: a lane's VEL never survived a session save/load. Full story
in `Docs/euclideous-status-log.md`.
- [ ] DEVICE: see `Docs/euclideous-device-verification-debt.md`'s "MIX tab" section (pad legibility, touch feel + two pads, 28pt OCT buttons,
      grey off state, per-layer legato vs a real synth, the tab row without its readout, and the portrait panel's 66pt pads).
- [ ] DECIDE (Paul): portrait pads are 66pt tall (the shared row is capped at 248pt) — below the ferry's 76pt floor in EVERY portrait layout.
      Give the panel more height in portrait, or accept?
- [ ] DECIDE (Paul): the "TAP = RESTART" hint (shown while a RESET box is held) left with the tab-row readout — redraw it inside the LANES body?
- [ ] DECIDE (Paul): GATE's slider goes down to 1% but the engine clamps GATE to 5% (SnapshotBuilder, pre-existing) — lower the clamp to 1%
      (and the notes gate with it)?

## ★ EUCLIDEOUS — "Fourfold settings (a gear, one sheet, three tabs)" — SHIPPED (2026-10-15; LANDED on
`feat/fourfold-settings-sheet`, macOS 1511 green incl. +12, iOS builds clean) — × replaced by a gear opening a
3-tab settings sheet (MIDI IN channel filter · MAIN OUT per-output channel + ALL NOTES OFF · CLOCK KEEP
PLAYING/STOP); × 's old job moved to the sheet footer's WORKBENCH link. Plan-mode-first per the ferry's own
ask — 4 research forks mapped every prerequisite before any edit. Full story in the status log.
- [ ] DEVICE: see `Docs/euclideous-device-verification-debt.md`'s "Settings sheet" section (7 items) — KEEP
      PLAYING/STOP against AUM's real transport and ALL NOTES OFF against a genuinely stuck note are the two
      with the most riding on them.
- [ ] DISCLOSED, not decided: STOP mode doesn't fully isolate Euclideous from a simultaneously-active 8×8-
      workbench free-run reason (ddSolo/staging/play) — Router's one process() call shares a single playing/
      beatPos across every row. Flagged as out of this ferry's scope (8×8 State on hold), not fixed.

## ★ EUCLIDEOUS — "Fourfold header (key pill, no ON, outputs that point at the lanes)" — SHIPPED (2026-10-15;
LANDED on `feature/fourfold-header`, macOS green, iOS builds clean) — ON chip gone (page always runs), one MIDI IN ·
CHORDS · KEY control + a key pill, MAIN OUT turned into output rings (tap pulses / hold traces / quarters flare on real
strikes), header regrouped BRAND · OUTPUTS · NOTES · UTILITIES with an A/B/C fit ladder from one pure layout function.
Full story in `Docs/euclideous-status-log.md`.
- [ ] DEVICE: see `Docs/euclideous-device-verification-debt.md`'s "Header (Fourfold…)" section (fit in AUM both
      orientations, tap-vs-hold, flare sync, popup anchors, fresh-instance-plays-at-once).
- [ ] DECIDE (Paul): should a fresh instance ship with lanes stopped now that nothing but lane PLAY/STOP and the rings
      can silence it? (Currently default lanes 1–2 play at once.)
- [x] RESOLVED 2026-10-15 (Paul): the five riff-grid walk-tag questions — timing log + tag/thumbnail lag accepted as built,
      stride cue = thread length only, GAPS (and WITH) lanes now get threads, footer fixed under LOCK + ADV STEP. See the
      status log ("WALK-TAG FOLLOW-UPS").
- [x] DONE 2026-10-15 (Paul approved): a FOLLOW lane's step bar + footer now draw the PARTNER's inherited pattern.
- [x] DONE 2026-10-16 (Paul): a FOLLOW lane's comet sweeps at the partner's rate × multiplier, its lit cells are the partner's
      colour (faded), and its bar gestures edit the partner. See the status log ("A FOLLOW LANE LOOKS AND FEELS LIKE WHAT IT
      FOLLOWS").
- [x] DONE 2026-10-16 (Paul): LISTEN remembers its partner (and ANY / per-mode settings) across off/on and mode swaps, on all
      three rows. See the status log ("LISTEN REMEMBERS ITS PARTNER").
- [ ] DECIDE (Paul): lighting FOLLOW zeroes the lane's OWN offset and turning it off doesn't restore it — save the lane's own
      offset when FOLLOW lights and put it back when FOLLOW goes off (one new saved field)?
- [ ] DECIDE (Paul): an unlit LISTEN row shows a plain "—" (the ferry's wording) — show the remembered partner faintly instead?
- [ ] DECIDE (Paul) — "similar clarity" for the OTHER listen modes (proposals in the 2026-10-16 reply): (a) SHADOW's footer
      still draws the lane's OWN riff step numbers although the engine ignores them (a bug, same class as the FOLLOW footer) —
      show plain partner-colour bands instead? (b) WITH/GAPS: mark which of the lane's own hits sound vs are silenced, and the
      partner's coinciding hits? (c) AVOID: flash a blocked hit as a partner-coloured outline? (d) DUCK/ACCENT: mark the
      coinciding cells (partner-colour top edge + faded/brighter fill)? (e) one at-a-glance "listening to" dot per row (R/P/L)
      beside the step-count badge?
## ★ EUCLIDEOUS — "per-step restart points on the LANES tab" — SHIPPED (2026-10-15; LANDED on
`feat/euclid-per-step-restart-marks`, macOS 1454 green incl. +14, iOS builds clean) — replaces the old
OFF/1/2/4/8 per-lane RESET with an 8-bit per-step restart mask, editable by holding a lane's RESET box and
tapping its steps. Reviewed against the raw ferry text before building; 3 findings (DRUNK already removed,
the TIE lookahead's reverse-derivation, the migration-layering subtlety) folded in rather than blocking. Full
story in CLAUDE.md's status log.
- [ ] DEVICE: see `Docs/euclideous-device-verification-debt.md`'s "Sequencer panel" section (6 items) — the
      two-finger hold+tap gesture is the one with the most architectural weight riding on it.
## ★ EUCLIDEOUS MELODY POP-UP — SHIPPED (2026-10-10; LANDED on `fix/euclid-no-scroll-direction-order-2x2-grid`,
macOS 1280 green incl. +12, iOS builds clean) — see CLAUDE.md's status log for the full writeup.
- [ ] DEVICE: the pop-up's layout in portrait/landscape (RIFF mode, NOTE mode, a case forcing the scroll).
- [ ] DEVICE: the anchored-popover mechanism — pointer lands against the tapped strip; above/below flip for
      lane 1 vs lane 4; the non-dimming tap-catcher reads as intentional.
- [ ] DEVICE: the 30pt tap zone catches a tap near the track without the track/note-box ever responding to one.
- [ ] DEVICE/EAR: STRIDE/LENGTH/ADVANCE/TRANSPOSE's feel, especially TIE+STRIDE+LENGTH+ADVANCE=STEP together;
      the LOCK+REVERSE starting-position reading (flagged as a judgment call, not confirmed intent).
- [ ] DEVICE: a fresh instance opens on SOURCE=KEY and NOTE=LOWEST now; the old 4th-pad SHIFT control and the
      new pop-up's own SHIFT stepper agree once LENGTH≠8.
## ★ EUCLIDEOUS — "rhythm cards cleared of melody; MISS becomes an invert" — SHIPPED (2026-10-10; LANDED on
`fix/euclid-no-scroll-direction-order-2x2-grid`, macOS 1283 green incl. +9/-3, iOS builds clean) — the §6
follow-up to the melody pop-up ferry above. Full story, incl. the `!isEuclideousRow`-guard correction (the
shared `missNoteSel`/etc. fields could NOT literally be deleted from the engine — they still serve the
regular, non-Euclideous BUILD-page EUCLID editor's own dual-voice feature) and the post-build self-review
that caught a real engine bug (a 0-pulse line was skipped entirely before `patternMiss` could invert it, 
contradicting the ferry's own "0 hits in MISS plays every step" example), in CLAUDE.md's status log.
- [ ] DEVICE: one lane in HIT and MISS mode side by side — the step bar's outlined-silent/filled-sounding
      split and NOTE VIEW's inverted comets, no hollow rings or outline-style boxes anywhere.
- [ ] DEVICE: the slimmed 3-pad, 3-tab (I/O·PATTERN·MASK) card in portrait and landscape — the 3 remaining
      pads visibly widen to fill the space the 4th vacated, no dangling gap where the source badge/selector sat.
- [ ] DEVICE: the restyled HIT/MISS control reads as a persistent setting (LANE-20/LANE-100-border), not the
      old underline view-style.

## ★ EUCLIDEOUS — "Euclid mask, modes and settings" — SHIPPED (2026-10-10; LANDED same session as the riff-
cell-wipes ferry — see CLAUDE.md's status log, "the mask-modes ferry was found fully built and tested, carried
forward as-is, verified green"). This pending-tasks entry had gone stale (still said PLANNING/not-started) —
corrected here. All 11 modes (MUTE/PAUSE/RATCHET/REPEAT/CHORD/OCT/MIRROR/LEAP/CLIMB/ACCENT/SWELL) + CHANCE +
the 2-line MASK tab are built. DEVICE-eye/ear owed (not yet separately re-confirmed since landing).

## ★ EUCLIDEOUS — "sequencer panel, four riffs, per-lane reset" — SHIPPED + SELF-AUDITED (2026-10-14; LANDED
on `fix/euclid-no-scroll-direction-order-2x2-grid`, macOS 1417 green incl. +11 total, iOS builds clean) — full
writeup in CLAUDE.md's status log (two entries: the original build, then the audit-and-fix pass). NOTE VIEW
panel replaced by a two-tab SEQUENCER panel (LANES/RIFFS); RESET moved machine-wide→per-lane (now correctly
on the LANES tab, see below); the single riff became four tabbed riffs with long-press copy/paste/clear.
**A FOLLOW-UP SELF-AUDIT against the ferry's raw text (not the plan's own paraphrase) found + fixed 10 real
shortfalls** — 1 genuine engine/audio bug (the per-lane reset didn't re-anchor relative to the LANES
sequencer's own LEN, only invisible because the shipped default LEN=8 happens to divide every reset option
evenly) + 9 missing/mis-positioned UI elements (the RESET control was on the wrong tab entirely; the grids
reflowed to LEN columns instead of staying a fixed 8-wide grid dimmed past LEN; walk arrows weren't hidden
when editing a non-playing riff; no STEP-N-OF-LEN status, per-tab ON/OFF dot, RIFFS per-row label, "NOT
PLAYING" label, or column-number header; the title/tabs/NOT-PLAYING weren't sharing one row) + several
colour/sizing deviations (restart-mark shape/colour, RIFFS lit-cell fill, the ON/OFF fill-flip, RATE/LEN
stepper proportions). All fixed; +2 tests locking in the one real audio-correctness bug specifically.
**A THIRD PASS, "fixes after the sequencer build" (design-channel ferry, 5 numbered items, 2 of them Paul's
own fixes not corrections) — LANDED same day, macOS 1417 still green (pure UI, no new tests), iOS builds
clean.** §1 the data rows used a genuine ZERO inter-row gap (not ~1pt) — rows now have a real gap + the
controls row grew from ~34pt to the ferry's own 44-equivalent + the current-step highlight now spans the
header row too, not just the 4 data rows. §2 "RESET" was truncating to "RES…" (SwiftUI single-line-truncates
once it can't fit a 2nd line vertically, even with no explicit lineLimit) — fixed via `.fixedSize` + removed
letter-spacing. §3 the editing riff tab's own selected-look was a thin translucent outline (fixed to a flat
`#DFE3EA`/ink fill-flip) and the shared `riffOutlineBars` had its colour hardcoded to white regardless of
background (gained a `tint:` param so the tab row and the row-label can each use the right colour for their
own background). §4 (Paul's own fix) every slider's value/label text now sits on a small opaque backing so
the value line can't visually cross it. §5 (Paul's own suggestion, explicitly unratified in his own ferry
text) — an OFF sequencer's grid/row-labels now dim to 42%, tabs/step-numbers/ON-OFF stay full strength.
- [ ] DEVICE: the sequencer panel's proportional (not pixel-exact) grid sizing at real card width.
- [ ] DEVICE: the per-lane RESET box's new position (now on the LANES tab itself) + its popup's legibility.
- [ ] DEVICE: the riff-tab row's mini-grid icon (REPLACED the bar-chart preview, see the icon-redesign entry
      below) + play-triangle + long-press timing/feel.
- [ ] DEVICE: confirm the removed header RESET countdown isn't missed before the per-lane control is found.
- [ ] DEVICE: the restart-mark bar's legibility at real cell height; the ON/OFF toggle's new fill-flip
      contrast; a LANES/RIFFS LEN away from 8 (now engine-correct + test-covered, but never visually checked).
- [ ] DEVICE: the row-gap/controls-row-height fix actually reads as 4 distinct rows now, not merged.
- [ ] DEVICE: confirm §5's 42%-dim-when-off reads as helpful, not a nuisance — **Paul to confirm/ratify**,
      his own ferry text marks this one as a suggestion, not a settled ruling.
- [x] `activeRiff`'s dual edit/play role — **RATIFIED by Paul (2026-10-14): "yes, that's right."** No change.
- [x] TIE lookahead freezing the triggering hit's own riff selection (not re-resolving per future tick on a
      RIFFS-sequencer switch) — **Paul: leave as built for now, revisit once actually heard.** No change.
**A FOURTH PASS, "engine fixes from a recorded clip" (design-channel ferry, 3 items from a device recording) —
INVESTIGATED same day, macOS 1420 green incl. +3 regression tests; NO PRODUCTION CODE CHANGED for 2 of the 3
items — a thorough investigation that came up short of a confirmed fix, not a fix-and-ship.** Full writeup in
CLAUDE.md's status log.
- [ ] §1 PER-LANE RESET "only every 4 bars" — core mechanism CONFIRMED CORRECT by both reading and 3 new
      empirical RouterTests at the exact repro parameters (all pass). The one concrete hypothesis that WOULD
      exactly reproduce the symptom: `euclideousLanesSeqRate` resolving to `.fourBars` instead of `.oneBar`
      — but every write/resolve path checked reads `.oneBar` correctly, so the real cause is unconfirmed.
      **NEEDS FROM PAUL:** watch the sequencer panel's own "STEP N OF LEN" readout while playing — does it
      advance once per bar, or once every 4 bars? That single observation pins this down either way.
- [ ] §2 MIDI TIMING "quantised to the buffer" — traced the complete emission pipeline (Router's `sampleOf`,
      `iterateTicks`, `strikeChord`, `PartTap`/`ReelTap` pass-through, `LiveMIDIEmitter` pass-through) and
      found the EXACT fix the ferry asks for already built and used throughout — could not find a bug
      matching the symptom in this codebase. May be host-side (AUM) behaviour, not ours — only an actual
      device recording at both buffer-size extremes (as the ferry's own ack already asks) can tell.
- [x] §3 TILT "no effect at −16% on E(3,8)" — **CONFIRMED EXPECTED, not a bug**, by re-deriving the exact
      formula: the shift magnitude at 16% doesn't cross the rounding boundary for a pattern this sparse (the
      last hit needs >30% tilt before it moves at all). A genuine "dead zone" for small tilts on sparse
      patterns, worth knowing, not a defect.
**A FIFTH PASS, "riff icon redesign" (design-channel ferry) — SHIPPED same day, iOS builds clean (pure UI, no
macOS test-target reach).** The bar-chart outline (`riffOutlineBars`) is RETIRED entire, replaced by a new
`riffMiniIcon` — a literal, fixed 31×23pt mini riff grid (8 steps × 8 ranks, note marks + dots, rest = a
dotted column) used in both the riff-grid tab row (now a ONE-LINE layout: triangle+number, 8pt gap, icon —
replacing the old two-line layout) and the RIFFS-tab row labels. Full writeup in CLAUDE.md's status log.
- [ ] DEVICE: the new icon's legibility at its fixed 31×23pt size in both placements, with a riff that has
      rests and an empty riff, exactly as the ferry's own acknowledgement asks for a screenshot of.
- [ ] DEVICE: confirm the fixed (non-scaling) icon width doesn't overflow a real, possibly-narrow tab —
      flagged as a genuine risk, unlike the old bar-chart which stretched to fit its container.
- [ ] §10 (where do silence messages go) — **Paul: not decided yet, leave the stub as is.** Still open, still
      un-built; don't invent an answer.

## ★ PASSGATE — REMOVED ENTIRELY (2026-09-28; LANDED on `refactor/remove-passgate`, `2839240`, macOS 1142 green, iOS
builds). The processor + its engine plumbing are gone; `ProcessorType.empty` is now purely the internal empty-chain-
slot sentinel (never user-addable). Factory scenes renumbered 10-16→9-15 (scene 9 cut, not replaced). Full story in
CLAUDE.md's status log.
- [ ] DEVICE: confirm no chain anywhere still shows a "PASSES" card.
- [ ] DEVICE: an old saved doc with a real PASSGATE cell opens as a silent inert passthrough (not a factory-reset/
      decode error).
- [ ] DEVICE: factory scene 15 PACIFIC — "wine" now sustains continuously instead of alternating every 2nd pass
      (its old mechanism no longer exists); confirm this reads as acceptable, not a regression.
- [ ] FLAGGED, not done: `midispark-spec-v2.8.md`/`v3.0-delta.md` still describe PASSGATE's pass-mask behaviour in
      several places — a separate spec-contract reconciliation pass, if wanted.

## ★ KILL STEP — a new TIME processor, sibling to CLOCK (2026-09-26; LANDED on `main`, engine+UI+tests, macOS 1121
green, iOS builds) — see CLAUDE.md's status log for the full writeup (the shape: reuses CLOCK's driver-retiming
plumbing, generalized to detect `.killStep` slots too, so it reaches the WHOLE generator roster CLOCK already does
with zero new call sites).
- **DEVICE-EAR/EYE OWED (nothing built yet has been heard/seen):** the 4-state matrix feel (below), the RATE/SPAN/
  PAUSE LEN controls, and — most importantly — the actual sound of "steps 1–4 of 8 ON → the first half repeats", "3
  of 8 ON → it rotates against the bar", a MUTE'd step leaving a clean silent hole, and a PAUSE reading as a hold/
  breath. Confirm against Paul's own worked examples first.
- **LIVE PLAYHEAD, now table-driven (2026-09-27):** `stateMatrixRadio` gained an optional `liveColOverride:
  ((Date) -> Int?)?` hook (nil for every other existing caller — unchanged, replacing the retired `toggleLane`
  row's own `live:` hook of the same shape) — KILL STEP's row calls `Derivations.killStepPhase` directly (the SAME
  function the engine folds through, via the SAME shared `killStepResolveTable`) to compute the highlighted index,
  so the lit cell and the audible step can't drift apart. Still DEVICE-eye owed.
- **✅ MUTE + PAUSE — LANDED (2026-09-27, `f35b595`; macOS 1134 green incl. fuzz).** The one boolean row is now a
  4-state `KillStepMode` (ON·MUTE·DROP·PAUSE) — see CLAUDE.md's status log for the full writeup. **FLAGGED, not
  built (scope, not a bug):** MUTE only has an effect when KILL STEP PRECEDES the driver it retimes
  (`[KILL STEP→ARP]`); in the `[ARP→KILL STEP→DEST]` shape there's no note-generation event left at KILL STEP's own
  position to suppress, so MUTE is a no-op there (DROP/PAUSE work in both positions).

## ★ PER-PARAM LFO + ARP EUCLID MASK (2026-09-15/16; spec `Docs/PLAN-param-lfo.md`)
LANDED on `main`: the ∿ LFO button (engine + UI) on ARP LENGTH · HITS/ROTATE/CHANCE · the GAPS=CHORD gap-stab
controls (OCTAVE · LENGTH · VELOCITY) · the SPEED/rate LFO with INCLUDE-family toggles (NORMAL/DOTTED/TRIPLETS) ·
and the FROM→TO→DURATION→WAVE **editor redesign** (FROM is two-views of the base param; depth/phase/quantize
dropped, `paramLFOValue` removed). The MOD editor was reworked to the same FROM/TO/DURATION/WAVE anatomy (`383ca9c`).
OPEN:
- **✅ EUCLID MASK — GENERALIZED INTO A STANDALONE DOWNSTREAM PROCESSOR — LANDED (2026-09-27, on `main`, `d6bb40d`;
  macOS 1116 green incl. fuzz, iOS builds; DEVICE ear/eye owed).** See CLAUDE.md's status log for the full writeup.
  Pulled GAP (REST·TIE·CHORD) + ROTATE out of ARP-only fields (`arpMask*`) into a new `ProcessorType.euclidMask` —
  a non-driver fold (`isModifierFoldable`) that gates ANY driver (RIFF, STRUM, RATCHET, EUCLID-as-driver, etc.), not
  just ARP. WAIT was DROPPED (Paul: "I'm happy to drop wait as an option") — it belongs to the CLOCK/KILL-STEP
  upstream beat-transform family instead, which would need the opposite chain position. ARP's own `arpMask*`
  fields/editor are untouched. +7 RouterTests + fuzz coverage. Plan: `~/.claude/plans/stateless-tickling-flask.md`.
  **✅ THE REMINDER THIS TRIGGERED WAS ACTIONED (2026-09-27):** KILL STEP DROP/MUTE/PAUSE — see the KILL STEP entry
  above and CLAUDE.md's status log; the memory file `euclid-mask-then-killstep-followup.md` can be deleted.
- **✅ ACCENT LAYER + FILL + INVERT + SPAN + PROBABILITY + CHORD PICK — ALL LANDED (2026-09-28, `2a54d5d`; macOS
  1140 green incl. fuzz).** See CLAUDE.md's status log for the full writeup. ACCENT is a second, independent K-of-N
  pattern boosting velocity on its own hits, exactly as pencilled in here. DEVICE ear/eye owed on the whole set.
  **✅ CHORD PICK extended with BOTTOM2/TOP2 (2026-09-28, `9d38406`; macOS 1141 green)** — a new dedicated
  `MaskChordPick` enum, not a reuse of `EuclidPick` (see CLAUDE.md status).
- **∿ LFO roll-out:** RIFF RATE (the rate-grid endpoint is arpRate-specific — generalise it), WEAVE LENGTH + OCTAVES,
  and other processors' continuous params (RIFF GATE LENGTH already has it).
- **DEVICE-EYE owed:** the ∿ buttons + the popover editor; the CHORD-stab controls; the long HITS label row not
  crowding its button; the MOD/RIFF/DEAL editors + the live CC marker.

## ★ RECORDER — the looper-in-a-chain (spec `AcceptanceCriteria-recorder.md`; stages 0–4 BUILT on `main` `87934e5`…`09d690a`)
BUILT: the driver-fed recorder — GRAIN passes|steps · LENGTH · ARM on-play|after-N · MODE LOOP/FREEZE(held·repeat)/CANON ·
MIX replace|layer · CAPTURE once|refresh · the persistence READ/CLEAR half (authored/persisted `recEvents` seeds the loop).
No stuck notes (fuzz + `testRecorder*`). DEFERRED (device-ear owed on the whole feel):
- **★ SAVE drain (the big one):** the live-capture→document handoff (render→main), so a loop RECORDED in a session
  persists to disk. The render↔main boundary is the crash-prone class — do it WITH device/host verification. Until then a
  session's live recording is lost on reload (re-records on next play); authored/loaded buffers already persist + play.
- **Standalone/hold-fed recorder:** a `[RECORDER]` with no upstream driver doesn't REPLACE-suppress (the identity hold
  layers over the loop) — needs a hold-path capture, not just the driver fold.
- **FREEZE-HELD true legato:** v1 re-pulses the frozen pad per loop; a real sustain wants the immortal-hold reconcile.
- **CAPTURE HOLD:** the momentary "grab a new take" button needs a control signal (behaves like ONCE now).

## ★ PLAY-FERRIES-ARE-PARTS — follow-ups (2026-09-08; feature DONE Phases 1–3, on `main`)
The 8 play ferries are now full `BuildPart` slots + the sole navigation (spec `AcceptanceCriteria-play-ferries-as-parts.md`).
OPEN:
- **DEVICE-OWED (the whole ferry UX):** ferry switch, up-to-8 simultaneous play (active via staging / background via
  flatten), edit-write-back, CLEAR-empties-ferry → SELECT, 16-step tiling, and the ADD-A-ROW menu
  (Duplicate/Mutate/Randomize/Create-new/Pick-from-Library on an empty part row).
- **DEVICE-OWED — FERRY DRAG-AND-DROP (2026-09-12, on `main`):** the whole drag feel — SELECT cell→ferry populate (name +
  colour inherited), ferry→ferry move/overwrite, ferry→machine-box trash delete; the floating ghost, the hovered-ferry cyan
  ring, the trash reveal on a ferry drag; the empty-slot colour REALLOCATION on a real 8-ferry palette. Spring-momentary
  play coexists with the drag (a SPRING ferry could briefly play as a drag starts — verify). (Replaces the retired
  long-press seed/copy.)
- **DEAD-CODE SWEEP 2026-09-12 (DONE, on `main`):** removed a whole-tree batch of grep-verified orphans —
  `buildArchivePartToPlay`/`buildClearPartGrid`/`buildSelectPlayColumn`/`buildStagingTap`/`buildAddCastMachine`/
  `buildPlaceCastSlot`/`buildRhythmDriverSlot`/`buildFocusedChain`/`partCellFill`/`partCellFrame`/`roomsPlayNavSliver`/
  `roomsSelectButton`/`roomsVerticalPlay` (BuildPage) · `roomsAssignPlayColumn`/`roomsFlattenPartToPlay`/`roomsStampSourceIO`
  + the stamp-copy cluster (earlier 2026-09-12 commit) · `Dice.fRole` · `DragDropPage.ddMachineCellsPublic`/
  `ddApplyStickyRoutingMutation` · `MidiSparkAudioUnit.saveCellToLibrary` + 3 UI mark-feed poll wrappers ·
  `Router.hasDuplicateVoices` · `@State buildPlayFerryRow`/`brush` · the whole `GridMacroBand.swift` file.
- **DORMANT CLUSTERS (flagged, NOT a live bug — investigated 2026-09-12):** ① `buildSelectMode` + its ~readers — the
  only thing that armed it (`roomsSelectButton`) was removed, so SELECT-mode is inaccessible; the readers are a harmless
  dormant cluster. ② `editArmed`/`editingCell` — `editArmed` is never set true → `editingCell` is always nil → the
  DragDropPage edit reads (`DragDropPage.swift:11,60`) are dead; this is the OLD edit-page machinery superseded by rooms.
  ③ `buildPlaceArmed` — never set true → `buildExitPlaceMode`'s body is a permanent no-op (PLACE-mode arming UI was
  removed); `buildExitPlaceMode` is still called from 5 live sites (kept — PLACE may return). All three want a dedicated
  DragDropPage/rooms-legacy pass, not a piecemeal removal. (`buildStopAllOnTransportStop` — the old "stop de-arms all"
  handler — was confirmed superseded by `buildTransportEdge` and REMOVED in the sweep; not a bug.)
- **✅ DEAD-CODE SWEEP A1–A5 DONE (2026-09-17, on `main` `40209bd`…`6a307b7`; iOS builds, macOS 1078 green):** removed
  ~640 lines of confirmed-dead UI + the test-only pure cluster: **A1** the retired AUTO/macro-authoring panel
  (`autoSpanColumn` + 15 helpers + the inert span-draw guard + `buildPartDragAnchor`); **A2** the ROW 8 edit page
  (`buildRow8EditPage` subtree + AU `setRow8Cell` + `buildRow8EditOpen/Slot` — kept the live `Row8Cell`/`buildRow8On`/
  `setRow8On`/engine/persistence); **A3** the `.play`/`.reel` rooms (enum cases + `roomsPlay`/`roomsReel`/`navDoor`/
  `roomsPlayGrid`/`roomsPlayCell`/`roomsPlayBottom`/`roomsPlayStartStop`/`roomsDoorBar`/`roomsDoorInk`/`buildTogglePlayColumn`/
  `buildColumnButton`); **A5** orphaned `@State` (`buildReturnPart`, `buildGridSelQuantStep`) + vestigial `workingPart` +
  `Snap.morphMaster`/`morphMasterResolved`; **A4** the 16 test-only pure fns + their 38 tests (laneValue/modCCValue/
  columnSweepFraction/sealFit/voiceLeadTowardPrevious/poolStep/swapCells/libraryStripped/loadLoop/unpackPlayCell/
  selectedRungs + the macro-authoring cluster). KEPT LIVE (do NOT remove): the play-ferry state/logic (`buildPlayColOn`,
  `buildSetFerryPlay`, `buildTogglePlayGrid`, `buildPlayCells/Sel/…`), the reel OVERLAY (a separate live pop-up), and
  `buildAutoActive`/`buildAutoInExtent`/`buildAutoLanesFor` (live inert-returning reads).
- **STILL OPEN — survey-flagged standalone orphans to RE-verify (NOT part of the A1–A5 sweep; some may now be live):**
  `buildSetPartRate`/`roomsGridCellW`/`roomsPartPianoRoll`/`roomsPartMacroSection`/`buildAddCastColour` + `@State buildRowMode`;
  possibly-now-orphaned `buildSelectedPlayCol` (was play-grid I/O reflection). Also the now-unused MacroAuthoring types
  (`MacroSlotBinding`/`MacroControlGroup`) left by the A4 macro-fn deletions. (`buildGridSelDriftFace` is RESERVED — "the ferries keep it".)
- **PICK-FROM-LIBRARY (add-a-row):** currently opens `buildOpenLibrary` (the browser); may need a row-targeted placement so the
  picked chain lands on the empty row directly. Also DUPLICATE copies the chain, not the register-home transpose.
- **GRID FOOTERS are PLACEHOLDER, not wired** (SELECT=pages · PART=column-loop) — reserve-space only; behaviour unbuilt.
- **VELOCITY processor:** DEVICE ear owed; the SCALE compressor MODE (floor/ceil/curve) is deferred (only the PATTERN lane shipped).

## ★ PROMOTE ARCHIVES THE PART GRID → RESTORE is UNBUILT (2026-09-05) — ⚠ LIKELY SUPERSEDED by play-ferries-as-parts
Promoting a part/cell from the part grid now stores a `BuildPartSnapshot` of the WHOLE grid on the play column
(`buildPlayColPartSnapshot`) and CLEARS the grid (CLAUDE.md status). **NOTE (2026-09-08): the play grid was re-architected —
each ferry IS a `BuildPart` (`buildFerryParts`, persisted) and per-cell play cells retired, so this promote/archive/restore
model is probably obsolete; the "re-entering a ferried part" + "editing cells on the part grid" concerns below are resolved
by the ratified playback model (active→staging, background→flatten, live edit-write-back). Reconcile/close on review.** OPEN:
- **RESTORE** (the point of the archive) — a way to bring a play column's stored part snapshot back into the part grid. UI +
  action unbuilt.
- **PERSISTENCE** — the snapshot is in-memory `@State`; to survive save/load it must ride the play grid's `BuildPlayGridData`
  (needs `BuildPartSnapshot: Codable` + the ephemeral colours it references). Do this WITH restore.
- **DEVICE:** confirm the archive+clear feel; whether a single cell-ferry from a part row should clear the WHOLE grid (current)
  or be exempt; the null-I/O pulse on the next select cell.

## ★ FOUR SCALE POOLS + THE CHORD SEQUENCER DOOR — both BUILT (2026-09-05); DEVICE eye/ear owed
Spec `Docs/SPEC-four-scale-pools.md`. SCALE (4 radio pools) + CHORD (`DoorMode.chord` — a chord SEQUENCER reusing the
CHORDS processor's config/editor/engine; time-varying pool; 4 default progressions; default rig C→D) both built end-to-end
(CLAUDE.md status; iOS builds, macOS 1057 green). OPEN:
- **DEVICE:** verify the live radio switch is heard (SCALE + CHORD); the CHORD sequencer actually walks on the beat (+ the
  free-run interaction when stopped); the mounted ProcessorBox editor renders cleanly in the door pop-up (legibility/sizing);
  the SCALE/CHORD strip amber self-arm visual (pre-existing); whether the strip label should show more.
- **CHORD follow-ups (flagged, not built):** FOLLOW on a door → wire the door's play-along live input to name the degree
  (v1 sits on the tonic); a matrix PLAYHEAD in the door editor (liveStep from the beat); voice-leading (INVERT) between
  progression steps; per-instance labels naming the progression (currently "SEQ 1–4").

## ★ SPAN-ONLY PART AUTOMATION — Phase 1 + Phase 2 LANDED; only CC-prominence still parked (2026-09-05)
Phase 1 (step spans, drag-to-draw, default-on-arm, compile-time bake) DONE (`ad9fb75`+`97038c7`). **Phase 2 (render-time
×N passes + STEP|SMOOTH) LANDED** (`50159b8`+merge `c6ab8fb`; iOS builds, macOS suite green): `AutoLane.spanPasses`/
`smooth` → `AutoParamField` (24 scalar targets) + `SnapParams.settingAuto` + `SnapshotBox.renderAuto` (builder populates
for an active render-time lane) → `Router.applyRenderAuto` overrides the cell's proc at emitTickRow + emitColumnHolds
(STEP = integer column rank, endpoint-inclusive; SMOOTH = continuous sawtooth); STEP/default spans stay the Phase-1 bake.
UI: ×N live + mutually exclusive with the 1–8 ladder + a STEP|SMOOTH row (SMOOTH continuous-only; ×N/SMOOTH greyed for
nested params). +6 RouterTests + AutoParamField/settingAuto clamp tests. Plans: `PLAN-span-automation.md` +
`PLAN-span-automation-phase2.md`. STILL OPEN:
- **★ CC FRONT AND CENTRE — PARKED (Paul's carve-out, NOT built).** Make automating a CC (a MOD stage's MIN/MAX) a
  PROMINENT, early choice in the PARAM row — a SMOOTH CC ramp is the marquee use case (CC read continuously → a true
  controller sweep). Design elaborated 2026-09-05: default CC 74 when auto off · spans/passes carry a SHAPE/waveform
  (linear/sine/tri/saw/S&H/draw; ×N = bar-synced LFO) · power-edit ideas (draw-the-curve · waveform chips + rate ·
  per-step value lane · punch-in hold-islands · named-CC picker · multi-lane mod matrix); route A = MOD-backed reuse.
  Plan §11. Consider a one-tap "automate CC" that arms a MOD-min/max lane in SMOOTH.
- **RENDER-TIME v1 LIMITS (flagged, not blockers):** SMOOTH is sampled once per render window (block-start, like
  applyInternalMods — deterministic per host schedule, not strictly block-size-invariant); the render surface is
  SCALAR-only (nested params stay step-bake); per-part-clock / 16-wide parts use the SCENE beat for the pass math
  (exact for the uniform 8-wide default).
- **DEVICE-EYE (owed, both phases):** the drag feel; default-on-arm; the amber tiling highlight; the STATE ramp/playhead; the
  fixed tab-dot + CLEAR; the two-column proportions + the SPAN 30% column legibility.
- **2 SMALL UI CALLS (Paul, on glass):** (a) the "AUTO N" highlight tiles the WHOLE row — keep, or mark only the first
  span? (b) the drag reads a column range from ANY row (1-D) — confirm.
- **MINOR DEAD CODE:** `AutoLane.span` (legacy) now fully unused; `cells` survives only for the load migration. Drop in
  a future verified sweep once old docs are unlikely. ALSO (housekeeping 2026-09-07): `holdCaptureDecision` + the `HoldCapture`
  enum + their ~10 `DerivationsTests` assertions are DEAD in production since the HOLD mirror-and-freeze rewrite (`4549d2e`) —
  KEPT for now (test-documents the old detect-replace model; may be needed if mirror-and-freeze is reverted after device
  verification). Also the dead-but-tested pure cluster `laneValue`/`voiceLeadTowardPrevious`/`peakHoldLevel`/`triggerMark`(+its
  glyph helpers)/`poolStep`(array wrapper) — reserved/held-for-rebuild, remove only in a coordinated cull with their tests.
- **★ DECODE-SAFETY HARDENING (housekeeping 2026-09-07, MEDIUM preventive — NOT an active bug):** the three CENTRAL persisted
  types `Colour`/`SceneState`/`Receiver` (stored directly in `PluginState.colours`/`scenes`/`receivers`) still lack a
  decode-tolerant `init(from:)` and each has non-Optional stored fields. Per the CR-8 mechanism the codebase documents, ADDING
  any non-Optional field to any of them = a whole-document factory reset. `Cell`/`Macro`/`BuildPart` etc. already got the
  tolerant-init treatment; these three are the highest-value remaining. Do it carefully (byte-identical encode; decodeIfPresent
  + memberwise defaults; + round-trip & missing-key tests). Leaf structs in PluginState arrays/dicts (`MacroCellValue`,
  `MacroTarget`, `ScalePool`, `MidiFile.NoteEvent`, `ProcessorSlot`) are the same latent class — Optional-only additions or a
  tolerant init keeps them safe.
- **HOLD — DEVICE EAR OWED + Finding 3 (housekeeping 2026-09-07):** mirror-and-freeze (`4549d2e`) — a sustained/chatty source
  must NEVER leave HOLD silent on a pass; verify on device. The cog HEALTH `PLAY`/`SND` + per-door `LIV`/`FRZ` stats (`90cc1dc`)
  are the bisect. FINDING 3 (deferred, MED): under `ignoreAllNotesOff` the LIVE pool isn't cleared on a transport stop, so a
  CC123-ONLY source (no per-note offs) re-sequences dead notes on the next play — the sustained-input case self-clears on real
  release; a stop-edge `pool.reset` would break free-run-on-host-stop, so it needs a guarded fix, not a blind one.

## ★ OVERNIGHT BATCH 2026-09-03 — landed + FLAGGED deferrals (needs Paul / a dedicated pass)
Seven queued jobs LANDED (`9010ca1`…`64330ae`; macOS 1023 green; see CLAUDE.md status). What's DEFERRED, and why:
- **JOB 5 — 16-wide ROW-span processors (SEMANTIC, needs Paul).** In a 16-wide part, ROW-span procs (tutti/length,
  the 8-slice patterns) use the 8-wide bar → they repeat every 8 columns (polymeter). Making them span the FULL part
  width (16) is a behaviour choice — polymeter vs full-span. NOT built (Paul rules which).
- **JOB 6 — CHORDS invert-toward-previous (NEEDS A DESIGN CALL).** `voiceLeadTowardPrevious` is pure + tested, but
  wiring it means voice-leading each chord toward the previous → PATH-DEPENDENT, which fights the "derived, never
  accumulated / replay-exact" rule (for FOLLOW it's genuinely cross-render memory). Needs Paul's ruling on the
  accumulated-state exception. NOT built.
- **CHORDS render-path allocation (MED, invariant 3; bug-hunt B#1 + refactor A).** `applyStage`/`emitColumnHolds` `.chords`
  allocate per fold: the PATTERN `(0..<steps).map` (Router ~3718) + `diatonicChord`'s internal arrays (Derivations ~686).
  The sibling harmonize case is hand-unrolled with fixed buffers. Fix = pre-allocated scratch through diatonicChord +
  chordsDegreeAt-takes-raw-array. Perf/invariant, NOT a functional bug — a focused tested pass (don't rush).
- **16-WIDE sounding/solo MASK widening (LOW, cosmetic/16-wide; bug-hunt A#2/A#3).** `snapshotCellSounding` (2×UInt64=128)
  + `cellSoloedOut/Forced/tapMuted` (`col*8+row` into UInt64) don't cover cellIndex 128–255, so a 16-wide part's cols
  8–15 drop from the SEAL feed (no light) and get force-silenced under PLAY-THIS-CELL solo. No crash (smart shift → 0).
  Widen to 4×UInt64 / a fixed [UInt64]. Device-owed (the 16-step grid is device-owed anyway).
- **editMode / EditPageMode residue (dead-in-effect, deferred by job 4).** `editMode` is a constant `.addEdit`; the
  `.move/.mute/.clear` cases are unreferenced. Left because removal touches the live `syncSingleModeActivation` guard for
  marginal value — a dedicated pass.
- **AVOID §G editor seg + OUTPUT-ref piano (DEVICE-owed).** The engine (`.soundingOut`) landed job 7; the LISTEN-TO seg
  (offer the OUTPUT domain: IN ▸ · EVERY IN · OUT ▸ · EVERY OUT) + the OUTPUT-ref illustration piano (needs a per-emitter
  output feed to stay honest) are device-owed — .soundingOut is engine/fuzz/test-reachable but not yet user-selectable.

## ★ HOUSEKEEPING FLAGS — 2026-09-01 (surveyed + verified)
- **✅ DONE — BIG DEAD-CODE CASCADE (`7b9d160`, ~820 lines):** removed the orphaned `GridView` (0 instantiations) + its
  subtree + the GridView-only seal render island + GridGeometry + accentCyan/cellBg/cellEdge (GridUI −604); the `flowDiagram`
  render subtree + the DIN-icon cluster (EditPage −211); the dead `DDZonePref`/`ddZone` (DragDropPage). `GridPos` was EXTRACTED
  to a standalone top-level struct (still used by EditSelection + colour-scope helpers). Per-symbol verified — the survey's
  cascade list was imprecise (cellChain is live via the AU; DragDropPage is mostly the live shared colour cluster). iOS builds.
  (Left: `armLadderRung` (VC) + its ladder-cluster callees — a separate small cluster.)
- **✅ DONE — BUG-HUNT Finding 4 (`9047463`):** MONO voice-steal now calls `forgetGlideAnchorAtSlot` when it closes a glide
  anchor (re-centre bend + clear the GlideVoice) so a reused slot can't be wrong-closed; +1 RouterTest (glide+MONO+steal path).
- **✅ DONE — PER-ROW ENGINE TEST GAPS (2026-09-01, +4 RouterTests):** (1) fixed the FALSE-POSITIVE lap test
  (`testPerRowLapLoopsEachRowsOwnColumns` — now a 16-entry `rowLane` + a discriminating "a col-off-the-lap cell stays SILENT"
  assertion the old uniform-sweep path would have failed). (2) `testPlayLayerRowsRunOnTheirOwnClockWithoutLeak` (a cell in
  engine rows 8–15 renders on its own clock — first coverage). (3) `testOnlyRowLegatoDroneSurvivesAFastNeighbourRow` (a slow
  legato drone strikes ONCE per note, adopted, while a fast neighbour row transitions — the onlyRow scoping). (4)
  `testPerRowGlideAndModFireOnTheRowsOwnClock` (fast row's glide re-anchors more; both rows' MOD emit independently). The
  clock-mode-switch #5 was already covered by the 2026-09-01 glide/mod-switch fix's test.
- **DOCS — "needs-Paul" removals (agent-flagged, left to avoid dangling refs):** cited spent plans (PLAN-presentation-redesign,
  implementation-plan-btw-authoring, implementation-plan-cells-and-colour-desk, AcceptanceCriteria-emitter-page-pass1) + the
  dedupe pairs (scenes-v2-multigrids ⟷ AC-scenes-v2; INSTRUCTIONS-room-palettes ⟷ AC-room-palettes; OPEN-listening-set ⟷
  design-listening-set) + "surface-retired" banners on the ~15 retired-era AcceptanceCriteria/design-ferry docs + the ~12
  landed SPEC-/FERRY- headers. All keep-as-history unless Paul says delete.
- **AUTO-RUN (`618eac5`) — DEVICE EAR:** cog → DEV → "▶ AUTO-RUN" should play a musical chord loop by itself (free-run) and
  leave nothing stuck over a long soak; the os_log `autorun` heartbeat + STUCK oracle report in Console.app.

## DEVICE-OWED (2026-09-01) — Tide & Ember colour scheme + housekeeping + reveal + unification inc.1 (landed `6537159`…`121c997`)
- **EYE — the colour REVEAL (`1a1fc1f`):** committing a SELECT draft (ferry → part side-button / play column) now BLOOMS the
  destination's real machine colour (a saturated wash easing out ~0.6s, settling to the cell) — was a white flash. Verify the
  bloom reads as "it became this colour" on the mostly-dark part/play cells.
- **EYE — MachineBinding inc.1 (`121c997`):** the play button + machine hue now derive from one resolver (behaviour-preserving —
  should look identical). Confirm no regression in the machine box/play-button state as you select select-cells / ferries / parts.
- **EYE** — the **Tide & Ember** scheme + **Even Dusk** play palette on device: do the 8 play columns now read as DISTINCT
  (the whole point — the old dusk set blurred)? Cool receivers / warm emitters / sea-blue PLAY door / ember PART door /
  warm→cool SELECT strip. Plus the SELECT-grid CHEQUER, the solid-block ▲▼ ferry cursor, and the alternating-bright-grey
  machine feedback on each new SELECT pick.
- **EAR** — the CC120/123 fix: with a HOLD/LATCH armed, a source app spamming all-notes-off (chord release / between phrases)
  must NOT cut the held chord at the SYNTH now (previously survived internally but was silenced downstream). Verify a legato/
  drone HOLD keeps sounding through a source's CC123, and that a real panic (nothing armed) still passes through.
- **OPEN colour follow-ups (Paul's call, from the colour study artifact — NOT built):** ① a muted "opposite-of-a-rainbow"
  SELECT nav (Graphite/Slate/Blueprint/Paper) — a one-line `roomsRainbowHues` swap; ② the disposable-sketchpad SELECT
  material + the colour-blooms-on-commit "reveal"; ③ raise the cell hue WASH/frame opacity so the play hue reads more boldly
  (independent of palette); ④ warm-shift the 16 machine `colourHexes` (left a full spectrum — only if Paul wants it).


## ★★★ FERRY INTAKE 2026-09-01 — macro-automation (RATIFIED) + CHORDS §2 (canon) — PLAN: `Docs/PLAN-incoming-2026-09-01.md`
Two docs read + merged from `_dear_claude_code/` (inbox cleared): **`INSTRUCTIONS-macro-automation.md`** (NEW, RATIFIED — the
one automation currency; 16 macros in TWO SPECIES = 8 TOGGLE + 8 SLIDER; four collapsible tabs on the part page: BIND · PLAY ·
PUNCH · SPAN; base⊕offset, boundary-deferred, drawn=config; overrides survive mutate/randomize). **SUPERSEDES `SPEC-macro-lanes.md`**
(now tombstoned — the grid-as-canvas + ×-spans cover the band's whole job; the wave-chip = a possible uncommissioned SPAN fill).
And **`SPEC-chords-stage.md`** grew a **§2 DEGREE MATRIX (canon)** — 8 rows (I–VII + REST) · radio-per-column · empty column =
CARRY the previous chord · quality-aware self-updating headers (I·ii·iii°…) from the declared key · VOICING/WINDOW/ROTATE chips.
CHORDS itself is RATIFIED (derive diatonic progressions from a key: FOLLOW·PATTERN·WALK modes; no chord stored — rank arithmetic
on the scale pool); the STATUS note says the three MODES + voicing await Paul's ratifying word before build, §2 is canon.
- **Read the grounded plan `Docs/PLAN-incoming-2026-09-01.md` before building either.** Macro-automation is the bigger lift
  (four tabs + the toggle/slider species + per-cell/per-span application). CHORDS reuses the SCALE-door pool + the state-matrix
  + pedal machinery (kin to AVOID/§2 the degree matrix).
- **✅ §K RESOLVED (Paul 2026-09-01):** K1 — macros are **PART-PAGE-ONLY** (never the play page); the per-cell amount grid
  (option a) is scoped to the part grid, lives per-part. K2 — a toggle is a binary gate on the bound offset (value ∈ {0,1}).
  K3 — RETIRE the 8 timeline macros (bank = 16: 8 slider + 8 toggle; enum case kept decode-safe). K4 — **all three CHORDS
  modes RATIFIED** (FOLLOW·PATTERN·WALK + voicing). **LAYOUT:** the macro band = the bottom HALF of the PART grid (interior 8×8
  −50% height; ferry row · ▲▼ · STOP unchanged). **BUILD ORDER:** CHORDS C1 (pure core) → C2 PATTERN → C3 FOLLOW → C4 WALK;
  macro M1→M2 (the part-scoped amount grid) → M3–M6 (the 4 tabs).
- **✅ CHORDS — DONE / FEATURE-COMPLETE (2026-09-01, `64ed992`+`df5289c`+`2fd8d98`; 995 green, iOS builds; DEVICE ear owed).**
  C1 pure core → C2 PATTERN → C3 FOLLOW → C4 WALK → C5 lone/tail emission + voicing/downstream. All three modes + VOICING/SPREAD
  + the quality-aware degree matrix ship; wired via applyStage (upstream fold) + emitColumnHolds (lone/tail hold, no stuck
  notes). **DEVICE-FIX PASS (2026-09-01, `a038a68`; Paul "doesn't respond / one chord"):** default → FOLLOW (responsive: play →
  chord) + C2b#1 DONE (CHORDS reads the key from a receiver door in SCALE mode). **REMAINING C2b (flagged, NOT blockers):**
  ① INVERT-toward-previous (the pure `voiceLeadTowardPrevious` exists + is tested, but wiring it needs a per-cell last-chord
  memory across windows); ② WINDOW CELL|ROW|BAR (the span family — CELL only today); ③ the PATTERN degree-matrix headers show
  major-quality Roman numerals (a POSITION reference; the real quality follows the SCALE-FROM door's scale at play — threading
  that door's scale into the editor for live-accurate headers is a device-owed nicety). **SCALE FROM ▸ (referenced SCALE door)
  + editor mode-clarity DONE `0ab1b00`; the card KEY picker is REMOVED (the earlier own-receiver-scale read is superseded).**
- **✅ MACRO-AUTOMATION M1+M2 — DONE (2026-09-01, `2aa17ed`+`f157ef8`; 999 green, iOS builds; engine-only). M1** = the 16-macro/
  two-species bank (8 slider + 8 toggle; timelines retired §K3, decode-safe). **M2** = the per-cell value store
  (`MacroCellValue` + `PluginState.macroCellValues`; builder-side fold `override ?? global`; no render change; persistence free).
  **NEXT = M3–M6 (the 4-tab band UI, PART-PAGE-ONLY, DEVICE-OWED):** M3 the band shell + layout split (part-grid interior −50%,
  the freed bottom half = the collapsible band; ferry/▲▼/STOP unchanged — `roomsPartGrid`) + BIND (tap-to-assign, reuse
  `MacroAuthoring`) + PLAY (8 pads + 8 faders → `setMacroValue`); M4 PUNCH (arm→tap cells→draw per-cell, writes `macroCellValues`);
  M5 SPAN (arm→ladder→sweep/×-pass); M6 mutate/randomize survival + rooms-@State ↔ document sync. Held for Paul's device eye —
  a large blind UI surface with layout-interpretation room; the engine it drives is proven + tested.

## ★★★ FERRY INTAKE 2026-08-31 — the ratified batch (DETAILED PLAN: `Docs/PLAN-incoming-2026-08-31.md`)
Five docs merged/added (interface-redesign +§8/§8b/§9 · scale-door +§6/§7/§7b · room-palettes · listening-set · macro-lanes).
`Docs/PLAN-incoming-2026-08-31.md` is the grounded, file:line implementation plan — read it before building any of these.
- **RATIFIED, buildable (sequence + risk in the plan §J). PROGRESS 2026-08-31 (unattended):**
  - ✅ **§A MIDI-tab scale label** — DONE (`Receiver.scaleLabel` shared helper; the tab shows "A MIXO" for a SCALE door; +test).
  - ✅ **§5 play-grid undo** — DONE (the 10 play arrays added to BuildSnapshot; ferry/flatten now record undo).
  - ✅ **§E GRID 8|16 stage 1** — DONE (Voice.cellIndex Int8→Int16, byte-identical, full suite green). STAGE 2 (the
    cols=16 flip + mask/cellSounding/Snap.cols widening) is device-verified, Paul-present — see plan §E.
  - ✅ **§B AVOID / LOCK (UNIFIED)** — DONE (`7c60dac`) + **CLASHES axis & LIVE-DOOR reference** (`6477fbb`). Paul unified
    "avoid clashes" + "lock to key" into ONE processor: a per-note pitch filter (keyFilterNote as a chain stage) —
    REFERENCE (KEY·DOOR·WIRE·ALL SOUNDING) × MODE (LOCK|AVOID) × ACTION (REMOVE|MOVE), placeable anywhere (position-
    independent; no SKIP — §K1 resolved). Subsumes the separate §H LOCK-TO-KEY. Full surface + self-naming (LOCK A MIXO /
    AVOID CLASHES) + storefront cards + fuzz. **CLASHES (`6477fbb`):** WHAT = SAME | CLASH | CLASH+ widens the reference
    set to its ±1/±2 pitch-class neighbours (widenClashMask) in AVOID mode (LOCK keeps the exact key) — so it dodges the
    dissonant semitones, not just the notes. **LIVE-DOOR (`6477fbb`):** a DOOR-referenced AVOID now reads what ANOTHER
    receiver is playing THIS render (latched/SCALE pool if present, else the live THRU input via doorLivePitchClassMask) —
    Paul's "listen to a different receiver" scenario, +test. Also fixed: standalone/single-slot [AVOID] + [X→AVOID] were
    silently emitting nothing (emitColumnHolds guard + isHoldTailChain lacked `.avoid`). WIRE/SOUNDING keep the L1 later-
    row caveat. **EDITOR REWORK (`b810558`, UI-only, DEVICE eye owed):** removed the KEY picker; REFERENCE → "LISTEN TO" =
    INPUT (▸A–D) | EVERYTHING (WIRE dropped from the UI); plain labels (AVOID|LOCK · ALSO DODGE NOTHING/CLASHES/MORE · IF
    BLOCKED DROP/MOVE) + an illustration PIANO (two live C1–C7 keyboards: the reference notes + clash halo · YOUR OUTPUT).
    Engine keeps every enum case (decode/test safety). DEVICE ear owed.
  - ✅ **§F PLAY-FERRY ROW CURSOR** — DONE (`7c60dac`; Paul's #4 clarification, NOT the abstract track-swap): a ▲▼ picks
    which grid ROW the play-ferry buttons target (`buildPlayFerryRow`). The ghost-previews/track-swap of redesign §9 remain
    a separate incremental-redesign item. DEVICE eye owed.
  - ⏸ **§G AVOID — OUTPUT/EMITTER references (RATIFIED 2026-08-31)** — extend the LISTEN-TO axis from input-domain only
    (INPUT ▸A–D · EVERYTHING IN = other receivers, excl. own) to ALSO output-domain: **OUTPUT ▸A–D** (what one emitter is
    actually PLAYING, post-arp/harmony/generators) + **EVERYTHING OUT** (all emitter output EXCEPT this chain's OWN
    emitters). Point: avoid the real MIX, not just raw held chords — a bass dodging a busy lead arp catches every arp note.
    Same PITCH-CLASS model (octave-agnostic — a ref C blocks every C). **Self-exclusion is mandatory** (else self-thin/
    flicker): v1 = exclude by BUS (read `soundingPitchClassMask` for emitters ∉ cell.busMask — simple, correct; also skips
    other chains on that bus); v2 = exclude by VOICE ownership (colourIndex/cellIndex — precise, keeps other chains on the
    same bus). **Engine ~mostly there:** `.wire` = one emitter (`soundingPitchClassMask(bus:)`), `bus:nil` = all — add
    "all except own buses"; the enum already has `.wire`. **COSTS to design around:** (1) L1 ORDERING — an output ref reads
    the live voice table (emitted-so-far this render), so the avoider must sit on a LATER grid row than its source, else it
    reads last render's output (~1 block lag); mutual refs ping-pong at 1-block latency. (2) MOVING TARGET — an emitter's
    output changes note-by-note; DROP = holes open/close musically, but a LEGATO hold could drop+re-strike (click) as the
    source crosses its class. (3) PIANO — the pianos predict from input doors (recvHeldNotes); an output ref needs a NEW
    per-emitter output feed to stay honest, else the OUTPUT-ref piano is degraded. UI = a LISTEN-TO domain toggle
    INPUTS|OUTPUTS × (one A–D | EVERYTHING). Effort: small engine + a UI axis + (for the honest piano) an emitter-output feed.
  - ⏸ **§C scale-aware IN strip** — the §6 SCALE-door IN readout + the "arm AVOID CLASHES from the strip" chip (thin UI over
    §B now that AVOID exists). Buildable next.
  - ⛔ **§D MACRO LANES — SUPERSEDED (2026-09-01)** by the ratified `INSTRUCTIONS-macro-automation.md` (the 4-tab band; see
    the 2026-09-01 intake + `PLAN-incoming-2026-09-01.md`). The old below-grid-lane framing is retired.
- **ALREADY BUILT (verified — do NOT rebuild):** the bazaar-muted select cells · scale-doors-name-themselves (on the
  receiver chip; only the MIDI-config tab bar is left = §A) · the room palette signatures (roomsField near-black PLAY,
  roomsDoorBar rainbow/amber/indigo/red, ▲PLAY indigo) · CHORDS/the dynamic reference.
- **⛔ DECISIONS PAUL MUST SETTLE before the risky pieces (plan §K):** ~~(1) AVOID SKIP downstream~~ ✅ RESOLVED (Paul: no
  SKIP at all — AVOID is a per-note pitch FILTER, REMOVE|MOVE, position-independent before/after an arp) · (2) macro-lane render path (build-side table vs render-side eval)
  + part-local scope (never write the global Macro.value) · (3) GRID 8|16 = always-16 allocation + active-width, per-doc? ·
  (4) ▲▼ axis/glyph (tracks are COLUMNS — swap c↔c±1? ▲▼ vs ◀▶) · (5) OK to add the 10 play arrays to BuildSnapshot (play
  grid has NO undo today).
- **CAPTURED, NOT ratified (HOLD):** LOCK TO KEY stage (scale-door §7 — ≈ AVOID with only:true at chain END) · the rest of
  the LISTENING SET (SHADOW/FEEL-THIEF/IMITATE/…) · the full rooms/tracks/provenance/footer redesign (build with Paul).

## ★ HOUSEKEEPING SWEEP — 2026-08-30 (dead code · 30-bug hunt · tests · refactors, unattended)
- **✅ DEAD CODE DONE:** 24 grep-verified zero-ref orphans deleted (`Housekeeping: delete 24 grep-clean dead orphans`) —
  22 BuildPage leaf helpers (buildBandNumber/BandRange/BlankSlot/CastMemberAt/ColourTabs/ColumnHasSelection/
  FirstFreePaletteSlot/FooterBoxBtn/Lighten/MidiOutInfo/MSBtn/RowButtonIcon/SetPartLen/SetSource/Step/TargetMark/
  colSelCellPart/row8Live + vars CurrentDeployed/PerformPopulated/ShowColourBox/StagingPopulated) + `clearReceiverLatch`
  + `buildPlacedOrig` (dead write-only PLACE-verb state). KEPT (reserved/conformance/WIP, do NOT delete): the macro-
  authoring + colour-chain + mark-feed + Row 8 AU APIs, the EditSelection undo cluster (markBorn/recordUndo/wasBorn/
  asSet/syncAnchor), `roomsPlayHeader` (active rooms surface), makeUIViewController/updateUIViewController.
- **✅ BUGS DONE (this pass):** K1 presets now carry the BUILD workspace · K2 load paths drop stale pending · K3 empty-
  scenes guards · P1 chain-audition fallback sweeps (not pins) · R1 master-MUTE closes sustained notes · R3 no-machine wire
  honors emitter enable/solo · Rooms1 play-rung tap re-publishes · Rooms2 pass-aware transport · Rooms4 ragged-restore guards.
  The 2026-08-24 pre-surveyed bug list (below, §"Wrong audio / correctness"…) was RE-VERIFIED — nearly all already fixed by
  unticked CR-6/9/10/11/15/16/17/18 passes; only [7]'s gate-stack half remained (= R2, flagged).
- **⚠ FLAGGED, NOT fixed (need a dedicated tested + device pass):**
  - **R2 — GLIDE gate stack — ✅ DONE (2026-08-30):** routed glide through the emitOneBus output pipeline via two helpers
    (`glideOutNote` = OCT + master KEY + FENCE · `glideBusAvailable` = emitter ENABLE + output-SOLO), applied at every open
    site in emitColumnGlide + emitGlideDriven; an unavailable bus phrase-ends the voice. Byte-identical when KEY/OCT/FENCE
    unset (330 RouterTests unchanged); +2 tests + fuzz. DEVICE ear owed (glide in key; disabled-emitter silence).
    **STILL DEFERRED:** CLAIM + CONVERSATION for glide — their discrete note-ghost / per-onset-stance models don't map onto
    a continuous mono bend (a design question, not a mechanical fix); the STEP-mode intermediate zipper notes aren't
    re-FENCEd (transient; endpoints are). This closes the open half of old finding [7].
  - **Rooms3 — a flattened play PASS's per-step I/O chips edit-but-are-ignored** (the engine uses playColStepRecv/Emit; the
    chips write only the column default). Overlaps the ⛔ PAUL-TO-DEFINE pass-editing model below — settle that first.
  - Minor (low): glide stamps a stale currentCellIndex (cosmetic SEAL/reel tag); flood governor undercounts BROADCAST.
- **`buildGCColours` (ephemeral-colour GC) was removed with the old UI** — the rooms UI never called it, so no behaviour change,
  BUT ephemeral colours (minted on ferry/flatten/audition) no longer GC. If a long rooms session shows colour bloat, add a
  rooms-side colour-GC (the old one keyed off the old-UI liveset; a rooms one would key off buildStagingCells + buildPlayCells +
  buildColourReg + the selection).

## ⛔ PAUL TO DEFINE — design decisions BLOCKING further build (2026-08-30, rooms multi-step passes)
- **★★★ HIGH — RE-ENTERING A PART ROOM AFTER IT'S BEEN FERRIED.** When a part has been flattened onto a play column
  (`roomsFlattenPartToPlay`), the flatten stops the part audition — but re-entering the PART room re-arms it
  (`roomsSyncVoice(.part)` sets `buildStagingPlaying = true`), so the part can play on rows 0–7 WHILE the flattened pass plays
  the same sequence on the play layer → DOUBLING/phasing. Need Paul's ruling: on re-entry should the part (a) stay silent
  because it's "moved to play", (b) play as normal (accept the double), or (c) something else (e.g. the pass mutes while you're
  in the part room)? Blocks a clean re-entry rule. Flagged in CLAUDE.md status (multi-step-play-passes entry).
- **★★ PRIORITY — EDITING CELLS ON THE PART GRID + FERRIES.** How editing works across the part grid, the select→part
  ferries, and (now) a flattened multi-step PLAY pass is under-defined. Current v1: a play pass's machine edit hits only the
  representative (first-step) colour — pass editing isn't a defined operation. Need Paul to define the model: what does
  "edit this ferry/pass" mean (edit one step? the whole pass? re-flatten?), and how the part-grid ↔ ferry ↔ pass edits
  relate. Blocks a coherent edit UX for the rooms surface.

## ★★★ ACTIVE THREAD — THE UNIVERSAL SPAN MODEL + STANDARD PANEL ANATOMY (2026-08-27)
- **✅ SPAN = re-anchor period, decoupled from an ABSOLUTE RATE (grain). DONE for the free-running generators:**
  - **RIFF + EUCLID** → FREE·1·2·3·4·6·8·×2·×4 re-anchor with an absolute GRID grain (`a94f4a8`; Paul "go absolute").
  - **FREE on TUTTI + RATCHET** (`5fa2451`, UI-only) — fixes the "shows 1 but free-runs" mislabel; adds a FREE chip.
  - **Cascade/burst/length LEFT on CELL|ROW** — their ROW is a real windowed reveal / bar roll / bar gate (not "just slower").
- **✅ STRIKE PER SPAN v1 — DONE on the DRONE** (`1c029ac`, spec `AcceptanceCriteria-strike-per-span.md` ratified): STRIKE
  HOLD|PER SPAN chip + RE-STRIKE EVERY ladder; re-articulate at each span origin, legato-hold between. One gate on the
  emitColumnHolds adopt decision. +2 tests + fuzz. DEVICE ear owed.
- **OPEN — STRIKE PER SPAN on the span-ladder DRIVER cards** (euclid/riff/ratchet/tutti-pattern/burst/cascade): each is
  tick-driven, not a hold, so each needs its own adopt/reconcile bolted on (bigger, riskier). Spec calls them "legal but not
  the point." HARMONIZE/TUTTI-COIN holds are the easy same-path follow-ups. Flagged in `_dear_paul/strike-per-span-drone-*`.
- **STANDARD PANEL ANATOMY §1 (spec `AcceptanceCriteria-standard-panel-anatomy.md`) — IN PROGRESS:**
  - ✅ **FOOTER** (`c01e966`+`5aedb06`+`e3ed45f`): `frameRow` = compact horizontal GRID·ROTATE·SPAN (Paul chose horizontal;
    gridMenu/spanMenu tap-menus + ◀n▶ rotate) + `pairsWell` line. On RATCHET + TUTTI PATTERN (the reference pair).
  - ✅ **HEADER OCT** (`ce0954d`): per-slot `stageOct` ±3 (stage's own voice); engine on all paths + `applyStage` post-shift; +2 tests.
  - ✅ **HEADER SOURCE** (`c5fffce`): per-slot `stageSource` CHAIN|MIDI IN|BOTH; v1 = the composeChainSet fold; +1 test.
  - ✅ **FOOTER SWEEP** (`b273afb`): the frame row + pairs-well now on RATCHET · TUTTI · EUCLID · RIFF · BURST(PATTERN).
    Footer redesigned per Paul's device iterations (`e3054e7`…`b273afb`): compact chips in one `FS` knobs block; GRID left /
    ROTATE centre / SPAN right; left-aligned labels above; GRID 2-row, SPAN 2-row (FREE·×2·×4 / 1–8); pairs-well under
    ROTATE; no "FRAME" word (rule kept). CASCADE excluded (a reveal). Per-card: EUCLID hides ROTATE in LINES; RIFF no ROTATE;
    BURST GRID gated by SLICES=RATE. Still open: OPTIONS chips in the footer (deferred).
  - ⏳ **CHROME** — reposition the IN truth-strip UNDER the header + the OUT roll to the FLOOR (currently one IN|OUT band below the body).
  - ⏳ **SOURCE downstream** (the [ARP→HARMONIZE(MIDI IN)] headline) — needs the door threaded into emitDriverNote (cascades
    through emit helpers) + the hold-tail source + **a FEEL ruling from Paul** (per-tick door read vs a sustained parallel voice).

## ★★★ THE INTERFACE REDESIGN — captured 2026-08-28 (`Docs/INSTRUCTIONS-interface-redesign.md`, ferry). BIG, build with Paul.
The whole surface geography, to be built INCREMENTALLY under Paul's guidance (door-loop pattern; device steps outrank prose).
Headline shape: **three rooms + the tape, one grid in view** — SELECT (shop) · PART (workshop) · PLAY (stage) · REEL (tape);
navigation = TAPS on thin door-buttons (no pane drags). **★ STANDING ORDER (§6): reuse REAL existing components, never
approximations** — docked chain editor → summoned overlay; I/O console → footer mixer layer; MIDI/RACK sheets → footer config
layer; pass-browser selection → reel assign payload; multi-row/stack machinery → the tracks; stateMatrix/slider-lane/nudge-pair
unchanged. **Anything that would be approximated: STOP + ask Paul.** Key laws: shared 8-cell HEADER (tap=play/stop track ·
long-press=assign) · PLAY grid = 8 equal vertical TRACKS, NO chain panels (§3b) · bottom band = 10 provenance doors
(SELECT · 8 per-track · PART; corners=general, middle=specific, doors follow the LIT slot §4c) · slot-column model (tap=take,
hold=FLIP LIVE|UNPACK §3c) · room-scoped audition silence (§5). Composes with `design-play-grid-lanes-OPEN.md` (the tracks/
stack model) + the just-landed panel-anatomy footer/header (the chain editor is the re-housed overlay). NOTHING built yet.

## ★★ DESIGN INBOX 2026-08-22 BATCH — 8 RATIFIED SPECS, filed to `Docs/` 2026-08-24 (sequencing = Paul's word). NONE built yet.
Read + filed: `INSTRUCTIONS-state-matrix.md`, `SPEC-arp-additions.md`, `SPEC-euclid-variations.md`, `SPEC-exclude-complement.md`,
`SPEC-glide-modes.md`, `SPEC-grid-selector.md`, `SPEC-motif-processor.md`, `SPEC-riff-processor.md` (all in `Docs/`). Reply in
`_dear_claude/REPLY-2026-08-24-eight-specs-filed.md`. **Recommended build order (mine — Paul picks):**
1. **✅ QUICK ENGINE WINS — DONE (2026-08-24, `3b096dd` + next):** ARP OCT-DIRECTION + RANDOM-ANCHOR · EUCLID PICK +
   INVERT · GLIDE SYNTH + STEP modes + on-screen text · KEYS EXCLUDE complement door. All additive-Optional chips,
   +10 tests, macOS green incl. fuzz, iOS builds. DEVICE ear/eye owed. v1 flags: GLIDE driven-path stays BEND (mono-
   driver commission); STEP run-window = glideTime (rate chip later); KEYS EXCLUDE Kernel subtraction device-owed.
2. **THE FOUNDATION (big cross-cutting UI):** STATE MATRIX + SLIDER LANE + SPAN LADDER (`INSTRUCTIONS-state-matrix §1-3`).
   - **✅ STATE MATRIX — DONE (2026-08-24, `bc40be2`):** the `stateMatrixRadio` widget (rows = states · cols = 8 steps ·
     radio-per-column · instant, no brush). Converted LENGTH · RATCHET PATTERN · TUTTI PATTERN (8×8) · BURST PATTERN.
     UI-only, reads the same slice arrays. DEVICE eye owed.
   - **✅ SLIDER LANE (§2) — DONE:** `modStepBars` was renamed to the shared `sliderLane` and now has 4 consumers
     (STEP MOD · CHANCE · TIMING · VELOCITY 2026-09-07). Draw-across-the-bars was fixed 2026-09-07 (one gesture hit-tests
     the column from the finger's X, was per-bar-captured).
   - **SPAN LADDER (§3) — Paul RULED: RATE × ladder (both)** (RATE = slice width · SPAN = loop period in columns). Staged:
     - **✅ STAGE 1 — DONE (2026-08-24, next commit):** the 3 WIDTH procs (EUCLID · BURST · LENGTH) — dial 1·2·3·4·6·8·×2·×4,
       `spanLadderBeats`, byte-identical CELL=1/ROW=8, polymeter for odd N. +1 test, fuzz-hammered. DEVICE ear owed.
     - **STAGE 2a — DONE (2026-08-24, next commit): TUTTI PATTERN** — the RATE×ladder model proof. RATE = slice width;
       `tuttiSpanN` (opt-in, nil ⇒ legacy byte-identical) sets the loop period; the 8-slice walk re-anchors every N cols.
       +1 test, fuzz-hammered. **DEVICE EAR OWED before rolling further.**
     - **STAGE 2b — DONE (2026-08-24): RATCHET PATTERN + CASCADE** — same RATE×ladder (opt-in, byte-identical legacy).
       RATCHET: RATE = slice width, SPAN N = loop period. CASCADE: RATE = reveal spacing, SPAN N = reveal window. +2 tests,
       fuzz-hammered. **MOD EXCLUDED by design** — its rate IS the LFO/shape period (no width×period split; STEP MOD already
       has `modStepSpan`). SPAN LADDER now on 6/7 span procs. Whole rate-proc feel DEVICE-EAR OWED. **TIER 2 ENGINE DONE.**
- **RATIFIED UI DELTAS filed 2026-08-25 (from the ferry channel; engine-untouched, render+interaction only):**
  - **`Docs/FERRY-rotate-control-ratified.md`** — the numbered ROTATE row RETIRES everywhere: a **◀ n ▶** nudge pair
    (tap = slide one step, wrapping; offset shown small between) + **drag the lane/matrix itself** to rotate. Applies to
    CHANCE/RATCHET/BURST/TUTTI/LENGTH rotate (currently 8-chip 0–7 segs) + euclid lines (per-line ◀▶). Clean self-contained
    render pass; do after DEST unless prioritised.
  - **`Docs/FERRY-complement-extensions-ratified.md`** — KEYS EXCLUDE (already BUILT this session) grows: chip → **FREE |
    MINUS[door] | ONLY[door]** (ONLY = palette ∩ door = scale-lock), LATCH-mode generalisation, truth-strip carving, an
    exclude-lag hysteresis. All additive on the shipped MINUS door (ONLY = ∩ vs − one-line flip).
  - **TAP processor is now RATIFIED** (`AcceptanceCriteria-tap-processor.md`) — build when sequenced. Storefront
    increment-2: per-panel sub-header = YES · type-swap-through-catalog = YES (design-answered, captured).
  - **DESIGN REQUEST answered** (inventory delivered) → **PRESENTATION REDESIGN RATIFIED + PLANNED (2026-08-25):** the
    design side returned `Docs/SPEC-presentation-pass-ratified.md` (6 hierarchy rules + per-card remap) +
    `Docs/FERRY-presentation-ideas-ratified.md` (32 ideas; Paul's high-value wave 21·23·16·15·8). My implementation plan =
    **`Docs/PLAN-presentation-redesign.md`** — ALL render-only (engine + params untouched; device-eye is the judge).
    Sequence: **✅ A** `numPair` keystone (`0bf0fdd`) → **✅ B** hero law + options cluster (`1f46a94`) → **✅ C** section
    long cards (`49366c3`) → **D wave (partial):** ✅ 8 self-drawing chips + ✅ 15 playhead-sweeps-matrix (`d45e409`) · ✅ 23
    hold-bypass A/B (`321e885`). **DEFERRED (each has a wrinkle):** **16 SPAN BRACKET** — the ladder's ×2/×4 values don't
    fit an 8-column bracket cleanly (needs a design for the multi-bar case). **21 DEFAULTS-RECEDE** — needs per-control
    "is-at-default" plumbing across ~50 controls (a large mechanical pass; the options-chips already show deviation).
    → **✅ E** two-column (= width-Pass-2, `e773fa5`) — `row2` pairs the short couples. → **F (batch 1, `bb378b2`):** ✅ 30
    CC picker (MOD CC → numPair with named-CC format) · ✅ 4/22 double-tap-to-zero (bipolarSlider: FAVOUR·VOL TILT·SHAPE·
    ECHO NUDGE) · ✅ 9 teach-lines (CHANCE·NUDGE mode) · ✅ 18 lane-readout-at-the-finger. **A–F landed.** F REMAINING (each
    needs infrastructure, do on request): 3 detents+haptics · 5 fine-mode (custom slider) · 7 touch-preview (window render) ·
    10 long-press-chip-explain (per-enum text) · 12 tap-value big-picker overlay · 14 hold-to-accelerate · 17 result-ghosting ·
    19 pinch-lane · 20 lane-header-mute · 24 touch→OUT-strip diff (needs truth strips) · 25 conditional-animate-in ·
    26 long-press=bind-macro (macro flow) · 27 sticky-hero · 28 section-anchor-chips · 31 keypad-overlay · 32 hero-glyph
    thumbnails. **✅ 21 DEFAULTS-RECEDE — DONE (`90c105e`):** keypath-`field` overload vs one static `ColourParams()`
    snapshot dims ~45 at-default fields (no per-render alloc, one Equatable compare — Paul's low-cost constraint met).
    **16 span-bracket = LEFT AS-IS** (Paul's call — the ×2/×4 multi-bar look isn't worth reworking now).
    **F INFRASTRUCTURE (started 2026-08-25):** ✅ **12+31 VALUE OVERLAY (`8a78175`)** — tap a numPair's number → a grid
    picker (small ranges) / keypad (CC 0–127) for exact entry, self-contained on NumPair. ✅ **5 FINE-MODE SLIDER
    (`e233b8c`)** — a custom FineSlider replaces SwiftUI's Slider at all 29 sites (+ bipolar + morph); coarse = absolute,
    PULL AWAY from the bar (>44pt) → latches FINE ×10 relative scrub (thumb grows, "FINE ×10" pip). Drop-in via
    `slider(_:in:)`. Device-eye owed on the pull-away feel + threshold. ✅ **3 DETENTS + HAPTICS (`1e30344`)** — every
    slider fires a soft SELECTION haptic on notch crossings (20/range coarse · 100 fine); optional `detents` (musical
    values) add gravity-snap + a firmer bump + track pips. Wired glideTime/glideRange octaves/mod attack+release. Device-
    ear owed on the haptic feel. **THE CONTROLS-POLISH WAVE (numeric grammar + fader) is now COHESIVE + done.**
    **REMAINING TRACKS (each a distinct build):**
    (b) LONG-PRESS EXPLANATIONS (10) — DEFERRED by Paul (2026-08-25, "ignore for now"). ✅ **§1 TRUTH STRIPS v1
    (`98bec19`)** — IN silhouette (held @ door) + empty-state teach + OUT mini-roll on the processor editor. ✅ **§4 STAGE
    EYE v1 (`ff8a350`)** — tap a strip → a full-page 3-lane input·mechanism·output view (DRIFT model; EUCLID draws its
    pulses, others an 8-step position lane). ✅ **IDEA 24 TOUCH-TO-DIFF (`535cae5`)** — while editing, the OUT strip + eye
    output lane show a live before/after: NEW notes (born after the gesture, stamped at the `buildApplyChain` choke point)
    bright + ringed, the BEFORE dim, box glows. **The truth-strips track (§1 · §4 · 24) is now FEATURE-COMPLETE** — all
    device-eye owed. LEFT (v2, deferred): §4 column-aligned SWEEP (needs the engine to tag output notes by emitting step) ·
    bespoke per-type mechanism art · embed the real hero widget read-only. (d) MACRO-BIND (26) — HELD by Paul (downstream);
    (e) LAYOUT — sticky-hero (27) · section-anchor chips (28) · conditional-animate-in (25) · hero-glyph thumbnails (32);
    (f) LANE gestures — pinch-scale (19) · header-mute (20) · result-ghosting (17);
    (g) hold-to-accelerate (14, low value now — scrub+overlay cover it).
3. **NEW FEATURES ON THE SUBSTRATE:** ✅ **THE E-BRUSH — DONE (2026-08-25, `a17efe0`):** `EBrushButton` (ε + K/rotate
   popover) wired into the SHARED widgets — `sliderLane` (CHANCE·STEP MOD·TIMING), `stateMatrixRadio` (RATCHET·BURST·
   TUTTI·LENGTH), the MUTE matrix — so euclidean fills land on every grid; UI-only. ✅ **EUCLID LINES MODEL — DONE
   (2026-08-25, `85d715a`):** `EuclidLine`{target·K·N·rotate·invert} + `euclidLines: [EuclidLine]?` (nil ⇒ single euclid,
   byte-identical); engine `runEuclidLine` loop (per-line N = polyrhythm; note-target via strikeChord onlyIndex); UI = the
   LINES STACK + ADD LINE. +1 test, fuzz. Both were `SPEC-euclid-variations §10/§5`. STILL OPEN: per-line PICK + a per-line
   die (v1b). ✅ **TAP — DONE (2026-08-25, `2621dd3`):** the mid-chain SEND — `ProcessorType.tap` (note-transparent, cellMode
   `.identity`); a fold-loop special case in `emitDriverNote` mirrors each note to the TAP wire (LEVEL scale · TO THIS/A/B/C/D ·
   MUTE) via emitArtic, then passes `cur` through; +1 test, fuzz (`AcceptanceCriteria-tap-processor`). STILL OPEN: TAP hold-path.
   ✅ **ROTATE RETIRE — DONE (2026-08-25):** part 1 (◀ n ▶ nudge pair) already shipped in the presentation pass; part 2 = the
   `RotateOnDrag` modifier — horizontal drag on the pattern MATRIX rotates by direct manipulation (~26px/step, wrap, taps
   still set), wired to RATCHET·BURST·TUTTI·LENGTH. The ◀▶ pair stays as the visible hint + precise control. sliderLane cases
   (CHANCE·STEP MOD·TIMING) keep the ◀▶ pair only (drag conflicts with the vertical draw gesture — flagged); DEST matrix has
   no rest/rotate. UI-only, device-eye owed. ·
   **✅ RIFF STAGE 1 — DONE (2026-08-26): the rank-stencil ENGINE + editor** (`ProcessorType.riff`, a DRIVER; pure
   `riffResolve`/`riffNote` — rank→sorted-pool note, WRAP fold/clamp/wrap, oct, rest; `emitRiffRow` on the arp tick
   lifecycle, composes as a chain driver; the RANK MATRIX editor + STEPS/RATE/WRAP; MELODY card; +2 tests + fuzz). RIFF
   **remaining stages (open):** the OCT/ACCENT/TIE/SLIDE modifier lanes (§5) + the GLIDE-SYNTH slide interlock · CAPTURE
   (§2, arm + play-in, records as ranks — input-driven, device-owed) · the FOLLOWING frame (§4, rank-vs-chord-at-its-
   moment) · then MOTIF (plays the riff library — `SPEC-motif-processor`, depends on RIFF).
4. **GRID SELECTOR §2/§3** (`SPEC-grid-selector`) — **ACTIVATED 2026-08-26** (ferry `FERRY-select-grid-activated` = Paul's
   go-signal; sequencing still his word). Enhances the ALREADY-BUILT grid selector: EXCLUSIVE ON|OFF toggle + layered
   audition (QUANTIZE already ships), PART-BUTTONS-as-COMMIT (retire COMMIT; tap cell→tap part N deals it), LAYERED DEALS
   (EXCLUSIVE-OFF + N lit + part → the part's rows, one undo), right-column BROWSE-CONTEXT I/O (audition-only; deal uses the
   part's own I/O), the PREGEN CORPUS (bulk background gen → instant DEAL + preset mining; profile the live-roll first).
   Riders NOT ratified: HOLD part = preview · OCCUPIED/EMPTY part-button states. **Plan: `Docs/PLAN-grid-selector-and-
   ratchet-coin.md`**. **✅ §3.1 PREGEN CORPUS — DONE (2026-08-26, Paul):** `Dice.rollCorpus` (quality `rollEnsemble` passes,
   cheap STRUCTURAL dedup — not the render-heavy sig — seeded/deterministic) + `buildGridSelBuildCorpus` (INCREMENTAL 64/
   batch → 256 target, background utility thread, non-blocking); DEAL now SAMPLES 64 instantly (RE-DEAL bumps the seed),
   fresh-64 fallback until batch 1 lands. +1 DiceTest (8.6s; was 95s before dropping the double-render). v1: in-memory
   (persist-to-disk + preset-mining curation = follow-ups). **STILL OPEN (device-owed interaction increments): EXCLUSIVE
   ON|OFF + layering audition · PART-BUTTONS-as-COMMIT (retire COMMIT) · LAYERED DEALS · right-column BROWSE-CONTEXT I/O**
   — these touch BUILD's delicate device-verified part-deploy/audition model + are feel-heavy (recommend a device pass).
   **↳ ✅ RATCHET COIN — SHAPING THE DICE — DONE (2026-08-26, Paul ordered it):** all four seeded additive-Optional COIN
   additions — ① SIZE WEIGHTS slider-lane over 2·3·4·6·8 (`rtcSizeWeights` + `rtcCoinSize`; replaces SIZE LO/HI, empty ⇒
   LO/HI byte-identical) · ② REFIRE GAP 0–4 · ③ QUOTA FREE|~2|~3|~4 · ④ ODDS FROM FIXED|VELOCITY. ②③ = the bounded
   deterministic `rtcCoinFires` per-row SCAN (gap spaces, quota caps; "derived never accumulated", v1 resets per row);
   ④ = `coinVelFactor` (pool peak vel). +3 tests, fuzz-hammered, iOS builds. v1: gap/quota reset per 8-step row.
5. **THE MATRIX/LANE CANDIDATES (ratified §5):** **✅ CHANCE PATTERN + ✅ TIMING LANE — DONE (2026-08-25).** CHANCE =
   the odds SLIDER LANE (SINGLE|PATTERN, step-aware `effectiveProbability`). TIMING = NUDGE FIXED|LANE (per-column ±8/16
   pocket; step = cell column). Together they delivered the SLIDER LANE species fully: `modStepBars`→shared `sliderLane`
   with unipolar + CENTRE(bipolar) modes, now 4 consumers (STEP MOD · CHANCE · TIMING · VELOCITY — Paul 2026-09-07). **✅ DEST MATRIX — DONE
   (2026-08-25):** a new routing-class `ProcessorType.dest` — the 8-slice per-onset EMITTER hocket via `chopMask`; UI =
   the STATE MATRIX (A–D × 8, radio). +1 test, fuzz-hammered. **✅ MUTE MATRIX — DONE (2026-08-25):** a new routing-class
   `ProcessorType.muteMatrix` — an A/B/C/D × 8 MULTI-SELECT grid; each GRID COLUMN removes the muted emitters (indexed by
   `columnStart(m,S)/S mod 8` like CHANCE PATTERN — the `9a00e69` "MUTE does nothing" fix; was chopSlice = inert for holds;
   composes on top of DEST/CHOP in `chopMask`; last-MUTE-wins; empties → note dropped, no stuck note). Additive-Optional `muteSlices`
   (nil ⇒ nothing muted, byte-identical). +1 RouterTest, fuzz-hammered. **The §5 matrix/lane family is now COMPLETE**
   (STATE MATRIX · SLIDER LANE · SPAN LADDER · CHANCE PATTERN · TIMING LANE · DEST MATRIX · MUTE MATRIX). ARRANGEMENT
   MATRIX = NOT ratified.
6. **SLIDER LANE / WIDTH:** the `sliderLane` shared component now has 4 consumers (STEP MOD · CHANCE · TIMING · VELOCITY). Processor-editor
   WIDTH PASS 1 landed (compact segs + ≤600pt panel); **PASS 2 = two-column packing** of short fields (device-eye owed).

## ★ DESIGN INBOX 2026-08-22/23 — FILED + QUEUED (4 ferries read + filed to `Docs/`; sequencing = Paul's word)
- **⟳ ROW 8 — LARGELY BUILT 2026-08-24 (overnight autonomous; see CLAUDE.md status). DONE: the type MODEL + factory deck +
  per-scene toggle capture; the FREEZE + HALFTIME engines (live, tested, fuzzed); REDIRECT + SWAP (wire re-stamp, tested,
  fuzzed); the perform STRIP + the EDIT PAGE (author every type); SETUP/MACRO/KILL wired to the existing engine. OPEN
  (deferred, each substantial): BROADCAST (a per-note fan-out — voice/refcount+governor design), PART (scene-independent
  part playback), INPUT (door mode-act — reuse latch/replay engage), CC-PUNCH/PC-SEND (need an on-demand CC/PC emission
  path), the HUB (retire the 2 bottom config buttons + the SETUP "edit setups →" jump + the INPUT cell type), and the
  HELD-mover spring press-gesture (v1 toggles via row8On). Device eye/ear owed on all of it.**
- **⟳ SCENES V2 — v1 SWITCHER BUILT 2026-08-24 (in-memory). DONE: BuildSceneSnapshot + a chip strip on the play column;
  capture/restore/add (arrangement per-scene, parts/colours shared). OPEN: PERSIST scenes with the document; PASS-QUANTIZED
  switch (arm/blink/next-pass + a hard sceneFlush) — v1 is an instant republish; drag-swap + cog-trash delete; the §2
  user-defined grid makeup (band count/heights) + factory form templates. Device owed.**
- **ROW 8 (the "fifth row") — RATIFIED WHOLE, BUILD-READY** (`Docs/row8-spec.md`; supersedes the scenes-v2 doc's §3–6
  fifth-row sections). The bottom row becomes **8 TYPED performance cells** `{TYPE · payload · MOVER (HELD|TOGGLE|ONE-SHOT)}`.
  Type catalog: SEQUENCE · PART (play a part from a pad, scene-independent) · SETUP (rack-config radio) · MACRO · FREEZE ·
  STUTTER · BROADCAST · SWAP · REDIRECT · HALFTIME · CC-PUNCH/PC-SEND · INPUT (door mode-act) · KILL. Factory "danger gradient"
  deck (STUTTER·FREEZE·HALFTIME · `[+]` · REDIRECT·SWAP·KILL·BROADCAST). CONFIG lives on a dedicated **ROW 8 EDIT PAGE**
  (the compact grid goes PERFORM-ONLY for row 8); ROW 8 is the **HUB** — the two bottom config buttons (MIDI/RACK CONFIG)
  RETIRE, INPUT/SETUP cells jump to their sheets, ALL latch control runs through ROW 8. §5: NO factory reset. ENGINE ask
  (the one genuinely new op): **REDIRECT** (stream re-stamp A→B while held) + its refcount handback; most other actions
  reuse specced machinery (MACRO/TRIGGER/FREEZE/STUTTER/CC/PC). STATE split: authoring = DOCUMENT, pressing = RUNTIME
  (scene-captured toggle states). A BIG feature → its own STAGED effort (type model → the edit page → each action's engine).
  Sequence the build with Paul before starting.
- **SCENES V2 — MULTI PLAY GRIDS** (`Docs/scenes-v2-multigrids.md`). A SCENE = one play-grid ARRANGEMENT (the deployed
  instances per band); PARTS/colours/receivers/master are SHARED above the scenes. REFERENCE-not-move across scenes (a part
  deploys many ways); **scene CHIPS** (8, pass-quantized switch · re-cue · drag-swap, never overwrite). M/S = LIVE mixer
  (NOT scene state); rung-actives/mutes/FREE-picks/rates = per scene. §2 USER-DEFINED GRID MAKEUP (band count/heights/types
  in the 8-row budget) = **DOCUMENT-LEVEL**, "captured, NOT commissioned" (v2). This retires the always-length-1 `scenes[]`
  gap (the flagship-unbuilt hole in CLAUDE.md status). Large model change (per-scene arrangement state + chip grammar +
  instance mapping) — design captured, build on Paul's word.
- **MICROTONAL LADDER** (`Docs/microtonal-ladder.md`). Tuning-agnostic by construction (we emit note numbers). **TIER 0 =
  CLAIM IT** (manual + one marketing line "we send the notes; your synth's tuning decides the pitches" + a GLIDE-caveat
  support note) — DOCS-only, do now / at launch. **TIER 1 = ★ ONE "NOTES PER OCTAVE" cog setting** (default 12) read by
  CLAIM's mod-12, OCTAVE/OCT±/FOLD's ±N, and the KEYS-door key count → EDO-native (19/24/31-EDO…); small, safe (12 = today),
  future-proofs OCTAVE/PEDAL — **AWAITING PAUL'S WORD**. Tiers 2 (MTS-ESP client for display) + 3 (scala import · ratio-
  HARMONIZE · per-scene tunings) parked with the KEY-door session.
- **STANDALONE APP** (`Docs/standalone-app-analysis.md`; complements the DEFERRED `Docs/standalone-plan.md` + its 3 seam
  rules, already enforced). ~2 Code-weeks, ENGINE UNCHANGED: (1) AVAudioEngine driver + internal transport (~2–3d, also
  unlocks BACKGROUND) · (2) CoreMIDI OUT (4 virtual sources A–D) + IN (~2–3d; Network/BT MIDI free) · (3) Ableton Link
  (~1–2d) · (4) app chrome — transport bar/port pickers (~2–3d) · (5) polish + device pass (~2–3d). WHY NOW: the beta pool
  explodes (no host needed), XCUITest becomes possible, the standalone IS the store page. Recommendation: schedule the
  spike AFTER the current queue settles; phase ① driver+transport+OUT (playable alone) → ② IN → ③ Link → ④ chrome.

## ★ CODE-REVIEW FINDINGS 2026-08-23 — ✅ ALL 18 FIXED (overnight autonomous batch + CR-8 closed later; see CLAUDE.md
## status). **[9]/CR-8 (PluginState non-Optional post-v2 fields) is DONE** — `activeScene`/`morphMaster`/`busChannels`
## are now additive-Optional with `*Resolved` helpers (Models.swift ~1029; test testPreV2DocMissingBusChannelsActiveScene
## MorphDecodes). **2026-08-29:** the SAME class on `Cell.inputChannel` (v3.0 non-Optional → a formatVersion-2 doc's
## cells threw at decode, BEFORE migration could run → whole-session data-loss) is closed with a decode-tolerant Cell
## init(from:) (the Macro/BuildPart pattern; fields stay non-Optional so encode is byte-identical; +3 tests). Commits:
## e1f6925 (CR-1/12/16/17) · 67bd53c (CR-2/3/4/5/6/7/9/10/11/13) · 9e72626 (CR-14/15 + the 7 EXTRAS). The historical
## finding text is kept below for the record.
## **RE-VERIFIED 2026-08-30 (housekeeping sweep):** every item below re-checked against current code — ALL closed by the
## CR passes above EXCEPT [7]'s emitOneBus-gate-stack half (GLIDE), now flagged as R2 in the top housekeeping section.
## New data-loss fixes this pass extend the same class: K1 (presets now carry the BUILD workspace) + K2 (load paths drop
## stale pending) — see the top section. The list below is HISTORICAL; do not re-chase without re-verifying first.
##
## (original sweep header:) 6-reviewer adversarial sweep — Router · Kernel · Derivations/Builder · Models/Emission · BuildPage · VC/AU; each finding VERIFIED against the code. Fix in small individually-verifiable commits (macOS suite + iOS build after each); the render-engine ones are byte-identical-sensitive — lean on RouterTests + fuzz.

### Crashes & races (do FIRST)
- **[1] Nested `[[UInt8]]` receiver-sounding feed = live render↔main race (the known SIGTRAP class).** `Kernel.swift:389,398,428`
  (`recvHeldVel`/`recvHeldNote`, written per-element on render, polled every tick at `AudioUnitViewController.swift:784/789`
  via `MidiSparkAudioUnit.swift:434`). The scalar-mask fix was applied to the DOT but NOT these — same pattern the
  `soundVel`/`markVel`/`withheldVel` feeds were FLATTENED to avoid. TWO reviewers found it independently. FIX: flatten to
  `4×W` value arrays (+`recvHeldCount`), like the emitter feeds.
- **[2] `Int8(colourIndex)` traps at ≥128 colours.** `SnapshotBuilder.swift:54` — `colourIndex` is a document-order index but
  `SnapCell.colourIndex` is `Int8`; with the 16-cap gone (unlimited ephemeral colours) a big BUILD session crosses 128 →
  overflow trap on publish. FIX: widen `SnapCell.colourIndex` to `Int16`/`Int` (or clamp with a documented ceiling).
- **[3] Colour param observer/provider/resync index `document.colours` unguarded < 16.** `MidiSparkAudioUnit.swift:1067,1083,1271`
  — sibling setters bounds-check; these don't. Latent (builders make 16), but a decoded/hand-crafted <16-colour preset +
  host automating `morph_15`/`transpose_15` traps. FIX: `< document.colours.count` guards.

### Stuck notes
- **[4] GLIDE bookkeeping not flushed on the emitter-disable + preview edges.** `Router.swift:1951` (bus disable via `closeBus`)
  and `2022` (preview via `allNotesOff`) close the immortal glide anchor but omit the `flushGlide()` the transport/panic/
  scene/latch edges pair with (warning at 2006). Kill a glide via the fader → stale `glideVoices.slot` → the reused slot
  later emits a spurious note-off on an unrelated note + the glide goes silent. FIX: add `flushGlide()` at both edges.
- **[5] ReelDeck `cap`(16384) vs `histCap`(8192) asymmetry drops note-offs on re-selection.** `Emission.swift:38,48,62,66,88` —
  the auto-loop keeps 16384 but the archived ring slot keeps 8192, and `replay()` re-emits verbatim with no synthetic offs.
  A dense pass replays fine immediately but, re-selected from the browser, is truncated → stuck notes (looks intermittent).
  FIX: unify the caps, or have `replay()` close notes still open at loop end.
- **[6] Uniform vs multi-clock paths keep separate column-edge trackers that desync on a live clock-mode switch.**
  `Router.swift:2101–2136` — `prevEffColumnRow[]` only re-inits when `prevEffColumn == -1` (a flush); enabling a per-row rate
  live is NOT a flush → a stale row tracker can skip a row's transition reconcile → phantom sustained drone. Low-probability.
  FIX: reset `prevEffColumnRow[]`/`modLastColumn`/`glideLastColumn` on the uniform↔multi-clock transition.

### Wrong audio / correctness
- **[7] GLIDE emits note-ons via raw `openVoice`, bypassing the whole `emitOneBus` gate stack.** `Router.swift:2422+` — no
  `busEnabledMask`/`soloEmitterMask`/CLAIM/FENCE/master-KEY/OCTAVE/flood reads in the glide path (MOD, its sibling, checks
  them). A disabled/soloed-out emitter still plays its glide line; master transpose/fence never applies to glide. FIX: route
  glide through the same gates (or replicate the enable/solo/key/fence checks).
- **[8] BURST "HITS 12"/"HITS 16" both render as 8.** `SnapshotBuilder.swift:291` clamps shared `count` to `2…8`, but BURST
  writes up to 16 and the engine expects it (`Router.swift:2700` `min(16,…)` is dead). FIX: `clamp(v, 2, 16)` (RATCHET
  unaffected — `effectiveRepeats` re-snaps ≤8).
- **[9] Master MUTE / master-kill doesn't silence BYPASS voices.** `Router.swift:461` `reconcileBypass` has no `masterMute`
  guard while grid/MOD/GLIDE all do → a bypassed door plays new notes straight through master mute. FIX: gate on
  `masterMute` (or confirm monitor-through-mute is intended).
- **[10] Parameter tree never resynced on the REAL load paths.** `MidiSparkAudioUnit.swift:1168` (factory), `1187` (preset),
  `1309` (fullState) skip the `syncParameterTreeToDocument()` that `loadTestSession` (1108) calls → after a restore the host
  shows the previous doc's stepRate/transpose/morph/macro + the next knob nudge fights the new doc. FIX: call it (suppress-
  rebuild wrapped) in all three.
- **[11] MONO steal runs BEFORE the flood governor → silent emitter.** `Router.swift:1173–1195` — MONO closes the holder (1185)
  then the governor can `return -1` (1193), dropping the note it stole for → the emitter goes silent for the rest of the beat.
  FIX: move the governor check ahead of the MONO steal.
- **[20] REPLAY discontinuity forward-jump threshold is a fixed `> 1.0` beat.** `Kernel.swift:662` — doesn't scale with
  `renderWindowBeats` (the comment even says a normal block advances by ~that), so at high tempo × large buffer a normal
  block trips `clearHistory()` every block → "LAST N" captures nothing. FIX: `> max(1.0, k * renderWindowBeats)`.

### Persistence / data-loss
- **[12] ✅ DONE (PluginState + Cell).** Non-Optional post-v1 fields broke decode of old documents → whole session silently
  lost (Swift ignores the `=` default on decode → `keyNotFound`, swallowed by `try?`, so the doc reverts and the migration
  never runs). PluginState's `activeScene`/`morphMaster`/`busChannels` are now additive-Optional with `*Resolved`. **2026-08-29:**
  `Cell.inputChannel` (added at v3.0) was the same trap for a formatVersion-2 doc — closed with a decode-tolerant `Cell`
  init(from:) (decodeIfPresent every field; fields stay non-Optional so encode is byte-identical). +tests both.
- **[13] `rackConfigsResolved` discards saved rack setups unless length == 4.** `Models.swift:833` — siblings PAD; this drops
  a length-3/5 array to the legacy default → all four user rack configs lost. FIX: pad/truncate to 4.
- **[14] `fullState.set` never resets `pendingBuildUnassigned`.** `MidiSparkAudioUnit.swift:1305/1311` — a host that saves right
  after loading session B re-persists session A's BUILD part (or nil) over B's. FIX: set `pendingBuildUnassigned =
  doc.buildUnassigned` in `fullState.set`.

### UI / state
- **[15] Processor-editor CANCEL reverts the WRONG colour after an in-editor colour switch.** `BuildPage.swift:3641/3648` —
  snapshot captured once in `.onAppear`; the editor has no backdrop (left column stays tappable), so switching the selected
  colour mid-edit leaves the snapshot on the original → CANCEL reverts X and strands Y's edits. FIX: re-snapshot on
  `ddSelectedColourID` change (`.onChange`), or revert the current target.
- ~~**[16] A door's running REPLAY loop is stranded when its mode is switched**~~ FIXED 2026-08-23 (folded into the THRU/SET-button
  rewrite): `buildReceiverLatchButton` now computes `engaged = replayOn || latchOn` and the tap stops whichever arm is live,
  so a mode switch can't strand a running loop.
- **[17] RANGE-picker keyboard hard-codes `width: 660`, overflowing narrow sheets.** `BuildPage.swift:375` — sheet is
  `min(720, width-32)`; on a < ~712 pt AUM pane the top octaves render off-screen → high MIN/MAX bounds untappable. FIX:
  derive the keyboard width from the available sheet width.

### Perf / invariant-3
- **[18] Per-event heap allocation on the render thread in `handleIncoming`.** `Kernel.swift:913` `var hearing =
  [false,false,false,false]` per forwardable CC/PB/AT (same class as the fixed "M1" alloc). FIX: reused member scratch, or
  fold the OR inline without the array.
- **[19] The 4 Hz poll isn't gated on `uiAppeared`** (the 30 Hz `meterTimer` at `AudioUnitViewController.swift:717` is;
  the poll at `723` isn't) → drains render→main feeds every 250 ms while the view is hidden (wasted work + widens finding-1's
  race window). FIX: add the `uiAppeared` guard (keep `buildPersistTick` running if needed).

### EXTRAS — lower value, fold into a cleanup pass
- **Inverted per-cell velocity window mutes a cell** — no `floor ≤ ceil` guard (`SnapshotBuilder.swift:88`; SPLIT's `splitVel`
  and the RACK FENCE both guard theirs). Reachable only via decoded/library cells (the per-cell UI was removed). FIX: order
  the bounds in `resolve`.
- **`rangeLo/HiResolved` has the same missing `lo ≤ hi`** (`Models.swift:536`) → an inverted decoded window silently kills the
  door. FIX: `hi = max(lo, hi)` in the resolver.
- **ARP ignores the cell's `chordSplit`** while HOLD/STRUM/RATCHET honor it (`Derivations.swift:942`). May be intended like the
  vel-window omission — DECIDE, then either honor it or document the asymmetry.
- **`bypassDestResolved` doc-comment says "ALL four" but the code intentionally defaults to emitter A** (`Models.swift:547-548`,
  "user 2026-08-05"). Stale COMMENT — fix the comment (code is correct).
- **`receiverNote` is dead write-only state + `nudgeReceiverNote` is missing** (`AudioUnitViewController.swift:260,526`; the AU
  `setInputSemitone` has no live caller). Either wire the ±semitone nudge or delete the dead state.
- **Reel-replay logs a spurious "playing silence leak" self-heal** from a stale `diag.activeVoiceCount` (`Kernel.swift:768/818` —
  `router.process` is skipped during replay so the count never updates). Diagnostic noise only (bumps `diag.panics`). FIX:
  zero `activeVoiceCount` on entering replay, or exempt the replay state from the silence-leak net.
- **`buildDeployCurrentPart` lacks the `>= 0` guard its siblings have** (`BuildPage.swift:2028`) — latent `[-1]` crash,
  currently unreachable. FIX: guard `buildCurrentPart >= 0` for symmetry.


## ★ FERRY 2026-08-20 — REDESIGN FIXES + reel fixes + banking (much LANDED unattended 2026-08-20)
- **REDESIGN FIXES** (`Docs/AcceptanceCriteria/AcceptanceCriteria-redesign-fixes.md`): §3 QUIET LEFT BOX DONE (`871d94d`
  — neutral chrome frame, hue accent only when the chain audition sounds, thin hue spine on the left edge). §1 CHAIN
  PANEL DONE (`6a43129` — ghost-dashed empties + a flow line drawing ORDER with turn marks; the flow-line GEOMETRY is a
  first pass, device eye owed to tune). **§2 THE RACK TWO VERBS — ANSWERED, folded into THE CONFIG SHEETS**: the design
  confirmed RACK 1–4 = 4 rack CONFIGS (the SETUPS radio lives on the RACK SHEET). It's now part of the config-sheets
  reframe (below), Paul-walked — not a standalone fix. Membership stays a MARK on the strip; the radio + matrix live on
  the sheet. Needs the 4-config engine model (saved configs + per-config membership + a live selector) first.
- **PASS BROWSER v1 fixes** (`…-pass-browser-v1-fixes.md`): §1 DONE (`34b91cd` — SAVE PASS n · collapse empty lanes ·
  neutral selection wash). DEFERRED: "tap the roll to select the pass under the finger" needs the roll to become a
  MULTI-PASS session timeline (the shipped v1 roll is single-pass) — a larger change; §4 dim-future-slots optional.
- **PAUL'S FOUR + THE CARRIAGE + TIMELINE PAIR** (same doc §2–§4, roadmap, Paul walks): BANK-AND-FOLLOW (overwrite-row
  switches the edit target — the ladder as a typewriter carriage `[◀][chips][BANK ▶]`, forward deals / backward visits);
  SUB-PASS + TRACK-FILTERED saves (drag a roll region / toggle lane labels); PASS RANGES (drag pass chips → SAVE PASSES
  3–6); DEEP HISTORY (the 32-ring stands + an opt-in SESSION TAPE file); REVERT-TO-HERE (per-pass state snapshots, restore
  as one forward event — "revert the revert"); PASS LABELS (per-pass changelog badges). = the reel as **TAPE·SNAPSHOTS·LOG**.
- **THE BANKING WORKFLOW** (`…-banking-workflow.md`): STAMP TELL DONE (`4f4b34a`); THE CARRIAGE `[◀][chips][BANK ▶]` DONE
  (`5ae1037` — BANK ▶ deals to the next row + follows, ◀ visits the previous fossil, both disable at the ends);
  occupied=filled / empty=hollow editor chip states DONE (`0c94064`). STILL OPEN (device eye): the EDITING-vs-tap-to-
  overwrite live-mark refinement + HOLD-chip = preview that row's machine.

## ★ AUDIO CRACKLE IN AUM (Paul reported 2026-08-21 — UI actions glitch the host audio; may be partly AUM/other apps)
- **Render (audio) thread is real-time-safe** — verified: pre-allocated scratch buffers (Router), lock-free `store.acquire()`,
  no locks/dispatch/ObjC/allocation on the audio thread for normal use. So the plugin isn't inherently glitching the graph.
- **Cause = main-thread CPU pressure** starving the audio thread on a loaded host: (a) presenting a SwiftUI Menu (e.g. the
  RATE selector) re-evaluates the HEAVY BuildPage body — the "opened the rate selector, it crackled" case; (b) every doc
  edit ran `SnapshotBuilder.build` synchronously on main — repeated spikes during interaction.
- **DONE (`3a0fb30`):** coalesced `scheduleRebuild` → one build per runloop (was N synchronous builds per gesture).
- **STILL OPEN (device-verify + bigger):** reduce the BuildPage body's re-evaluation cost (the menu-open spike) — a
  SwiftUI-perf pass (Equatable views / smaller diffed subtrees / fewer poll-driven @State re-renders). Also: the new 30fps
  `meterTimer` adds some main-thread load (trade against the velocity-indicator latency fix if needed). And a KNOWN niche
  invariant-3 spot: MOD §2 `applyInternalMods` COW-allocates when a cell uses an INTERNAL-target MOD (unused today; fix
  if that feature sees use). Device factors outside us: AUM's audio buffer size + whatever else is running.

## ★★★ HOUSEKEEPING — TOP PRIORITY (Paul 2026-08-31): UNIFY THE MACHINE↔CELL PLAYBACK/SELECTION MODEL
- **PROGRESS 2026-09-01 — INCREMENT 1 LANDED (`121c997`, behaviour-preserving + tested):** the pure `BuildSceneLogic.machineBinding(...)`
  → `MachineBinding { kind: .none|.selectAudition|.partRow|.playFerry(c), isGrey, playing }` (primitive inputs so it's in the
  test target; +testMachineBindingResolvesFerryAuditionAndGrey). `buildMachineBinding(room)` gathers the four axes; `buildMachineHue`
  AND the play button (`roomsVerticalPlay` active/hue/tap) now DERIVE from it → the machine's play state == the represented cell's
  by construction. **INCREMENT 2 (OPEN, device-owed):** route the remaining PER-CELL indicators through the same binding —
  `roomsSideChip` (D3), `roomsPlayFerry`/`roomsPlayCell` `on`, `buildGridSelCell` roll (D1's extra `!buildChainLiveChord.isEmpty`
  term) — and reconcile D5's second "grey" (the cell selGrey vs the machine grey). This CHANGES on-screen state → verify on device.
- **The problem (Paul's device report):** the machine (box + play button) is meant to ALWAYS represent exactly one cell —
  a select-grid cell (light grey), a part cell, or a ferry (its colour) — and its play/stop must drive THAT cell, with the
  cell reflecting the play state (and vice-versa). Today there's a disconnect: the machine can be playing while no cell shows
  it, and edits/selection can diverge from what plays.
- **Root cause (mapped 2026-08-31 by an Explore agent — see the session transcript):** playback truth is split across
  FOUR independent axes, reconciled only inside individual tap handlers (`buildGridSelAudition`, `buildSelectPlayColumn`,
  `roomsAssignPlayColumn`), so any state change touching one axis without the others desyncs:
  1. `buildVoiceOwner` (`.none|.chain|.part`) — the shared EXCLUSIVE audition voice (ddSolo/buildStagingPlaying are mirrors).
  2. `buildPlayColOn[8]` — the PERSISTENT per-column ferry layer (sounds on every page, independent of selection).
  3. `buildSelID` → `ddSelectedColourID` — MACHINE identity (which cell the box/chain/play button represent).
  4. `buildGridSelSel` — the SELECT-grid cell highlight.
  Machine hue greys iff `buildSelID == buildGridSelAudID` (gsAud); the play button's `active` is `buildDisplayVoice==voice`
  OR `buildPlayColOn[buildSelectedPlayCol]`; the select cell's "playing" adds `!buildChainLiveChord.isEmpty`; the ferry's is
  `buildPlayColOn[t] && buildPlaySel[t]==buildPlayFerryRow` — five different derivations of one conceptual binding.
- **The disconnects (agent's D1–D6):** D1 machine `active` ≠ select-cell roll-scroll (extra live-chord term); D2 a ferry keeps
  playing while the machine represents gsAud and reads STOPPED; D3 selecting a ferry kills the chain audition; **D4 (partly
  fixed 2026-08-31, `e01e77d`)** entering SELECT auto-played an orphan colour with no visible cell — now gated on
  `buildGridSelSel != nil`; D5 two independent "grey" conditions; D6 five "playing" derivations off different @State.
- **The task:** collapse to ONE source of truth. Sketch: a single `MachineBinding { kind: .selectCell(i) | .partRow(n) |
  .ferry(c) | .none, playing: Bool }` (or equivalent), from which the machine identity/hue, the play button state+action, and
  EVERY cell's highlight/playing indicator all DERIVE — so they cannot diverge. Keep the persistent ferry layer (`buildPlayColOn`)
  but make the machine's play button + the represented cell read the SAME state. Do it TEST-GUARDED (extract the pure
  binding→state resolution into a Foundation-only function with unit tests, the BuildSceneLogic pattern) — this is UI-model
  logic that's currently untestable and device-verify-only. Was going to rush it blind; Paul said do it LATER, carefully.

## ★ HOUSEKEEPING FLAGS — surveyed + verified 2026-08-19, DEFERRED (need a focused tested pass, not unattended)
- **Render-path allocations (invariant 3):** (1) ~~`srcNotes` local array in the 4 driver emitters~~ DONE (2026-08-19,
  `ac7eb2b`) — a reused `srcNoteBuf`/`srcNoteCount` + `srcNoteBuf[0..<srcNoteCount]` slice view; byte-identical.
  (2) ~~`euclidPattern`/`burstFractions`/`tuttiSliceRanks` array returns in the hot loop~~ DONE (2026-08-20, `a87e492`)
  — `*Into(&buf,…)` no-alloc variants in Derivations (array versions wrap them for the tests); Router reused buffers,
  separate tutti A/B for the `[TUTTI→TUTTI]` nest; byte-identical. (3) ~~`process()` uniform-vs-multi-clock transition
  block ~duplicated~~ DONE (2026-08-21, `c338eda` — `emitColumnTransition(effCol:prevEdge:onlyRow:…)`; onlyRow nil =
  global clock, r = per-row; byte-identical, proven by the acceptance oracle + fuzz determinism). The TICK loops
  (`emitTickRow`) were already shared; only the trivial MOD/GLIDE per-row loop stays inline. Closes codebase-review §12.
- **TAB SECTION RETIRED (2026-08-21, `96a484d`→`7b01ade`) — BUILD is the sole surface; GRID/MIDI IN/MIDI OUT-tab/
  MACROS/AUTOMATION + the tab bar deleted (~2.4k lines); MIDI OUT `RackMatrix` kept as a BUILD overlay.** **EDIT/verb/
  proc-editor CLUSTER also deleted (2026-08-21, `7b01ade`, ~980 lines):** with BUILD sole, `editArmed` is permanently
  false + `heldVerb` permanently nil, so the whole grid-EDIT / verb / flow-diagram-proc-editor machinery was dead (kept
  alive only by flowDiagram's interactive buttons, which BUILD renders display-only + edits via its own
  `buildProcessorEditor`). Removed the chain-edit/macro-authoring/pop-up/output-split/selection machinery from EditPage,
  the verb + selection-undo cluster + 22 dead @State + Verb enum from the VC, dd* residue, and the whole
  `MacroAuthoringView.swift`. KEPT (BUILD-reached): `flowDiagram` + its display subtree, `cellChain`, `editPointedCell`,
  the dd* colour cluster + `EditSelection`/`sel` (BUILD scopes via `ddScopeToColour`), `syncSingleModeActivation`,
  `refreshTapMasks`, `setHold`. STILL LEFT (low-value, not chased): a few write-only mark @State (`emitMarks`/`recvMarks`/
  `emitHeld`/`emitRelease`/`recvRelease`/`recvLiveHeld`) + their poll writes; `GridView` + its renderers + `GridMacroSlider/
  Button` (BUILD uses `GridView.GridPos` + shares the components — the grid component itself is still referenced). Total
  tab-retirement sweep: ~3.4k lines. DEVICE eye owed on the whole BUILD surface (esp. the flow diagram still renders, and
  RackMatrix via EDIT TREATMENTS).
- **UI dead-code (grep-clean, FLAGGED not removed — the EDIT/verb surface may be intentional WIP like BuildPage):**
  `AudioUnitViewController` `toggleHold`/`onVerbEngaged`/`clearSelectionUndo`/`selectionMixed`/`sceneName`; `EditPage`
  `setEditMode`/`commitSession`/`revertSession`/`editGridLongPress`/`editGridLongEnd`/`midiSectionHeader`/
  `chainSectionHeader`; latent AU API (`setPreviewOverlay`/`clearPreviewOverlay`, `addMacroEmitterTargets`/
  `removeMacroEmitterTargets`, `setCellChain`, `listLibraryCells`, `factoryLibraryCells`, `loadFactoryScene`,
  `uiEffColumn`). Confirm each surface isn't held-for-rebuild before a sweep. (`Router.hasDuplicateVoices` +
  `MacroParam` decode zombies are RESERVED — keep.)
- **DONE this pass (`main`):** fixed the composeScene bug (a default-rate deployed part silently lost its short LENGTH,
  + staging-row clock could be clobbered by the piece) with a `clockClaimed` tracker + 4 composeScene tests; removed 2
  render-path allocations (`emitColumnHolds` per-call array, `applyStage` harmonize interval array); +1 rowLen-clamp
  test; removed the accidental `continuousRange` orphan.

## ★ FERRY-CAPTURED, NOT A BUILD ORDER (2026-08-19 — Paul steers; his device steps outrank the docs)
- **THE CONFIG SHEETS** (`Docs/AcceptanceCriteria/AcceptanceCriteria-config-sheets.md`, 2026-08-20 — big reframe, Paul
  walks). The legacy MIDI IN/OUT tabs RETIRE; config lives at the thing via three SHEETS opened by HOLDING a console
  subject (TAP = act · HOLD = sheet): DOOR SHEET (tap an in-strip name), WIRE SHEET (out-strip), RACK SHEET (rack chip).
  The DOOR gains a MODE RADIO **LATCH · HOLD · REPLAY · KEYS · FILE**: LATCH (toggle-in pool) · HOLD (chord-detect) ·
  REPLAY (the DOOR LOOP as a mode — input ring, PASSES 1·2·4·8 loop as living input) · KEYS (on-screen) · FILE (a loaded
  .mid loops as living input; "a FILE IS A CABLE" — CH/BLOCK/OCT/vel all apply; beat-locked f(file,beat), replay-safe).
  Console strips wear a dynamic MODE BADGE (label + tap-act: LATCH clear · RPLY·n re-catch · FILE play/pause). The RACK
  SHEET carries the SETUPS radio (RACK 1–4) + membership matrix + treatment stack — resolves the §2 two-verbs. Reconcile
  REPLAY/FILE with the door-loop ferry (siblings: remembered vs loaded input).
  **ENGINE MODEL — staged:** STAGE 1 the 4 RACK CONFIGS **DONE** (2026-08-20, `0933cf2` — rackConfigs/rackActiveConfig +
  resolvers, builder reads the active config, AU edits it, byte-identical, +3 tests). STAGE 2 the DOOR MODE enum **DONE**
  (2026-08-20 — `DoorMode {latch·hold·keys·replay·file}` + `Receiver.doorMode` + `doorModeResolved`; the latch resolvers
  honour it when set, else fall through to the legacy latchAdd/latchPiano EXACTLY → byte-identical; AU `setDoorMode`/
  `uiDoorMode` sync the legacy fields; REPLAY/FILE resolve to a HOLD-like fallback until stages 3/4; +3 tests, 803 green).
  **DOOR RANGE (Paul 2026-08-20): the door sheet must ALSO expose the note RANGE — the model ALREADY has `rangeLo`/
  `rangeHi` (+`rangeLoResolved`/`rangeHiResolved`), so it's a UI-surface item, not new engine.** **DONE (2026-08-21,
  `f497bea`/`e87c55c` — the MIDI INPUTS sheet's door section: 16-channel multi-select buttons + ALL/NONE, OCT ±, a
  RANGE row → a 6-octave keyboard MIN/MAX picker, the mode radio, and a LIVE INPUT|[MODE] test-in-place engage pair.
  Rides the MULTI-CHANNEL engine `fae473a`.)** STILL OPEN (each needs a
  device checkpoint — the latch/kernel is delicate + verified): STAGE 3
  REPLAY = the door input ring recording (a NEW engine feature, the door-loop v1); STAGE 4 FILE = .mid playback as living
  input ("a file is a cable"). STAGE 3 REPLAY **DONE** (2026-08-20, `6ad8e34` — DoorRing input ring, self-arm, capture at
  N-pass boundaries, pool from the loop; byte-identical, +tests; device-ear owed). **BUGFIX (`5b8b0d6`, Paul reported
  "REPLAY works sometimes, other times not"):** `capture` now seeds beat-0 note-ons for notes HELD across the catch
  window start (their on was before the window → previously dropped → silent). OPEN follow-ups (device-verify): a note
  still held at the catch END drones (on, no off in the window); a host that LOOPS transport makes the ring's absolute
  beats discontinuous. STAGE 4 FILE engine foundation **DONE**
  (2026-08-20, `aafdc97` — `MidiFile.decode` SMF parser + `DoorRing.loadLoop`; round-trips; 811 green). Interim UI:
  door MODE row on BUILD (`c80b7bc`/`115ce17`) — but §5/§6 below RELOCATE it.
  **⚠ DESIGN REVISION (config-sheets §4–§9, 2026-08-20) — answers "where does MIDI I/O live? it isn't per-build":**
  (§5 LAYER MODEL) the **console = the raw-input layer** (door CONFIG is global/infrastructure, correct as-is); the
  **compact grids = performance** (chrome-quiet, no config furniture); the **EYE opens a SPACIOUS VIEW = the detail layer**
  where per-row door info + row I/O pickers live (the eye is a VIEW-ZOOM, not inspection — the earlier "eyes never set"
  law is WITHDRAWN). (§4) door OWNERSHIP is per-row (which door a row hears); the door CONFIG stays global — the two
  grains separated. (§6) **TWO STACKED BUTTONS bottom of the page: `[MIDI CONFIG]` / `[RACK CONFIG]`** (left of the
  receiver strips, right of the record/reel button) → the MIDI sheet (4 INPUTS + 4 OUTPUTS) / the rack sheet. (§7) the
  sheets are the TEACHING surface — every mode carries its plain-English description in place (reuse the friendly-labels
  copy); `[RACK CONFIG]` bears the active setup ("OUT CHAIN · 2"). **⇒ my interim door-MODE row on the BUILD grid should
  MOVE into the MIDI CONFIG sheet (spacious view); the compact grid keeps at most a per-row door-tint edge (visibility
  only). Don't polish the BUILD-grid version.**
  **§9 NAMES RATIFIED (user-facing text ONLY — code identifiers NEVER rename, standing law):** "door" → **MIDI INPUT**
  (sheet "MIDI INPUTS"; per-row badge "INPUT: A"; radio "INPUT MODE"); "rack" → **OUTPUT CHAIN** (sheet header; button
  "OUT CHAIN · 2"; strip button "CHAIN"; the 4 configs → **SETUP 1–4**). So `DoorMode`/`rackConfigs`/`setDoorMode` etc.
  stay as-is in code; only the LABELS change when the sheets are built.
  STAGE 5 the UI: MIDI CONFIG sheet **DONE** (2026-08-20/21 — spacious MIDI INPUTS sheet: 16-ch multi-select, range
  keyboard, mode radio, LIVE INPUT|[MODE] test-in-place; `f497bea`/`e87c55c`). RACK CONFIG sheet **v1 DONE** (2026-08-21,
  `33965c6`; deep treatment stack inline **DONE** 2026-08-21, `427fc4d` — the OUTPUT CHAIN sheet is now one self-contained
  surface: SETUPS radio RACK 1–4 · a compact ON BOARD membership row (A·B·C·D chips, lit=in path / dim=RAW) · the full
  RackMatrix treatment editor INLINE (`RackMatrix.embedded` mode drops its header/scroll/panel; OWNS/KEY/TURNS/MONO/
  FENCE/CURVE/POCKET/CONVERSATION edited in place); the read-only summary + EDIT TREATMENTS jump + the separate overlay
  are gone). ~~PER-ROW INPUT·MODE INDICATORS~~ BUILT then DROPPED at Paul's word (2026-08-21, `969f745`→revert `436279d`
  — the staging-row-button door-tint stripe + "A·L" badge; Paul hadn't checked the placement first and pulled it). The
  full per-row I/O PICKER (the spacious "eye" view) remains the intended home for per-row door info — NOT the compact
  grid; don't re-add compact per-row badges without Paul's steer.
  The ~~RECORD button move to the top-right banner~~ TRIED + REVERTED (2026-08-21, `43ba611`→revert — Paul prefers the
  reel/RECORD glyph in the bottom-left cluster where it was; don't re-move it). DEVICE eye owed on the inline matrix (it now
  lays out in a ~640pt sheet, not the old full width). **§9 LABEL RENAME DONE** (2026-08-21, `c566054` — SETUPS radio +
  the 4 play-grid buttons "RACK n"→"SETUP n" (the buttons now WIRED to setRackConfig, active lit); dropped "door" wording;
  the "RACK CONFIG" button keeps Paul's override). **FILE STORAGE RECONCILE DONE** (2026-08-21, `89d2432` — the imported
  clip persists on Receiver.fileClip (Codable, capped 8192) through the document round-trip + rebuilds into the box + the
  Kernel reloads the DoorRing; +`testFileClipSurvivesDocumentRoundTripAndRebuilds`. Follow-up if heavy: store raw .mid
  bytes + decode-on-load instead of decoded notes).
- **MOD · SPAN + INTERNAL TARGETS** (`Docs/AcceptanceCriteria/AcceptanceCriteria-mod-span-target.md`, 2026-08-20 — MOD
  grows two axes, NOT a new processor): **§1 STEPS SPAN DONE** (2026-08-21, `8334342` — PERIOD|ROW|ROW×2|ROW×4 = 8/16/32
  breakpoints across 1/2/4 bars; `ModStepSpan` enum, box carries N breakpoints, `modStepsUnipolar` generalised to N,
  Router derives the STEPS period from it, 4-way SPAN seg + N-bar step editor; old cell|row modSpan migrates, byte-
  identical; +3 tests). **§2 TARGET → THIS CHAIN DONE** (2026-08-21, `8896219`, Paul-approved v1 mapping): `ModTarget
  {cc,chain}` + `modChainParam`; render-time BOUNDARY-DEFERRED — `applyInternalMods` copies the SnapCell at the top of
  `emitTickRow`/`emitColumnHolds`, samples each internal MOD once at the column start, re-ranges by MIN/MAX (MIN>MAX
  inverts), scales by the param's span (`macroParamSpan`), adds to every slot's param (`applyModChainOffset`, clamped
  like macros — composes on one lane); no render-path alloc; emitColumnMod skips CC + reset for internal; UI SEND = CC |
  THIS CHAIN + a param menu. Byte-identical when target=CC (oracle + fuzz green). +3 tests. Mapping of record: `offset =
  (min/127 + u·(max−min)/127) × param-span`, added to base + clamped. v1 boundaries (device-tune): STRIKE sampled at
  t=0 (≈0); ON EXIT HOLD nominal (the param only applies while the cell renders its column). Partially lands the CC-RAIL
  birthstone's mapped-values half. **DEVICE ear owed on the feel + mapping.** MOD · SPAN + INTERNAL TARGETS = COMPLETE.
- **THE MELODY/CHORD SUITE** (`Docs/AcceptanceCriteria/AcceptanceCriteria-melody-suite-UNRATIFIED.md`, UNRATIFIED —
  CAPTURE ONLY, do NOT build). RIFF (capture+remap) · TRIGGER (chords play the melody's rhythm; STAB|CLOCK) · HARMONIZE
  SOLI mode (dynamic block harmony from a door's pool) · PEDAL (hold the bar/cell's first note; FOLD-to-home register) ·
  a shortlist (gap-intelligence, contour extraction, canon rail, self-accumulation). Interface rule: receiver door chips
  (THIS·R1–R4) live IN the processor panel. Held UNRATIFIED at Paul's word.
- **THE DOOR LOOP family** (`Docs/design-door-loop-2026-08-19.md`, ratified-for-the-channel). **CORE SHIPPED** = the
  REPLAY door mode + `DoorRing` (config-sheets stage 3, `6ad8e34`): record a door's raw input, cycle it back as living
  input; RETRO-CAPTURE (the CATCH ring / LAST N; 1·2·4·8 bars); per-door independence. **CHANNEL-PRESERVATION FIX
  (2026-08-22, `a3373ad`): a channel-filtered door replayed SILENT — `DoorRing` dropped the note channel and the Kernel
  re-stamped OMNI→ch1, so channel-N cells rejected the loop; now records+replays the original channel (device
  re-verify owed). A HEALTH-panel diagnostic (`RPLY ENG · LOOP · RPOOL`) was added to bisect it.** Device-ear owed. **RIDERS
  DEFERRED TO A FUTURE VERSION (Paul, 2026-08-21):** (1) OVERDUB = ADD accumulates across passes vs CHORD replace
  (DoorRing accumulate mode); (2) PLAYBACK IS RE-ASKING = RATE (half/double-time) · TRANSPOSE · QUANTIZE-on-playback
  transforms inside `notesSoundingAt(phase)` + per-door controls; (3) THE PROGRESSION REEL = one long harmony take,
  scenes address SECTIONS (scene→beat-window model + longer ring — the big architectural one). Paul walks each directly
  (device steps outrank the doc); interlocks with the UNRATIFIED melody suite (RIFF FOLLOWING) but neither blocks.
- **BURST · PATTERN + CARRY DONE** (2026-08-21, `44ed611`; `AcceptanceCriteria-burst-pattern-carry.md`). BURST gained
  the MODE radio ONCE|COIN|PATTERN (byte-identical default ONCE): COIN = seeded chance-of-burst per step
  (`burstCoinFires`); PATTERN = the 8-slice pick-then-paint B/C/R row, CARRY = span-stretch (the roll's strikes+curve
  redistribute across the burst slice + its contiguous CARRY run, `burstCarryRun`; CELL = S/8 slices in the column, ROW
  = the 8 columns; ROTATE). Shared `layBurst` (no render-path alloc); fuzz randomises mode/slices/rotate (no stuck
  notes); +3 tests; oracle confirms ONCE byte-identical. **RATE axis deferred** (the fixed 8-slice = SPAN geometry
  covers v1 — `burstRate`/`burstRateBeats` fields exist, unused). **DEVICE ear owed** on the carry feel.

## ★★ PER-PART CLOCK — Stages A/B/C/D LANDED (2026-08-19; commits in CLAUDE.md status). OPEN follow-ups:
- ~~**Stage D — length < 8 UI.**~~ DONE — the corner control now carries a LOOP LENGTH section (1…8) editing the part's
  `buildPartLen`; staging + play grids dim columns past the loop (per-row by each row's part length); playheads already
  wrap at length. `testPerRowLengthLoopsShorterThanTheBar` proves a short row loops shorter. (Paul's "promote only
  LOOPED columns → parts shorter than 8" — the render + UI now support any length; the promote-picks-looped-columns
  behaviour itself is a separate future step.)
- ~~**echo / mod / glide per-row clock (v1 limitation).**~~ DONE (2026-08-19) — each fires on its ROW's own clock in the
  multi-clock path; MOD/GLIDE leave-disposition is now per-slot (per-row + a global slot), uniform path byte-identical.
  Remaining sub-limit: MOD SPAN=ROW's period still uses the scene bar, not the row's (minor).
- **DEVICE ear/eye owed:** two parts at different rates in one play grid (hear the drift, incl. echo/mod/glide now
  retimed per part); the per-row playheads drift out of phase; the RATE/LENGTH corner control; the reel colour roll.

## ★ THE REEL-TO-REEL — STEP 1 LANDED (Paul 2026-08-18)
The 1-pass output-tape (RECORD → REPLACE live output, LOOP; second touch resumes). Built at the Kernel seam: `ReelDeck`
+ `ReelTap` (Foundation-only, in Emission.swift, unit-tested); the tap records every emitted event with its pass-relative
beat; on ARM the just-finished pass becomes the loop and REPLACES live from the next pass boundary; a second touch
resumes live. Flushes on the transitions (allNotesOff entering replay · CC120/123 leaving) → no stuck notes. Reel-to-reel
glyph bottom-left of the BUILD page (amber armed · green replaying). Rulings applied: REPLACE the output · loop 1 pass ·
second touch resumes. macOS 762 green (4 ReelDeck tests), iOS builds. **DEVICE EAR OWED** (render path — unheard here).
- [x] **STEP 2 — EXPORT LANDED (Paul 2026-08-18)**: LONG-PRESS the reel glyph → the recorded pass exported as SMF files
  (`MidiFile.swift`, pure + unit-tested): `MidiSpark-All.mid` = the A–D SUM (each emitter on its stamp channel, cable-0
  All duplicates dropped) + a per-emitter stem (`-A/-B/-C/-D`) for each cable that has events. Files written to the temp
  dir + presented in a share sheet (`ReelShareSheet`). The deck now keeps the last COMPLETED pass every boundary (not
  only on arm), so export works after any pass. macOS 766 green (+4 MidiFileTests). **DEVICE test owed** (the share
  sheet from an AUv3 extension is the risk).
  - Delivery = SHARE SHEET, chosen (Paul 2026-08-18, "simple version for now"). The robust App Group + Files-sharing
    route (extension → shared container → container app copies to its Files-visible Documents via
    UIFileSharingEnabled / LSSupportsOpeningDocumentsInPlace) is DEFERRED — revisit if the share sheet won't present in
    a host, or once the standalone app lands.
- [x] **STEP 3 — THE PASS BROWSER pop-up LANDED (Paul 2026-08-19)**: the reel glyph now TAPS OPEN an 8×8 pop-up. TOP 4
  rows = the last 32 passes (`ReelDeck` gained a 32-slot history RING: flat `hist` buffer, `passNumbers()` oldest→newest
  so the newest lands bottom-right, `selectPass`/`selectedPassNo` pin, `selectedRoll()` note-pairing); each populated cell
  shows its 1-based pass number, tap = SELECT + REPLAY NOW (replace live output), tapping the replaying one stops → live.
  BOTTOM 4 rows = the selected pass drawn as A/B/C/D piano-roll lanes (Canvas, pitch shared-scaled, x by pass length,
  opacity by velocity). SAVE = export the selected pass via the share sheet (STEP 2 path). Engine: `reelSelectRequest`/
  `reelStopRequest` consumed on the render thread (select → replaying + allNotesOff; stop → off + blanket-off + clear pin);
  ring fills continuously while live (recording was already always-on), promote pins-aware. macOS 771 green (+5 ReelDeck
  ring tests), iOS builds. **DEVICE EAR/EYE OWED.** Answers of record (Paul 2026-08-19): tap opens pop-up (retires
  tap-replay/long-press-export) · pass tap = select+play now · Save = selected pass → share.
  - v1 notes: bottom-right = the most-recent COMPLETED pass (the in-progress pass isn't replayable); ring per-pass cap
    8192 events (dense-pass overflow drops, as the record cap already does); selecting a pass while STOPPED pins it for
    SAVE but only sounds once the transport runs.
  - **FREEZE-WHILE-BROWSING (Paul 2026-08-19)**: the history tape stops writing whenever the browser is open OR a pass is
    replaying (`reelBrowsing` set by the pop-up's onAppear/onDisappear · `reelFrozen = reelBrowsing || replaying`), so the
    pass list is a stable snapshot; recording resumes on the NEXT FULL pass on exit (only a pass recorded start→finish,
    uninterrupted, is filed — `reelRecordFromStart`). Kernel-only (not unit-tested; device-verified path).
  - **ROLL PLAYHEAD (Paul 2026-08-19)**: while a pass replays, a white playhead sweeps the piano-roll lanes (TimelineView,
    beat-extrapolated one-clock) and each note LIGHTS (full hue + glow + thicker) as the head crosses it.
  - **ROLL GRID (Paul 2026-08-19)**: each lane now draws 8 CELL dividers + OCTAVE dividers (pitch framed to whole
    octaves) with the C labelled on BOTH the left + right axis, under the notes.
  - **FULL-SCREEN + RECORDING GLYPH (Paul 2026-08-19)**: the pop-up now fills the screen (opaque backdrop, 8 equal rows
    fill the height). The reel glyph reads as RECORDING — red tape + a pulsing red dot while the tape captures live
    (`d.playing && !replaying`); green while a pass replays; dim stopped.
  - **ROLL DIVIDERS v2 (Paul 2026-08-19)**: kept octave + cell dividers; REMOVED the C-axis text labels; added a divider
    line between the four output lanes.
- v1 caveats to revisit: the pass boundary is detected at the render-block START (a few ms of slop); a brief gap on STOP
  (CC123 → the grid re-emits at the next column); the glyph is BUILD-page-only (could go global); doesn't yet snapshot
  tempo/scene changes mid-record.
- **REEL DEFERRALS — design answers (ferry `REPLY-reel-scope-answers`, 2026-08-26; scope pre-agreed, build when convenient):**
  - **#3 boundary handoff + roll-follows-reel** — device-paced is right; the switchover is BOUNDARY-deferred and the roll's
    source flips ATOMICALLY with playback (never half-live/half-reel). Build with Paul on device.
  - **#5 REVISIT (per-pass state restore)** — the snapshot = the FULL DOCUMENT STATE, captured at each pass boundary into
    the ring beside the emissions. ⚠ MEASURE the real size first (32 × KB-class); if fullState is heavy on device,
    delta-chain from the previous snapshot (fallback PRE-APPROVED — no second design pass). RESTORE = load the snapshot as
    ONE FORWARD EVENT (one undo step; the tape rolls through; history never rewrites). Nothing else restores (transport/host
    untouched). [increment 1 already landed a live-switch restore of the play-grid arrangement; this is the full-state v2.]
  - **#6 the acts log (per-pass change badges)** — stamp every UNDOABLE ACT with the pass index current AT COMMIT (acts only —
    never navigation/selection/view; undo/redo ARE acts). Entry = {passIndex · short label ("ARP RATE" · "BANK→3" · "+RTC") ·
    the act's machine HUE, or nil for scene-level}. Keep the FULL per-pass bucket (a detail line will want it); the pass CHIP
    renders the FIRST entry tinted by its hue (neutral ink when nil). Empty bucket = unlabelled chip. Build when convenient.

## ★★ RANDOMIZE = AN ENSEMBLE (grid-roll rework) — v1 LANDED (2026-08-19; commit in CLAUDE.md status)
**BUILT:** `Dice.rollEnsemble` → 8 archetypes (pad · bass · stab · arp · groove · texture · sparkle · wild), each
register-separated via `Colour.transpose` (threaded through the ephemeral-colour path) + inherent density; grid RANDOMIZE
sorts by complexity + lays them onto the 8 rows; rung-per-column is now `buildAssignArcRungs` (a sparse→peak→breath→land
ARC, not random); the flood CAP is judged at a 6-note chord (`Dice.peakAt6`), character at 3. macOS 773 green (+2). DEVICE
EAR OWED. Follow-ups still open from the contract below: true events/beat density BANDS (v1 uses inherent archetype
density + the complexity sort, not an explicit per-row budget); richer call-and-response (v1 = arc + jitter); SCALE-LOCK
(its own KEY-door session). The full ratified contract, kept for the follow-ups:
Ferry `REPLY-density-audit-answered` (design-side, absorbed 2026-08-19) answered my note-density audit and set the
PRIORITY: **THE ROLL FIRST — ahead of the note-sweep plumbing AND the display/label reconcile queue.** Rationale: the
roll is the front door's first impression; every STAGE press sells or kills the instrument, and chrome can't rescue
un-musical music. Order of work: **roll rework → display layer + reconcile (small, queued) → the feed + sweep.** My lean
was endorsed AS WRITTEN: reuse `buildByRole` + archetype/register assignment + a sparse-biased density target; **NO new
engine.** The contract:
- **AN ENSEMBLE, not 8 rolls.** The player brings the chord; the roll hands back A BAND — contrasting archetypes across
  the 8: pad · bass pulse · chord stab · arp lead · texture · sparkle · groove · wild-card. "Musical" = CONTRAST; the
  current "wall of activity" IS the failure mode.
- **Density = a SPARSE-BIASED pyramid.** Most rows sparse→medium, ONE dense, the FLOOR row GENUINELY sparse (a two-note
  pulse must be possible). Assign each row a DENSITY BUDGET BAND (events/beat) + a REGISTER HOME (oct offset / split
  range) BEFORE rolling → simple→complex true BY CONSTRUCTION; the complexity sort then sorts something real.
- **Role model + rate coherence.** Adopt `buildByRole` for the grid roll (slow root under faster figures), replacing
  `rollSimple`'s random-rate stacks.
- **Rung-per-column = AN ARC, not random.** Sparse open → build through the middle → one breath/drop column → land;
  call-and-response between adjacent registers as seasoning. Pure-chaos stays reachable as a dice DEPTH, never the
  default (SURPRISE-FIRST governs flavour, not structure).
- **Onset BUDGET** (events/beat) alongside the concurrency cap = the budget bands above. Probe fix: judge the flood CAP
  at a 6-note worst-case chord, judge CHARACTER at 3 — cheap, closes the under-prediction.
- SCALE-LOCK (the KEY door) = a real PROCESSOR, its OWN design session — NOT a randomize tweak. Parked.
- Sweep-feed connection (for later): the `ReelTap` already records per-note EMITTED events at the Kernel seam — the live
  per-cell feed the note-sweep renderer needs is that tap's COUSIN, not a from-scratch job. Start there when sweep's turn comes.

## ★ SOON — PatternSpan (SPAN: CELL | ROW) rollout to the pattern processors (Paul 2026-08-18)
EUCLID SPAN landed (`e7e0043`, on `main`; commit line in CLAUDE.md status). `PatternSpan { cell, row }` + `euclidSpan`
are in place. ROW stretches a processor's N-step timeline across the whole 8-column BAR (a cross-column phrase) —
this is the arp/weave PHASE=FREE axis generalised, NOT note-sustain legato. The `iterateTicks` column gate already
scopes each cell to its own column, so per processor the work is small + uniform: engine = ONE line (the tick-grid
denominator `S` → `cycleBeats`), model = an additive-Optional field (nil ⇒ CELL, old docs safe), UI = a SPAN CELL|ROW
seg on the face, + a row-fills-a-row test (`testEuclidSpanRowSpreadsPulsesAcrossTheBar` is the template). Roll onto
(every processor rated ★★ or higher, in priority order):
- [x] **LENGTH** ★★★ — DONE (2026-08-19, `c01a9fb`): the 8-slice gate spans the bar (standalone + composed paths).
- [x] **MOD** ★★★ — DONE (2026-08-19, `c01a9fb`): ROW = one LFO/STEPS cycle per bar; CELL = the modRate period (default,
  unchanged). The CC-stage `SPAN CELL|PHRASE|FREE` sketch resolved as CELL(=rate)|ROW(=bar); no FREE variant added.
- [x] **TUTTI (PATTERN)** ★★ — DONE (2026-08-19): ROW = the 8 slices span the bar (else the RATE stride).
- [x] **RATCHET (PATTERN)** ★★ — DONE (2026-08-19): ROW = the per-slice counts span the bar (else the RATE stride).
- [x] **BURST** ★★ — DONE (2026-08-19): ROW = the accel/decel roll unfolds across the whole bar.
- [x] **CASCADE** ★★ — DONE (2026-08-19): ROW = the reveal spreads evenly across the bar.
All six: additive-Optional model fields (old docs = CELL), snapshot + builder + `SPAN CELL|ROW` face seg, a row-vs-cell
RouterTest each, + the fuzz flips ROW on ~half of span-capable procs (no-stuck-notes across every edge).
(CHANCE was ★ — deferred. ARP/WEAVE already have PHASE; DRONE/ECHO/GLIDE already flow across boundaries.)
**DEVICE ear owed on EUCLID + LENGTH/MOD/TUTTI/RATCHET/BURST/CASCADE ROW.**

## ★ DONE (2026-08-05/06) — MACROS (phase 2 track)
Specs: `AcceptanceCriteria-macro-panel.md` · `-macro-ab-authoring.md` · `-overlay-rule-macro-lanes.md`. `feat/macros`
MERGED to `main` 2026-08-05; the canonical MACRO AUTHORING FLOW landed 2026-08-06. Commit refs in CLAUDE.md status.
- [x] M0 state model · M1 offset term (base ⊕ Σ value×delta, folded at build; seals stable) + tests · M2 the 8
  slider macros as automatable AU params · M3 the MACROS tab panel (BTN|SLD|TML; sliders drive values + padlock) ·
  **M4 A/B authoring** (the [AB] popup on the Edit page's CHAIN header → live B demonstration → bind delta to a
  SLIDER macro; base restored to A on close). **MACROS ARE USABLE END-TO-END.**
- [x] BUTTON bank completed end-to-end (values via a direct document setter for 8–23; [AB] popup SLD|BTN selector).
- [x] OUTPUT group done end-to-end: the offset extended to the per-emitter role amounts (LEAK/DUCK/CURVE/POCKET,
  MacroEmitterTarget, folded in the builder) + the [AB] popup's CHAIN|OUTPUT selector + OUTPUT authoring.

## Open within macros (forward)
- [ ] INPUT group — the source shaping. **Underspecified**: the panel spec lists INPUT as a group but doesn't name
  its continuous targets. Candidates: the velocity window (floor/ceil) · the note range (lo/hi). Needs a pick before
  building (SnapCell-field fold + an INPUT group in the popup).
- [ ] TIMELINE bank (lane editor + per-column STEP|SMOOTH|BYPASS + the render-time per-column path, which replaces
  M1's bake-at-build for lanes) · BUTTON/TIMELINE binding + mover-eligibility live-dim · the A↔B morph-audition
  slider · the CC rail · the perform-surface panel in the GRID top band (part of the phase-2 GRID redesign) ·
  announce/ghost-thumb tells.

## ★ DONE (2026-08-05) — LAYOUT v2 tab shell (phase 1)
Spec of record: **`Docs/AcceptanceCriteria/layout-v2-tabs.md`**; plan `~/.claude/plans/resilient-imagining-truffle.md`.
On `main`, iOS builds, 428 green; commit refs in CLAUDE.md status; **device pass owed**.
- [x] Part 0 — retire SELECT · Parts 1-2 — six-tab bar + body switch (`AppTab`) · Part 3 — clock→header ·
  Part 4 — RECEIVERS tab (`ReceiverConfigView`) · Part 5 — EMITTERS tab (rack out of the grid).
- [ ] **Phase 2+ (deferred, captured):** GRID top-band 8 macro sliders+buttons · SINGLE|MULTI toggle · HOLD
  localisation per slider group · the MACROS + AUTOMATION engines/pages · global FREEZE/STUTTER gestures ·
  MIDI-OUT channels moved into the emitters tab. (These are engine/authoring work — needs Paul to prioritise.)

## ★ DONE (user, 2026-07-29) — /btw authoring UX + AcceptanceCriteria wave
Spec of record: **`Docs/AcceptanceCriteria/verbs-behaviour.md`**. All LANDED off-device (device pass owed) —
commit refs in CLAUDE.md "Current status":
- [x] **/btw ⑥** one-per-column per-hold · **④** retro-repaint · **⑤** per-cell + row selectors (already built) ·
  **STROKES** · **MIXED-SET law** · palette-live-during-holds (via ④).
- [x] **AcceptanceCriteria additions**: SELECT empty-tap no-op · **DELETE = SEVER** (children cut to MIDI-IN) ·
  **DESK RE-POINT** hard rule · **multi-cell routing (per-column)** + **SRC/DEST pulsing candidate look** ·
  placed/selected cells always WHITE · PLACE nearest-above nudge · **sticky routing** · **verbs do NOT latch**.
- [x] Refactor + tests: routing logic → pure `Derivations` helpers (`routeFociByColumn`, `placedCellRouting`) +
  `deleteCell` dedup (`181bf7c`).

## A. Blocked on the user (need a decision before building)
- [~] **Accent-colour dedup (refactor B1)** — MIGRATION IN PROGRESS. A `DesignKit.swift` token layer LANDED
  2026-08-16 (`enum UI`: cyan/amber/red/green/editHue/ink, values unchanged, migrated across ~10 files). BUT it's
  PARTIAL: the cyan literal still appears ~18×, amber ~16×, `editHue` is defined twice, and `FlowView.swift` still
  hardcodes a divergent receiver-hue array. **REMAINING OPEN DECISIONS:** `FlowView.swift`'s cyan is
  `Color(red:0.145,g:0.878,b:0.941)` — a real ~0.005 near-miss of the canonical `0.15/0.88/0.94`, still unruled
  (unify to canonical, or keep FlowView's tuned-for-dark-canvas value); and the same call on FlowView's divergent
  lighter receiver-hue array vs `receiverHues`.
- [ ] **midiNoteName convention** — the shared `midiNoteName` is 0-based (note 60 = "C5"); `RackMatrix.noteName` is
  `n/12−1` (note 60 = "C4"), so FENCE labels read an octave below the receiver RANGE labels. `midiNoteName`'s doc
  says it exists "so naming can't drift". Pick the canonical convention (C4=60 is the common MIDI one) → unify (a
  visible label shift, hence a ruling).
- [ ] **HOLD latch re-home** — §5c latch UI slot is vacant; CONTROLS-corner restoration recommended, awaiting the nod.
- [ ] **SCOPE ops home** — chips-during-SELECT-hold vs deferred (design device-nod).
- [x] **DELETE-sever fallback in the null era** (user ruled NULL, 2026-07-30) — severed children now fall to NULL
  input (inputRow nil AND inputReceiver nil, own emitters kept) instead of a phantom R1 re-point. Done in
  `deleteCellSever`; test updated. Reply to design-side owed (bundle with the file-read ack).

## B. ✅ DEVICE-VERIFIED (user device pass, 2026-07-30 — "happy with things as they stand")
The whole accumulated GUI + engine stack was run on device and ACCEPTED. Cleared from the owed list:
- [x] **Adoption ear-check** · **Strips** (session faces · LATCH · DUCK · SPACE-FILL · receiver marks · emitter buttons · verbs-as-pills) · **COPY·PASTE** · **preset enlarge + UNDO/REDO** · **white selected ring**.
- [x] **AcceptanceCriteria wave (2026-07-29)** — /btw ④⑥ · STROKES · MIXED-SET · DELETE-sever · multi-cell routing · candidate body-pulse · desk re-point.
- [x] **Routing view + visualisation (2026-07-30)** — IN/OUT labels · candidate-hides-content · the routing overlay (curved flows + comets · cell→cell arrow · band dots · clip-over-uncrossed · lane separation · lit-through-selected).
- [x] **Cells & colour desk overhaul (2026-07-30)** — cell face (emblem · digest · dots · compass tint · trigger glyph · white selection) · desk title-as-picker + popover · Colour NAMES · SPARSE palette · census protection. _(Placeholder SF-Symbol emblems still stand in for real artwork — the drawing job is a separate asset task, not a bug.)_
- [x] **Fresh-cell + naming + furniture (2026-07-30)** — fully-null new cells · full processor names · grid down-chevrons (watermark + column keys) · dual-side row rails · DELETE-sever→NULL.

## C. Buildable now (next increments)
- [x] ~~**MOSAIC §2 — THE CREST**~~ — DROPPED 2026-08-23 (Paul): the whole MOSAIC cell face was removed (it was dead on
  the main grid since the piano-roll face won 2026-08-19). The crest follow-up is moot; the piano-roll face is the cell
  visualisation now. `AcceptanceCriteria-mosaic-face.md` deleted.
- [ ] **THE WINDOW — the pre|post note graphic** (design ferry 2026-08-06, spec `AcceptanceCriteria-the-window-
  graphic.md`). ONE parameterized piano-roll component (NOW divider · held input bars left · derived-future rects
  scrolling in + firing at the line; brightness=velocity). LIVE (derive-ahead ~2 beats, pure) + CANNED modes; sizes
  S/M/L; sites = processor boxes · macro page MAIN/ALT · library · manual · receivers. §2 THE EYE = a header-bar
  inspect toggle → cell-tap opens the window popup. Needs a pure `scheduleAhead(...)` derive-ahead + the `NoteWindow`
  view. Larger feature; §3 LONG WINDOW / RACK VARIANT flagged futures.
- [x] **MACRO AUTHORING FLOW (canonical)** (Paul + design 2026-08-06, spec `AcceptanceCriteria-macro-authoring.md`;
  **LANDED 2026-08-06 — `MacroBindPopup` removed**) — a GENERIC control-group authoring page (MAIN/ALT instances →
  TEST slider+button → ADD-TO-MACRO assignment view), hosted by a control-group registry so processors · receivers ·
  emitters · rack all reuse it. Sparse relative deltas (the M1 offset model — already built); host-adaptive
  transactions (staged vs live); mover eligibility (discrete→buttons only); ALT persists per group; first-assign sets
  spring/toggle then locks it. KEPT the offset engine (M1) + AU params (M2) + MACROS tab (M3). **Residue still open:**
  the receiver / emitter / rack authoring domains (only the processor domain shipped) + the discrete-param binding
  path (only the 7 foldable continuous keys reach the engine). A future MACRO MAIN TAB (management surface) is
  separate + later.
- [x] **CONTROLLER ROUTING v1** (design ruling 2026-08-06, spec `AcceptanceCriteria-controller-routing.md`;
  **LANDED 2026-08-10 — `Receiver.controllerMask` exists**) — per-door cog mask CONTROLLERS→[A·B·C·D] (default
  all-live); forward matching CC/PB/AT/PC to each selected emitter RE-STAMPED to its channel; supersedes the
  hardwired `passthroughCableMask`. **CC123/120 = pool/latch FLUSH + forward** (all-notes-off must release us).
  **UMP legacy parity where cheap** (system/SysEx pass). BEND-ownership rule reserved for the future per-emitter
  bend stage. Model seam: `Receiver.controllerMask: UInt8?` (nil ⇒ 0b1111).
- [x] **MPE toggle + auto-detect RETIRED** (design ruling 2026-08-06, on `main`) — the RECEIVERS-tab MPE toggle
  (`ReceiverConfigView.mpeRow`) + the write-only auto-detect (`mpeSeenAt`) are gone (manual-honesty law: the UI
  stopped promising what nothing reads). `Receiver.mpeMerge` stays Codable + `setReceiverMpeMerge`/`mpeLikely`
  reserved for the two-lane expression era.
- [x] **THE "STRIPS DONE" WAVE** — emitter hold-while-sounding feed built + **device-verified 2026-07-30**
  (steady cargo-tinted `SoundMark` ticks + fade-on-release; `Router.snapshotEmitterSounding`; test
  `testEmitterSoundingReportsHeldNoteOnItsBusThenClearsOnRelease`). ④ polish-laws accepted at current values on
  the device pass. _(Latent: the release-fade keys on (vel, colour) not the wire note — same-vel chords could
  mis-pair a fade; not seen on device, revisit only if it surfaces.)_
- [x] **Full strip EDIT-face sweep** — DONE (off-device): the strips' EDIT faces were dead in the live path
  (nothing passed `editing:true`) and their config already lives on the cog (`CogPage.swift`). Retired
  `OutputsView.channelStepper` + `ReceiversView.editFeatures` and the `editing` param on both, plus the orphaned
  callbacks/helpers. Strips are single-face forever. _(Separate future: `GridView.editing` — the grid's own
  cell-editor mode — is untouched.)_ Device-verify: the strips look/behave unchanged (perform face only).
- [~] **CELL EDIT** (spec `Docs/AcceptanceCriteria/AcceptanceCriteria-cell-edit.md`; user-chosen phased build).
  **⚠ BANNER (2026-08-13): the PROCESSORS / cell-edit page was RETIRED — BUILD supersedes it; `editSpikePage` is now
  unreachable dead code.** So the whole block below is HISTORICAL: the crash bug is MOOT (the page can't be reached),
  and every open sub-item here needs TRIAGE — folded-into-BUILD, wanted-elsewhere, or dropped. Detail kept for the
  record; do not treat the `[ ]`/`[~]` marks below as live forward work until triaged.
  Decisions locked: start with the station skeleton; **triggers stay Colour-side** (no per-cell schema change).
  **LAYOUT (evolving): design-side revised B to a full-page takeover (2026-07-31); the USER then overrode that —
  the page REPLACES THE GRID in its slot (via `gridBlock`, like FLOW) while receivers/emitters/strips/desk/arr-bar
  stay visible + reachable. Spec B on file still says full-takeover — ferry the user's grid-slot override to
  design-side.** Content/model/engine/tests unaffected by all this layout churn.
  **~~OPEN BUG~~ MOOT (page RETIRED 2026-08-13, unreachable): crash on tapping the TRIGGERS section (device, first
  Cell-Edit device run). No logic error on that path (collapsed rows are plain text) → suspected a SwiftUI
  transition/nesting crash; the grid-slot move may have cleared it. No longer reachable, so no retest needed.**
  - [x] **Phase 1 — station skeleton + full-page rework** (off-device): EDIT = a 6th TOGGLE (out of the `Verb`
    enum); tap re-points + suppresses the trigger fire. **Re-architected to the full-page takeover**: `cellEditPage`
    replaces the whole grid layout when a cell is pointed; pinned breadcrumb (scene · column · 8-dot minimap ·
    DONE); persistent LOOP+TEST strip (placeholders; test pad shows the glyph, H6); ONE vertical accordion
    (IDENTITY · INPUT · TRIGGERS · OUTPUT · sound-desk, B4). Retired the `primarySlot`/`deskSwapBar`/`deskShowsColour`
    in-place swap. Device-verify: takeover push/return (DONE + re-tap EDIT), breadcrumb minimap, one-open accordion.
  - [x] **Phase 2a — triggers accordion** (Colour-side, off-device): a one-open accordion editing `Colour.on`
    via `editOn`→`editBrushColour` (undoable); reused `OnConfig` wholesale — no schema change. **Curated to the
    WIRED actions only** (user, this version): TAP none/alt/mute/solo · HOLD none/alt/oct · ARRIVE none/alt-
    alternate/morph-drift/emitter-rotate; the inert placeholders (fill/replay/freeze/slice-cycle/morph-scrub/dice)
    + the LEAVE & SCENE rows are hidden (enum cases kept for a future TOUCH-box design pass). Device-verify:
    pickers offer only the wired actions, each fires in perform, edits ride to the cell-face glyph.
  - [ ] **Phase 2b — REDIRECT + retrigger style** (NET-NEW model+engine): the REDIRECT TAP/HOLD action + ALT-DEST
    A–D toggles (new `OnConfig` field + admission-time engine effect); the TAP CUT|LAYER retrigger field.
  - [~] **Utilities §I**: [x] Apply-input-to-scope (twins / all-colour, reuse `applyToScope` + live counts) +
    Reset-input (off-device). [ ] Copy/Paste CONFIG (a cell input+triggers clipboard, `ProcClip` pattern) — deferred.
  - [x] **Phase 3 — input editing** (COMPLETE, off-device): source · octave/transpose · chord-split · velocity window.
    - [x] **3a source picker** (off-device): NONE · MIDI-IN R1–R4 · FROM ROW n value-chip, editing the existing
      `inputRow`/`inputReceiver` (reuse `routeInReceiver`/`routeInRow`/`routeInSourcesAbove`). No schema change.
    - [x] **3b chord-split** (NET-NEW, off-device): ALL · TOP n · BOTTOM n · KEY RANGE. `Cell.chordSplit?`
      (migration-safe) → `SnapCell`; pure `chordSplitWindow` applied inside the `srcCount(for:)`/`srcAscending(for:)`
      readers (contiguous window, ALL fast-path); station INPUT SPLIT control (per-cell). Tests: window (all
      modes+edges) · readers apply it · Codable/migration. _(Follow-up: preview/audition STRUM use a raw filter,
      so the split doesn't reach those two paths yet.)_
    - [x] **3c velocity window** (NET-NEW, off-device): `Cell.velWindow?` (migration-safe) → `SnapCell`;
      velocity-aware base readers composed as velocity-admit THEN chord-split (full-range fast-path); station
      VEL ≥ / VEL ≤ steppers. Tests: gating + composition + Codable/migration.
    - [x] **3d input octave + transpose** (off-device, REUSE not net-new): per spec "existing steppers,
      unchanged" — surfaces the per-Colour `transpose` (−24…+24 st, already engine-wide) as a SHIFT row (octave
      ±12 + semitone ±1) via `setBrushTranspose`. Colour-side like triggers; no schema/engine change. _(If a true
      per-CELL input transpose is wanted later, that's the net-new ~5-site version — deferred.)_
  - [~] **Phase 4 — output/chop** (spec F REVISED 2026-07-31):
    - [x] **UI + model** (off-device): MAIN dest A–D (LIVE, edits cell.buses) · the 8×2 chop grid (MAIN+redirect
      dot / MUTE) · shared ALT A–D. New `Cell.chop` (Chop = 8 slots + alt set, migration-safe; Codable test).
      Grid/alt edits persist but are labelled "routing engine pending".
    - [~] **chop routing ENGINE** (SEMANTIC confirmed by user: 8 slices divide the CELL'S OWN column, a per-cell
      output gate — not pass columns):
      - [x] **TICK cells** (off-device): `chopSlice(mBeat, columnBeats:)` → each ARP tick / RATCHET repeat routes
        MAIN/ALT/MUTE by its slice within the column (`chopBusMask`); MUTE-slice = silent. Tests cover both pure
        fns. (Reverted the earlier wrong pass-column indexing.)
      - [ ] **HOLD cells** (identity/chance/harmonize) — the trance-GATE: sub-articulate the sustained
        chord into 8 slices (note-off at MUTE edges, ALT redirect), interacting with legato/harmonize/adoption.
        The bigger piece.
      - [ ] **STRUM + row-fed MIRROR** chop (thread the onset slice in).
    - Open call F (emitter-picker vs spatial ROUTE-OUT) — both surfaced now (two doors); leave as-is unless the
      user rules to collapse them.
  - [ ] **Phase 5 — LOOP**: single-column loop ≈ one-bit `laneMask` via existing `lapColumn` (very low engine
    risk); UI toggle + wiring. Resolve open call G3 (LOOP-starts-playback-when-stopped).
  - [ ] **Phase 6 — test pad**: real-path stopped-time trigger fire (self-driven clock + silence-invariant
    exemption + scope). Hardest engine piece.
- [x] **Trigger-glyph cell face** (§3) — built in the cells-and-colour-desk overhaul (emblem · trigger glyph · digest · dots · compass tint) and device-verified 2026-07-30.
- [x] **Touch completions** — palette LIVE during holds · **STROKES** · **MIXED-SET law** — ALL DONE (2026-07-29; see the DONE block above).
- [ ] **Live preset previews** · **SCROLL+TEACH** (both deferred-flagged).
- [ ] **Tag `v0.7-gui`** (user tags manually).
- [ ] **CAPTURED via ferry 2026-08-07 (specs of record, NOT built — design-side Claude, Paul's asks):**
  - [x] **GLIDE processor** (`AcceptanceCriteria-glide-processor.md`; **LANDED 2026-08-10 — `ProcessorType.glide` +
    `GlidePriority` exist**) — notes→pitchbend: first note = anchor, each next = a bend ramp (mono sliding voice);
    RANGE handshake; out-of-range RE-ANCHOR (steps glide, leaps articulate) or CLAMP; params TIME/RANGE/PRIORITY.
    Shares BEND's expression scheduler + channel-ownership plumbing.
  - [ ] **WEAVE driver** (`AcceptanceCriteria-weave-driver.md`) — a rank-clocked polyrhythm DRIVER (arp/rtc/strum
    family; last-driver rule): each pool member ticks on its own rank-derived clock. MODE = LADDER / HARMONIC★ /
    DRAWN; params BASE/GATE/SPAN. Two chips: TAPE (rate×2 → +12) · DUR-BY-INTERVAL (leap → length). Pure per-rank.
  - [ ] **EDIT-TIME DERIVATION SERVICES** (`AcceptanceCriteria-edit-time-derivation.md`) — one facility
    `deriveInput(toSlot:against:span:)` (the dice's audition machinery, exposed offline) → four services: FITTED
    DEFAULTS (a newborn stage seeds from its input) · PICKER PREVIEWS (choose a type by result) · DEGENERACY
    WARNINGS (flag near-silence/wrap before commit) · ADAPTIVE RANGES + derived slot summaries.

- [ ] **RATIFIED 2026-08-22 (Paul's word) — `Docs/processor-pairings.md` §7 ① and ② are BUILD ORDERS (IN PROGRESS):**
  - [x] **① GLIDE AFTER A MONO DRIVER — v2** (`processor-pairings.md` §7 ①) — **LANDED 2026-08-22, macOS 827 green,
    iOS builds; DEVICE ear owed.** `[driver→GLIDE]` — the driver's notes feed GLIDE's mono voice (steps bend over
    `glideTime`, leaps past RANGE re-anchor/clamp, column-exit/key-release ends the phrase). `emitDriverNote` records +
    suppresses the driver note (keyed by `currentCellIndex`); a post-tick `emitGlideDriven` pass drains the targets into
    the shared `glideVoices` (flushGlide/phrase-end/no-stuck-notes cover it). Generic across ALL drivers, not just
    ARP/CASCADE. +2 RouterTests. Multi-emitter fan-out stays a SEPARATE deferred v2 item.
  - [x] **② ECHO MID-CHAIN** (`processor-pairings.md` §7 ②) — **DRIVER-PATH LANDED 2026-08-22, macOS green, iOS
    builds; DEVICE ear owed.** The ferry's "existing birthstone stands ready" was WRONG — no ROUTE chip existed; built
    from scratch. NEW `EchoRoute { direct, chain }` (append-only, `.direct` default = byte-identical). CHAIN: each echo
    repeat is re-folded through the stages AFTER the ECHO slot at ITS OWN beat (`refoldEchoRepeat` in `drainEchoTails`,
    which now takes `box`; the `EchoTail` carries `route`/`cellIdx`/`echoSlot`). `emitDriverNote` registers CHAIN tails
    from the pre-post-echo set. `[ARP→ECHO→LENGTH]` = repeats choked/tied by the slice they land in · `[ECHO→SPLIT]` =
    thinned by register/velocity · `[ECHO→HARMONIZE]` dressed per repeat. +1 RouterTest. ROUTE chip in the echo box.
    **NON-DRIVER HOLD PATH LANDED 2026-08-23** (macOS green incl. fuzz, iOS builds): hold-tail `[ECHO→HARMONIZE/SPLIT]`
    `chainEchoParams` block made ROUTE-aware; `[ECHO→LENGTH]` (registered ZERO echoes — swallowed) now registers via
    `registerLengthChainEcho` (from `emitEchoColumn`) + an `echoMuteDry` guard. +3 tests + fuzz echo-CHAIN randomizer.
    An adversarial-review workflow caught 2 bugs (FREE+MUTE silence regression → free-timeBeats fix; SPAN=ROW dry/echo
    divergence → refold honors lenSpan). v1: hold-tail block stays synced-only; MUTE not honored for hold-tail echo.
  - [ ] **③ PASSES v2 — the per-lap switchboard** — STILL CAPTURED, NOT ratified. Do not build until Paul's word.

- [x] **THE UTILITY SET — OCTAVE·TRANSPOSE·CHANNEL·NUDGE — LANDED 2026-08-22** (`AcceptanceCriteria-utility-set.md`;
  ferry-ratified). New UTILITY catalog group; 4 simple per-chain transforms. OCTAVE/TRANSPOSE = pitch-shift set
  transforms; CHANNEL/NUDGE = note-transparent emit overrides (byte-identical when unset). +6 RouterTests; macOS green
  incl. fuzz; iOS builds. DEVICE eye/ear owed. **Echo tails now INHERIT the cell's channel/nudge (2026-08-23 review
  sweep) — [CHANNEL→ECHO] echoes on the cell's channel; the earlier "wire defaults" v1 limit is resolved.**
- [ ] **RATIFIED 2026-08-22, UI-HEAVY — captured, DEVICE-owed (built off-device is not meaningful; need Paul's eyes):**
  - [~] **THE GRID SELECTOR** (`AcceptanceCriteria-grid-selector.md`) — **v1 LANDED 2026-08-23** (iOS builds; UI-only,
    device eye/ear owed). Full-page 8×8, each cell = a complete MIDI chain; the active cell shows a piano-roll of its
    output (hue tiles otherwise); QUANTIZE defaults to INSTANT; tap = live audition vs
    current input (mutually-exclusive, QUANTIZE STEP|INSTANT); COMMIT overwrites the arrival row's chain (one undo) /
    CANCEL restores the pre-open voice; RIGHT column = read-only chain; the reel records it. Banks v1: **DEALT** (64
    seeded, off-thread + RE-DEAL) + **MY LIBRARY** (saved+factory by section). Built understand→implement→review (a
    4-lens adversarial review caught + fixed 7 bugs). **DEFERRED / for Paul:** FACTORY as its own curated 64-bank (the
    content deliverable); §2 EXCLUSIVE-OFF layering (audition BANDS); stopped-transport audition is silent (inherent,
    a hint shows); the working name pending the no-metaphors pass.
  - [x] **THE IN/OUT TRUTH STRIPS + THE STAGE EYE — LANDED 2026-08-25** (`AcceptanceCriteria-in-out-truth-strips.md`;
    §1 truth strips `98bec19`, §4 stage eye `ff8a350`, idea-24 touch-to-diff `535cae5`). The track is FEATURE-COMPLETE
    (all device-eye owed); v2 sweep items remain (§4 column-aligned sweep · bespoke per-type mechanism art · embed the
    real hero read-only).
    - [–] **§2 AUDITION FALLBACK — REMOVED 2026-08-23** (NOT landed). The reference-chord fallback was deleted entirely
      (Paul: "should never be part of the user experience"); no `refPool`/`refChordDoor`/`setChainReference` in the code.
      The truth strips are now the SOLE cure (the see-it half). Superseded, not shipped.
- [x] **TAP processor — LANDED 2026-08-25** (`2621dd3`, `AcceptanceCriteria-tap-processor.md`, ratified). The mid-chain
  SEND: `ProcessorType.tap` mirrors each passing note to a chosen wire (LEVEL · TO THIS/A/B/C/D · MUTE the dry) then
  passes `cur` through unchanged. +1 test + fuzz. (This was "NOT RATIFIED" — now built; see §3.)

## D. Parked futures — log only, NO build (re-explain from `design-ferry-completions-phase-cc-2026-07-28.md`)
- [ ] FEEDBACK EDGES (unit-delay) · THE PIN · MASTER+TEXTURE multi-playhead · **THE CC RAIL** · **THE TWO-LANE INSTRUMENT** (+ cross-lane valves) · MORPH desk (16 faders) · EXTERNAL processor type + standalone-app milestone.
- [ ] **MULTI-INPUT / fan-in — THE G1 RULING** (design-Claude, 2026-07-30; captured here because the ferry note is
  transient). Shipping subset = **multi-RECEIVER-in** only (merge the four doors); keep the single row-parent so
  chains stay trees (no DAG, cycles impossible). At a union point: the pool is a **refcounted SET** (a note lives
  while ANY source holds it; entry dies at count 0; dedup by wire note-number after per-source transforms).
  **Velocity** = the latest strike UPDATES the pool entry but NEVER re-strikes a sounding hold-voice (applies to
  the next articulation). **Voice identity stays source-blind**: note + emitter + Colour-and-face, refcounted at
  the union. Full multi-row-parent remains the parked birthstone (schema-as-set already insures it).

## E. Architecture debt (opportunistic, all accepted)
- [ ] §6a CLAIM L3 residual (short-note All `on,off,on,off`) · `TODO(spec §7)` param route (writes doc then rebuilds) · `Cell.stack`/`srcMix` kept load-bearing for the v2→v3 migration.
- [~] **HARMONIZER hung-note ROOT CAUSE** (user-reported device bug, 2026-07-31) — the §a8b playing-time net auto-clears
  it within ~1 s (safety net, committed). **INVESTIGATED 2026-08-23 (adversarial 4-lens hunt + repro tests):** the
  NORMAL-PLAYBACK harmonize path is CLEAN — all four leak modes (fan-out collision vs refcount · drainDue-vs-strike
  boundary ordering · live interval change without flush · on/off wire divergence via fence/octave/masterKey) were
  traced to safe with line citations, and a repro test (collision {60,67}+7 + mid-sustain interval change) shows the
  sounding set stays refcount-balanced with nothing stuck. The reported transient hung-note was **NOT reproducible
  off-device** → it is device-timing-specific (render-block/note-tracker), still owed a device repro to pin.
  **The hunt DID find + FIX a separate real bug** (`adoptLegatoBus` over-un-marking under a SELF-COLLIDING harmonize
  auditioned via PLAY: THIS CELL — a per-window immortal-voice/refcount leak that machine-guns toward the voice cap;
  62 re-strikes over 94 windows → <6 after the fix, adopt one own+All pair per call). +2 RouterTests. Root-cause work
  is thus advanced but the ORIGINAL device symptom remains open (needs the device repro).

## F. Codebase-review carry-over (§12, 2026-08-16)
The currently-open medium/large work captured in `Docs/codebase-review-2026-08-16.md §12` (and CLAUDE.md status) that
this file otherwise omits — one line each, see the review for detail:
- [ ] **BuildModel / ColourRegistry extraction + BUILD selection unification** — pull BUILD's model out of the view.
- [ ] **Colour-owned routing** (the "four steers ①") — lift buses/receiver/chop off `Cell` onto `Colour`.
- [ ] **Split `Router.process`** — the ~35-arg monolith.
- [ ] **Persisted-DTO / working-model split** — separate the on-disk document from the live working model.
- [ ] **Total macro model** — discrete-delta bake (bug M1: discrete-param macros don't fold yet).
- [ ] **RACK engine tests** — fence / mono / pocket / conversation / curve are untested.
- [ ] **Unassigned-BUILD-part persistence follow-ups** — the deployed play-grid isn't persisted yet, and "exactly
  one unassigned part" isn't a hard invariant.

---
_Done this thread (moved off the list): /btw ①②③ · adoption · strips session-faces/LATCH/DUCK/SPACE-FILL/receiver-marks · verbs reverted to pills · CONTROLS single-face · §10 spec fold. **2026-07-29 wave:** /btw ④⑤⑥ · STROKES · MIXED-SET · DELETE-sever · multi-cell routing + SRC/DEST look · desk re-point · sticky routing · verbs-no-latch · routing refactor+tests. See CLAUDE.md status for commit refs._
