FERRY: Ribbon settings: a settings tab in the riff panel (TOUCH SCRUB · TUTTI · LOOP, RELEASE, LATCH, PARTS per lane), TUTTI marks set on the ribbons, and LOOP on the rails

Ratified by Paul, 2026-11-16, from the "Fourfold riff panel · settings" design canvas (boards A, B and C, drawn over his screenshot of the 16 Nov build), plus chat: LOOP is a one-finger TOUCH mode on the rails only; marks are set on the ribbons, not in the settings; no marks means TUTTI is off; TUTTI shares the PARTS toggles. Build it. The canvas isn't shared with you, so this text is the whole spec. Read it literally, and audit against this raw text, not a plan paraphrase. Sizes are in pt. Where source disagrees about an existing value (a frame, a colour, a field name, how an existing view draws or an engine path works), source wins; report each difference. §12 lists the values that can be tuned on device.

Paul's aims, from chat: the ribbons (the rails under the riff grid and the rank axes) should be able to act on the riff, the stack or both, defaulting to both, with each lane included or excluded separately for riff and stack. TUTTI: steps and ranks marked on the ribbons; whenever a marked step or rank plays, every other included lane takes that rank on the same step. LOOP: one finger on the rails holds a range of steps, and every lane's riff walks only inside it while held. RELEASE chooses whether lanes snap back (SLIP) or carry on from where the hold left them (CONTINUE). LATCH keeps a hold after the finger lifts. A settings button in the empty space at the panel's bottom left opens all this in the grid area. Labels and values only: no explanatory text anywhere in the interface.

Build on: the riff scrub ferry (2026-11-15), the riff rails ferry (2026-10-19), the stack grid, stack live and stack riff arrow ferries, the riff map ferry, the stack ranks grey ferry (2026-11-15), the riff grid stack dots ferry (2026-11-16) and the PLAY AS rows ferry with its amendments. The riff scrub ferry may not be built yet: if it isn't, build it first, as amended here, then this. Where those ferries disagree with this text, this text wins:
- Riff scrub 1.1 (three values: riffColumnHold, riffRankHold, stackRankHold): replaced by §2 here (columnHold, rankHold, loopSpan, each with a latched flag). Both rank axes write the one rankHold.
- Riff scrub 3.6 and 4.5 ("unaffected" parts): replaced by the PARTS gate (§3). The rails and the riff grid's axis now reach the stack, and the STACK grid's axis now reaches the riff, wherever PARTS includes them.
- Riff scrub 3.5 and 4.4 (slip): slip becomes RELEASE SLIP, the default. RELEASE CONTINUE is §7.
- Riff scrub 1.3 (holds clear on lift): unless LATCH is ON (§8).
- Riff scrub "out of scope: latching a hold": now in scope (§8).
- Riff scrub §6 (audition while stopped): applies to SCRUB and LOOP touches; TUTTI touches never audition.
Everything else in those ferries stands, including the scrub's display marks, the slip rules under SLIP, the stack dots following what was played, and every cell edit on both grids.

How to work: Plan Mode first. Map before editing:
- The riff panel as built: its header (the RIFF | STACK switch, its frame and looks), the rank axis boxes, the grid, the rails and their lane numbers, and the free space at the bottom left under the rank 1 box and beside the rails' lane numbers, at both references and the portrait-AUM size. The same for the STACK view: whether it has the same free space.
- The riff scrub's state and engine path as built (or, if not built, the paths its How to work names).
- The riff walk: riffStepAt and its inputs (direction, LEN, STRIDE, SHIFT, EVERY, ADV STEP or HIT), the walk's period, and the melody restart events (RESETS) that zero a lane's ordinal.
- PLAY AS's walk state, how its position advances per hit, and its restart events.
- How the engine computes a host step: whether all four lanes' hits on one step are computed together before any note goes out, or lane by lane at different times. TUTTI (§6) needs every lane's hits on a step known together.
- Where session settings live (the document, presets, host state), how they're versioned, and which settings go through undo today.
- The rank axis component on both grids: whether it's shared, and its touch handling after the scrub.
Names here come from the status log and earlier ferries; search for them, don't trust them. Ask only if something here contradicts the code. Do not guess; report.

