# STACK WHEN ferry — findings map (slice 1, before any code change)

Ratified 2026-11-22. Spec: the STACK (code "notes") layer's WHEN row becomes **NOTE · REST · GAP**
then **FIRST**; CHANCE goes; a gap stack fires on steps the rhythm doesn't hit, isn't a hit, and the
PLAY-AS sequence index `k` counts **kept steps** (not raw hits). Full plan + approach in the session
plan file; this is the §0.1 (a)–(h) findings + the source-disagreements the spec asks to report.

## (a) WHEN RIFF row as built
- `Fourfold/UI/EuclideousPage.swift:6193` `whenRiffRow(idx,line,accent,width)`; mounted `:5988` in
  `notesTabContent` `:5979`; row layout `euclideousPlayAsRowsLayout` `:5982`.
- Body `:6197-6209`: label `riffRowLabel("WHEN","RIFF").frame(width: labelW)`, inner `HStack(spacing:4)`
  of two tiles, `Spacer`, CHANCE stepper; row `.frame(width,height:28)`.
- Tiles `whenToggle` `:6212-6219`: 11pt heavy mono; label `on ? #1B1D22 : #8D939D`; `frame 72×23`; bg
  radius 4 `fill(on ? lane100 : #24262C)`. ON=A1.1 / OFF=A1.2 (§C4.2 comment `:6211`).
- Taps `:6200-6201`: `notesWhen ^ 0b01` (PLAYS) / `^ 0b10` (RESTS), guard ≥1 bit; `EuclideousLockOutline` `:6203`.
- CHANCE `:6195/6205-6206`: `chanceStops=[25,50,75,100]`, `melodyStepper("CHANCE", width:88,…)` → `notesChance`.
- `labelW:55`, `chanceW:88` — `Fourfold/Engine/PlayAsRowsUI.swift:11`.
- Undo: `edit(idx)` `EuclideousPage.swift:1707` → `onEdit` `Models.swift:906`.
- A9 tab dim (PLAY STACK off ⇒ 42%): `euclideousNotesTabBodyOpacity` `:5984`, applied `:5995`.

## (a2) Model `notesWhen` / `notesChance`
- `Models.swift:711` `var notesWhen: UInt8? = 0b11`; `:712` `var notesChance: Int? = nil`.
- Resolvers `:978-981`; decoder `:1413-1414`, migrate `:1465-1470`; SnapshotBuilder `SnapshotBuilder.swift:473-474`.
- New-per-lane-Bool precedent: `notesRing` (`Models.swift:666/1255/1358`, `SnapshotBuilder.swift:461`),
  `poolSustainOn`, `notesBassOn`. No spare bits in `notesWhen`; new flags get their own `Bool? = nil`.

## (b) Where the stack note plays on a hit
- `Router.swift:3910` `if isHit {` master gate (riff/mask/notes all nested).
- `Router.swift:4698-4699` gate `notesOn, thisLaneCount>0, litOrder.count>0, euclideousNotesWhenChooses(when,
  isRestHit: ranks[playedStep]<1)`; `:4700` `notesH`; `:4701` CHANCE `euclideousNotesChanceAllows(…, h:notesH)`.
- `Derivations.swift:9248` `euclideousNotesWhenChooses` = `(when & (isRestHit ? 0b10 : 0b01)) != 0`.

## (b2) Where CHANCE rolls
- `Derivations.swift:9245` salt ("NOTESCHA"); `:9252-9255` roll; `:9257` allows. Calls: `Router.swift:4701`
  (live), `:4788` (TIE lookahead); `Derivations.swift:9290/9306` (CountBefore), `:9448` (display).

## (b3) The count `k` + cache
- `Derivations.swift:9273-9311` `euclideousNotesCountBefore`, block `1024` `:9243` — **DISPLAY-ONLY** now
  (called only from `:10128`), never from Router.
- Render uses `euclideousRowsResolve` (`Router.swift:4704`, `PlayAsRows.swift:185`) with `notesH`; no
  render-thread k cache; bound `runBlock 2048`/`simCap 4096` (`PlayAsRows.swift:166-170`). REPEAT cache
  `euclideousLastSounded*` (`Router.swift:635-643`).

## (c) How the engine walks steps
- `iterateTicks` every tick (`Router.swift:2355`); `isHit` `:3832`; **non-hit ticks early-rejected by
  `if isHit` `:3910`** — a non-hit step cannot reach the notes path today.
- FILL synthesizes hits: `Router.swift:3819` `euclideousFillHitsNow==1` ALL / `==2` FLIP /
  `euclideousFillForceHitNow` LAND.

