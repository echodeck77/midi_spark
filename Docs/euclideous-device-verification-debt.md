# Euclideous — open device-verification debt

A running checklist, not a log. `Docs/euclideous-status-log.md` is full of "DEVICE-OWED" flags
(160+ of them as of 2026-10-14) scattered across hundreds of entries with no way to tell which
are still open versus quietly confirmed by a later entry — that's the actual problem this file
exists to fix. Historical backfill into this list is NOT done (deliberately — most of those 160+
are stale, superseded, or already implicitly confirmed by later work touching the same code, and
mining them accurately would mean re-reading the whole archived log). Starting fresh from here.

## The rule going forward

When a ferry/fix ships with something that can only be confirmed on-device, add ONE line below
under the right subsystem — not a paragraph, not a re-explanation, just enough to know what to
go check next time the iPad is in hand. When Paul confirms something on-device, delete the line
(or move it to "confirmed this session" briefly, then delete on the next pass) — this list should
shrink as often as it grows. If it only ever grows, it's not doing its job.

## Open items

### LISTEN REBUILT (2026-10-23)
- LAUNCH the DEBUG build from Xcode into AUM first (`listenPausedOverlay`/the RHYTHM-tab rate-grid rewrite are new/changed leaves on the 1 MB main stack).
- The LISTEN tab's FOLLOW row chips, RHYTHM OWN/COPY/FILL row + its DELAY/FEEL/SPEED/DIRECTION panel, and PITCH OWN/SHADOW/ECHO/AVOID row + its INTERVAL/OCTAVE panel: legible and tappable at the real card width in all four lane colours; the panel's proportional shrink under pressure (down to its 30pt floor) actually looks acceptable rather than cramped.
- The paused-card overlay (link glyph, "X FOLLOWS LANE n", explanatory line, GO TO LISTEN / USE MY OWN) over a borrowed RHYTHM/RIFF/NOTES tab: legible over the 18%-dim content behind it, both buttons easy to hit, GO TO LISTEN actually switches tab and USE MY OWN actually restores control.
- The RHYTHM/RIFF/NOTES tab header's "← n" link glyph vs the normal count/glyph — reads clearly as "this is linked to another lane," not as a typo or a truncated number, at a narrow tab width.
- COPY vs FILL sounding correct by ear (FILL audibly plays the gaps, not the hits) at DELAY > 0, a non-zero FEEL, and each SPEED setting (¼ ½ 1 2 4), including PING-PONG DIRECTION against a source lane that's itself running BKW.
- ECHO sounding like a canon (the source's own line, played back in the source's own order) rather than a simple doubling — especially the handoff at a cycle boundary (does the last-completed cycle's tail audibly connect to the new cycle's head, or is there an audible gap/glitch?).
- AVOID dropping EVERY colliding pitch class (not just the lowest) when a chord is held — listen for a note that should have been muted but wasn't.
- VoiceOver: a RHYTHM/RIFF/NOTES tab reads "paused, following lane n" once (not duplicated); the LISTEN tab's mode buttons and SPEED/DIRECTION segments read their new labels correctly; the paused-card's two buttons are each individually reachable and actionable, not swallowed into one combined element.
- An OLD session (saved before this ferry) that used FOLLOW, WITH, GAPS, SHADOW, AVOID, DUCK, or ACCENT loads with the stated migration mapping and SOUNDS the same as before (bar FOLLOW's own multiplier/rate wording, and DUCK/ACCENT, which have no replacement and will sound different) — listen for anything that migrated silently wrong.

### FOURFOLD STEP 3 — the standalone app (2026-10-23)
- Install the `Fourfold` app. PLAY starts the page from the top; STOP silences it with nothing stuck; BPM − / + / slider changes tempo with no jump; the bar·beat readout follows. Launched stopped it plays NOTHING.
- Its MIDI outputs "Fourfold All / Out A–D" appear in another app (AUM, a synth app, a DAW) and the notes land ON the grid — record a few bars and look at the spacing; this is the one thing the simulator could not show (it reports packet timestamps as "now"). Compare Out A against All: same notes.
- MIDI IN: a keyboard (USB, Bluetooth or another app) plays into Fourfold with the source set to MIDI IN; HOLD / LATCH work; the app never feeds its own output back in.
- Background: with PLAY running, switch to another app / lock the screen — it keeps playing and sending MIDI (UIBackgroundModes audio). Another app's audio is not ducked or stopped.
- Interruptions: a phone call / Siri / unplugging headphones — the app recovers by itself and the bar position carries on rather than jumping.
- Quit and relaunch: the lanes, riffs, FX, key — your session — come back; the tempo too.
- Settings (gear) → CLOCK: no "WHEN THE HOST STOPS" row (only STRIKE PULSE).
- The extension still works in AUM as before (the app and the extension are separate; the app does not touch AUM's).

### FOURFOLD STEP 2 — the page in the extension (2026-10-23)
- LAUNCH the DEBUG build from Xcode into AUM FIRST (the root view's frames were measured, not run on the iPad: `pageView` 214 → 9.7 KB, `slowPoll` 36.9 KB; the old 1 MB-stack crash was on a Debug launch).
- "Outlier MIDI: Fourfold" in AUM opens the real page (not the placeholder), in AUM's plugin window size; edit a lane, play: notes on the routed Out A–D ports (All carries everything); the 20 factory presets load AND are heard at once (`publish()` after load).
- Settings sheet (gear): the footer has NO WORKBENCH link; 8x8 State's Fourfold settings sheet still has it and still returns to the workbench.
- REEL: tap the tape icon → the browser opens above the page (landscape; portrait shows the rotate prompt), passes appear after a few bars of the host playing, tap a pass to hear it, SAVE opens the share sheet over the browser (the sheet is now presented by the browser itself, not by a hidden workbench view — check it appears), CLOSE resumes live.
- Undo / redo, lane LOCK, SOLO, RANDOM, the key pop-up, SWING, the output rings: all copied code — exercise each once.
- The pulse level starts at FULL (a new storage key), and the settings sheet's STRIKE PULSE row still changes it.

### FOURFOLD STEP 1 — targets (2026-10-23)
- Install the `Fourfold` scheme from Xcode: AUM lists "Outlier MIDI: Fourfold" as a MIDI processor (separately from "8x8 State"), it opens to the placeholder, and its MIDI outputs are named All / Out A–D. 8x8 State must still be listed and unchanged.

### FOURFOLD REEL LINK (2026-10-23)
- LAUNCH the DEBUG build from Xcode into AUM first (`headerUtilities` gained a child; `Scripts/debug-frame-sizes.py` against the FX-ferry build: its closure 3264 → 3344 B (+80 B) with the reel button as its own `AnyView` leaf (inline it was +624 B); the icon's own TimelineView body closure is 2.8 KB at render — the 1 MB stack only really answers on the iPad).
- The tape icon sits between SWING and the gear; it reads dim when stopped and RED, breathing, with a pulsing dot while the host plays (and stays still under Reduce Motion). Tapping it opens the pass browser ABOVE the Fourfold page (not behind it), landscape.
- Header at your iPad's real width: still ONE row at 1190; check any narrower window (below a 1134-wide view the header goes to two rows — an iPad mini 6 at full width is 0.86 pt short).
- Play a Fourfold session in AUM for a few passes, open REEL: passes are filed; tap one — it replays Fourfold's output (the live output is replaced while browsing); the roll's A–D bands match the lanes' MAIN OUT routing; CLOSE returns to the page and the live output resumes with nothing stuck.
- The DOWNBEAT: a pass that starts on a hit shows that hit at the START of its own roll (it used to sit at the end of the previous pass's roll). Export a two-pass range and open it in a DAW — no doubled note-on at the first beat, no orphan note-off.
- SAVE → share sheet appears over Fourfold (anchor is the workbench header's hidden view under the page); the lane (A–D) selection exports only those outputs.
- The sidebar line `1 PASS = n BEATS` matches your clock (8 steps of the 8×8 step rate — Fourfold's lanes have their own rates, so a pass is a slice of time, not a lap); RESTORE SETUP is absent; the wording says "output".
- Portrait: the browser shows ROTATE TO LANDSCAPE (as the 8×8 always did) — say if you want a portrait layout.
- A very busy Fourfold session (four lanes at 1/32, chords, RATCH 3–4): does a pass keep its tail? (past ≈ 8k events a pass drops the end).

### FX REVIEW FIXES (2026-10-23)
- LAUNCH the DEBUG build from Xcode into AUM first (`EuclideousFXPanel.strip` gained a RATCH branch with a stepper; the lane buttons' modifiers changed).
- RATCH at fast steps: a 1/32 lane with RATCH 4 at 1024 / 2048 buffers plays all four strikes, evenly spaced, every time; a 1/16 lane at 160+ BPM too — listen for dropouts that used to be there.
- RATCH on a default session (scene step 1/2): a 1/16 lane with RATCH 3 / 4 plays 3 / 4 strikes (it played 2); a 1/16T or 1/32 lane ratchets (it did not).
- RATCH SHAPE: ACCENT / FADE / RAMP read as a roll with a shape, not as noise; RAMP into the next step feels like a crescendo, FADE like a decay; the numbers (65 %, 45 %) are a first guess.
- Four lanes on one output with RATCH 4 at 1/16 — no missing notes (they lost a quarter before).
- NOTE row with a melody restart: the LANES roll's bars match what plays (a melody [2] returns the ladder with the riff); a melody [1] lane's NOTE row climbs a rung per lap.
- The FX tab for a lane whose riff is off or that SHADOWs: its lane buttons and rail dots read as dimmed, and a VoiceOver swipe on a VEL / CC cell moves 4.

### FLOORS ferry (2026-10-23)
- RIFF tab on a small/windowed AUM panel: the WALK strip actually disappearing (not just shrinking) when the direction row would otherwise be under 32pt, and the direction row's chevron/"Invert melody" buttons at their real, now-variable height.
- RHYTHM tab: TILT's/OFFSET's "EARLY"/"LATE" end-labels dropping cleanly (no half-clipped text) below the new 28pt threshold, slider still fully usable without them.
- MIX tab at a cramped panel size: the OCT stepper and OUT row visibly shrinking together (18pt/14pt) rather than the pad alone looking squeezed; "OCT +1" still legible at the compact stepper height.
- Riff grid panel at a cramped box: the tab row (RIFF 1-4 selector) at its 14pt compact height — tap targets and the mini pattern icon still legible/hittable; the note-label column at its 20pt compact width — note names ("A♭3" etc.) not visibly colliding with the grid.
- FX tab at a cramped panel: the hint row actually disappearing (not just truncating) once the six rows would otherwise hit their hard 24pt clamp; confirm the panel no longer visibly overflows its own bottom edge in the case that used to.
- All five: confirm none of the new compact-floor NUMBERS (my own picks, chosen smaller than the existing floor so they bite only in genuinely cramped cases) look wrong on a real iPad at the sizes they're meant for — easy to retune once seen.

### CLARITY PASS (2026-10-23)
- LAUNCH the DEBUG build from Xcode into AUM first (the lane tab row and the MIX tab were rebuilt; the DEBUG frames were compared against the previous build and the strip's draw closure is +16 bytes, `mixCell` −1.6 KB); the RHYTHM tab row and the MIX tab must come up on all four lanes.
- Beat shading reads as countable blocks without looking busy at 8, 12 and 16 steps and under a triplet (groups of 3): #41454F / #30333A rests on the card ground, a 0-hit lane still showing every step.
- Hit columns at 42 % / 30 % in all four lane colours: clearly hits, clearly lane, and the chips still read on them (computed: the white chip stays ≥ 2.8:1 and ΔE ≥ 38 from the lane column).
- The current chip vs a 42 % lane column (spec 1.4): no border was added; the worst case is the red lane, group A, at the chip's top (2.79:1) — if it is not distinct enough on the iPad add the 1 pt #F2F4F7 inner border to the current chip only.
- The 9 pt glyphs: square vs bar distinguishable at a glance beside the label; the 40 % off state reads as off, not broken; LISTEN's circle in the source lane's colour (and the four-colour circle for AVOID + ANY).
- "RHYTHM n/m" at real tab widths — it truncates the count, not the label, on a narrow tab or a locked lane.
- MIX lane panels (6 % tint, 35 % border) group the pads without adding clutter; the panels' 2×2 positions match the lane cards.
- "VEL 100" / "90%" and the pad labels legible over the pad fill in all four lane colours; the label and the puck/extension lines crossing when VEL is high and GATE mid (label top-left, puck near it).
- An OFF pad: the dashed outline, "OFF", the label and glyph (outline) legible; a tap does nothing; its stepper at 50 % still edits.
- Solo a lane: the other lanes' whole MIX panels (tint, border, pads, steppers, OUT row) dim once to 42 %; and "OCT +1" with the 21 pt buttons at the real width.
- A FOLLOW lane: its RHYTHM tab shows the PARTNER's hits/steps (and its strip shades in the partner's division), not its own sliders' numbers; a WITH / GAPS lane still shows its own.
- Switch a layer off right after it struck (a riff or notes pad mid-pattern): the OFF pad must show no ripple / flash / knob afterwards.
- VoiceOver on the lane tab row and the MIX panels (never exercised): each tab reads its §4.1 sentence and a double-tap switches tab; the panels read lane by lane (riff pad, notes pad, OUT row); an OFF pad reads "Lane N riff, off" and offers no adjust.
- "RHYTHM 10/16" … "16/16" (87.6 pt vs an 87.2 pt tab) truncates its last digit landscape; a locked lane truncates earlier. Look for whether that reads acceptably.

### RESTART TILES (2026-10-22)
- LAUNCH the DEBUG build from Xcode into AUM first (new leaves `restartEditorStrip`, `restartTileLayer`, 2.8–3.3 KB each on the 1 MB main stack); the RHYTHM tab and the restart editor must come up on all four lanes.
- Repeat strikes on one MELODY cell read as "the same note again", not as noise, with four lanes running (EVERY 2, ADV STEP, REPEAT on rest).
- Clear and refill reads cleanly at the walk's wrap (the first cell lighting in the same frame the others clear), including at a melody restart.
- Ghost cells (the dashed notes this walk cycle won't reach) legible at 6 pt in all four lane colours; the track's eight cells at 160.75 pt.
- The restart editor's live strips at real size: sweep and track under each chain row, following a tapped link / + / FREE at once; no timeline, "BAR 1–16" or hint line left.
- Dashed rests restored on the lane strip in all four lane colours (a rest column present beside the 24 %-fill hit columns, never a dot), at OFFSET 0 and with a fractional OFFSET.

### Random mode badge placement (2026-10-22)
- Turning random mode on draws the thin "RANDOM" border and its badge ON THE RIFF GRID (top-left of the grid), nothing over the header; lock mode's dim washes the riff grid and the MIX | LANES | FX panel where they are (it was drawn at the page's top-left too).

### RHYTHM POLISH (2026-10-22)
- LAUNCH the DEBUG build from Xcode into AUM first (the 1 MB main-thread stack: the slider body closure grew ~0.9 KB, four new leaves of 1.3–3.5 KB); the RHYTHM tab must come up on all four lanes.
- The 36 pt HITS number and its clamp, in all four lane colours: centred on the filled part, the "OF n" caption legible in the pale lane colour, 0 hits fully inside the tile (block at y 51–99 of 124), FOLLOW lane (42 %) still reads.
- OFFSET and TILT at 38.67 tall: the drag feel, the 0.08-step and 3 % detents (do they feel like a magnet or a snag?), and EARLY / LATE fitting under the "TILT" label and the value (the line boxes overlap 4.3 pt, the ink should not touch).
- FLIP HITS legible at 8 pt in a 38.8 pt button, on and off; the direction row's four buttons even.
- The sweep: smooth at 60 and 120 Hz, the hard drop at the restart reading clearly, and not noisy with four lanes running; the border/fill of a set vs FREE tile.
- The rhythm ghosts (dashed) and the melody ticks legible at 6 pt; a 3-link chain's label truncating to "MELODY RE…" reads acceptably.
- A fractional OFFSET sounding as a clean shift (5 → 5.25: every hit a quarter of a step later), including under BKW (earlier) and PING-PONG, and the hit that wraps to the start of its pass; TILT unrounded (drag through a few %) with no zipper noise, and a locked lane snapping a fractional offset back.
### RIFF tab labels + ADVANCE EVERY cap (2026-10-22)
- The WALK strip's readout line reads cleanly without "LINES UP EVERY n PASSES" — confirm it doesn't now look like something's missing where that text used to anchor the line.
- EVERY pips (one dot per hit/step) at 8 don't look cramped or run together at a narrow card's column width (they're 2pt circles, 1pt apart — 8 of them is noticeably more than the old max of 4).
- "Invert melody" at 10pt actually fits (or truncates acceptably) at the riff tab's real card width, now that the direction row is 4-way split instead of 5-way.
- The three chevron buttons ("<"/"><"/">") on the riff tab read clearly as directions without the word labels, matching how the RHYTHM tab's own chevrons already read.
- EVERY 5-8 sounds correct in AUM (no stuck notes, no doubled/dropped hits) — these values were reachable before only via a corrupt/out-of-range stored document; now they're a normal, UI-reachable setting.

### RANDOM MODE lane-box buttons (2026-10-22)
- The dice's marching-ants dashed ring reads as "this is on" without being distracting at the header's small scale, in both header layouts (A/B/C).
- The new PLAY/SOLO row on a picture-mode card looks and behaves exactly like normal mode's — tapping PLAY actually starts/stops that lane while rolling, tapping SOLO latches/holds exactly as it does outside random mode, and the row doesn't visually collide with the RHYTHM/RIFF/NOTES selector just below it.
- The picture's own height (now 50pt shorter) still fits each of the three pictures comfortably at the card's real frame.
- With the riff grid and MIX/LANES/FX fully interactive during random mode now, confirm nothing about editing them while a roll is queued or held causes a visual/audio glitch (this was never exercised before, since those panels used to be blocked).
- The riff grid's new "RANDOM" badge + border reads clearly without obscuring the grid's own labels/arrows, in all four lane colours' arrows underneath it.
- Confirm tapping the riff grid or MIX/LANES/FX no longer accidentally finishes random mode (it shouldn't — only the dice does now) and that nothing on those panels now misinterprets input while a hold/landing is active.

### LANE LOCK (2026-10-21/22)
- (review 2026-10-22) The comet bar's dashed outline (drawn round the bar only, radius 8) reads clearly beside the SOLO button and doesn't clip at the card's top edge; with VoiceOver on, each outlined control (incl. direction, INV, rate cells, riff card, notes keys) ends its value with "will snap back"; with SWING above 0 on a quarter-note page step, a BEAT-grid snap at an odd beat may land a swing-width off the line (known limit).
- LAUNCH the DEBUG build from Xcode into AUM first (the 1 MB main-thread stack; the page must come up), open lock mode with the padlock, then tap off the cards to finish: the finish never presses something underneath.
- Snaps on the bar line sound clean in AUM at 64 and 1024 buffers — no doubled or dropped hit, no stuck notes — including the hit ON the downbeat after the line (the fill: lock a lane on 4 BARS, push HITS up and flip REV in bar 4, hear it return on bar 5's downbeat).
- The BEAT grid's momentary buttons feel immediate (hold REV: reversed while the finger is down, back on the first beat after the lift); drags (OFFSET, HITS) move while dragging and snap back cleanly on the beat after the lift.
- Snapping on a 2- or 4-bar line reads as "on the phrase"; the badge's count-in (a number of bars, then dots per beat in the last bar) is easy to follow by eye.
- The badge's countdown and the dashed outlines read as "this will come back" without hiding values, in all four lane colours.
- The tab row with the badge: tab labels still read, and the 34 pt badge (44 pt touch target) is comfortable to tap (unlock) and hold (lock what's playing, at 300 ms).
- The lock card reads at a glance at ≈381 × 319 and ≈387 × 320 (summary rows, the SNAP BACK selector, the tick strip).
- The header with the padlock: BRAND is 52 pt wider — the output rings now sit flush against it, right of the lane gutter (see pending-tasks) — and the header ladder (A / B / C) still fits at AUM's real window sizes.
- Undo never moves a locked lane; save and reload brings the locks and their states back; a locked lane saved while deviated reopens at its locked state.
- The stopped page: editing a locked lane with the transport stopped puts it straight back on release.
### LANE STRIP readability (2026-10-22)
- Hits countable at a glance at 16 and 8 steps in all four lane colours (24% fill, 70% border, floor bar).
- The 2 pt rest dot reads as "rest, present" without competing with the hits.
- The riff contour still reads as the melody with ranks 2 pt apart.
- The current chip separates from its lane-tinted column in all four lane colours.
- The playhead band at 14% still reads as "now" over lane-tinted hit columns; tune its fill and edge alphas if not.
- A 42%-dimmed strip reads as greyed out, distinct from a live lane, in all four lane colours.
- Whether any real layout puts a column under 6 pt wide (the floor bar's full-width fallback) — not confirmed either way during source mapping, only on device.

### RANDOM MODE (2026-10-21)
- Landings sound clean — no doubled or dropped hit — in AUM at 64 and 1024 buffers; also judge whether the ~150 ms safety margin before a bar/beat line feels too eager or too laggy.
- The hold's switch on the beat feels immediate enough to compare by ear (touch-down → original, release → current).
- The three pictures (RHYTHM circle, RIFF path, NOTES pattern) read at a glance at a lane card's real frame (≈381×319 landscape, ≈387×320 portrait).
- The THROW/TWEAK/BACK/KEEP buttons (two-up and four-up) are comfortable to hit at their real card width.
- `die.face.4` actually renders (SF Symbols availability unverified at this deployment target — no compile-time signal either way if it's missing).
- The simplified §7.3 return highlight (a ring fade + "KEPT · UNDO TO GO BACK" tag, not the full per-control glow the spec also names) reads as "these moved" without hiding the values.
- Tapping off the lane cards (header, margins, gutters, the dimmed riff/bottom panels) reliably finishes and never also presses something underneath.
- The riff panel + bottom-right panel's dim wash (rgba(12,14,18,0.62)) reads as "inert" without looking broken, in all four lane colours' pictures on top of it.

### RANDOM MODE adversarial-review fixes (2026-10-22)
- The RHYTHM picture's new live playhead ring (a FREE-pattern-phase approximation — it ignores restart chains) tracks believably against what's actually heard, at 64 and 1024 buffers.
- The NOTES picture's new 3-state dot (sounds / CHANCE-dropped at 35% / never-in-pattern at 4pt) reads as three states, not two, in all four lane colours; the ROLL/RUN dot spreading (3pt/6pt per strike place) doesn't look like visual noise at 8 ranks.
- The new §3.4 hint row ("HOLD THE PICTURE TO HEAR THE ORIGINAL" / "PLAYING THE ORIGINAL · LET GO FOR THE NEW ONE") is legible at 7.5pt beside the caption above it, and the two never collide.
- The selector pill now spanning the full row width (instead of shrinking to its content) still looks balanced at the card's real width, not stretched.
- VoiceOver: the picture's spoken label (per tab) and the "Play the original"/"Play the new one" custom actions actually surface in the rotor and behave like the touch hold (switches on activation, not after a delay).
- The §6.8 external-write-decides-the-roll path (host automation/MIDI learn touching a field mid-roll) — no real device trigger exists yet for these specific fields, so this is logic-only verified; flag if a future ferry adds host automation to RHYTHM/RIFF/NOTES fields and this needs a real exercise.

### Restart tiles — labels and flash (2026-10-21)
- The RHYTHM tab's two tiles read "RHYTHM RESTART" / "MELODY RESTART" and are legible at 8 pt; on a narrow card they fall back to "RHYTHM" / "MELODY".
- The flash reads as "stylish" and in time: each tile flashes on the chain restarts you set and — on FREE — at the pattern's natural restart (RHYTHM: every pass; MELODY: the riff coming back to its first step, which is NOT every pass), in all four lane colours; the sweep, the rim glow and the spinning ↻ don't feel busy at fast rates (1/16 passes every ~1 s).
- It stops when the lane stops or the transport does, honours PULSE OFF / SUBTLE and Reduce Motion, and the tiles still open the restart editor on a tap.

### Lane SOLO (2026-10-21)
- LAUNCH the DEBUG build from Xcode into AUM first (the 1 MB main-thread stack; the page must come up), then: 300 ms tap versus hold on the SOLO button feels right, and solo engages on touch-down with no lag (the snapshot path: one run-loop turn + the next window — judge the hold).
- "SOLO" legible at 44 × 44 in all four lane colours; the latched (lane colour) and held (#DFE3EA) looks read as different; the OFF border shows.
- A whole card at 42 % reads as "greyed out", not "disabled" or "broken", in all four lane colours — and the SOLO button beside it reads as the way back in.
- Two-handed play: holding two SOLO buttons at once in AUM, and a latched lane plus a held one.
- Solo in and out mid-phrase sounds clean: no clicks, no stuck notes (legato / TIE / ratchet lanes especially), lanes back in time.
- The 0.15 s ease: the card, MIX, LANES, riff arrows / rails, FX dots and ring quarters all ease (and the existing LANES-mute dims now do too); a quarter of a ring and a shared riff cell's blend snap by design.
- Preset load: a factory preset clears solo; a user preset saved while a lane was latched restores it (decide if that is wanted).

### RHYTHM tab fixes — restart-engine edges, STEPS, layout fallbacks, accessibility (2026-10-21 ferry)
- The restart editor below 192pt: it should keep drawing (chain rows + editor), losing only the
  timeline under 156pt and the hint line under 128pt too, instead of refusing to render at all.
  Check all three bands in both orientations on a small split-screen AUM window.
- OUT button (MIX), restart-editor close ×, steps-picker close × — the widened touch targets (24pt
  tall now, drawn size unchanged) should feel easier to hit without any false taps on the OCT
  stepper directly below OUT.
- VoiceOver: the restart editor's close button now reads "Close restarts"; a STEPS swipe (±1) should
  record its OWN undo step — two swipes then two undos should land back where you started, one step
  at a time, not jump back two steps on the first undo.
- An AUTO-lane ramp that changes STEPS, then a manual HITS/OFFSET edit afterward: the edit should
  land on the fresh default pattern, not resurface whatever HITS/OFFSET was asked for before the
  ramp (this was the stale-request-field bug; fixed, but only test-covered, never heard).

### DEBUG-build launch (2026-10-21)
- Run the DEBUG build from Xcode into AUM and open the page: it must come up (the 2026-10-21 DYNAMICS ferry crashed it at launch — `Thread stack size exceeded`, fixed by `fix/dynamics-stack-depth`). Then open the RHYTHM tab on each of the four lanes (the right half is two rows again, OFFSET and TILT — both must drag as before) and switch RHYTHM → RIFF → RHYTHM: none may crash. This is the ONLY check the stack fix has had (frame sizes were measured off the binary, the page was not run).

### Riff grid — only a running lane has an arrow (2026-10-21)
- Switch a lane's PLAY off while the others run: its arrow leaves the grid and its rail shows only the played columns; switch it back on: no arrow until its first hit lands, then it follows.
- Take a lane to 0 HITS: same. Stop the transport: every arrow goes (as before); start: arrows appear lane by lane at each lane's first hit.
- The RIFF tab's thumbnail: no highlighted current column and no "now on step" while its lane is stopped (the WALK strip's ring already behaved so).
- A lane muted by the LANES grid still shows its arrow, dimmed to 42%.

### Lane strip — the riff contour over the notes keys, in place of the comet (2026-10-21 ferry — §11)
- The riff contour reads as the riff's melody at 8 and 16 steps (ranks ≈ 2.6 pt apart; columns at 16 steps are 11.2 / 13.6 / 17.1 wide on a 10.2" / 11" / 12.9" iPad landscape, so chips are 7 / 10 / 13 wide and carry a label from ≈ 345 pt cards up; key labels begin at 12 steps, and "G3+2" truncates to "G3…" at ≈ 16 pt).
- Chip labels at 7 pt on the light chip and on the lane gradient (current chip), in all four lane colours; the chip is #DCDCDD and the cell #28292D (the riff grid's real composites), not the ferry's #DFE3EA / #24262C.
- Key labels at 7 pt and the 2 pt bar at 14 pt tall; the CHANCE ring reads as "may skip"; the key glow (clipped at the strip's bottom edge) and the chip glow (clipped at rank 8's top edge).
- The playhead band reads as "now" without the comet, glides smoothly over the 7 pt group gaps, and slides off the end cleanly; 60 fps while a lane runs — watch the iPad with four strips + the riff overlay (the per-frame work is pure and tiny, the Canvas text/shadow draw cost is unmeasured).
- The strip's key and the NOTES tab's key feel like ONE event (the tab key's shadow radius is 10, the strip's 5 — the codebase's half-a-CSS-blur convention; say if the strip should match the tab).
- Velocity still reads without the level mark (chip glow/dip and key ring/glow strength).
- The current chip follows the arrow on the riff grid, including TIE's stay-put and REPEAT's hollow chip; ADVANCE EVERY 2-4: the chip numbers now agree with the engine (they did not before this ferry).
- A PING-PONG lane: the strip flips to the way-back chips and keys when the playhead turns at the end (the up sweep and the way back read different notes); the current chip follows the arrow on both.
- A SHADOW lane: no chips, the partner-colour band over the key row; a FOLLOW lane: no partner-coloured cells any more (the count box's dot still says who it follows), the playhead runs at the partner's rate.
- Mute a lane on the LANES grid: the whole strip dims to 42% and nothing strikes; PULSE OFF and Reduce Motion as §4.5 says; VoiceOver reads the strip as one element ("Lane 1 step strip").

### NOTES tab rebuilt — keys, WHEN, PLAY AS, CHANCE, RECEIVED; FILL leaves ON REST (2026-10-20 ferry — §15)
- The 27.85pt keys at real size: labels, the 3pt bar, the hollow bar, the 8.5pt place numbers and the riff dot, in all four lane colours, on received and copy keys; TOP 2's lower-note-plus-"+" label (it keeps its PAIR) and its "2–3" place number.
- The PLAY AS button's 19.6 × 30 preview columns and the picker's 47pt previews: legible, with RUN's split bars and ROLL's offsets readable.
- The picker's cells (106 × 85 and 79 × 85) and its 30 × 18 close button are comfortable to hit; the picker closes on a tab switch.
- The pips on 8- and 16-step lanes, and the grey footers with the riff off (WHEN one-sided); a rest hit where the notes strike flashes solid.
- ROLL's 25ms spacing sounds like a strum, and RUN sounds like a quick figure, at slow and fast tempos (and at a large host buffer — a note inside the current window is struck directly).
- CYCLE, BOUNCE, SPLIT and BUILD follow the lit order and restart cleanly at a melody restart.
- RECEIVED: lit ranks join in as the held chord grows (the hollow bars fill in).
- A tied rest with RESTS on sounds like the notes striking under a held riff note (and never re-strikes the held pitch).
- The 42% dim while the notes are off (right of the strip only).
- An old session with the riff on and ON REST SKIP/TIE loads PLAYS-only (sounds as before); one on FILL loads SKIP with PLAYS+RESTS (sounds as before). Check one of each by ear.
- With nothing held every key shows an en dash and the copy look (the ferry said rank numbers; kept the grid's own look).
- VoiceOver reads and operates every control, the picker included.

### FX GATE row: legato removed; LISTEN SHADOW/AVOID follow the partner's real walk (2026-10-20)
- FX GATE row: the top cell reads 95 (it was 100 / "LEG"); the strip says only "REPLACES THE LANE'S GATE"; a repeated pitch under a GATE cell re-strikes. A session saved with a GATE 100 cell loads it as 95.
- LISTEN: give a lane EVERY 2 (or a MELODY restart chain, or a RHYTHM chain that cuts a pass short), put a second lane on FOLLOW + SHADOW (unison) of it — the second lane now sounds the same notes as the first, hit for hit
  (it used to follow a different column). AVOID/MUTE of such a partner mutes the colliding hits.

### Header: output rings at 75%, HOLD/LATCH buttons (2026-10-20)
- The four MAIN OUT rings' actual on-screen size at 0.75× — the `.scaleEffect`+reclaiming-`.frame` technique
  (same idiom as the Settings Sheet's existing 0.8× mini rings) is untested on a real render; confirm the ring,
  its tap target, and the flare/pulse animations all still read cleanly at the smaller size, in both the full
  and compact header layouts.
- HOLD/LATCH chips beside the key pill: legible at 48/54pt wide, selected-state fill reads clearly, dim to ~40%
  and stop responding to taps the moment the source control leaves MIDI IN (tap CHORDS/KEY while one is
  engaged — does it visibly go inert, not just silently no-op?).
- HOLD against real MIDI input: play a chord, release every key — does the engine actually keep sounding the
  last chord (not just pass the off-device unit tests)? Then play something new — does it cleanly replace,
  with no overlap/double-sounding of the old chord's notes?
- LATCH against real MIDI input: tap a note on, release it (it should keep sounding), tap the SAME note again
  (it should stop) — does the toggle feel immediate, or is there audible lag from the render-tick granularity?
- Switching HOLD ⇄ LATCH ⇄ off mid-performance: any audible glitch/double-note from the reset, or clean?
- Undo/redo (↶/↷) across a HOLD/LATCH change — does it restore the prior mode cleanly, including the sounding
  state?

### Riff panel — arrows, rails, compact tabs (2026-10-19 ferry — §12)
- The 31 × 17 arrows and their numbers in all four lane colours and in every blend (2 / 3 / 4 lanes), on the light note cells — the single-lane fill is the comet tile's 95 → 55% alpha, so its bottom reads paler (one constant if you want the mock's × 0.86).
- Hollow dashed on-rest arrows on the dark rest cells (SKIP, FILL and REPEAT all draw them; TIE keeps the solid arrow on the tied note).
- The 8pt rails, their chevrons (› ‹ •) and the 8.5pt numbers, landscape and portrait; the current segment's glow.
- The 21.7 × 12.8 tab icon, filled and empty, and the 5 × 6 triangle on the active tab (it did not exist in the restored row — check it reads as "playing").
- 25pt rows still comfortable to tap and paint (24.4 / 24.7 if the page really is 9pt short).
- The flare and its 1.06 scale: in time with the lane's comet bar, not jumpy at fast rates; a lane routed to no enabled MAIN OUT never flares (no strike event).
- A blend reads as two lanes, not a fifth colour (blue into amber for 2·3).
- The arrow now JUMPS to the latest hit's cell (the tag's flight and flip are gone) — does PEND/PING read as turning at each end without the flip?
- VoiceOver: a cell with an arrow reads "Step 3, E♭, lane 1 heading right"; each rail reads as one element ("Lane 1: plays columns 1 and 3 to 8, on 4, heading right").

### Page layout — six equal boxes (2026-10-19 ferry)
- Both orientations in AUM on the 11-inch iPad Pro: six equal boxes (landscape 3 × 2, portrait 2 × 3), 8pt apart, 16pt margins, nothing clipped, the header's gear visible in portrait, MIX | LANES | FX all showing.
- THE 885 CHECK: run a DEBUG build from Xcode in portrait and read the console — `EUCLIDEOUS root view size` (AUVC) and `EUCLIDEOUS page size … box …` (page) should both say ≈814 wide. If the root says 885 the cause is above DiagView (AUM's container), not the ZStack — say so and the fix moves.
- THE 9PT BOTTOM (Paul's ruling 2026-10-19): run a DEBUG build and read `EUCLIDEOUS root view size … safeAreaInsets …` and `EUCLIDEOUS page size … bottomInset …`. If the root's bottom inset is ≈ 9 the page now lays out on the full height with a 16pt margin (boxes 319 / 319.67, ending 16 above the bottom); an inset of 20 would give a 20 margin. If the inset is 0, the 9pt is something else — send me the lines.
- MIX in portrait: all eight pads, the OCT steppers and the four OUT rows; pads ≈ 87 × 82 (landscape) and 89 × 82 (portrait), OUT buttons ≈ 42 wide, comfortable to use; the VEL strip reads "VEL".
- Riff cells ≈ 38 × 30 comfortable to tap and paint, with the walk-tag markers still legible (their glyph scales to ≈0.89× at this width).
- LANES cells ≈ 18 wide comfortable to tap and drag-paint; blocks ≈ 55 tall.
- FX in portrait: columns sit exactly under the riff grid's (same width, same offset); the strip's descriptions and the hint row truncate (a few letters) but stay readable; rows ≈ 32 tall.
- Rotate the iPad / resize AUM's plugin window: the page re-lays at once, nothing clipped.
- Any other size you can try (an iPad mini, a windowed AUM panel): note which floors the DEBUG `page size` line lists.

### Legato removed from a lane's gate (2026-10-19)
- The MIX pad's gate axis stops at 99% (far right) and its strip never says LEGATO; every hit re-strikes, including a repeated pitch. A session saved with a lane at 100% loads at 99%.
- Nothing else about the pad changed: puck, ticks, double-tap reset (90%), the VoiceOver "longer gate" step (now stops at 99%).

### CHORDS source — hits on a chord change (2026-10-19 fix)
- With the CHORDS source and a chord that changes on the bar line, a lane with a hit ON the bar line plays the NEW chord's note there (it used to play the old chord's, or — on a
  GATE-100 lane — nothing). Re-check the yellow-lane video setup: step 5 should now sound the new chord's root; step 3 stays silent under GATE 100 (same pitch, held).

### RIFF tab rebuilt / WALK strip (2026-10-19 ferry — §13)
- The WALK strip at real size: 13.4pt slots with their numbers, dashes, EVERY pips, ring and 42% dims, in all four lane colours.
- The readout's longest kind ("LINES UP EVERY 1312 PASSES · 4 NEVER PLAY") shortens as §3.2 says and stays legible, in landscape and portrait.
- The 5.6pt mini-grid cells and their 32% dims on all four lane colours.
- The 45.7 × 40 direction buttons and the 76 × 38 EVERY stepper are comfortable to hit.
- The header row and tab row hold still when switching between RHYTHM and RIFF (the real contentAreaH-derived row-A height is 76pt, not the ferry's own assumed 82 — confirm this doesn't read as a visible height jump against RHYTHM's own zones).
- EVERY 2-4 sounds like the riff holding each note for 2-4 hits (or steps), and a melody restart regroups cleanly.
- REPEAT sounds like the riff's previous note again, and at GATE 100% like one held note.
- The strip's ring keeps pace with the riff, and agrees with the riff-grid marker under ADV HIT.
- A long PING tie (test 6: 56 hits at EVERY 4) holds as one note.
- The TIE lookahead's wider bound (P × EVERY, up to 64 hits, vs the old ≤8/4-laps) doesn't audibly change any of the 20 factory presets beyond what the golden diff already predicts.

### RHYTHM tab rebuilt / restart chains (2026-10-19 ferry — §16)
- The STEPS stepper: the 81 × 36 +/− buttons, and tap versus drag on the value box at 12pt per step.
- The picker's 4.6 × 6 preview bars at real size, in all four lane colours.
- Restart tiles: the 8pt name and unit, and a four-link chain without its unit.
- Restart editor: the 49 × 38 link buttons, the 7pt axis label, the 14.5pt timeline cells and their marks, and every hint line fitting.
- TILT's EARLY and LATE end labels: legible, and the slider still feels the same.
- MIX at padH 76: pad legibility, VEL (not VELOCITY — confirm the word choice reads right, not just that it fits), the 24pt OCT buttons, and the 46 × 20 OUT buttons being comfortable to hit.
- The dashed OUT button on MIX reads as "routed, main out off" (same look `laneOutRow` used to draw as a circle, now a rounded rect).
- The pulse and trace rings on the MIX OUT buttons and the MIX tab: noticeable without being noisy; a ring on an OUT button and the tab's own selected-state underline don't visually clash.
- Restarts sound as the footers and timelines predict, including TIE across a melody restart (DRUNK/RAND don't apply to Euclideous's own riff walk — confirmed hard-mapped to FWD at the model layer).
- The 42% dim of a cut-short pass (a rhythm restart about to cut a lap) reads as "this lap won't get here."
- The restart editor's "current bar/pass" ring on its timeline: confirm it doesn't visibly lag behind the real beat (it updates on the page's existing re-render cadence, not a dedicated timer).

### FX tab (2026-10-18 ferry — six fixed effect rows on the riff's steps)
- 29pt rows and 24pt strip controls are comfortable to tap, paint and drag inside AUM.
- The 8pt axis lock separates painting from value drags reliably, and the step sizes (RATCH 18, GATE 5, VEL 2, NOTE 14, CC 2 pt/step) feel right.
- The 320 ms double-tap window doesn't misfire on quick taps (it runs lift → touch-down), and a double-tap undoes as ONE step.
- FX columns sit under the riff grid's columns in landscape (portrait has no FX tab: its panel sits beside the grid and is 248pt tall).
- RATCH, GATE 100 and TIE sound as described at fast and slow lane rates (incl. RATCH after a GATE-100 hit, a TIE after a ratchet, TIE as the first hit after a start).
- NOTE passes on a FREE 3-hit lane and on a LOCK lane sound as the strip's preview says (C4 › E♭4 › G4 › C5 with a C minor triad), and a melody restart sends them back.
- CCs arrive at their notes' sample, ahead of the note-ons, on the right channel, on a hardware synth and in AUM's MIDI monitor (and FOURFOLD ALL's cable 0).
- The firing flash keeps up at fast rates and reads in all four lane colours (TIE cells never flash; two hits in one poll flash only the later).
- The four strip descriptions and the hint row fit at the smallest supported width; the NOTE preview truncates by design and still reads when cut.
- RATCH ticks (2.5 × 12, 4pt gaps), the GATE/VEL/CC bar, the tie arc and the bubble with its notch read at real size; a rest column and a lane-less row dim to 42%.
- The legato re-strike now closes at the hit's own sample: a lane at 80% with GATE 100 on one hit, then a different pitch, then the same pitch, never overlaps a pitch with itself.
- VoiceOver reads the rails, cells, lane buttons and steppers as §14 says (the tab is read "FX").

### MIX tab (2026-10-18 ferry — gate, velocity and octave for every layer)
- NOTES layer on/off follows the selection: a fresh lane's NOTES strip is grey, its card dot is hollow and its MIX notes pad/stepper are grey;
  select one key (or TOP / TOP 2) and all three come on together; de-select the last one and all three go grey again. With the switch itself
  off but notes remembered, selecting a note switches it back on.
- The MIX pads' turned label reads "VELOCITY" and doesn't touch the velocity number at the reference size; on a short (portrait) pad it
  truncates to "VELO…". Say if you want it lower-case.
- Pad legibility at 96 × 96: the 8pt names, the 11pt values, the puck and lines. (The portrait panel's pads are only ~66 tall — check those too.)
- Touch-to-value feel: the puck sits under the finger, no stray edits from a plain tap, and two pads dragged at once stay independent.
- The 28pt OCT buttons are comfortable, and the end button dims at −2 / +2.
- The grey off state reads as "off, still editable" (turn the riff card / NOTES off and drag its pad; tapping a notes OCT button on an off layer switches it on).
- Per-layer gate and legato against a real synth: riff at 60% while notes sit at 100% (and the reverse) — held vs retriggered, no stuck notes.
- The tab row without its readout or the ring beside LANES: MIX / LANES split it evenly and nothing else sits in it.
- One undo per touch: drag a pad, lift, drag another, undo twice; double-tap a pad and undo once returns it to before the first tap.
- The RHYTHM tab's GATE/VEL follow the riff pad; the NOTES VEL bar follows the notes pad's velocity; dragging a notes pad never moves its riff pad.
- A lane's VEL now survives closing and reopening a session (it used to reset to 100).

### Four riff tabs restored, loop dropped (2026-10-18 ferry — DROPS the looper tabs entry below entirely; its own device checks never happened before the feature was retired)
- The 4 riff tabs (over the shared grid, in the standalone riff panel) read clearly at real size: the
  selected tab's flat fill, each tab's `riffMiniIcon` glyph legible across all 4 lane colours.
- Tap a tab switches which riff is both edited and sounding, audibly, with no gap.
- Long-press a tab opens COPY/PASTE/CLEAR; the card is readable and doesn't block unrelated page gestures.
- HOLD NOTES TO PLAY over the grid still reads as a message, not clutter (unchanged, but re-check with the
  loop row gone from above it).

### Timing — the "odd timing" / gate investigation (2026-10-18)
- **The buffer-size test.** Set a lane to 16 hits on 16 steps at 1/16, record, then repeat at different AUM buffer
  sizes. The engine is proven sample-accurate off-device (`RouterTests.testEuclideousOnsetsAreSampleAccurate…`), and
  every displacement measured so far is a whole number of render blocks, so the limp should shrink in proportion to
  the buffer: 2048 → 4,3,3,3,3 · 1024 → 7,6,7,6,6 · 512 → 13,13,13,13,12 · 256 → inaudible. If it shrinks, it is the
  host's MIDI delivery granularity and nothing in the plugin can fix it. **If it does not change with buffer size,
  the whole diagnosis is wrong and this reopens.**
- Whether the same limp is audible when the plugin drives a synth INSIDE AUM vs routed to another app (different
  MIDI paths, possibly different timestamp handling).

### LANES tab (2026-10-18 ferry — per-lane mute grid, live roll, rhythm + melody restart rows)
_(Replaces the old "Sequencer panel" items — the hold-RESET gesture, the presets popover, "TAP = RESTART" and the step grid are gone.)_
- 20 × 24pt restart cells and 20 × 50pt mute cells are comfortable to tap and drag-paint on the real panel inside AUM (the stroke starts on the
  cell you touch and paints its opposite; dragging down a column across both RESTART rows sets or clears the pair; a plain tap toggles).
- The roll's legibility at 45% on the RESTART tab behind the marks, run outlines and dashed "tap here" slots, in all four lane colours; on MUTE the
  bars (lane colour when audible, grey when muted) read over both sounding and muted cells.
- Playhead speed and position agree with what is heard, for each unit (STEP / 4STP / PASS / 2PASS) and on all four lanes; tap a lane's RATE box
  through the units and confirm the cells keep their pattern while the roll rescales and the playhead speeds up or slows down.
- The 2pt gaps and the playhead's jump over them look right at real size.
- The legend and the hint text fit without truncating at the smallest supported width (the hint is allowed to truncate; the two legend labels are not).
- RHYTHM-only restart: set a mark on cell 8 of the top row — the hits re-phase there while the riff's pitches carry straight on. MELODY-only: every hit
  stays put and the riff goes back to its first rank at the mark. Both on one cell: exactly the old single restart. (Engine-proven; wants an ear.)
- A mark on a MUTED cell still restarts the lane; the next audible hit is a fresh restart there.
- A lane going muted closes its held (100% gate) note at ITS OWN cell boundary, with two lanes on different cell sizes.
- A muted lane's card dims at that beat (cells, comet and hit flashes stop, the riff-grid tag dims to 42%) and the header ring does not flare for it.
- The comet and hit flashes on a lane card follow a RHYTHM restart (they used to ignore restarts); the lane footer's predicted riff steps stay right
  after a MELODY restart (they cannot foresee a restart inside the lap — that is by design).
- A pre-feature session (sequencer ON, a reset) loads with the same sound: its migrated cells/units/marks appear on the tab, and a lane whose lap is
  not a bar sounds slightly different (nearest unit, see the status log). A NEW instance now has no restarts: the riff counts straight through.
- VoiceOver reads "Lane 1 cell 5, sounding", "Lane 2 cell 3 rhythm restart, set", "Lane 3 cell size PASS" (action "Next size"), and the sub-tab chips announce
  selected state.
- Portrait panels: the lane blocks scale to the height the 248pt panel leaves (≈37pt); check the cells are still comfortable.

### LISTEN remembers its partner (2026-10-16)
- On each LISTEN row (RHYTHM / PITCH / LEVEL): pick a partner, tap the lit mode off, tap a mode on again — the same partner is
  back with no re-choosing; swapping FOLLOW → WITH → GAPS (and SHADOW ↔ AVOID, DUCK ↔ ACCENT) keeps it too.
- PITCH: choose AVOID + ANY, switch to SHADOW (it shadows the lane you had picked before ANY), switch back (ANY returns).
- A remembered partner that has since become illegal (it now follows something, or lighting it would close a loop) falls back to
  the next valid lane instead of lighting something broken.

### FOLLOW lanes look and feel like their partner (2026-10-16)
- The follower's lit cells are the PARTNER's colour at 75% — faded enough to read as "borrowed", not so faded they look off;
  the comet head is still the follower's own colour; a strike's flash still reads against the faded fill.
- The comet's speed matches what you hear for a follower at ×1/×2/÷2 and against a partner at a different rate; the 4-vs-3
  step grouping follows the partner's feel.
- Dragging a follower's bar moves the PARTNER (hits up/down, offset left/right, pinch for steps), the readout says
  "LANE n · FOLLOWED", and both lanes' bars update together. A two-finger ALL-lanes OFFSET drag moves every lane once.
- The follower's OFFSET *slider* still shifts only the follower (a shifted copy of the partner) — confirm that split feels right.

### Walk tags — GAPS/WITH threads and the footer fix (2026-10-15 follow-ups)
- A GAPS lane (and a WITH lane) now shows a thread to its next SOUNDING hit and the tag departs early, like any other lane;
  it should never fly to a step that then doesn't sound. Check with a partner whose hits overlap the lane's.
- The lane footer under LOCK + ADV STEP on a ROTATED pattern (first hit not on step 1) names the same riff steps the lane
  actually plays.
- A hand-placed restart mark (LANES tab, RESTART sub-tab): the tag still threads and departs early instead of falling back to a static tag.
- A FOLLOW lane's step bar now shows the PARTNER's hits (not the lane's own idle pattern) under the colour wash, with one cell
  per partner step (check a partner whose step count differs from the follower's own), the footer bands sit inside the right
  cells, and the lit cells line up with what you hear. The comet's speed on a FOLLOW lane is still the lane's own rate, so
  expect it to look wrong against a partner at a different rate (known, see the status log).

### Header (Fourfold: BRAND / OUTPUTS / NOTES / UTILITIES) — 2026-10-15 ferry
- SWING icon (2026-10-17, UTILITIES' 3rd icon): the popover anchors correctly under the metronome icon in all three
  layouts (A/B/C), at both the smallest and largest panel widths; the tint change at swing≠50 reads clearly at 18pt;
  dragging the slider to 50 reads as "STRAIGHT" not a bare "50"; the wider UTILITIES group didn't visibly crowd NOTES
  or the output rings on a real device at the layouts this ferry only checked by formula.
- Header fit in AUM, full-screen and windowed, both orientations: A, B and C switch cleanly with nothing clipped;
  C (floor: page width 373) fits a 375pt-wide windowed panel.
- The header rows are now 44 tall with a 9pt top margin (keeps the spec's 31pt centre line): the lane cards below
  haven't been squeezed, and 44pt targets don't collide in the two-row layouts.
- 300ms tap vs hold on the output rings: a hold never toggles; a cancelled touch (system gesture, app backgrounded)
  never leaves three lanes dimmed.
- Lit vs unlit quarters at 36pt for all four lane colours; the dashed OFF state reads as off.
- Pulse and trace rings noticeable without being noisy; the RHYTHM-tab ring reads as "your OUT toggles are in here";
  the OUT-circle ring (≈6pt outside) overlapping its neighbours at the 3pt circle gap looks acceptable.
- Sounding flares stay in step with the comet bars (they use real strike events, so under swing they can differ by up
  to a quarter step), lit-notes-only lanes flare too, at no noticeable CPU cost.
- The FOURFOLD mark and wordmark at real size.
- Key pop-up anchored under the pill and chord grid anchored under the CHORDS segment: position and clamping in both
  orientations; the chord card fits below the header at 375pt.
- C's 36pt icon targets are still comfortable.
- Holding an OFF ring: the light disc with dashed quarters and an ink letter reads clearly (macOS render looked right;
  confirm at 36pt on the iPad).
- The OUT-circle pulse ring is no longer painted over by its neighbour, and expanding over the 3pt gaps still looks tidy;
  tapping two rings with two fingers toggles both.
- Ring flare vs the comet bar: the ring follows REAL strike events (not the comet bar's pattern+clock), so under SWING
  they can differ by up to a quarter step, and AUTO-rate lanes use the comet bar's `rate ?? 1/16` step. Compare them with
  swing at 75% and with a lane left on AUTO rate at a non-1/16 machine rate; if they visibly disagree, calibrate or share
  one feed.
- VoiceOver on a ring (iOS 17+ speaks "toggle"; iOS 16 speaks "button"): "Main out A, on, fed by lanes 1 and 4" is read
  once, with no trailing duplicate "on".
- A FRESH instance now plays immediately (no ON chip; free-run is always on; default lanes 1–2 use the KEY source,
  which needs no input) — is that acceptable, or should defaults ship with lanes stopped?

### Settings sheet (gear, MIDI IN / MAIN OUT / CLOCK tabs) — 2026-10-15 ferry, "Fourfold settings"
- Sheet fit and position in AUM, full-screen and windowed, both orientations, including a window short
  enough that only the tab content scrolls.
- 32pt channel buttons (MIDI IN) and stepper chevrons (MAIN OUT) are comfortable to hit.
- The 42% dim on the page below the sheet reads as "still playing behind," not "off."
- The 32pt mini output rings (0.8 scale of the header ring) read as the same objects as the header's own.
- A real MIDI controller on one channel, filtered by LISTEN ON; a multitimbral synth fed per-output channels.
- ALL NOTES OFF against a genuinely stuck synth note.
- KEEP PLAYING vs STOP against AUM's own transport, including the disclosed edge case where an 8×8-
  workbench free-run reason (ddSolo/staging/play) is active at the same moment STOP is selected.
- The footer's WORKBENCH link.

## Subsystem headings to file new items under

- Sequencer panel (MIX / LANES tabs; LANES = MUTE + RESTART sub-tabs)
- Riff grid + riff capture
- Per-lane mask
- Rhythm sliders / gestures
- Layout (portrait/landscape sizing, real panel width)
- Header (Fourfold: BRAND/OUTPUTS/NOTES/UTILITIES)
- Settings sheet (gear, MIDI IN/MAIN OUT/CLOCK tabs)
- Presets
- Engine/audio (anything that passed its tests but needs an ear, not an eye)
- **Fourfold Step 4 (engine copy-and-trim, 2026-10-24):** the Fourfold AU in AUM and the standalone app on the iPad must sound EXACTLY as before the trim — the golden proves 21 documents byte-identical, but it has no MIDI input, host transport edges, reel, lane lock or HOLD/LATCH: play a chord through MIDI IN, start/stop the host, toggle HOLD and LATCH, lock a lane, record + replay a reel pass, change a MAIN OUT channel mid-note and mute a lane mid-hold, and listen for a stuck or missing note.
- **Fourfold identity change (2026-10-24):** the app and extension now carry `com.outliermidi.Fourfold[.AU]` and the AU manufacturer `OutM`. A build installed under the OLD ids (`com.paulbarrett.Fourfold`) is a different app — delete it from the iPad, and re-add the plugin in AUM (it appears as "Outlier MIDI: Fourfold"). Confirm Xcode can sign the new ids with the team in project.yml.
- **App icon (Canon, 2026-10-24):** the Fourfold icon shows on the iPad home screen, and the four lanes read as four separate rows at 60 pt.
- **App icon (Canon):** at Settings / Spotlight sizes (29–40 pt) the icon still reads as staggered bars, not a smudge.
- **App icon (Canon):** AUM's AUv3 picker shows the Fourfold icon for the "Outlier MIDI: Fourfold" extension (the extension has no icon of its own, so it should inherit the app's).
- **App icon (Canon):** 8x8 State's icon is unchanged on the home screen (it has its own catalog, `App/Assets.xcassets`, untouched).
