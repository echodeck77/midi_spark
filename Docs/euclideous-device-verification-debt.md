# Euclideous — open device-verification debt

A running checklist, not a log. `Docs/euclideous-status-log.md` is full of "DEVICE-OWED" flags
(160+ of them as of 2026-10-14) scattered across hundreds of entries with no way to tell which
are still open versus quietly confirmed by a later entry — that's the actual problem this file
exists to fix. Historical backfill into this list is NOT done (deliberately — most of those 160+
are stale, superseded, or already implicitly confirmed by later work touching the same code, and
mining them accurately would mean re-reading the whole archived log). Starting fresh from here.

> **NINE PORTS (2026-10-27):** the header output rings, the MAIN OUT toggle, the RIFF/NOTES OUT circles/column, ALT routing,
> per-layer routing, default emitters and the per-output channel stepper NO LONGER EXIST. Any older line below that mentions
> them (rings, OUT circles, MAIN OUT, ALT, "fed by lanes…") is void — the status log keeps the history. The routing lines of the
> three ferries that built them were removed from the tail of this file; the open checks for what replaced them are the
> "Nine ports" lines at the end.


## The rule going forward

When a ferry/fix ships with something that can only be confirmed on-device, add ONE line below
under the right subsystem — not a paragraph, not a re-explanation, just enough to know what to
go check next time the iPad is in hand. When Paul confirms something on-device, delete the line
(or move it to "confirmed this session" briefly, then delete on the next pass) — this list should
shrink as often as it grows. If it only ever grows, it's not doing its job.

## Open items

### SMALL WINDOW — the fallback is REMOVED (2026-10-26, Paul: "remove this")
- Shrink the plugin's AUM window below ~760x480 (landscape) or ~480x760 (portrait): you get the live page, no "RESIZE TO CONTINUE" screen — everything is tappable. At small sizes expect a cramped layout (text truncated or overlapping); report the smallest size at which it is still usable and what gets in the way.
- Known limit (seen in the simulator at 320x480, not at 480x320 or 440x700): when a lane card's box is smaller than its controls, the controls overflow it and can catch taps meant for the panel below (the RHYTHM RESTART tile of lane 4 swallowed the LANES tab). Say if you hit this in AUM — the fix would be to scale the whole page to fit (still interactive) rather than cram it.
- The standalone app in Split View / Slide Over / Stage Manager: `sizeRestrictions.minimumSize` (760x480) is still asked for and is only a preference; below it the page stays live.

### ▶ FOURFOLD — THE iPAD PASS (one ordered session; written 2026-10-24 — the per-step Fourfold lines further down stay as the detail)
Nothing in Fourfold has run on a device yet: everything so far is simulator + unit tests. Do these in order (an early failure makes the rest moot); report each as "step N.n: what I saw". Prefer a RELEASE build for judgement calls and a DEBUG run as a second opinion — Debug has crashed on the plugin's 1 MB main stack before (2026-10-21).

**1 · INSTALL**
- 1.1 Run the `Fourfold` scheme from Xcode onto the iPad (installs the app AND the plugin). Xcode must sign `com.outliermidi.Fourfold[.AU]` with the team in project.yml; if it complains about the team or bundle id, stop and report the message.
- 1.2 Home screen: the Canon icon shows and the four lanes read as four rows at 60 pt; at Spotlight / Settings sizes (29–40 pt) it still reads as staggered bars, not a smudge; 8x8 State's own icon is unchanged.
- 1.3 Launch it: the Fourfold page with the transport bar above it; rotate through all four orientations, nothing clipped.
- 1.7 FILES + BLUETOOTH MIDI (release hygiene, 2026-10-24): (a) Files app > On My iPad > Fourfold shows `Presets` (save one in the preset browser first) and `Reel exports` (export a pass range from the reel); (b) the antenna button in the transport bar opens Apple's Bluetooth MIDI screen, a Bluetooth MIDI controller pairs from it, and with the note source on MIDI IN it plays the lanes; (c) with the controller connected, background the app for a minute and play — if the connection drops, add the `bluetooth-central` background mode (not added yet); (d) the first TestFlight upload passes App Store Connect's privacy-manifest check and accepts the build number (run `sh Scripts/bump-build.sh` before each upload).
- 1.6 (OLDEST iPad you have — iPadOS 15 / 16 if possible) Minimum OS is now iOS 15.0 and has never run on it: install the app, then check (a) the standalone app launches and plays, (b) the AU loads in AUM and draws the whole page, (c) the animated parts (lane strips, arrows, pulse) hold frame rate, (d) the lane tab on a narrow lane reads "RHYTHM 5/…" instead of "RHY 5/16" on iOS 15 (known fallback), (e) nothing the audit flagged as iOS-version-dependent (SwiftUI layout / gesture differences) looks off. If it misbehaves, raise `deploymentTarget` for the Fourfold targets in `project.yml` back to 16.
- 1.5 VoiceOver (turn it on in Settings > Accessibility): in the riff grid, swiping through the 64 cells reads "Step 3, E♭3, off" and double-tap sets / clears that note (the grid used to be untouchable without a finger); the settings sheet's three tabs read "MIDI IN" / "MAIN OUT" / "CLOCK" (they all read "Settings" before) and the X reads "Close settings"; the preset browser's rows read "<NAME>, factory preset", with "Save preset" and "Close presets". Judge whether 64 swipes is usable or the grid needs a rotor / a shorter route — that is a design question the simulator cannot answer.
- 1.4 (iPad MINI only, or any view narrower than the base iPad) After the mini-legibility fix: TILT reads just "TILT … 0%" with the EARLY / LATE captions gone and nothing garbled; the MIX octave stepper shows "− 0 +" / "− +1 +" (portrait: no OCT caption; landscape: a small "OCT") and the number never turns into "…"; a lane tab with a long count reads "RHY 5/16". Simulator pictures looked right; the real glyph widths are the open question.