Build order, committing at each green step: (1) the findings, before changing anything; (2) the settings model (§1) and its saving; (3) the pure functions (§10) and their tests; (4) PARTS (§3) through the scrub's engine path; (5) the settings button and tab (§4, §5); (6) TUTTI marking and fading (§6.1–6.4); (7) TUTTI firing (§6.5–6.9); (8) LOOP (§9); (9) RELEASE CONTINUE (§7); (10) LATCH (§8); (11) states and VoiceOver (§11).

SUMMARY
- A settings button sits in the free space at the riff panel's bottom left. Tapping it shows the settings tab in place of the grid and rails; tapping it again, or RIFF or STACK in the header, closes it.
- RIBBONS: TOUCH (SCRUB · TUTTI · LOOP), RELEASE (SLIP · CONTINUE), LATCH (OFF · ON).
- PARTS: RIFF and STACK toggles, both on, each with lanes 1–4 included or excluded. Holds, loops and TUTTI act only on included parts of included lanes.
- TOUCH SCRUB: the ribbons scrub, as the riff scrub ferry says.
- TOUCH TUTTI: tapping a rails column marks or unmarks that step; tapping a rank box on either axis marks or unmarks that rank. Unmarked steps or ranks fade while any are marked. No marks means TUTTI is off. Marks act in every TOUCH mode.
- TUTTI firing: on a host step where an included lane plays a marked step or a marked rank, every other included part on that same step plays that rank.
- TOUCH LOOP: one finger on the rails holds a range of steps; every included lane's riff walks only inside it. The rank axes scrub ranks as in SCRUB.
- RELEASE CONTINUE: after a hold or loop ends, lanes carry on from where it left them instead of snapping back.
- LATCH ON: a hold or loop stays after the finger lifts, until a tap on it clears it.
- Settings and marks are saved with the session. Holds, loops and latched holds are not.

§1 SETTINGS MODEL (saved)
1.1 Fields, global, saved with the session and in presets: touchMode (SCRUB, TUTTI or LOOP; default SCRUB); release (SLIP or CONTINUE; default SLIP); latch (OFF or ON; default OFF); riffOn and stackOn (default on); riffLanes[4] and stackLanes[4] (default all on); tuttiSteps[8] and tuttiRanks[8] (default none).
1.2 Old sessions and presets load with the defaults.
1.3 Changes follow whatever undo path session settings take today; report which.
1.4 The engine reads these lock-free and allocation-free, as the scrub's holds are read (scrub 1.1).

§2 LIVE STATE (not saved, not in undo, not host parameters)
2.1 columnHold (1–8 or none), rankHold (1–8 or none), loopSpan (a range from column a to column b, a ≤ b, or none), each with a latched flag. Both rank axes (the riff grid's and the STACK grid's) write the one rankHold.
2.2 Per lane, for RELEASE CONTINUE (§7): riffWalkOffset and stackWalkOffset, integers, default 0.
2.3 Clearing: as scrub 1.3, except that a latched value survives lift (§8). Panic, transport stop and app background clear every hold and loop, latched or not; transport stop also zeroes the walk offsets.

§3 PARTS GATE
3.1 A lane's riff part is included when riffOn and riffLanes[n] are both on; its stack part when stackOn and stackLanes[n] are both on.
3.2 columnHold, rankHold, loopSpan and TUTTI change only included parts. An excluded part plays exactly as it would with no hold, loop or mark.
3.3 Holds on the stack:
 - rankHold r: as scrub 4.1–4.4 (one voice at rank r).
 - columnHold c: the stack hit plays one voice at the written rank of riff column c. If column c is a rest, the stack hit is a rest. Every stage after the rank choice runs as normal.
 - loopSpan: the stack hit plays one voice at the written rank of the column the lane's loop walk reads on that hit (§9.3); a rest column gives a stack rest.
 - rankHold beats columnHold and loopSpan, as scrub 3.4.
