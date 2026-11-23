# KIT SOURCE ferry — findings (mapped before any edit, 2026-11-23)

Ratified by Paul 2026-11-23 from the "Fourfold KIT source" canvas. Built on INPUTS + HARMONY. Fourfold only.
**Held on `feature/kit-source` until Paul signs off — not landed to main.** Audited against the raw ferry text;
differences flagged (source wins). Spec build-order step 1: these findings, before any change.

## (a) PICK's retirement
`pickOn`/`pickNotes` live on `SourcePlan` (`Models.swift:174,177`; `pickOnR` defaults **false**). Per-lane PICK is
`poolSrcMask` **bit 2** (`Models.swift:1714`; names `Derivations.swift:13244`). The PICK chip in the SOURCES row is
drawn at **`EuclideousPage.swift:7829`** (`poolSourceChip("PICK", on: line.poolSrcOn(2))`, toggles bit 2) — the KIT
replacement site. The PICK note editor is still mounted inside HARMONY (`HarmonyPage.swift:668`, popover `.pick`;
`euclideousPickToggle` `Derivations.swift:4674`; pool build `fillPickLayer` `Router.swift:3407`). → **KIT replaces the
PICK chip** in SOURCES; PICK's fields + its HARMONY editor stay decodable/compiled (hide, don't delete; no migration).
With no SOURCES chip a new lane can't turn PICK on, but an old session with PICK still sounds.

## (b) Pitch stages — what each does on a KIT lane (§2.2)
Pool build `euclideousBuildSourceStack` (`Derivations.swift:1129`); per-lane `mergeLaneStack`/`refreshLaneStack`
(`Router.swift:3343/3359`). A KIT pool is exactly `kitNotes` (§2.1 — the stack build is SKIPPED), so these are **moot
for KIT**: OCTAVES-fold `euclideousFoldToBase` (`Router.swift:3222`), ROOT transpose `euclideousRootMoved`
(`Derivations.swift:1166`), KEY nearest-mean (`:1233`), pc-dedup (`:1211/1225/1246`), CLASHES drop (`:1212`), ascending
sort (`:1165`).
**Pitch changes forced neutral for KIT:** `riffResolve`'s `+12·oct` (`Derivations.swift:1671`; pass `oct:0` — mono
`Router.swift:5746`, poly `:4548`, notes `:4780`, FILL `:4851`, mask `:5028/5756`); ALT octave (`altRiffOct/altNotesOct`
`Router.swift:4008/4015/4019`→0); `strikeChord` `rawNote+transpose+12*octave` (`:3033`; Euclideous passes `octave:0` —
confirm `machineTranspose` `:1540` is 0 for the Euclideous machine, else guard); ANSWER PITCH interval move
(`euclideousListenMoveByInterval` `Derivations.swift:3609`, applied `Router.swift:4501`; SHADOW/ECHO/MIRROR) + DODGE
(`Router.swift:4373`). PITCH pad = RETIRED (`Router.swift:4358`), nothing to do.
**Rank-choices kept (act as today):** INVERT (`:5574`), TRANS/`melodyTranspose` (`:5583`), FILL RANKS climb
(`euclideousFillRankOffsetNow` `:4548` etc. — clamp 1–8, drop any shift past rank 8), MIRROR/CLIMB (`:5584`), PLAY AS,
the riff walk, riff-source borrowing (`riffSourceLane` `:529`), the riff scrub, TUTTI (`tuttiFireRank`), grid CHANCE.