**2 · THE STANDALONE APP**
- 2.1 Launched stopped it plays NOTHING. PLAY starts from the top; STOP silences it with nothing stuck; BPM − / + / the slider change tempo with no jump.
- 2.2 In AUM (or a synth app) the sources **Fourfold All** and **Fourfold Out A–D** exist; route one to a synth: Out A carries the same notes as All; record a few bars somewhere and the notes sit exactly on the grid (the thing the simulator could not show).
- 2.3 Switch to another app while it plays: it keeps playing in the background.
- 2.4 MIDI IN: with the note source on MIDI IN, a keyboard (USB, Bluetooth or another app) plays into it; HOLD sustains after release, LATCH toggles notes in and out; no doubled notes (it must never hear its own output).
- 2.5 Change something audible (a lane, the key), force-quit, relaunch: the change is still there.
- 2.6 ABLETON LINK — **ON HOLD, Link is switched off until after release (2026-10-24); skip this line and the ABLETON LINK section below until `sh Scripts/link-switch.sh on`.** (2026-10-24 ferry) — see the dedicated section below for the full list; this needs Apple's multicast entitlement approved first (Paul's own step, not landable from a build).

**3 · THE PLUGIN IN AUM** (the first time the extension is ever loaded by a real host)
- 3.1 AUM lists **"Outlier MIDI: Fourfold"** as a MIDI processor, separate from "8x8 State"; adding it opens the REAL page (not a placeholder) at AUM's plugin window size; the AUM picker shows the Fourfold icon.
- 3.2 Play (MIDI-in, or the key / chords source): notes on Out A–D, All carries everything. Load a few of the 20 factory presets: each is heard at once.
- 3.3 AUM's transport start / stop: stop closes every note; the settings sheet's CLOCK tab KEEP PLAYING keeps going with the host stopped, STOP waits for the host.
- 3.4 Settings (gear): there is NO workbench link. Change a MAIN OUT channel while a note is held: no stranded note.
- 3.5 Lane lock (padlock, hold the big padlock 0.3 s to capture): edit a locked lane, it snaps back on its grid line. Dice: throw / tweak a roll and let it land.
- 3.6 Reel (tape icon between SWING and the gear): opens ABOVE the page; play a few passes, open one, CLOSE returns to live sound with nothing stuck; SAVE offers a share sheet and the files are named `Fourfold-*.mid`.
- 3.7 Mute or solo a lane while one of its notes is held: it ends cleanly.

**4 · 8x8 STATE STILL WORKS** (the Fourfold work edited its files and it has not been on the iPad since)
- 4.1 Still listed in AUM, separate from Fourfold, opens as before; play a preset, it sounds normal.
- 4.2 Open the Euclideous page from its header icon: the settings sheet still has the WORKBENCH link and it returns to the workbench.
- 4.3 Open the preset browser and the cell library; save and load one preset (those files were moved in Step 1).

If something fails: which step, what you saw, and for a crash the line Xcode prints. Don't try to fix it on the device.

### ABLETON LINK (2026-10-24 ferry — standalone Fourfold app only) — ON HOLD: switched OFF until after release; nothing here applies to the current build
- BLOCKED on Paul's own step first: real-device peer discovery needs Apple's `com.apple.developer.networking.multicast` entitlement, a RESTRICTED entitlement Apple must approve per App ID (developer.apple.com) — not something landable from a build. Builds and Simulator runs work without it; nothing below is checkable until it's granted.
- Discover a real peer (AUM's own Link toggle, Ableton Live, or another Link app on the same Wi-Fi) with LINK on in Fourfold: the peer count updates, and Fourfold adopts the peer's tempo within a beat or two.
- Change Fourfold's own BPM (stepper or slider) while connected: the peer's tempo follows.
- PLAY/STOP: starting the OTHER app's transport starts Fourfold (if the user has turned on "Start Stop Sync" in Fourfold's own Link settings screen — reachable by long-pressing the LINK button — since LinkKit has no programmatic setter for that, only its own settings view can turn it on); the reverse direction too.
- Backgrounding: with LINK on and connected, background the app (or lock the screen) — confirm the peer connection survives, the same way audio already does (UIBackgroundModes).
- A route change (headphones in/out, AirPlay) while connected: confirm Link doesn't drop the peer or glitch the tempo.
- The LINK button's three states (dim outline off / lit outline on-no-peer / filled with a peer count) read clearly at a glance against the rest of the transport bar.
- Toggling LINK off mid-session: Fourfold's own tempo/transport stop changing with the (former) peer immediately, with nothing stuck.