3.4 Holds on the riff: columnHold and rankHold as scrub §3; loopSpan as §9.
3.5 Excluding a part or lane while a hold is set takes effect from that part's next hit. Sounding notes end at their own note-offs.

§4 THE SETTINGS BUTTON
4.1 Place: the free space at the riff panel's bottom left, under the rank 1 box and left of the rails' lane numbers, aligned with the rank box column's left edge and the rails' vertical extent. On the 16 Nov screenshot that's about 36 × 41 pt from x 8, y 277.5 in the panel. The rails' lane numbers stay where they are. If the space is smaller than 30 × 30 pt at any layout, stop before building it and report the sizes.
4.2 Look: radius 6. Closed: #2A2D34 fill, a sliders icon in #AAB0BA (three horizontal lines, each with a knob, 17 pt square, 1.2 pt stroke). Open: #DFE3EA fill, the icon in #0D0F14. No text.
4.3 The STACK view shows the same button in the same place if the same free space exists there; if it doesn't, report it and show the button on the riff view only.
4.4 Tap toggles the settings tab. VoiceOver: "Settings", a toggle.

§5 THE SETTINGS TAB
5.1 Where: it replaces the grid and the rails (or the STACK grid) inside the panel; the header stays. While it's open, neither RIFF nor STACK in the header shows as selected; tapping either closes the tab and shows that view.
5.2 Layout, top to bottom, on the grid's own geometry: the label column is the rank axis column; controls span the grid's eight columns. Rows 25 pt tall, 4 pt apart:
 - Header RIBBONS.
 - TOUCH: SCRUB · TUTTI · LOOP, three tiles sharing the eight columns' width equally, 2 pt apart.
 - RELEASE: SLIP (columns 1–4) · CONTINUE (columns 5–8).
 - LATCH: OFF (columns 1–4) · ON (columns 5–8).
 - 9 pt gap, header PARTS.
 - RIFF row: in the label column, a RIFF toggle; then lanes 1–4, each two columns wide.
 - STACK row: the same, with STACK.
 Spare height stays empty below.
5.3 Looks:
 - Headers: 6.5 pt heavy, 0.16 em tracking, #6E7480, with a 0.5 pt #26282E rule under the full width.
 - Row labels (TOUCH, RELEASE, LATCH): 7.5 pt heavy, #AAB0BA, right-aligned in the label column with 6 pt right padding.
 - Option tiles and the RIFF and STACK toggles: radius 4.5; on #DFE3EA with #0D0F14 text; off #2A2D34 with #AAB0BA text; 8.5 pt heavy, 0.06 em tracking.
 - Lane tiles: on, lane100 fill and #0D0F14 number; off, no fill, a 1 pt inner ring in lane100 at 40% and a lane100 number. With the row's part toggle off, the four lane tiles draw at 35% and keep their own on/off states and stay tappable.
5.4 Taps set the values at once. Choosing a TOUCH mode clears any live hold or loop (latched or not).
5.5 VoiceOver: each tile a button with its label and selected state; lane tiles read "Riff lane 2, included" or "excluded".

