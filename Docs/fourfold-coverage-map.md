# Fourfold coverage map (ENGINE HARDENING 1, 2026-11-21)

Every release-reachable control of the Fourfold page, with what it writes, which engine code reads it, which macOS tests exercise it, whether `PortsStressTests` randomises its fields (and over what range), and any matching device-owed item.
Built from 17 per-area control surveys + the test-suite map + the stress-fuzz recon + the device-debt recon (paths in **Sources**). One row per control (gesture variants of one control — tap/drag/double-tap/VoiceOver — are merged when they write the same fields).
Read **Writes** as `EuclidLine.*` unless prefixed; `live word:` = a Kernel/Router live value, never saved or undone. **GAP: none** = no test reaches the control's fields. **Fuzzed? NO** names the reason (NOT-randomised list, absent, or a live word left at default).
Caveat on the Fuzzed? column: the two `PortsStressTests` base fingerprints are RED on main (pending re-capture since ANSWER v2, `Docs/pending-tasks.md:2133`) — the invariants still run, the pins don't currently gate.
Sources: 19 survey tables (~160 source rows), 148 test files / 2,731 tests (testsmap), stress.md §1 randomised + NOT-randomised lists, docs.md §1 `[engine-behaviour]` list. 136 control rows below.

| Control | Writes (document fields) | Engine readers | Tests (by name) | Fuzzed? (field + range) | Device-owed |
|---|---|---|---|---|---|
| **AREA — TAB STRIP + LANE CARDS** | | | | | |
| Tab-strip segment tap (8 segs in release) | none (page `@State pageTab`) | — (display only) | LaneViewStripTests | n/a | — |
| PLAY RIFF tile (×4, every front tab) | `riffOn` (+`enabled` on turn-on; master-off path: all lanes' `riffOn` + `riffMaster`=nil) | `laneSounds(riffOnResolved, riffMaster)`, `enabledResolved` | PartPlayButtonTests, PlayButtonsAmendmentTests, MastersTests, RouterTests | riffOn YES (rLine Bool); riffMaster NO | — |
| PLAY STACK tile (×4) | `notesOn` (+`enabled`; seeds `notesLitOrder` rank 1 if none lit; master-off path: all lanes + `stackMaster`=nil) | `notesOnResolved` × `stackMaster`, `euclideousNotesLayerIsOn`, litOrder | PartPlayButtonTests, MastersTests, NotesTabTests | notesOn NO (rLine draws litOrder, never the switch); stackMaster NO | — |
| Lock badge tap (unlock) / hold (capture) — only on a doc already locked | `PluginState.euclideousLocks[lane]` | `Router.planLocks`, `Kernel.euclideousLockLive` | LaneLockTests | locks YES (50 % of rDoc docs locked); snap churn NO (`lockRevs: 0` always) | LOCK snap clean at 64/1024 buffers; stopped snap-back (debt L219–230) |
| Comet strip: vert drag HITS / pinch STEPS / horiz drag OFFSET (×4) | `pulses`+`hitsRequested`+`customHits` / `steps`+`rotate`+`customHits`=nil / `rotate`+`offsetRequested`+`offsetFraction` | Router `L.pulses/steps/rotate`, `euclideousHitPatternInto`, `euclideousHitLayoutInto` | RouterTests, RhythmPolishTests, DerivationsTests (euclideousSliderCommit), LaneLockTests | pulses 0…16, steps 1…16, rotate −8…8, offsetFraction nil/0…0.999 YES (rLine); customHits NO | — |
| Comet strip two-finger (ALL lanes HITS / OFFSET) | every lane's `pulses`/`customHits` / `rotate`+`offsetRequested` | same pattern builders | same (fields); the all-lane funnels themselves are UI-only, untested | same as above; customHits NO | — |
| Comet strip tap a step (toggle hit) | `customHits`, `pulses`, `hitsRequested` | Router `customHits` (replaces Euclid build) | TapStepTests, RouterTests | customHits NO | — |
| **AREA — EUCLID tab** | | | | | |
| HITS stepper (+ / − / value-drag / VO) | `pulses`, `hitsRequested`, `customHits` (rebuilt) | Router `L.pulses`, `euclideousHitPatternInto`; `hitsRequested` has no render reader (by design) | RouterTests, DerivationsTests, LaneLockTests | pulses YES 0…16 (rLine) | — |
| STEPS stepper / drag / VO / length picker | `steps`, `pulses`, `rotate`, `customHits`=nil, pins `hitsRequested`/`offsetRequested` | Router `L.steps`/`L.rotate` | RouterTests, DerivationsTests | steps YES 1…16 (rLine) | — |
| OFFSET slider + double-tap + VO | `rotate`, `offsetRequested`, `offsetFraction` | `rotate`; `euclideousHitLayoutInto` (HIT TIMING) | RhythmPolishTests (own golden), RouterTests | rotate −8…8, offsetFraction YES (rLine) | — |
| TILT slider + double-tap + VO | `tilt`, `tiltFine` (drag no-ops on hand-edited lane) | `euclideousHitPatternInto` (bias), `euclideousHitLayoutInto` (fine) | RhythmPolishTests | tilt −1…1, tiltFine nil/−1…1 YES (rLine) | — |
| Rate tiles 1/1…1/32 + feel EVEN·DOT·TRIP | `rate` | Router `L.rate?.beats`, lap maths | RouterTests, EffectiveParamsTests | rate YES nil/any ArpRate (rLine) | — |
| Direction tiles ◀ ⇄ ▶ | `direction` | `directionResolved`, `euclidCycleLen`, walk mirror | DirectionDisplayTests, RhythmDirectionHuntTests, RouterTests | direction YES [fwd, bkw, pingpong] (rLine) | — |
| FLIP HITS tile (one-shot) | `customHits` (baked flip), `patternMiss`=false, `pulses` | Router `customHits`, `patternMiss` gate | RhythmPolishTests (euclideousFlipHitsPattern) | customHits NO; patternMiss YES nil/true (rLine) | — |
| LET RING tile | `notesRing` | Router:4396 stack notes ring to walk-cycle boundary | RouterTests, EffectiveParamsTests | NO (stress NOT list: RING) | RING release clean at cycle boundary, by ear |
| **AREA — RIFF tab** | | | | | |
| RIFF toggle tile | `riffOn` (+`enabled`; master-off path as PLAY RIFF) | `laneSounds(riffOnResolved, …)` | PartPlayButtonTests, MastersTests, RouterTests | riffOn YES (rLine) | — |
| Direction segmented BKW / PING-PONG / FWD | `riffDir` (+`riffOn` — tap lit segment switches riff off) | `euclideousRiffDirResolved` → walk | RiffDirectionHuntTests, RiffDirectionMirrorHuntTests, RouterTests | riffDir YES all 6 incl. retired (rLine) | — |
| ADVANCE EVERY stepper (1…8) | `riffAdvanceEvery` | `riffAdvanceEveryResolved` → `euclideousRiffWalkStep` | RiffWalkTests, RouterTests | PARTIAL — rLine draws 1…4 only; UI reaches 5–8, never fuzzed | ADVANCE EVERY 5–8: no stuck/doubled hits (debt L204–209) |
| HIT \| STEP segmented | `riffAdvanceStep` | `riffAdvanceStepResolved` | RiffWalkTests | YES (rLine Bool) | — |
| STRIDE stepper (1…7) | `riffStride` | `riffStrideResolved` | RiffWalkTests, RouterTests | YES 1…7 (rLine) | — |
| LEN stepper (1…8; 1…16 on a legacy POLY doc) | `riffLength` | `riffLengthResolved` (SnapshotBuilder clamps 1…16) | RouterTests, PolyRiffRouterTests | YES 1…8 (rLine); POLY lengths via repoly | — |
| SHIFT stepper (wraps) | `riffRotate` | `riffRotateResolved` | RouterTests | YES 0…7 (rLine) | — |
| TRANS stepper (−7…+7) | `melodyTranspose` | `melodyTransposeResolved` (rank-space) | RouterTests, StackGridLiveTests, MixPanelTests | NO (absent from rLine) | — |
| FLIP NOTES toggle | `riffInvert` | `riffInvertResolved` | RouterTests | YES (rLine) | — |
| Output discs A–D (riff part) | `riffOutMask` (own-output mask stored nil) | `riffOutMaskResolved` → `partOut`, ALL union | PortsStressTests (testEachPartLeavesOnExactlyTheOutputs…), RouterTests, NoteRollTests | YES — rRouting [nil, 0…15, 0] + mid-note mask churn 1-in-3/window | jack tapped off mid-hit cancels deferreds (debt tail L65) |
| OCT five-box (riff) | `riffOctave` (0 stored nil) | `riffOctaveResolved` → pitch math, TRADE re-voice | MixPanelV2Tests (EuclideousOctaveTouch), RouterTests | YES −2…2 (rLine) | — |
| **AREA — STACK and PLAY AS (NOTES tab)** | | | | | |
| RANKS pop-up role cell (ONCE/DOUBLE/RETURN/PEDAL × rank) | `notesLitOrder`, `notesRankRoles` | `euclideousRowsResolve(litOrder:roles:)` | PlayAsRolesTests, PlayAsRowsAmendment3Tests, PlayAsRowsEngineTests | litOrder YES (rLine shuffled subset of 0…9); notesRankRoles NO | — |
| WHEN PLAYS / RESTS toggles | `notesWhen` (≥1 bit guard) | `euclideousNotesWhenChooses` | NotesTabTests, RouterTests | YES [0b01, 0b10, 0b11] (rLine) | — |
| CHANCE stepper (25/50/75/100) | `notesChance` | `euclideousNotesChanceRoll/Allows` | RouterTests | YES [25, 50, 75, 100] (rLine) | — |
| ORDER/VOICES/SPREAD chain chips (add / move / remove / value / hits) | `notesOrderChain` / `notesVoicesChain` / `notesSpreadChain` | `euclideousRowsResolve` chains | PlayAsRowsEngineTests, PlayAsRowsModelTests | NO (chains never drawn by the fuzz) | — |
| ORDER pop-up SHIFT stepper (0…15) | `notesShiftStart` | `euclideousRowsResolve shiftStart` | PlayAsRowsModelTests, EffectiveParamsTests | NO | — |
| ORDER pop-up DRIFT switch + step (−8…+8) | `notesDriftOn`, `notesDriftStep` | `euclideousRowsResolve` drift | PlayAsRowsModelTests | NO | — |
| BASS switch + HOLD/FIRST segments | `notesBassOn`, `notesBassMode` (mode writes even while switch off) | `euclideousRowsResolve` bass | PlayAsRowsModelTests, EffectiveParamsTests | NO | — |
| EMIT output discs A–D (notes part) | `notesOutMask` | `notesOutMaskResolved` → `partOut` | PortsStressTests, RouterTests | YES (rRouting + mid-note churn) | — |
| OCT five-box (notes) | `octave` (direct — never switches part on) | `euclideousOct` (clamp ±2), stack note names | RouterTests, StackGridLiveTests, MixPanelV2Tests | YES −3…3 (rLine) | — |
| STACK grid cell quick tap (<0.3 s) | `notesOn` (set if off) + `notesLitOrder` | litOrder → `euclideousRowsResolve`/`euclideousNotesPlayList` | StackGridTests, StackGridLiveTests, NotesTabTests | litOrder YES; notesOn NO | — |
| STACK grid cell hold (audition) / stack axis hold (default mode) | live word: `euclideousNotesAuditionLive` / `stackRankHold` (scrub) | `euclideousNotesAuditionLaneNow/Order` (overrides litOrder while held); `scrubStackRankNow` | RouterTests (NotesAuditionLive), ScrubRouterTests | NO — live words left at default by the fuzz | — |
| **AREA — INPUTS tab** | | | | | |
| TEST audition button (hold) | NONE — live word: `euclideousTestLive` | `Router.euclideousRunAudition` via `euclideousTestLaneNow` | InputsTestAuditionTests | NO — live word at default | — |
| MIDI IN / PICK / KEY source chips | `poolSrcMask` (bits 0/2/3; default stored nil) | `euclideousLaneSourcePlan`/`euclideousLaneKey` → per-lane pool build | PoolEngineTests, PoolTabModelTests, SourceStackTests, InputsGoldenTests | YES — repool mask 0…15 (+bit 4) | — |
| CHORDS toggle + grid 1\|2 segments | `poolSrcMask` (bits 1/4, mutually exclusive) | grid pick → `SnapParams.chords`/`chords2`, `chordRateBeats(grid)` | PoolEngineTests (TWO CHORD GRIDS), ChordsGridTests | YES (repool incl. a grid-2 progression) | — |
| MIDI mode segmented ADD / REPLACE / ROOT | `midiMode` (tappable while dimmed, chip-off lane) | `euclideousLaneMidiMode` → build; ROOT → `euclideousRootT` | InputsRouterTests, InputsModelTests, InputsGoldenTests, MidiInOctavesTests | YES — reoctaves (ADD/REPLACE/ROOT) + repool per-lane | — |
| APPLY TO ALL | other 3 lanes' `poolSrcMask` + `midiMode` | same readers as the fields | InputsV2Tests (euclideousApplyInputsToAll) | fields YES (as above); the copy funnel itself n/a | — |
| DELAY CHORD — BY stepper (0…8) | `chordDelay` (0 stored nil) | `euclideousCanonDelayBeats`, `refreshCanonStack`, `canonAnyLane` | ChordCanonTests, ChordCanonSourcesTests | YES — recanon 1…8 | CANON DELAY by ear; incoming-MIDI canon (debt L91–96) |
| DELAY CHORD — UNIT stepper (STEPS·PASSES·BARS; tappable while dimmed at BY 0) | `PluginState.euclideousCanonUnit` | `p.canonUnit` in `euclideousCanonDelayBeats` | ChordCanonTests, InputsRouterTests | YES — recanon | — |
| **AREA — ANSWER (tab is DEBUG-only; these remnants reach release via loaded docs)** | | | | | |
| USE MY OWN (EUCLID-tab paused overlay) | `answerRhythmOn` → false | `Router.planAnswer`, `segRhythmMode` via `euclideousAnswerEffectiveRows` | AnswerRouterTests, AnswerTabTests, AnswerModelTests | YES — reanswer (all rows + SWAP pairs) | ANSWER CYCLE/TRADE by ear (debt tail L111) |
| USE MY OWN (RIFF / STACK paused overlays) | `answerPitchOn` → false | `segPitchMode` → `runEuclidLine listenPitch` | AnswerRouterTests | YES — reanswer | — |
| ANSWER strip DELAY ‹ › (shown only while rhythm borrowed) | `listenDelay` (inc has NO upper clamp at write) | `listenDelayResolved`, borrowed-pattern rotate | ListenTabTests, RouterTests | YES 0…6 (rLine) — stored values >6 never drawn | — |
| ANSWER strip FEEL ‹ › (±5 %) | `listenFeel` (clamped −1…1) | `listenFeelResolved` | ListenTabTests | YES −1…1 (rLine) | — |
| ANSWER strip SPEED ×¼…×4 | `listenSpeed` | lap ÷ 2^n (Router:267) | ListenTabTests, RouterTests | YES −2…2 (rLine) | — |
| ANSWER strip DIRECTION < >< > | `listenDirection` | `euclideousListenBorrowedLap/Index` | ListenTabTests | YES (rLine) | — |
| **AREA — RESETS tab** | | | | | |
| FREE pill (rhythm / melody halves) | `restartRhythmOn`/`restartMelodyOn` (+`[1]` seed on empty chain, + first-edit pin) | `euclideousRestartSettings` → schedule / chain core | RestartUnitsModelTests, RestartScheduleTests, RestartEditorUITests | NO — `restart*On` not drawn (NOT list: restart UNITS fields) | RESTART UNITS: cross-lane in-step restart, mid-play rebuild, headless 3/4·7/8 (debt L142–151) |
| Unit chips ×3 per half (RHYTHM PASS·BAR·RIFF / MELODY HIT·PASS·BAR) | `restartRhythmUnit`/`restartMelodyUnit` (+side-writes: source, live-wake) | unit resolvers → `EuclideousRestartScheduleSet` | RestartScheduleTests, RestartUnitsModelTests, RestartUnitsGoldenTests | NO | — |
| Source squares ×4 per half | `restartRhythmSource`/`restartMelodySource` | schedule source graph | RestartScheduleTests | NO | — |
| Count chip (tap halves ±1, vert drag, VO adjust) | `restartRhythmBars`/`restartMelodyPasses` (one link, ladder-snapped) | `euclideousLaneChainTick`, schedule readers | RestartChainsTests, RestartEditorUITests (euclideousRestartCountChipDragValue), ResetsCardLayoutTests | YES — legacy chains: 50 % of lanes, 1–4 links of {1,2,3,4,6,8} (rLine) | — |
| Count chip long-press remove / + add / − remove-last | same chain fields (never empties) | same | RestartUnitsModelTests (euclideousApplyRestartEdit) | YES (same legacy draw) | — |
| WITH RHYTHM link button | `restartMelodyWithRhythm` | `euclideousIsLoop`, schedule WITH-RHYTHM re-align | RestartScheduleTests (tests 26–29) | NO | — |
| **AREA — FILL tab** | | | | | |
| FILL tile (on/off) | `fillOn` | `usesFill` gate → `EuclideousFillPlan` | FillRouterTests, FillEngineTests | NO — FILL is on the NOT-randomised list (whole area) | — |
| Bar cells (4/8/16) | `fillBars` | `fillArmed(bar:)`, `FillPlan.armed` | FillTimingTests, FillRouterTests, FillTabV2Tests | NO | — |
| LOOP tile (4→8→16) | `fillLoop` | `FillPlan.loop`, armed modulo | FillTabModelTests, EffectiveParamsTests | NO | — |
| SPEED segmented ×½…×4 | `fillSpeed` | `fillSpeedMultiplier` → `FillPlan.m` | FillTimingTests | NO | — |
| LENGTH segmented ¼ ½ BAR | `fillLength` | `fillLengthFraction` → region D | FillTimingTests | NO | — |
| RUSH / BREAK / LAND tiles | `fillCurve` / `fillBreak` / `fillLand` | `FillPlan.curve`/`breakOn`/`land` | FillRouterTests | NO | — |
| ORDER / HITS / NOTES segmented | `fillOrder` (+clears `fillReverse`) / `fillHits` / `fillNotes` | `FillPlan.order` (SHUFFLE via `euclideousFillShuffle`) / walk advance / `FillPlan.notes` | FillRouterTests, FillTabV2Tests | NO | — |
| RANKS shape + stepper (−7…+7) | `fillShape`, `fillRanks` | `FillPlan.shape/ranks` | FillTabV2Tests, FillRouterTests | NO | — |
| SWELL / ROLL / CHANCE steppers + double-tap reset | `fillSwell` / `fillRoll` / `fillChance` | `FillPlan.swell`; `euclideousFillRollCount`; `euclideousFillChancePlays` (splitmix, replay-exact) | FillRouterTests, FillTimingTests, EuclideousFillModelTests | NO | — |
| **AREA — ALT tab** | | | | | |
| UNIT segmented STEP·HIT·BAR·PASS | `altUnit` | `altUnitResolved` → `euclideousAltX` (read only when `usesAlt`) | AltRouterTests, AltStateTests, AltCardLayoutTests | NO — ALT state on the NOT-randomised list (whole area) | — |
| MAIN / ALT count steppers (1…16) | `altMainCount` / `altAltCount` | `euclideousAltState` | AltStateTests | NO | — |
| OUT pill + emitter tokens A–D (per part) | `altRiff`/`altNotes` `.outOn`/`.out` (seeds main mask on first on) | `altRiffOut`/`altNotesOut` → `addPitch(altOuts:)` (0 mask = rest, walk advances) | AltRouterTests | NO | — |
| OCT pill + five boxes (on + greyed-off variants) | `.octOn`/`.oct` (−2…+2) | `altRiffOct`/`altNotesOct` → `riffResolve(oct:)` | AltRouterTests | NO | — |
| VEL pill + slider + double-tap reset | `.velOn`/`.vel` (1…127; drag-while-off enables) | `altRiffVel`/`altNotesVel` → `addPitch(vel:)` | AltRouterTests | NO | — |
| GATE pill + slider + double-tap reset | `.gateOn`/`.gate` (1…99) | `altRiffGate`/`altNotesGate` (÷100) | AltRouterTests | NO | — |
| **AREA — MUTE tab** | | | | | |
| Emitter token tile tap (unit cycle 1/16→1/8→1/4→BAR) | `PluginState.euclideousOutputMutes[o].muteUnit` | `euclideousOutputMuteUnitBeats` (gate + off-clamp window) | OutputMuteTests (cyclingUnit), MutePanelTests | NO — rMutes draws `cells16`+`passes` only, never `muteUnit` | mark on muted cell still restarts; off-clamp at cell boundary (debt L456–459) |
| Strip paint drag + VO cell toggle (16 × 4) | `euclideousOutputMutes[o].cells16` | `euclideousLaneAudible(beat: euclideousStrikeMuteBeat, …)` gate; §2.3 off-clamp | OutputMuteTests, MutePanelTests, PortsStressTests (testOutputMuteSessions) | YES — rMutes cells16 0…0xFFFF | same |
| **AREA — RATCH tab** | | | | | |
| Toggle disc (collapsed + expanded column) | `euclideousEmitterRatchets[x].on` (+arm defaults length/vel/depth) | `EmitterRatchetSnap` → `emitterCounter.hit(cfg:)` | EmitterRatchetTests, EmitterRatchetRouterTests | YES — rEmitters `on` | lane-order counting by ear (debt tail L61) |
| Strip drags: vert HITS / horiz OFFSET / pinch STEPS | `.hits` (+`customMask` rebuild) / `.offset` / `.steps` (both clear `customMask`) | `patternMask = emitterRatchetEffectiveMask` | EmitterRatchetTests, EmitterRatchetMutationTests | steps 2…16, hits, offset YES (rEmitters); customMask NO | — |
| Strip single tap (toggle one step) | `.customMask` (hand pattern) | `emitterRatchetEffectiveMask` (customMask wins) | EmitterRatchetTests (emitterRatchetToggleStep) | NO | — |
| STEPS / HITS / OFFSET value cells (drag / double-tap / VO) | same three fields | same | EmitterRatchetTests (drag maths) | YES | — |
| COUNTS ×2 ×3 ×4 chips | `.countsBits` (never empty) | `maxCount`, strike-count draw | EmitterRatchetV2Tests | YES — rEmitters 1…7 | — |
| Expanded big-strip tap (cycle a hit's count 1→4) | `.hitCountBits` | `hitCount(ord)` under perHit | EmitterRatchetTests (settingHitCount), EmitterRatchetV2Tests | NO | — |
| STRIKES PER HIT switch | `.perHit` | counter uses per-hit counts | EmitterRatchetV2Tests | YES — rEmitters (mostly off) | — |
| CHANCE / RESTART value cells | `.chance` / `.restartBars` (0 = FREE) | splitmix roll ("EMITRTCH"); `restartKey` N-bar block reset | EmitterRatchetTests, EmitterRatchetRouterTests (restartBars) | chance YES {100,75,50,25,5,0}; restartBars NO | — |
| SPREAD LENGTH segmented (AUTO ½ 1 2 3 4) | `.length` | `emitterStrikeResolveLength` | EmitterRatchetV2Tests | YES — rEmitters | RATCH LENGTH choke on dense lanes (debt L117–122) |
| BEND cell + VEL segmented + DEPTH cell | `.bend` / `.vel` / `.depth` | `emitterStrikeCappedCount(bend:)`, spacing; `emitterStrikeVelShare(vel:depth:)` | EmitterRatchetV2Tests | YES — rEmitters | — |
| **AREA — CC tab** | | | | | |
| Slot cell tap (on/off; 4 outputs × 4 slots) | `PluginState.euclideousEmitterCCs[k].on` | Router `emitterCCs[k].on` gate; off→on park-at-LOW (`ccPendingReset`) | EmitterCCTests, CCPageV2Tests | NO — CC slots on the NOT-randomised list (whole area) | — |
| CC page power button | `.on` | same | EmitterCCTests | NO | — |
| CC number ‹ › skips + relative drag + VO | `.ccNumber` (skips numbers taken by sibling slots) | `cfg.ccNumber` on every send | EmitterCCTests | NO | — |
| Driver lane picker row | `.driverLane` (1…4; no UI path back to AUTO/nil) | `euclideousCCDriver(…)` picks the driving lane | EuclideousCCSlotsTests | NO | — |
| VALUE segmented (HITS RIFF PING CLIMB) | `.valueMode` | `EmitterCCCfg.value(…)`, `effectiveTo` (HITS forces REST) | EmitterCCTests, EmitterCCTraceTests | NO | — |
| HIGH / LOW / HOLD / RAMP / PASSES bar sliders | `.high`/`.low`/`.hold`/`.ramp`/`.passes` | value interpolation; `ccBuildSegment` hold/gap; muted-output park = `.low`; CLIMB span | EmitterCCTests | NO | — |
| TO segmented (REST/NEXT) + CURVE (LIN/EXP) | `.to` / `.curve` | `effectiveTo`; `ccSegCurve` ramp shaping | EmitterCCTests, CCPageV2Tests | NO | — |
| **AREA — MIX routing (MIX panel)** | | | | | |
| Lane play tile (×4) | `enabled` | `enabledResolved` gates the lane (idle lane still pool-samples) | RouterTests, UntouchedLaneTests | YES — rLine nil/Bool | — |
| Band rhythm strip gestures (drag/pinch/tap, same funnels as the lane-card comet strip) | `pulses`/`steps`/`rotate`/`customHits`/`offsetFraction` etc. | see TAB STRIP rows | see TAB STRIP rows | see TAB STRIP rows | — |
| S per-part solo tap (latch) | `PluginState.euclideousPartSoloMask` (+ folds legacy `euclideousSoloMask` → 0; no undo) | `partSoloMaskNow` → `euclideousLaneMayStrike`, `dropSoloSilencedPitches`, `cutPartVoices`; live word ≤1 buffer | PartSoloTests, LaneSoloTests | NO — partSoloMask never drawn (only lane `soloMask` 0…15 + the lane-solo live word 1-in-4/window) | part solo silences within one buffer, cuts clean (debt L211); SOLO mid-phrase no clicks (L263–270) |
| S per-part solo hold (momentary) | none — held UI mask | live word: `Kernel.euclideousPartSoloLive` | PartSoloTests | NO — live word | same |
| Part toggle plate (riff / notes glyph) | `riffOn`/`notesOn` (+`enabled`, litOrder seed, master-off path) | `laneSounds`, litOrder | PartPlayButtonTests, MastersTests | riffOn YES / notesOn NO | — |
| VEL tile (drag / double-tap 100 / VO) | notes: `notesVelocity`; riff: `velocityAbsolute` (+notes-layer pin) | Router `velocityAbsolute`/`notesVelocity` args; hocket re-base | MixPanelV2Tests, RouterTests | YES — velocityAbsolute nil/1…127, notesVelocity 1…127 (rLine) | — |
| GATE tile (drag / double-tap 90 % / VO) | notes: `notesGate`; riff: `gate` (cap 99 %) | `gateResolved`/`notesGateResolved` | MixPanelV2Tests, RouterTests | YES — gate [1.0, 0.99, 0.9, 0.05…1.0], notesGate [1.0, 0.99, rand] (rLine) | — |
| OCT five-box (per part) | `octave` / `riffOctave` | pitch math (Router:3996/4071) | MixPanelV2Tests (EuclideousOctaveTouch), RouterTests | YES (rLine) | — |
| A–D output discs (per part × output) | `riffOutMask`/`notesOutMask` (main mask only — never the ALT mask) | `partOut`; deferred strikes follow the live mask | PortsStressTests (mask exactness), RouterTests | YES (rRouting + mid-note churn) | jack-off mid-hit cancels deferreds (debt tail L65) |
| Emitter card tap (full output mute) + VO toggle | `euclideousOutputMutes[o]` (`toggledFull`) | `emitOneOutput` gate + off-clamp (same as MUTE tab) | OutputMuteTests, EmitterTokenTests (toggledFull), MutePanelTests | YES — cells16 via rMutes | — |
| Emitter card hold (trace) | none — `@State heldOutputs` | — (display dim only, by design) | MixPanelV2Tests (dims) | n/a | — |
| **AREA — RIFF PANEL (grids)** | | | | | |
| RIFF \| STACK header segment | none (`@State riffPanelTab`) | — | RiffPanelTests (layout) | n/a | — |
| RIFF segment long-press → CLEAR | `PluginState.riffs` (active → empty) / `polyRiff` reset on a POLY doc | riffs → `SnapParams` → riff walk (`riffResolve`/`euclideousRiffColumn`) | RouterTests (riff walk), RiffMapTests | NO — riff grid content never randomised (every fuzz doc plays the DEFAULT riff) | — |
| MONO riff grid drag (tap toggles, drag paints) + VO activate | `riffs[active].ranks`, `.steps` | same riff-walk readers | RouterTests, RiffWalkTests, DerivationsTests | NO — same gap | — |
| POLY grid drag + VO (reachable only on a stored `riffPoly` doc) | `PluginState.polyRiff` | `PolyRiffSnap` → `triggerMask`/`euclideousPolyTrigger` | PolyRiffTests, PolyRiffEditTests, PolyRiffRouterTests | YES — repoly notes 0–20 (col 0–15, rank 1–8, len 1–16) | POLY note rings to last hit; REV end-strike (debt tail L88–90) |
| **AREA — RIBBONS (riff panel scrub)** | | | | | |
| Column ribbon (hold/slide over the rails) | NONE — live word: `riffColumnHold` | `scrubRiffColNow` → `euclideousRiffHitSource` substitution | ScrubRouterTests, ScrubTests | NO — scrub holds left at default (process params) | scrub by ear: no stuck note, slip/continue (debt L203–210) |
| Rank ribbon (rank-number axis) | NONE — live word: `riffRankHold` | `scrubRiffRankNow` → rank substitution at natural column | ScrubRouterTests | NO — live word | same |
| STACK axis ribbon | NONE — live word: `stackRankHold` | `scrubStackRankNow` → `euclideousStackHitRanks` collapse | ScrubRouterTests, ScrubTests | NO — live word | same |
| **AREA — HEADER** | | | | | |
| Undo ↶ / Redo ↷ | restores the full undo snapshot (lines, riffs, chord sets, key, plans, ratchets/CCs/mutes, masters…) | whole-document republish → entire SnapParams | UndoAuditTests (+ the UI-side FourfoldUndoAuditTests) | n/a — the fuzz never drives undo | — |
| HOLD chip / LATCH chip | `PluginState.euclideousHoldLatchMode` (mutually exclusive, tap-again = nil) | Router `euclideousHoldLatchPool` capture/latch; livePool passthrough when nil | RouterTests, HeaderStatusTests, SnapshotBuilderTests | YES — rDoc nil/.hold/.latch | HOLD/LATCH against real MIDI (debt L334–341) |
| PLAY RIFF / PLAY STACK masters (tap) | `PluginState.riffMaster` / `stackMaster` (nil = on) | `laneSounds` gates every lane; also AU host params addr 2/3 | MastersTests, FourfoldParamTests, RouterTests | NO — masters never drawn | — |
| Masters press-and-hold (momentary master part solo) | none — held bits (0x55/0xAA) | live word: `Kernel.euclideousPartSoloLive` → `euclideousPartAudible` | PartSoloTests | NO — live word | part solo ≤1 buffer (debt L211) |
| HARMONY status button / PRESETS button / settings gear | none (page `@State`s) | — | HeaderStatusTests (status looks) | n/a | — |
| **AREA — HARMONY sources (HARMONY page)** | | | | | |
| Root key (×12) | `PluginState.euclideousKeyRoot` | key layer (`fillKeyLayer`/`euclideousKeyPitchClassMask`), `diatonicChord`, ROOT base | ChordsGridTests, DerivationsTests, RouterTests | YES — rDoc 0…11 | — |
| Scale chip (×13) | `euclideousKeyType` | `euclideousChordKeyTones` → chords + key layer | ChordsGridTests, DerivationsTests | YES — rDoc all types | — |
| Chord grid CHORDS rows (tap/drag contour + VO) | `MachineParams.chordsDegrees` (16-array; columns beyond STEPS written but inert) | `chordSeqNotes(Into)` → `fillChordLayer` | ChordsGridTests, DerivationsTests (grid-isolation fuzz) | PARTIAL — recanon draws a progression (degrees −1…11, 2–16 steps) in the CANON stream; repool draws grid 2; the two BASE fingerprint runs keep the default grid | hit ON the bar line plays the NEW chord (debt L369–371) |
| Chord grid COLOUR rows (tap/drag + VO) | `MachineParams.chordsColours` | chord colour voicing in `chordSeqNotes` | ChordsGridTests | NO — colours never drawn | — |
| STEPS − / + (1…16) | `chordsSteps` | `ChordsAdvanceConfig.steps` → `chordColumn` | ChordsGridTests | YES — recanon 2…16 (canon stream only) | — |
| ADVANCE unit / rate / lane / every | `advanceUnit`, `chordsRate`, `advanceLane`, `advanceEvery` | `chordsAdvanceConfig` → `chordColumn` (TIME = old path; LOOP/RIFF read the restart schedule) | ChordsGridTests (chordColumn) | chordsRate YES (recanon); advanceUnit/Lane/Every NO | — |
| RESTART unit / lane / every / on-switch (editable while dimmed-off) | `restartUnit`/`restartLane`/`restartEvery`/`restartOn` | `chordColumn` restart gate | ChordsGridTests | NO | — |
| PICK keys (×12, EDIT popover) | `SourcePlan.pickNotes` (≤16) | PICK layer in `euclideousBuildSourceStack`; canon history carries PICK | SourceStackTests (euclideousPickToggle), PoolEngineTests | YES — rDoc 0–6 notes of 36…84 | — |
| OCTAVES IGNORE \| KEEP | `SourcePlan.midiOctaves` | `euclideousFoldToBase` in `mergeStack`/`mergeCanonStack` | MidiInOctavesTests, InputsGoldenTests | YES — reoctaves (base runs PIN `.keep` — fingerprints depend on it) | — |
| **AREA — SETTINGS sheet** | | | | | |
| LISTEN ON — ALL tile + channel grid 1–16 | `PluginState.euclideousMidiInChannelMask` (no undo, by design) | `globalSrcChanMask(Set)` → pool reads, HOLD/LATCH capture, fill layers | RouterTests, EffectiveParamsTests, DerivationsTests (euclideousListenOnAfter*) | NO — on the NOT-randomised list | — |
| ALL-NOTES-OFF IGNORE \| OBEY | `PluginState.ignoreAllNotesOff` | `SnapshotBox.ignoreAllNotesOff` → Kernel CC120/123 suppress | SnapshotBuilderTests (threading only — Kernel is out of the macOS target: **GAP: no behavioural test**) | NO | — |
| PORTS channel steppers A–D | `PluginState.busChannels` (1…16) | wire channel stamps, CC, mid-note channel reconcile | RouterTests, PortsStressTests (channel-stamp oracle), MigrationTests | YES — rDoc 5 forms (8-form, 4-form, out-of-range 0…99, short, nil) + mid-note change 1-in-3/window | — |
| ALL NOTES OFF button | none — render one-shot | `Router.process(euclideousAllNotesOff:)` row-scoped flush | PortsStressTests (fires 1-in-11/window), RouterTests | YES — driven as a process param | — |
| WHEN THE HOST STOPS (KEEP \| STOP; AU only) | `PluginState.euclideousHostStopBehavior` | `Kernel.freeRunEnabled` via `publish()` (not the snapshot) | EffectiveParamsTests (resolution only — **GAP: no behavioural test**, Kernel out of target) | NO — on the NOT-randomised list | — |
| SAME-NOTE GAP ON \| OFF | `PluginState.euclideousSameNoteGuard` | Router:4245 + `euclideousSameNoteGuardGapBeats` | SameNoteGuardTests | NO — absent from the fuzz | by-ear confirm (debt L96) |
| STRIKE PULSE OFF·SUBTLE·FULL | UserDefaults `fourfold.pulseLevel` (not a document field) | NO ENGINE READER (display only, by design) | PulseTests (envelope fns) | n/a | — |
| **AREA — PRESETS / DOCUMENT IO** | | | | | |
| Browser SAVE / OVERWRITE? (two-tap) | preset FILE only (`PresetStore.save`) | n/a | PresetStoreTests (store; the confirm flow is UI-only, untested) | n/a | — |
| Browser user / factory preset row (LOAD) | WHOLE document replaced (8 rig fields preserved); `PresetStore.decode` normalizer chain — **missing `normalizeHocketAtLoad`** | whole engine (flushVoices + full snapshot rebuild + param-tree sync) | PresetsTests, PresetStoreTests, MigrationTests, UndoAuditTests (preset undo), EffectiveParamsTests | PARTIAL — the fuzz replaces whole documents 1-in-4/window (fresh rDoc), but never through the preset/normalizer path | silence-leak fix by ear (L97); retired FX/out-transpose/PENDULUM docs sound different by design (dump L204) |
| Browser DELETE (two-tap) / ✕ close | preset file removed (not undoable) | n/a | PresetStoreTests | n/a | — |
| Host `currentPreset` set / `saveUserPreset` / `presetState(for:)` | whole doc (as browser load) / file save with **no overwrite guard** / raw file bytes | whole engine; `pinUnpinnedRestartChains` only runs when the page UI is open | **GAP: none** — no macOS test drives the host preset paths | NO | — |
| `fullState` GET / SET (session save/restore) | whole doc; SET runs the FULL normalizer chain incl. hocket; `super.fullState` skipped on SET (2026-11-13 crash guard) | whole engine | MigrationTests (decode), SnapshotBuilderTests | NO | host-param automation no deadlock; old-session restore no deserialize crash (debt L184–190) |
| App autosave (3 s + scenePhase) / launch restore / durable tape attach | `session.state` + `session.tape` files | SessionTape/TapeStore → reel engine (tape records in release with NO release surface) | SessionTapeTests, TapeStoreTests (the FourfoldAppModel save/restore flow itself: **GAP: none**) | n/a | IDLE RELEASE: crackle gone when stopped, first downbeat on time (dump L41) |
| Release-live launch args (`--fresh`, `--autoplay`, `--state-test-write`, `--hocket-test`, `--route-test`, `--soak…`, `--window-size`) | direct `editDocument` mutations (keyRoot, hocketRules, routing masks, soak churn) — no undo, autosaved | whole engine (hocket remap path included) | **GAP: none** — no test covers the launch-arg surface | NO | — |

## Excluded from the release build

- Dice (random mode) + padlock (lock mode) in the lane strip — `euclideousStripTilesVisible` `#if DEBUG` (LaneViewStrip.swift:129–133).
- All random-mode card controls (tab selector, THROW, TWEAK, BACK, KEEP, hold-preview, picture PLAY/SOLO row) — reachable only inside random mode (DEBUG dice).
- All lock-mode creation controls (lock tap, capture hold, SNAP BACK grid, tap-catcher finish) — reachable only inside lock mode (DEBUG padlock); release can only unlock/re-capture an already-locked doc via the badge.
- ANSWER strip segment + the whole ANSWER tab + GO TO ANSWER buttons — `euclideousAnswerTabVisible` `#if DEBUG` (LaneViewStrip.swift:31–35); engine still plays stored ANSWER settings.
- REEL: header tape icon + the entire V3 browser/export surface — `euclideousReelVisible` `#if DEBUG` (LaneViewStrip.swift:42–48); the SessionTape recorder still runs unconditionally in release.
- VEL tab (whole; `EuclideousVelocityPanel`, all `EmitterVelocityField` cells) — `euclideousVelocityTabVisible` false in release (LaneViewStrip.swift:44–47); `euclideousEmitterVelocities` engine path stays live for old docs (and IS fuzzed: rVelocities).
- Sequencer-panel MIX / RIFFS / FX tabs — retired/hidden (`EuclideousSeqTab.visible`); old MUTE ZOOM + pass rail (`EuclideousLanesPanel`, `OutputMute.passes` writer) unmounted.
- Settings DEBUG rows: CLASHES, FX COUNTS, CANON ENTRY, AU ICON PROBE, MIX STRIP FIT|ALIGNED, MIX TOGGLES FILLED|OUTLINE, STRIP CC — `#if DEBUG`; the three UserDefaults rows have UNGATED release readers (`fourfold.mixStripMode`/`mixToggleMode`/`stripCC`) — a DEBUG-set value leaks into a release build on the same device (display-only).
- POLY segment of the riff-panel header — `#if DEBUG` + `--poly-control` launch arg (`onSetRiffPoly` unreachable).
- Ribbon SETTINGS (TUTTI / LOOP / LATCH / PARTS) — button/tab unmounted AND `uiRibbonSettings()` hard-returns `.defaults`; TUTTI marks + LOOP span gestures can never fire (the engine `loopColNow` path is live code fed by a dead UI).
- RATCH FX COUNTS readout (`#if DEBUG`); RATCH legacy mode controls (STRIKES/FIX/RANGE/HIT/GAP — retired, fields decode).
- Compiled-unmounted/dead views (no gate needed — zero call sites): lane SOLO tile `soloButton`, card BACKs + pads/jacks/ADD HITS, strip glyph clusters, `stepCountBadge`, old RHYTHM layout (`rhythmUpperZone`…), EDITED chip/revert, restart tiles row + old restart editor + `.tapLink`, `notesShiftPopupCard`, `ringButton`, `playAsSequenceRow`, TOP/TOP−1/−2 stack rows, `notesRanksButton` (static label), `partOctaveControl`, `melodyValuesRow`, `riffTabRow`, `RiffGridPickerView`/label column, `MidiRootReadoutView`, FREEZE/SUSTAIN/SLIP rows, CC `leftColumn`/`rightColumn`, `EuclideousMixPanel` (MIX ROWS v1) + TRANS tile, HOCKET header pill, SWING button+popover (field still decodes), `resetPopupCard`, WORKBENCH link (never ported).
- Not release surfaces: `resetToFreshInit()` (harness only), `--undo-probe`/`--stack-probe` (read-only probes), `pendingBuild*` setters (8×8 vestiges, always nil), Ableton Link (`#if FOURFOLD_LINK`, compiled out), host-stop row in the standalone app (`showsHostStopBehavior` false).

## Gaps (the §2–§4 work list)

### (a) Controls with no test

1. Host preset paths — `currentPreset` setter (user + factory), `saveUserPreset` (no overwrite guard), `presetState(for:)` round-trip: no macOS test drives any of them.
2. Release-live launch-arg mutators — `--state-test-write`, `--hocket-test`, `--route-test`, `--soak…` compile into RELEASE, mutate the document with no undo step and are autosaved; zero tests.
3. `ignoreAllNotesOff` — only SnapshotBuilderTests threads it; the Kernel CC120/123 behaviour is untestable off-device today (Kernel out of the macOS target).
4. `euclideousHostStopBehavior` / `Kernel.freeRunEnabled` — only EffectiveParamsTests resolves the field; no behavioural test (same Kernel gap).
5. `FourfoldAppModel.saveState`/`restoreState` (app autosave/restore flow) — SessionTape/TapeStore are tested, the app-model flow is not.
6. Preset-browser two-tap confirms (OVERWRITE? / DELETE?) and the name sanitize/exists interplay — UI-only, zero test reach.
7. The all-lane comet funnels (`euclideousApplyAllRhythmX/Y`) — the written fields are tested; the multi-lane direct-mutation funnels themselves have no test (UI-side).

### (b) Fields the fuzz never randomises (PortsStressTests; base pins currently RED awaiting re-capture — pending-tasks:2133)

8. `customHits` — hand-edited patterns (tap-a-step, FLIP HITS) never appear in any fuzz document.
9. `PluginState.riffs` content — every fuzz document plays the DEFAULT riff; the MONO grid's ranks/steps are never randomised.
10. `melodyTranspose` (RIFF TRANS).
11. `notesOn` switch (rLine draws `notesLitOrder`, never the switch) and `notesRing` (RING).
12. All PLAY AS chain state: `notesOrderChain`/`notesVoicesChain`/`notesSpreadChain`, `notesRankRoles`, `notesShiftStart`, `notesDriftOn`/`notesDriftStep`, `notesBassOn`/`notesBassMode`.
13. All RESTART UNITS fields (`restartRhythmUnit/Source/On`, `restartMelodyUnit/Source/On/WithRhythm`) — only the legacy chains are drawn.
14. The whole FILL area (every `fill*` field) — named in pending-tasks:2205/2244 as a wanted extension.
15. The whole ALT area (`altUnit`, `altMainCount`, `altAltCount`, `altRiff`/`altNotes` parts) — pending-tasks:2224.
16. The whole CC area (`euclideousEmitterCCs` — on, ccNumber, driverLane, valueMode, high/low/hold/ramp/passes/to/curve).
17. `EmitterRatchet.restartBars`, `.customMask`, `.hitCountBits`.
18. `EuclideousOutputMute.muteUnit` (rMutes draws cells16 + the inert `passes` only).
19. `euclideousPartSoloMask` (latched) — only the lane-level `soloMask` + the lane-solo live word are driven.
20. `riffMaster` / `stackMaster`.
21. `euclideousMidiInChannelMask`, `euclideousSameNoteGuard`, `ignoreAllNotesOff`, `euclideousHostStopBehavior`.
22. `chordsColours`; the chord ADVANCE/RESTART config (`advanceUnit/Lane/Every`, `restartOn/Unit/Lane/Every`, `chordsRotate`); chord grid 1 in the two fingerprinted base runs.
23. `riffAdvanceEvery` 5–8 — fuzz range is 1…4, the UI reaches 8 (and 5–8 is a named device-debt item).
24. Live words left at default (process params): scrub holds (`riffColumnHold`/`riffRankHold`/`stackRankHold`), the ribbon loop span (`loopLo`/`loopHi`), TEST/notes audition (`euclideousTestLive`/`euclideousNotesAuditionLive`), lock revisions (`lockRevs: 0` — no snap churn), the part-solo live word.
25. Environment axes: swing, host bar length, sample rate (fixed 48 000), MIDI as events (CC/pitch-bend/running status — only held notes via `NotePool`), hocket rules in the fingerprinted runs.

### (c) Engine paths with no golden document

26. Chord grid 2 — no `GOLDEN CHORDS 2` harness document (grid-2 wire bytes unpinned; pending-tasks:2053).
27. FILL — no FILL-TAB document in the golden harness or the alloc audit (pending-tasks:2236).
28. ALT cycling — no golden/alloc scenario and no fuzz; only AltRouterTests' deterministic cases.
29. The ribbon LOOP engine path (`loopColNow`) — live render code with no release writer, no golden scenario.
30. The always-on SessionTape recorder in release — records + persists (~8 MiB resident, growing app session file, extension temp spill) for a feature with no release surface; DECIDE (also REEL-13).
31. Emitter VELOCITY — engine live for old docs with the tab hidden; fuzzed (rVelocities) but in no golden document.

### (d) Survey UNCERTAIN / NO-ENGINE-READER findings

32. `riffOnRest` — engine-read (`riffOnRestResolved`, TIE/SKIP/REPEAT) with NO release editor anywhere; only random-mode dice (DEBUG) ever wrote it. A stored value silently shapes sound.
33. `notesReceivedOnly` — engine-threaded, no release writer or clearer; a stored `true` changes sound invisibly.
34. `notesLitOrder` positions 8/9 (TOP 2/TOP) — still sound, no release writer or un-writer (RANKS pop-up and STACK grid reach 0–7 only).
35. `PluginState.ribbonSettings` — doubly inert (SnapshotBuilder forces `.defaults`) yet a stored `latch`/`touchMode` changes gesture behaviour expectations; effectively NO ENGINE READER.
36. `chordSlip` — still clamped/threaded through SnapshotBuilder, no sound reader (NO ENGINE READER for sound).
37. `hitsRequested`/`offsetRequested` — threaded into the snapshot, no render reader (by design; documented, keep).
38. `reelKeeps` — NO ENGINE READER by design; written via `editDocument` outside every undo funnel.
39. `PresetStore.decode` misses `normalizeHocketAtLoad` — a pre-retirement preset loads its hocket rules LIVE via the browser / host-currentPreset paths (the fullState path strips them). Inconsistent by path.
40. `listenDelay` — no upper clamp at write (repeated ‹› taps store an arbitrarily large Int); fuzz only draws 0…6.
41. ALT's `EuclideousOctaveBoxes` discards `startsNewUndoStep` — a drag across N boxes records N undo steps (breaks the one-step-per-touch contract the other mounts keep).
42. CC has no drag-end drop-unchanged (`onEmitterCCDragEnd` doesn't exist) — asymmetric with RATCH/VEL's UNDO-6 fix.
43. `EmitterCC.driverLane` AUTO (nil) has an engine reader but no UI path back once a lane is picked.
44. Dimmed-but-tappable controls write real undo steps with no audible effect: INPUTS UNIT stepper at DELAY 0, MIDI-mode segments on a chip-off lane, HARMONY RESTART rows while off (commented intended), TILT double-tap on a hand-edited lane.
45. MIX GATE UI floor 1 % vs engine clamp 5 % in SnapshotBuilder (pending-tasks:600).
46. DEBUG UserDefaults with ungated release readers: `fourfold.mixStripMode`, `fourfold.mixToggleMode`, `fourfold.stripCC` (display-only, but contradicts "release always FIT" comments).
47. Red tests on main to clear before this ferry's oracles mean anything: the two PortsStress fingerprints + rank assertion (ANSWER v2), `ClarityPassTests.testListenSourceResolvesToAStoredOrDefaultLaneWhileFollowing`, `CardBackReviewTests` header ladder, three stale UI tests (pending-tasks:2066/2111/2133/2175).

## Sources

- `scratchpad/survey/*.md` — 17 per-area control surveys, written 2026-11-22. File-name corrections: `mix.md` is a duplicate of the ALT survey (`alt.md`); `reel.md` holds the MIX-panel survey; `unknown-a2519901845d.md` holds the REEL survey.
- `scratchpad/recon/testsmap.md` — test-suite map (148 files, 2,731 tests), 2026-11-21.
- `scratchpad/recon/stress.md` — PortsStressTests fuzz architecture, randomised + NOT-randomised lists, pins, oracles, 2026-11-21.
- `scratchpad/recon/docs.md` — §1 device-verification debt ([engine-behaviour] items), §2 pending-tasks open issues, §4 golden/fuzz machinery, 2026-11-21.
- Spot-verified against source 2026-11-22 (grep over `Fourfold/Tests/`): hold/latch, channel-mask, audition, FLIP HITS, APPLY TO ALL, melodyTranspose, customHits, notesRing, restartBars, masters, ignoreAllNotesOff, freeRun, riffs-content, hitCountBits, muteUnit coverage claims.