### GESTURE PREDICTABILITY (2026-10-24)
- LAUNCH the DEBUG build from Xcode into AUM first (`EuclideousSlider`'s tilt branch gained a new ephemeral `@State`; the EDITED chip overlay was removed — a changed leaf on the 1 MB main stack).
- TILT's live-drag feel: the thumb now starts at 0/centre every touch and RETURNS to 0 on release (no persistent −1…+1 readout any more) — the single part of this ferry Paul hasn't seen a concrete mock of. Confirm it reads as "a gesture that nudges the pattern" rather than "a broken/reset slider."
- TILT visibly reshaping an already HITS-edited (gap-filled) pattern, instead of being disabled/showing an EDITED chip — drag TILT on a lane whose HITS has been dragged away from its pure count and confirm the hits visibly bias toward one end.
- OFFSET's restored 1:1 whole-step drag feel (band-snapped again, no fractional creep) — confirm a drag tracks the finger exactly one step at a time, matching the pre-RHYTHM-POLISH feel Paul is asking to get back.
- HITS: dragging the count up and down should visibly keep existing hits in place (only the minimal add/remove), even on a lane that's never been hand-edited — confirm it doesn't "feel" like it still jumps.
- LANE LOCK: since HITS and TILT now share one representation (`customHits`), a lane locked then edited on EITHER control shows the dashed "differs from L" frame on BOTH the HITS and TILT tiles (the stored array alone can't say which gesture moved it) — confirm this doesn't read as a bug on-device; it's a disclosed, deliberate trade-off, not an oversight.
- Double-tap on HITS or TILT now reverts to pure Euclid (replacing the old TILT-only "EDITED chip" tap zone) — confirm the gesture is discoverable and feels like "reset," not accidental.
- Scope note: this ferry's fix lives ONLY in `AUExtension/` (MidiSpark/8x8 State's engine copy, which Euclideous's reserved row rides) — Fourfold's forked engine copy (`Fourfold/Engine`) was NOT touched and does not get this fix; port it there too if Fourfold should feel the same way.

### CHORDS GRID (2026-10-24 ferry — four tabs, borrowed/colour rows, playhead, pool strip)
- 18 rows at 16 columns: still comfortable to tap at the real card size (`EuclideousChordsPopupMetrics.labelW`/
  row heights are REASONED estimates, not measured — confirm the label column (36pt) actually fits "♭VII"/"ADD9"/
  "SUS4" without truncating, and that the title/steps-rate row heights (22/26) match what actually renders).
- The 6% column wash and the 3pt playhead bar: legible against both lit and unlit cells, moving cleanly in time
  with the engine (no visible lag against the audible chord change).
- The 22×12 chord-tab icon and the step count on a 20pt tab: legible at that size, and the icon's marks actually
  line up with which rows are lit on the real grid below it.
- Tapping a tab switches the chord progression AT ONCE, with no stuck or doubled notes at the switch instant —
  this is a deliberate simplification (Paul, 2026-10-24: manual-only switching, no queue-to-next-boundary), so
  an audible retrigger glitch right at the tap is accepted behaviour, not a bug; confirm it's not WORSE than that
  (e.g. no hang, no silence).
- The colour chords (7/9/6/ADD9/SUS2/SUS4) heard as named, through VOICING/SPREAD, on both diatonic and borrowed
  rows, in both a minor and a major KEY.
- The pool strip's "colour tone" dashed border (inferred as "any rank ≥ 4" — see the status log's judgment-call
  #4) actually lines up with the tones a colour added, not the plain triad.
- §7.3's column-hold preview (press a grid cell, the pool strip follows that column instead of the playing one):
  confirm the gesture doesn't fight the cell's own tap-to-set, and releases cleanly back to the playing column.

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

### RANDOM MODE animation/timing review (2026-10-24)
- STRIKE FEEDBACK (new): with a lane playing in random mode, each picture flashes on a hit — the RHYTHM picture's playhead ring gets a lane-colour halo + a thicker ring, the RIFF picture's walk path brightens/thickens, the NOTES picture's lit keys glow — all velocity-scaled and fading on the SAME PULSE curve as the rest of the page. Confirm it reads as "a hit sounded," is in time with what's heard (at 64 and 1024 buffers), and isn't distractingly busy on a dense pattern; also confirm the glows fade out over ~1.5 s after STOP rather than freezing or vanishing instantly.
- THE WAITING BORDER MARCHES (changed): after THROW or TWEAK (while it's queued to land), that button's dashed border now scrolls ("marching ants") at the same rate as the dice's own ring, instead of sitting static — confirm the two read as the same "pending" signal and the motion isn't jittery at the button's small size.
- THE HOLD NOW HAS A 0.3 s THRESHOLD (changed): hearing the original by holding the picture now requires holding ~0.3 s (matching the output rings / SOLO / lock-capture), not a bare touch-down — confirm it feels deliberate (a quick tap on the picture does nothing), the switch to the original is crisp once it fires, and releasing returns to the new one cleanly with nothing stuck.

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
- **Session tape (reel phase 1a+1b, 2026-10-25):** nothing visible changed, so there is nothing to look at — but on the iPad in AUM, play a busy preset for 5+ minutes and confirm no hiccup or crackle every half second (the tape's main-thread drain runs on a 0.5 s timer; the render thread only appends). If the Diagnostics panel is open, `panics` should not climb faster than before this build (the stuck-note net's note-offs now also pass through the reel tap, same bytes).
- **Reel replay keeps the engine running (reel phase 1c, 2026-10-25):** in AUM or the standalone app, play a busy preset, open the reel, tap a pass (you hear that pass loop; the live material is silent), tap it again or CLOSE: live material comes back WITHOUT restarting from bar one and with no hung note. Do it with the transport stopped mid-replay too (a stop must end the replayed notes). Also: the reel now lists every pass played whole since the app started, not just the newest 64 — leave a loop running 10+ minutes (at 1/8 steps a pass is 4 beats), open the reel, and check pass 1 is still there and the PAGE counter says 2+ pages.
- **Reel session on disk (reel phase 1d, 2026-10-25):** standalone app on the iPad: play a few minutes, force-quit, relaunch, open the reel — the passes from before are there and playing again adds after them. In AUM there is no persistence yet (REEL-13): after reopening an AUM project the reel starts empty — that is expected for now, not a regression. In AUM, leave a dense preset running for an hour and watch the extension's memory (Xcode memory gauge / Instruments): it should plateau near 10 MiB for the tape rather than climb.
- **Undo fixes (2026-10-25):** (a) tap a lane's STEPS + three times, then ↶ three times: one step each time. (b) change HITS on lane 1, then OFFSET on lane 1, then HITS on lane 3: three ↶ undo them one at a time. (c) in AUM: edit something, then change the preset from AUM's own preset menu (or reload the project): ↶ must do nothing (it used to put the previous project's lanes back). (d) load a preset that stops some lanes, ↶: those lanes play again; ↷: they stop again. (e) random mode: THROW, then ↶ before it lands: nothing lands afterwards. (f) ↶, then any control you don't actually change: ↷ still works.
- **Stack overflow #3 (2026-10-25):** launch the DEBUG build from Xcode, put all four lanes on NOTES, drag a MIX pad for ~20 s (that was the crash), rotate, then open the settings sheet, the chords pop-up and the preset browser. No crash; if one comes back, send the `.ips` and run `FourfoldStackBudgetTests`.
- **SOURCES STACK — the three lights (§11):** the playing / waiting / off looks read at a glance in AUM, both orientations (playing = filled, waiting = outline, off = dim). Playing a note lights MIDI IN; letting go returns it to its outline (never off).
- **SOURCES STACK — RELEASE GRACE (§11):** at 50 ms, real legato chord changes don't let a NO-MIDI layer blip in between chords; it doesn't feel laggy (too long) or blip (too short).
- **SOURCES STACK — the pop-up (§11):** tapping the header opens SOURCES under it (the control gains its outline, the page keeps playing); tap again or outside to close. It fits and positions right in each layout, including a 343-wide (375 pt) panel where it spans the container and nothing clips.
- **SOURCES STACK — ALLOW vs DROP (§11, dev build only):** in a DEBUG build the MIDI IN tab shows CLASHES; DROP thins the key notes that sit a semitone from chord tones, judged by ear over a running progression; the sheet does not scroll with the block present. A release build has no CLASHES block.
- **SOURCES STACK — chips & ghosts (§11):** the MIDI note chips and their ghosts (last-held, until the next note-on) read at a glance while playing; "+n" shows when they don't fit. (Judgment call: ghosts are only captured while the pop-up is open; the chord-name NOW is derived per-render, not in a TimelineView — confirm both feel live enough.)
- **SOURCES STACK — old sessions with a controller (§11, the §1.3 change):** an old CHORDS or KEY session with a controller plugged in now stacks held notes onto the progression/scale (it used to ignore them); hold a chord → your notes lead the pool strip and the progression fills beneath; let go → the progression carries on alone, no blip between legato chords. And with MIDI always listening, HOLD/LATCH apply continuously (not only under a MIDI source) — confirm that feels right.
- **Nine ports — AUM (2026-10-27):** add Fourfold to AUM: the MIDI output list shows exactly `All`, `Emit Riff A`, `Emit Notes A`, `Emit Riff B`, `Emit Notes B`, `Emit Riff C`, `Emit Notes C`, `Emit Riff D`, `Emit Notes D` (note AUM may sort them alphabetically, putting the Notes ports before the Riff ports — if so, say whether the names or the order should change). Wire Riff A and Notes A to two different synths: lane 1's riff plays on one and its lit notes on the other; lane 2 is on Riff B / Notes B; `All` carries everything.
- **Nine ports — channels (2026-10-27):** Settings > PORTS has eight steppers (RIFF/NOTES for each lane A–D), 32 pt, comfortable to hit; a fresh instance reads 1…8; changing one while that port's note is held strands nothing. On a session saved before this, the four lane numbers appear on both of each lane's rows. Feed `All` into a multi-timbral synth: riff and notes of one lane are told apart by their channels.
- **Nine ports — the page (2026-10-27):** with the OUT columns gone, the RIFF and NOTES tabs have their old widths back (NOTES keys, WALK slots); the header has three groups only — BRAND on the left, UTILITIES on the right, an empty middle in two-row layouts B/C — and a one-row layout A now fits from 929.88 pt of container width (an iPad mini 6 in landscape gets one row); nothing looks stranded where the rings used to be. Both hand-checks are visual and unseen.
- **Nine ports — independent streams (2026-10-27):** a lit note on the same pitch as the riff's now sounds on BOTH ports (Riff A and Notes A) — turn the lit notes on and play with TIE on rests: the notes layer strikes under the held riff note, including its pitch. Confirm that reads as intended on a real patch (and that the doubled pitch on `All` — two channels — sounds right).
- **Nine ports — the reel (2026-10-27):** each of the four roll rows shows the lane's riff in its colour and its notes lighter; the two small port tags per row (and a tap on the row for both) are easy to hit; SAVE writes `Fourfold-Riff A.mid` … `Fourfold-Notes D.mid` (or one `Fourfold-All.mid`), only for ticked ports with notes, and says which port is empty.
- **FX CC on both ports (2026-10-27):** set an FX CC row cell on lane 1 and play with riff + lit notes: the controller arrives on the lane's Riff port AND its Notes port (each on its own channel, once per hit, ahead of the note-on) — a synth patched to either one hears the sweep. On `All` it appears once per channel; if Riff A and Notes A share a channel, `All` carries a single copy.
- **Nine ports — an AUM project saved BEFORE the change (adversarial review 2026-10-27):** open an old AUM session that had Fourfold with its five outputs patched: the plugin now has nine outputs and the order changed (index 2 was "Out B", is now "Emit Notes A"), so old routings land on different streams. Re-patch once; check nothing is left patched to a silent port.
- **Nine ports — controllers (review 2026-10-27):** turn a mod wheel / send CC from a controller into Fourfold: it arrives on every one of the eight ports, re-stamped with each port's own channel (the Kernel forward has no automated test). In the standalone app, the nine "Fourfold …" sources appear in another app's MIDI list.
- **Nine ports — narrow settings sheet and short reel (review 2026-10-27):** in a small windowed host (card under ~310 pt) each PORTS lane row shows RIFF over NOTES (indented) instead of clipping; on a small reel popup the two port tags sit side by side in each one-cell lane row instead of overlapping. Neither was seen.
- **Nine ports — header layout A (review 2026-10-27, seen in a simulator screenshot):** with the rings gone there is a wide empty band between BRAND and NOTES (NOTES still pins to the riff panel's leading edge; the band grows on wider iPads). Decide whether that reads fine or the header should rebalance.
- **Nine ports — an old reel (review 2026-10-27):** after updating the standalone app, the first launch starts a fresh reel (the old `session.tape` is discarded on purpose: its cables meant outputs A–D).
- **HOCKET — the button (2026-10-27):** the pill sits first in the header's utilities group, before PRESETS, and fits in every layout; it reads as off (dark, "HOCKET"), on ("HOCKET · n", lit) and open (the on look plus the open ring). Its width (92 pt) is an ESTIMATE from the page's monospaced advance, not a measurement: the utilities group grew by 100 pt, so layout A now needs 1029.88 pt of container width (was 929.88), B 587.88 (was 487.88) and compact C 433 (was 333) — **a 1024-wide landscape window (container 992) now takes the two-row header B where it used to take one row.** Check an iPad mini, an iPad 11" and a 12.9" in both orientations for a stranded or clipped pill.
- **HOCKET — the glyphs (2026-10-27):** on the 9 pt RIFF / NOTES / LISTEN tab glyphs (lane tabs AND the MIX pad labels) a RESTING part reads as waiting, not off (outline at full strength; an off part keeps the clarity pass's 40 % look); the 7 pt away disc (in the destination lane's colour, centred 3 pt right / 1 pt below the glyph's corner — my reading of the spec's placement) and the carrying ring read in all four lane colours, alone and together (a crossing). Seen only in simulator screenshots on an iPad Pro 11.
- **HOCKET — the strip (2026-10-27):** an AWAY layer's strike flashes in the DESTINATION lane's colour (chip / key + glow only) and reads as "this went there"; a RESTING layer's chips / keys are hollow 1.5 pt outlines, never flash, and read as rests — at slow and at fast tempos, in all four lane colours; a lane that is muted or solo-silenced keeps its 42 % dim on top.
- **HOCKET — a passed line's level (2026-10-27):** a PASSED line plays at the RECEIVING pad's MIX VEL (re-based: the destination pad replaces the source pad in the velocity formula; an FX-VEL accent travels as its absolute value) with the SENDER's gate and per-hit shape. Listen to RED NOTES' line on BLUE NOTES' synth at a very different MIX VEL and judge it against that synth's own part.
- **HOCKET — the chips, tags and badges (2026-10-27):** the 44 pt output chips, the R-tags on chips another rule holds and the order badges on a group of two or more read at a glance in all four lane colours; a chip taken by another rule reads as UNAVAILABLE (dimmed with its tag), not off.
- **HOCKET — the live displays (2026-10-27):** the pop-up's chips and bars and the cycle strip's ring, and the strip's / glyph's turn changes on the lane cards, make the turns obvious at slow (60 BPM) and fast (180 BPM) tempos; they follow the engine's own count (sampled at the START of the last render window, polled at 30 Hz, → `hocketTurn`), so a chip or glyph can trail the sound by a window (≈ 11–93 ms at 512–4096 frames) plus the poll — judge it at your usual buffer size. Stopped transport ⇒ nothing lit, every on part playing.
- **HOCKET — how it sounds (2026-10-27):** SWAP with HITS 1/1 across two synths sounds like a hocket (alternate hits); a BARS crossing sounds like two parts trading instruments; REPLACE and MERGE sound as their notes in the pop-up say; a fan-in (two lines to one output) and two lines on the same pitch (one note-on, held to the longer end) sound right on a real patch. Rule edits during held notes strand nothing (mid-note safety is tested, not heard).
- **HOCKET — the pop-up on a short window (2026-10-27):** the header (title, close) and the rule row stay fixed and the body scrolls under them when the window is short; the card is right-aligned like the settings sheet (width min(420, container)), NOT centred under the HOCKET button; at a 300 pt host the rule row wraps (four rules) and the chips / stepper values truncate — see `HocketLooksTests.testAtTheNarrowestContainer…` for what truncates. Also: VoiceOver on the button, the pop-up (modal, Close, tabs with the Delete-rule action, chips with their position / taken wording, adjustable steppers, the cycle strip as one element) and the lane tabs / MIX pads' appended state ("Notes, on, away on the blue lane") has been audited in the simulator only.
- **HOCKET — large buffers and repeated notes (adversarial review 2026-10-27):** with a rule lit, a note that ends inside a render window has its note-off sent at the END of that window (each message keeps its own sample time). Check in AUM at a 1024- and 2048-frame buffer that a lit output playing the SAME pitch on consecutive hits (a one-note riff, 1/16 at 99 % gate) still retriggers cleanly and never cuts a note short; if a host executes events in emission order instead of by time, this is where it would show.
- **HOCKET — the pop-up with VoiceOver on (review 2026-10-27):** swipe through the pop-up and confirm the reading order is header → rule row → mode → MAIN → SWAP EVERY → ALT → routes → footer (the accessibility tree is in that order; the real swipe order was not verified), that "Rule 1" tab and the RULE ON toggle are distinguishable, and that header taps (Undo, presets, gear) act while the pop-up stays open with VoiceOver's touch exploration.
- **HOCKET — the 44 pt hit areas (review 2026-10-27):** the rule tabs, add, RULE ON and the mode / unit / ALT / REPLACE-MERGE segments now take taps up to 44 pt tall (the drawn size is unchanged); confirm on the iPad that a finger on the gap between two segments rows picks the nearer one and nothing fires twice.
- **HOCKET — the device report fixes (2026-10-27):** on the iPad / in AUM with a fresh document (every NOTES layer off), PASS THE LINE with RED RIFF in MAIN and BLUE RIFF + BLUE NOTES in ALT must now come out of BOTH `Emit Riff B` and `Emit Notes B` on ALT turns (and `Emit Riff A` goes silent then), and RED RIFF → BLUE NOTES alone must sound on `Emit Notes B`. With ROTATE the line must visit one ALT output a turn. A fan-out to three or more outputs uses more of the 9-notes-a-hit limit — a hit with a big NOTES chord fanned to several outputs may lose its last copies; say if you ever hear that.

- **CARD BACKS — the switch (2026-10-28):** the PATTERN | MIX switch sits after the lock tile in the one-row header (and at the leading edge of row 2 in the two-row layouts), is 116 pt wide with 44 pt touch targets, and reads as a segmented control in both orientations; the 1180 / 1176 / 1133 / 1113 pt windows now get the two-row header (Paul's width decision) — check that is acceptable on the iPad and in AUM.
- **CARD BACKS — the flip (2026-10-28):** tapping the switch turns all four cards over (280 ms each, lane n starting n × 70 ms late, scale 1 → 0 → 1, swapping at the midpoint); it feels like one gesture, not a stutter; touches during a turn do nothing; with Reduce Motion on it is a 150 ms crossfade of all four at once; open lock or random mode while on MIX and the cards show PATTERN with the switch dimmed.
- **CARD BACKS — the back's layout (2026-10-28):** on every iPad size and in all four orientations the strip, both rows, the VEL/GATE pad, PITCH pad (CARD BACKS v2 replaced the OCT stepper), roll and jack strip are all there with nothing clipped (the floors: pads ≥ 44 wide and 60 tall, roll ≥ 40 tall, jack target ≥ 44 wide — any card under a floor is drawn at the formula and listed); the MIX strip's top is 60 pt (the source), not the ferry's 62.
- **CARD BACKS — the XY pad and OCT (2026-10-28):** the pad edits exactly what the retired MIX pad did (X = GATE, Y = VEL, double-tap resets to GATE 90 / VEL 100, one undo step per touch burst), the crosshair and fill read at a glance, and an OFF part's pad is inert and dimmed (judgment call: 42 %); OCT's − / + zones are easy to hit and the value reads in the lane colour when non-zero.
- **CARD BACKS — the roll (2026-10-28):** a part's notes scroll left over two bars of the page clock with the newest at the right edge, the pitch span grows at once for a new note and eases back over 300 ms, sounding notes glow by velocity, ended notes are dimmer, a silent note (a part routed nowhere) is a hollow outline, the playhead is lane-coloured while the part is audible; with the transport stopped it holds still; check it against what you hear and at 60 / 180 BPM and with a ratcheting lane.
- **CARD BACKS — the jacks (2026-10-28):** tapping a jack plugs / unplugs that output for that part (one undo step each); the plugged look, the light and the cell warm toward the lane colour on each note through that output and fall back over 220 ms; the seam between roll and jacks glows with the part; unplug all four and the part's roll still draws its notes hollow while nothing sounds on any output; AUM / the other app shows the note on exactly the outputs that are plugged.
- **CARD BACKS — the label pill and the invitations (2026-10-28):** the RIFF / NOTES pill is the part's on/off switch (its HOCKET glyph state included); an off part dims its roll (v2: there is no turn-on button — the label is the switch); a lane with no hits offers ADD HITS, which flips the cards to PATTERN and opens that lane's RHYTHM tab; the notes part's switch is the NOTES tab's (on = switch AND a lit note).
- **CARD BACKS — AUM (2026-10-28):** the plugin lists exactly `All`, `A`, `B`, `C`, `D` (second port change in two days — an AUM session saved with the nine-port wiring must be re-patched); with every part on its lane's own output two synths on A and B play exactly what they did before the nine ports; route the riff to A and C and the notes to B and check the three synths; the ALL output carries every note on the channel its output stamps.
- **CARD BACKS — channels and the PORTS tab (2026-10-28):** Settings > PORTS has four steppers (A–D), a fresh instance reads 1…4; changing one while a note is held on that output strands nothing; a document saved with the nine ports reads its riff-port channels for A–D.
- **CARD BACKS — the reel (2026-10-28):** the reel shows four lanes again (one tag per output, a tap on the row toggles it), SAVE writes `Fourfold-A.mid` … per selected output; the first launch after the update starts a fresh reel (the old `session.tape` is discarded on purpose).
- **CARD BACKS — VoiceOver (2026-10-28):** with VoiceOver on, the switch reads as two buttons in a "Card side" group with the selected one announced; each back is a "Lane n mix" group (play, SOLO, the riff row, the notes row); the label reads "Riff, on", the XY pad "Riff velocity 24, gate 38%" (adjustable: velocity ±4, plus Longer / Shorter gate and Reset), OCT "Riff octave, plus 1", the roll "Riff playing" / "Riff silent", each jack "Riff to output A, plugged in" / "empty"; the order inside a card is what a player would expect (the code puts the rows in layout order; this has NOT been listened to).
- **CARD BACKS — hocket (2026-10-28):** with a rule lit the part labels' glyphs show the same playing / resting / away states as the lane tabs, and a passed line shows on the RECEIVING part's roll and lights the receiving part's jacks.
- **CARD BACKS — small text and the narrow roll (2026-10-28):** Apple's accessibility audit lists "contrast" findings on the back's 8–10 pt texts (VEL 100, 90 %, OCT, the RIFF / NOTES labels) — they sit on the allow-list's accepted contrast class like the old MIX pad's did, but read them on the iPad in daylight; on the iPad mini in portrait the TURN ON NOTES invitation sits right against the NOTES label pill (touching, not overlapping — screenshot `8-back-1-portrait` on the mini) — say if you want it moved to the right edge of the roll.
- **CARD BACKS — the third header row (review 2026-10-28):** in a window under ~580 pt wide (Split View half, a small AUM window, the iPad in portrait Split View) the header takes THREE rows — brand and utilities, then the PATTERN | MIX switch alone, then NOTES with HOLD / LATCH — and the boxes start 48 pt lower (159 instead of 111); check HOLD / LATCH are reachable and the cards are still usable there.
- **CARD BACKS — TURN ON NOTES (review 2026-10-28):** on a lane with no lit note, TURN ON NOTES (and the NOTES label) lights the lowest note and turns the part on in one step; check that is what you want (the NOTES tab's own switch still does nothing without a lit note).

- **CARD BACKS v2 — the PITCH pad (2026-10-28):** drag a part's PITCH pad up one row and right two columns: it should read OCT +1 / TRANS +2 and the next notes should arrive an octave and two scale steps higher in the roll AND in AUM (the other part unmoved); double-tap puts both back to 0. Check the pad is playable live: the detents land where the finger expects, and a mostly-vertical drag for the octave does not slip a transpose step too often (if it does, that is the axis-lock follow-up the ferry puts out of scope). The two names are separate settings: this pad's TRANS is NOT the RIFF tab's TRANS.
- **CARD BACKS v2 — transpose follows the KEY pill (2026-10-28):** out-transpose steps are steps of the key pill's scale in every source mode (MIDI IN, CHORDS, KEY); change the key and check the shifted part stays in it. A note outside the scale moves as the scale note below it does and keeps its offset; at the ends of the keyboard a shifted note is PINNED to 0 / 127 (LISTEN folds by octave instead).
- **CARD BACKS v2 — the redrawn back (2026-10-28):** the 72 + 72 pt pads, the 32 pt jack strip with the lettered plugs (each note makes its plug flash and the seam glow; unplugged sockets are identifiable by position), the 50 × 44 jack targets reaching 12 pt over the roll (easy to hit, never catching a touch meant for the roll's label), the back's own fill + lane-coloured border on the card (reads as a different side at a glance). The roll is 56 pt NARROWER than before at the same card width: look at the 1133 pt mini, 1113 pt and portrait 744 pt layouts.
- **CARD BACKS v2 — pads live while a part is off (2026-10-28):** with a part switched off its pads draw at 42 % and still take touches (velocity, gate, octave, transpose are set before the part is switched on); a touch never turns the part on. The NOTES label with no note lit still lights the lowest note (the earlier review fix).
- **CARD BACKS — VoiceOver order within a row (review 2026-10-28):** the row's reading order is now set with `accessibilitySortPriority` (label, VEL/GATE pad, PITCH pad, roll, jacks, ADD HITS); the simulator cannot show it (its element tree follows view order), so LISTEN with VoiceOver on a back: the label first, then the two pads, the roll, the four jacks; the pitch pad should read "Riff pitch" then "octave +1, transpose +2" once.
- **CARD BACKS — a touch the system cancels (review 2026-10-28):** start a drag on either pad and interrupt it (Control Center swipe, a notification banner pulled down); the next drag on the pad must be its own undo step and must not behave like a double-tap reset.
- **RATCH tab — the cards in AUM (2026-10-28):** open the RATCH tab (the third tab, after FX) in landscape and portrait, including the narrowest portrait frame (iPad mini): four cards A–D, each a toggle disc, a 16-slot strip and the STEPS · HITS · OFFSET · CHANCE · STRIKES cells. The ferry's numbers are scaled to the REAL panel (380 × 319 at the 1190 × 726 reference, not 410 × 303: card width = panel − 16, heights and gaps as the ferry) — check nothing clips and the 7 pt cell labels are legible at real size (the accessibility audit will likely flag their contrast, #8A909A on #1B1D23: a look decision).
- **RATCH tab — 16 / 16 / ×4 (2026-10-28):** set an emitter to STEPS 16, HITS 16, STRIKES 4: all sixteen slots show four 2 pt bars (11 pt wide in a 17 pt slot, 14 / 12 / 10 / 8 tall) — do the bars stay readable at real size, and does the current slot (#2A2D34 against #20232A) stay visible?
- **RATCH tab — dragging the value cells (2026-10-28):** 10 pt per step for STEPS / HITS / OFFSET, 5 per 3 pt for CHANCE, 1 per 18 pt for STRIKES, recognised after 6 pt of movement; the first step lands at 10 pt of travel from touch-down (my reading of "starting once the touch has moved 6 pt"). Does it feel right with a finger, and is a double-tap reset easy to land without a stray drag?
- **RATCH tab — the toggle flare (2026-10-28):** a RATCHED hit thickens the toggle's ring 2 → 3 pt in the striking lane's colour over a 6 pt glow and washes the disc; the strip's current slot lights its bars in the lane colour (35 % on a MISSED hit, no toggle flare). It uses the PULSE flash timing (τ 0.16 s, 1.5 s afterglow) the deleted emitter circles used — does it read as the same object, and is the slot right when two hits arrive inside one 33 ms poll (both flare the later index)?
- **RATCH tab — counting HITS vs STEPS by ear (2026-10-28):** in a dev build open the settings sheet's CLOCK tab (FX COUNTS · HITS / STEPS), feed one output from two lanes and listen to which hits ratchet; the Router counts in processing order (lane, then time) within a window, so two lanes on one output whose hits land in ONE host buffer out of lane order (a few milliseconds apart is enough; polyrhythmic lanes on one output do this constantly) can differ with the host buffer size — try 64 and 1024 frames in AUM and listen for which lane's note ratchets (a hit on the same sample counts once and shares the decision).
- **RATCH tab — ratchets on one output against a single note on another (2026-10-28):** route one part to A and B, ratchet A: A must strike n times and B once; check with two synths that the ALL cable's channel stamping keeps the copies apart; check the one known limit — a pitch held LEGATO on several outputs whose copy on one of them ratchets is not carried on (unreachable from the UI: gates top out at 99).
- **RATCH tab — the iPad mini (adversarial review 2026-10-29):** the cells are 55–57 pt wide there, so each cell's LABEL truncates ("CHAN… 100%": the value always reads whole — fixed after the review caught "10…"); check how the truncated labels read at real size, and that the cards on the mini in LANDSCAPE (the standalone app's transport bar leaves ≈ 50 pt cards, under the §4.8 floor of 52; `.ratchRows` flags it) are still comfortable to use.
- **RATCH tab — a cancelled touch (adversarial review 2026-10-29):** start a value drag and interrupt it (Control Center swipe, a notification pulled down); the cell must return to normal, and the next drag must be its own undo step and start from the value on screen. A drag that returns to where it began must leave no undo step (↶ must not appear to do nothing).
- **RATCH tab — VoiceOver double-tap (adversarial review 2026-10-29):** on a value cell a VoiceOver double-tap is the activation, which now resets the value to its default (it never fires the touch double-tap); swipe up / down still steps the value.
- **RATCH tab — tapping a jack mid-hit and looping (engine review 2026-10-29):** with an output ratcheting a long step (a slow lane, STRIKES 4), tap one of the part's jacks off while its strikes are still to come: the pending strikes on that output stop at once (an output's own ratchet strikes and the ordinary ones of the same note alike). In a host that loops, the ratchet phase should repeat every loop instead of drifting (the count restarts at the loop jump); with a free-run (host stopped, keys held) that is handed back to a starting host the phase restarts too.
- **An untouched lane (2026-10-29):** load a factory preset (STRIDE WALK, MIRROR WALK, …), switch on its spare lane 3 or 4 (PLAY) and give it a few hits without touching anything else: it must play its RIFF (the riff pad and tab show ON) and the NOTES tab must stay off and silent. Before the fix it played one low note from the NOTES layer and the riff was silent. Also open an older saved session whose lanes pre-date the riff/notes fields and check the same.
- **TAB STRIP — "what the cards show" (2026-10-29):** the strip above the lane cards must read as the thing that chooses what the four cards show — distinct from the riff panel's 1–4 tabs and the bottom-right panel's LANES | FX | RATCH tabs beside it. Does the selected segment (#DFE3EA fill) stand out enough on the dark container?
- **TAB STRIP — the 6 pt glyphs (2026-10-29):** do the four per-lane glyphs on RIFF / NOTES / LISTEN read as on / off at a glance, in all four lane colours, on BOTH the light (selected) and the dark segments? The off outline is 1 pt (#8A909A selected / #4A4E57 unselected) — is it visible? With a HOCKET rule lit the glyphs draw resting / away / carrying at 2/3 scale (ring 1 pt, disc 4.7 pt) — do they still tell apart?
- **TAB STRIP — the 28 pt dice and padlock (2026-10-29):** plates are 28 × 28 (was 36), glyph 16, targets 36 × 44 (the two 4 pt apart: they overlap by 4, the padlock wins) — comfortable to hit? The dice's marching-ants ring is 32.
- **TAB STRIP — the flip (2026-10-29):** front tab → MIX and back still turns all four cards in lane order (280 ms, 70 ms apart); does it still feel quick now that the strip sits above the cards? Starting random / lock mode while MIX is showing swaps in the faces without a turn; finishing brings the backs back the same way.
- **TAB STRIP — the header (2026-10-29):** the centred middle group (source control, key pill, HOLD, LATCH) between the logo group and the HOCKET pill: balanced, nothing stranded? BRAND is the logo, FOURFOLD, undo and redo only. At 500-wide windows the header is two rows (NOTES alone on row 2) and the strip's clusters are hidden below a 553-wide lane area.
- **TAB STRIP — the lock badge (2026-10-29):** a locked lane's badge now sits in the card's top row before SOLO and the comet strip is 36 pt narrower (260.67 → 224.67). Not jarring? At 16 steps the columns are 12.3 pt.
- **TAB STRIP — the shorter cards (2026-10-29):** the cards are 301 pt tall (were 319) with a 145 pt RHYTHM upper zone (131 before): the RHYTHM / RIFF / NOTES / LISTEN bodies and the random and lock-mode faces at the new height — the lock card's rows and the random card's picture budget were designed for 319.
- **TAB STRIP — random mode (2026-10-29):** a tap on a strip tab while random mode is on FINISHES it and does nothing else (this reverses 2026-10-22 for the strip only; the riff grid and the bottom-right panel are still live while rolling).
- **SOURCES PANEL v2 — the colours (2026-10-28, §11):** the four source colours (srcMidi #F2F4F7, srcChords #B9A8FF, srcPick #F2A7CF, srcKey #8D95A3) and the three pip looks (playing fill+border / waiting border / off #3A3E47) read at a glance in AUM in both orientations; lilac (CHORDS) against slate (KEY) in the POOL block is legible.
- **SOURCES PANEL v2 — ADD / REPLACE (2026-10-28, §11):** the MIDI row's MODE segment reads without explanation (ADD stacks, REPLACE steps the others aside while MIDI plays); 35 % while MIDI off but still tappable.
- **SOURCES PANEL v2 — the keys under a finger (2026-10-28, §11):** the PICK keys and the KEY-editor ROOT buttons (≈ 21.6 pt wide at a 448 panel, not the spec's "about 24" — my derived formula; reported) are tappable without mis-hits; the octave stepper's ‹ / › at 26 pt.
- **SOURCES PANEL v2 — the CHORDS page (2026-10-28, §6/§11):** the page's push-in from the trailing edge (220 ms; Reduce Motion a 150 ms crossfade), the panel's frame MORPH from the 448 SOURCES width to the chord-grid frame, "‹ SOURCES" going back, and the lilac lit cells; the POOL block at the bottom is 52 tall vs the old strip's 32 — check it isn't clipped (the chord frame may want ~20 pt more).
- **SOURCES PANEL v2 — the POOL preview (2026-10-28, §7.4):** a finger down on a CHORDS-page grid cell shows THAT column's stacked pool with "COL n"; on lift it returns to the live pool. By ear/eye it matches what that column would play.
- **SOURCES PANEL v2 — REPLACE with real legato (2026-10-28, §11):** holding a chord with CHORDS/PICK/KEY on + REPLACE drops them to rings and the POOL is all white; letting go, they return with no blip between legato chords (the 50 ms RELEASE GRACE).
- **SOURCES PANEL v2 — 343 with the KEY editor open (2026-10-28, §5.2/§11):** at a 375-pt-wide panel (343 container) nothing clips and the region below the title scrolls when the KEY editor is open.

- **TAB STRIP review — the hocket glyphs (2026-10-29):** with a HOCKET rule lit, the strip's RIFF / NOTES glyphs draw their states at 2/3 scale on a 4 pt pitch; the screenshots show the carried rings of lanes 1 and 2 touching and lane 2's away disc overlapping lane 3's square. Read at arm's length on the iPad: still tell the four lanes apart?
- **TAB STRIP review — the lock face on the short cards (2026-10-29):** the lock card now drops its bottom hint line on cards under 276 tall (it crossed the tick strip). Check the lock face on the smallest windowed sizes, and that a 34 × 44 touch on the lane badge hits it.
- **POLY RIFF — the cells (2026-10-29):** the POLY grid's cells are ≈ 18.8 × 25 pt (MONO's are 37.8 × 25). Is a finger accurate enough to land on the cell it means, and to stretch a note across columns without catching the next column? Are the lane arrows (sized from the cell) readable at ≈ 12 pt?
- **POLY RIFF — the drag (2026-10-29):** touch an empty cell, drag sideways: does the note follow the finger both ways? Touching a long note and dragging — does the near end move as expected? Does lifting without moving (removing a note) ever happen by accident while trying to start a drag?
- **POLY RIFF — the control (2026-10-29):** the MONO | POLY control fills the row the four boxes had (20 pt tall, 14 compact). Easy to hit? Is the long-press CLEAR discoverable enough (there is no visible CLEAR any more)?
- **POLY RIFF review — long notes and PLAY (2026-10-29):** a POLY note of length 8+ on a lane with a sparse rhythm and a restart chain should ring to its last hit (not a fraction); switching a lane's PLAY off while a long POLY note rings should silence it at once; with ADV STEP and a melody restart the note ends at the restart. All three are off-device-proven (engine tests) — listen once in AUM.
- **POLY RIFF — reverse + chord arrows (2026-10-30):** set the riff direction to REV with a note held across most of the grid (say columns 2–15): it should strike when the arrow reaches the RIGHT end and sound exactly as long as it does forward. A chord (several notes on one column) should show an arrow on every one of its notes while it sounds — check the arrows are legible two or three stacked in an 18.8 pt column, that lane numbers on them don't collide, and that the tint under each flares. PENDULUM / PING-PONG still strike a held note at its left end only.
- **POLY RIFF — PENDULUM / PING-PONG ends (2026-10-30):** hold a note across most of the grid and set a lane to PING-PONG (`><`): it should strike when the walk reaches the note's LEFT end going up and again at its RIGHT end coming back — never silent for half a cycle; the chord arrows follow (a chord's arrows stack on the notes it strikes at that end). PENDULUM only arrives from a loaded document or a random-mode throw (its turn strikes both ends' notes).