§6 TUTTI
Marking
6.1 With touchMode TUTTI, touch-down on the rails toggles tuttiSteps at the column under the touch (riff scrub 2.1's hit area and mapping), and touch-down on either rank axis toggles tuttiRanks at the rank under it (scrub 2.2, 2.3). Dragging after touch-down does nothing more. No hold is set and nothing auditions.
6.2 In SCRUB and LOOP modes the ribbons don't touch the marks.
Display
6.3 While any step is marked, the rails' segments of every unmarked column draw at 30% in all four rails; marked columns draw as normal. While any rank is marked, every unmarked rank box on both axes draws at 30%. The rails' lane numbers, the grid cells, the arrows and the dots never fade.
6.4 Nothing else marks TUTTI on screen. The fade shows in every TOUCH mode.
Firing (any TOUCH mode, whenever a mark exists)
6.5 For each host step, after holds and loops are applied (§3, §9), take the included parts' hits that start on that step. A trigger is one of those hits that reads a marked step (a riff hit whose column is in tuttiSteps; the stack's column is the column its lane's riff reads on that hit) or plays a marked rank (riff or stack, the rank after substitution and before octave or transpose stages).
6.6 The fire rank: for a marked-step trigger, the written rank of that column (or the rank hold's rank, if one is set); for a marked-rank trigger, that rank. If several triggers on one step give different ranks, the trigger from the lowest-numbered lane wins, riff before stack within a lane.
6.7 Every other included part's hit on that step plays the fire rank, substituted where a rank hold substitutes (riff: the written rank, scrub 3.3; stack: one voice at that rank, scrub 4.1). Every later stage runs as normal, so each lane plays the fire rank through its own pool, OCT, TRANS and FLIP NOTES. A hit on a rest column still plays the fire rank. The triggering hits play as they would.
6.8 Only hits starting on the trigger's step change. Notes already sounding aren't retriggered or changed. TUTTI-substituted hits are not triggers themselves.
6.9 A set rankHold beats TUTTI: while it's set, TUTTI doesn't change any included part.
6.10 If the engine computes lanes for one step at different times (How to work), stop before building 6.5–6.9 and report how far apart they are.

§7 RELEASE
7.1 SLIP: as the riff scrub ferry (3.5, 4.4). Walk offsets stay 0.
7.2 CONTINUE, riff: when a columnHold or loopSpan ends (lift, a TOUCH mode change, or a latched hold cleared), for each included lane whose riff part played under it, let c be the last column its riff read under it. Set riffWalkOffset d to the smallest d ≥ 0 such that the lane's walk position at ordinal (o + d − 1) is c, where o is the ordinal of the lane's next hit; from then on the lane reads its walk at ordinal + d. If c never occurs in the walk's period, d stays as it was. A rankHold ending changes no riff offset.
7.3 CONTINUE, stack: when a rankHold, columnHold or loopSpan ends, for each included lane whose stack part played under it, let r be the last rank it played. Set stackWalkOffset the same way over PLAY AS's position sequence, so the next stack hit continues from the position after r. If r doesn't occur in PLAY AS's sequence, the offset stays as it was.
7.4 Offsets reset to 0 at the lane's next melody restart (RESETS), on transport stop and when release is set to SLIP. The rails' natural position and trail (rails 6.3) include the offset.
7.5 Report any walk or PLAY AS mode where the offset can't be applied this way.

§8 LATCH
8.1 OFF: holds and loops end when their touch lifts (scrub 1.3).
8.2 ON, SCRUB and LOOP modes: lifting leaves the hold or loop set, latched. A new touch on the same ribbon takes it over and works as a normal touch (drag moves it); on lift it latches again at its new value.
8.3 Clearing a latched value: a tap (touch-down to lift within 250 ms, with the column or rank unchanged) on the latched column, inside the latched loop, or on the latched rank clears it. Turning LATCH OFF, changing TOUCH mode, panic and transport stop also clear it.
8.4 A latched value draws with the scrub's held marks (scrub 5.1 and 5.3), unchanged.
8.5 Audition while stopped (scrub §6) ends at lift even when LATCH is ON.

§9 LOOP
9.1 With touchMode LOOP, one finger on the rails: touch-down at column a sets loopSpan to a–a; dragging to column x sets it to min(a, x)–max(a, x), with a fixed as the anchor until lift. The rank axes work as in SCRUB (rankHold).
9.2 Riff, each included lane: while loopSpan a–b is set, the lane's riff hits read columns from a loop walk instead of the natural walk. The loop walk is riffStepAt with LEN = b − a + 1 and its first position at column a, keeping the lane's own direction, STRIDE, EVERY and ADV STEP or HIT, ignoring SHIFT, at loop ordinal k, where k counts the lane's advances from 0 at its first hit after the loop is set. When the span changes during a drag, k carries on and the new span applies from the next hit.
9.3 Rests inside the loop: the lane's own SKIP, FILL, TIE and REPEAT treatments apply as normal, with SKIP's search limited to the span (a span of only rests gives rests) and REPEAT's lookback running through the loop's own earlier hits (at k = 0 it reads the natural lookback).
9.4 Underneath, the natural walk, ordinals, restarts and RESETS counts advance as without the loop. On release, SLIP or CONTINUE (§7) applies.
9.5 A columnHold can't exist in LOOP mode. A rankHold set on an axis during a loop beats it on rank (§3.3), and the loop keeps walking underneath.
9.6 Display: the held mark (scrub 5.1) drawn as one rounded rect around columns a to b in all four rails. Arrows and dots show what was played (scrub 5.4). The rails keep showing each lane's natural current column and trail.

§10 PURE FUNCTIONS (Derivations.swift, test-covered, allocation-free)
10.1 partIncluded(lane, part, settings).
10.2 loopColumn(lane, k, span) per 9.2, and the rest handling of 9.3.
10.3 tuttiFire(stepHits, marks, settings, rankHold) → the fire rank or none, and the set of hits it changes (6.5–6.9).
10.4 continueOffset(walk, ordinal, lastColumn) and its PLAY AS counterpart (7.2, 7.3).
10.5 The scrub's riffHitSource and stackHitRanks (scrub 7.2, 7.3) take the PARTS gate, loop and TUTTI inputs; with defaults and no marks they give exactly today's results.

§11 STATES AND VOICEOVER
11.1 Settings tab open: the engine runs as normal and live holds and latched values stay; the ribbons are hidden, so nothing new can be held.
11.2 HOLD NOTES TO PLAY (empty pool): settings and marks still work; nothing sounds.
11.3 A lane drawn at 42% (LANES mute, solo): unchanged. A muted lane is never a TUTTI trigger.
11.4 VoiceOver: the rails and rank boxes keep their elements and labels. A marked step or rank adds ", tutti". The ribbons' touch actions stay unavailable to VoiceOver, as in the scrub ferry; keep its pending-tasks line.

§12 TUNABLE ON DEVICE (named constants; change none in this ferry)
- Fade for unmarked steps and ranks (30%).
- Part-off dim for lane tiles (35%).
- Latched-tap clear window (250 ms).
- Settings row height (25), gap (4), header gap (9).

§13 TESTS (macOS target)
1. Defaults: a new session has SCRUB, SLIP, LATCH OFF, both parts on, all lanes included, no marks; an old session loads the same; golden renders of every factory preset over 32 bars, with no touch, sound identical before and after.
2. PARTS: with stackLanes[2] off, a rank hold changes lane 2's riff and not its stack; with riffOn off, nothing changes any riff; a column hold on column 5 (rank 8) makes an included stack play one voice at rank 8; on a rest column, a stack rest.
3. TUTTI marking: in TUTTI mode, touch-down on rails column 5 sets tuttiSteps[5]; a second touch-down clears it; a drag across columns 5 to 7 changes only column 5; in SCRUB mode the same touch sets a hold and changes no mark.
4. TUTTI firing: step 5 marked (rank 8); lane 3's riff reads column 5 on step s while lanes 1, 2 and 4 hit on s: they play their own rank 8; lanes hitting on s + 1 play as normal; a lane excluded in PARTS plays as normal; a substituted hit doesn't trigger again; with a rank hold set, nothing changes.
5. TUTTI rank: rank 3 marked; lane 2's stack plays rank 3 on step s: every other included part hitting on s plays rank 3; two triggers on one step with ranks 3 and 6 from lanes 4 and 2 give rank 6 (lane 2 wins).
6. LOOP: FWD lane, LEN 8, loop 3–5 set: the next hits read 3, 4, 5, 3, 4; PING reads 3, 4, 5, 4, 3, 4; REV reads 5, 4, 3, 5; dragging the span to 3–6 mid-loop continues k; release under SLIP returns to the natural column.
7. LOOP rests: column 4 a rest with SKIP inside loop 3–5: the hit reads 5; loop 2–2 on a rest column gives rests.
8. CONTINUE: FWD lane, LEN 8, column 6 held over 3 hits then released: the next hit reads column 7; a loop 3–5 released after reading 4 continues at 5; a lane whose walk never visits the released column keeps its offset; the offset clears at the lane's next melody restart.
9. CONTINUE stack: PLAY AS UP over ranks 1, 3, 5, 7, rank 5 held then released: the next stack hit plays 7.
10. LATCH: ON, a SCRUB touch on column 4 lifted keeps columnHold 4; a 200 ms tap on column 4 clears it; a tap on column 6 moves it to 6; switching TOUCH mode clears it; transport stop clears it.
11. Settings tab: the button opens and closes it; RIFF or STACK in the header closes it; choosing a TOUCH mode clears a live hold.
12. Fade: with step 5 marked, rails columns other than 5 draw at 30% and rank boxes don't; with rank 8 marked, rank boxes other than 8 draw at 30% on both axes.
13. Threading: settings and holds are read with no locks and no allocation.

§14 ACCEPTANCE (check each against this text before calling it done)
- The settings button sits in the bottom-left free space and opens the settings tab in the grid area; the header's RIFF and STACK close it.
- TOUCH, RELEASE, LATCH and PARTS show and work as §5 says, with no explanatory text.
- Turning STACK off, or a lane's stack, keeps scrubbing from changing that stack.
- In TUTTI mode, tapping rails columns and rank boxes marks them, and everything unmarked fades; with no marks, nothing fades and TUTTI does nothing.
- A marked step or rank pulls every other included lane onto that rank for exactly the step it plays on.
- In LOOP mode, one finger on the rails loops every included lane inside the held range, each in its own rhythm and direction.
- CONTINUE leaves lanes where the hold left them; SLIP returns them.
- LATCH keeps a hold or loop until it's tapped.
- Settings and marks reload with the session; holds don't.
- Old sessions and presets sound as before.

§15 DEVICE-OWED (one line each in Docs/euclideous-device-verification-debt.md)
- The settings button is easy to hit without catching the rails or the rank 1 box.
- The 30% fade reads clearly against the rails' trail and current segments.
- TUTTI firing at fast tempos reads as unison, not as a glitch.
- LOOP drags feel immediate; the held range mark reads over the rails.
- CONTINUE's re-phasing sounds intended.
- Latched holds are obvious enough that a stuck hold isn't mistaken for a bug.

§16 REPORT BACK (in your reply)
1. The findings, with file:line, including the free-space sizes for the button on both views.
2. Whether you built the riff scrub ferry here, and anything in it you changed to fit this one.
3. How a step's lanes are computed (6.10) and how TUTTI sees them together.
4. Where settings are saved and whether they go through undo.
5. Walk or PLAY AS modes where CONTINUE can't apply (7.5).
6. Anything in this spec that contradicted the code.

Out of scope: an on-grid indicator of the TOUCH mode; other mark types (MUTE, ACCENT and so on); a rank-range gesture on the axes; two-finger gestures; host parameters or MIDI learn for any of this; VoiceOver operation of the ribbons; anything not named here. When done, update the status log and pending tasks and ship as usual.