## (d) Per-note values and keys
velocity = HIT (base per-hit + ALT, `Router:4008/4736`); gate value HIT (`:4009`), length **TIME**
(`:4402-4405`); mask RATCHET + MUTE/PAUSE/REPEAT = HIT (`euclideousMaskOrd` `:597/847`, replay `:4900-4909`);
emitter ratchet = HIT (`:382`); ALT = selectable STEP/HIT/BAR/PASS (`euclideousAltX` `:4001`,
`Derivations:6763`, enum `Models:1627`); CC = HIT (`advOrd`, `:4261-4271`); LANES mute = **TIME**
(`euclideousLaneAudible` `:3908`); solo = mask + TIME (`euclideousLaneMayStrike` `:3907`).

## (e) What a pass is to RESETS
- `euclideousNotesHitOrdinal` `Derivations.swift:9261-9264` = `advOrd` (hits since melody origin, resets at
  melody restart). Origin `melodyOriginTick` `:6700`. Pass = `beat/lapBeats` floored, rebased at a rhythm
  restart (`RestartSchedule.swift:247-266`, `isMelodyRestartPass` `Derivations.swift:6726`). OFFSET shifts
  hit timing within a pass, not the pass origin.

## (f) Holds across hits
- RING (`notesRing`, `Models:666/1255`): holds to the walk-cycle boundary, length from riff HITS to the
  next cycle (`Router.swift:4395-4403`); keyed on HITS. BASS HOLD = every hit (`PlayAsRows.swift:193`). No
  DRONE stack mode (DRONE is a generator mode, `Models:16`); SPREAD = together/strum/run (`Models:1508`).

## (g) Lane strip stack footer
- `LaneStripBandPainter.swift:174-191`: `drawnSets[i]` = played `s.stackChipRanks[i]` (NOTE events) else
  predicted `d.hits[i].predictedStackRanks` (HIT prediction). Rank from note events via
  `laneStripSounding` reading `NoteRollNote.rank` (`LaneStripBands.swift:450-475`), fed by `stackHeld =
  rollLive.model.parts[2*lane+1]` (`EuclideousPage.swift:2743/2774`). Prediction `predictedStackRanks`
  (`Derivations.swift:10039/10051`, set `EuclideousPage.swift:2607`).

## (g2) Grid / RANKS / MUTE roll — hit vs note events
- STACK grid cell, RANKS tiles, MUTE-roll **played** notes are all **NOTE-event driven already**
  (`euclideousStackSounding(notesPart: rollLive.model.parts[2*lane+1])` `EuclideousPage.swift:8310/6029`,
  `StackGrid.swift:147-157`; MUTE-roll played `Derivations.swift:7579-7597`). **Upcoming** footer
  prediction + MUTE-roll **ghost** are HIT-based (`EmitterRollNote.ghost`) → a gap stack shows once it
  SOUNDS, not as a prediction. §6.1 needs only the played mark (note-driven); extending prediction is the
  open display item.

## (h) PLAY-AS SWITCH units
- ORDER/VOICES/SPREAD advance via `euclideousRowsActiveChip(hitOrdinal:h)` (`PlayAsRows.swift:150`), unit
  hardwired to `.hits` (`Models:1529/1541/1553`); `h = notesH`. Changing the ordinal source
  (`Router.swift:4700` / `Derivations.swift:9261`) to kept-steps is the single lever; a HITS chain then
  sees gap stacks (by design, §3.3). Do not change the chip unit (§3.4).

## Source-disagreements reported (spec: source wins)
1. **§3 k ↔ 6.4:** render no longer uses `euclideousNotesCountBefore`; it uses `notesH`→`euclideousRowsResolve`.
   "Amend 6.4" = change that ordinal to kept-steps, in render AND the display twin.
2. **§1.3 looks** match source (ON `#1B1D22`, OFF `#24262C`/`#8D939D`, radius 4, 23 tall). Tile WIDTH
   becomes computed (was fixed 72).
3. **§1.2 row fill:** today 2×72 tiles + Spacer + 88 CHANCE → four equal tiles filling label→right-inset,
   FIRST 10 right of GAP, no Spacer/CHANCE.
4. **§4/§1.6 CHANCE removed** from row + engine; `notesChance` field kept, ignored (no migration).
5. **§5.7 RING/BASS** keyed on riff HITS today → cycle phase moves to kept-step `k`; RING length stays a
   riff-hits lookahead (a gap step's RING falls to the next rhythm hit — device-owed).

## Two spec-vs-engine tensions — resolved for the spec, golden-neutral
1. **k in 1024-step blocks (§3.2)** per 6.4, not the render's unbounded `advOrd` (reduce 2048). Agree below
   1024 steps, so golden (≤~512 hits/32 bars) identical; follow the spec.
2. **RING on a gap step (§5.7):** phase on k, length a riff-hits lookahead — disclosed.

## Golden safety
All 22 factory presets use default `notesWhen=0b11` and set no WHEN; GAP/FIRST default off ⇒ kept-steps =
all hits = old hit ordinal ⇒ **byte-identical**. Verify before/after on the SAME tree (committed
`golden.txt` is independently stale vs the current preset roster).