## (c) Velocity stages in order (Router.swift) + the choke point
base (`velocityAbsoluteResolved`/`notesVelocityResolved`, `Models.swift:310/1285`) → ALT vel (`:4016/4020`) → `addPitch`
stores `pitchVel`+binds `pitchRank` (`:4370/4394`) → mask ACCENT/SWELL (`:5055`) → HOCKET passed (`:5159`) →
emitter-ratchet ramp (`:5359`) → `strikeChord` FILL-swell×velScale+clamp (`:3035`) → **EMITTER VELOCITY offset in
`emitOneOutput` (`:2080-2084`, LAST)**. **Per-rank KIT scale choke point: `emitOneOutput` after `:2083`**, guarded
`if euclideous && euclideousStrikeRank>=1` — `velOn` is final; it catches synchronous, echo-tail, emitter-ratchet and
audition strikes; `euclideousStrikeRank` (1–8; `:3022`/`:2278`) + `euclideousStrikeLane` (`:3568/2277`) give rank+lane.
(`euclideousRatchetStrikeVelocity` is dead/FX-retired — don't hook.)

## (d) INPUTS POOL row
Lane-card INPUTS tab (`poolTabContent` `EuclideousPage.swift:7761`; POOL row `poolNowRow` `:7803` → `PoolNowChipsView`
`AnswerViews.swift:50` → `EuclideousRankChipView` `RankChipPainter.swift:17`): each cell = rank over note name
(`stackRank:true`) + a lit bar + **the small square top-right = `sourcePip`** (`RankChipPainter.swift:109`, 5×5
source-colour; nil for octave copies — keep, §5.4). **A tap does NOTHING today** (pure display) → §4.1/§5.4 adds a tap.
Audition = `poolTestButton` (`:7901`, momentary) → `euclideousRunAudition` (`Router.swift:2200`): routes to the lane's
own outputs (`riffOutMask|notesOutMask`), the output's channel stamp, velocity **hardcoded 100**, **150 ms spacing /
120 ms gate**, free-running sample clock, **sounds while the transport is stopped**. Reuse this routing/timing for the
editor, scaled by the rank's kitVel (§5.5/§4.8).

## (e) APPLY TO ALL
`euclideousApplyInputsToAll` (`Derivations.swift:13186`) copies only `poolSrcMask` + `midiMode` (button
`EuclideousPage.swift:7792`; one undo step). → add the 4 kit fields (§1.8).

## (f) Same pitch / overlapping offs
`addPitch` dedups within a hit — first insertion wins, the second dropped (`Router.swift:4378`); the notes layer narrows
off the riff's outputs (`:4382`). At the wire, a per-(cable,ch,note) refcount (`:365`, bump `:1674`, release `:1861`)
emits the note-off only on the LAST release; a restrike re-articulates (off then on). → **§3.4 tweak**: a KIT stack
event's duplicate pitch on one emitter must be sent once at the **highest** of the duplicate ranks' velocities (today
keeps the first). The riff+stack same-pitch rule (first wins) is unchanged (§0.1(f)).

## (g) Note naming
Base-C = MIDI 48 = **C3** (`Derivations.swift:1023`), i.e. **C4 = 60** (`euclideousNoteViewName` `:2969`,
`euclideousAccessibleNoteName` `:2987`, ♯/♭ U+266F/U+266D). Use these (as PICK's editor does). → default kit KICK 36 =
**C2**; the editor's default range for the default kit is **C2–B3 (36–59)**.

## (h) HARMONY overlay (for §4.1)
Mounted in `pageBody` (`EuclideousPage.swift:1999-2003`): sized `page.lanes[0].union(page.lanes[3]).size`
(**769.33×610 landscape / 782×611.33 portrait**), offset to lane 0, `zIndex(6)`; `openHarmony()` (`:2549`),
`closeHarmony()`/`closeAllOtherOverlays()` (`:2461`), a tab-strip tap closes it (`:2220`). Surface: HARMONY card
`#1A1C21` r12 1pt `#2E3138` pad 16 (`HarmonyPage.swift:62`); inner popovers `#24262C`. GRID CHANCE's page-level
outside-tap catcher (`EuclideousPage.swift:2005`) is the reuse pattern. No piano keyboard exists — build from scratch.

## Differences from the spec (source wins)
1. §5.1 KIT chip on-look "#EDEFF3 + 8×8 dot" vs today's chips `#DFE3EA` + 4.5 pt lamp (`poolSourceChip` `:7844/7855`);
   spec also says "the on look of today's chips" → **match today's chips**; `#EDEFF3` isn't in the tree.
2. §4.1 editor surface "#1B1D23" vs HARMONY card `#1A1C21` / inner popover `#24262C` → use the spec's `#1B1D23` (new surface).
3. §5.4 "small square top-right" = 5×5 `sourcePip`, not 8×8 → keep as today.
4. §2.2 PITCH pad "skip" — already retired.
