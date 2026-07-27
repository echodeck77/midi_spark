# Design epoch — the arrangement bar, presets, the cog page, field rulings (2026-07-27)
_Ferried + preserved 2026-07-27 (a large accumulation). Internally consistent; SUPERSEDES several older layout
notes (per-band spanners; the ⋯ settings glyph; the two-persistence spanner face-swap). Status: **DIRECTIVE** =
build; **SUPERSEDED** = never build; **BUG/RULING** = field report. Most items sequence AFTER the device
checkpoint — which CLEARED 2026-07-27 (user: "happy with everything on device")._

## 1. THE SCENE STRIP — item 2/2b (CORE SHIPPED as multi-scene S1, `377c2f7`)
Sparse slots · numbers only (no caption) · empty = **+** = save-here the current scene · long-press = DRAG:
drop on empty = MOVE, on occupied = **SWAP — never overwrite** (scenes are precious) · the **TRASH** (red can)
appears only during a drag, drop = delete (undo-covered; the ACTIVE scene refuses — shake). Overwrite-by-save
dies (save-onto-occupied = delete-then-+). **Performance grammar:** ACTIVE chip wears the PASS SWEEP (2pt bar
crossing L→R) · tap another = **ARM** at next pass (§5d), tap PENDING again = CANCEL · **double-tap = IMMEDIATE
(column-quantised, decide by feel)** · tap/2× the CURRENT chip = **RESTART THE PASS** (→ column 1; subsumes
assert-the-present — a self-switch, invariant-4 closes lingering voices). Gesture table: tap = arm/cancel/restart
· 2× = now/restart · long-press = drag · + = save-here.
→ **STATUS:** S1 = sparse + save-here + switch (immediate) + voice-flush, shipped. **S2** (#27) = arm/immediate/
restart timing. **S3** (#28) = pass-sweep + drag/swap/trash.

## 2. THE ARRANGEMENT BAR — item 7/7b (DIRECTIVE; after EDIT retires)
With EDIT/PERFORM retired, the header row becomes **LOGO · the 16 scene chips · ⚙**. Fits portrait design
width (~1030pt: 16 chips @44pt + gaps ≈750 · cog 44 · padding 48 · ~190 for the logo). PINS: the **LOGO YIELDS,
never the chips** (compresses to the "8×8" mark under pressure — the song outranks the brand) · all strip
behaviours survive at chip scale (sweep = 2pt bar, pending blink, +, drag/swap) · **the ⚙ BECOMES the red TRASH
CAN in place during a scene drag** (reverts on drag-end; one corner, one identity — the cog isn't present while
the can is; never a floating can next to settings). The reclaimed strip row goes to the grid/bands. Identity:
the header IS the arrangement bar (arrangement above · signal through the middle · treatment below).

## 3. PRESETS v1 — item 3/3b/3c (DIRECTIVE; whole-document, no "create new")
A preset = THE ENTIRE STATE (16 slots · wiring · per-scene Colours · key · all of fullState) as NAMED JSON
FILES in the App Group container (standalone reads them natively later; share-sheet export ≈ free v2).
- **TWO PERSISTENCE LAYERS:** the host's automatic AUM fullState (unchanged) + the instrument's named presets.
- **NO "CREATE NEW".** The factory section ships **DEFAULT** (READ-ONLY, "new" in honest clothes) + **THE
  CURRICULUM** (the 16 teaching scenes RELOCATED here — the blank start stops shipping with homework).
- **DEFAULT = THREE SCENES, musical** (first launch IS music): scene 1 = a series of arps, an interesting
  pattern · scene 2 = adds elements · scene 3 = EPIC · slots 4–16 = +. Blank-page dies; users build on the arc.
- **MINIMUM-RIG LAW:** the DEFAULT arc is **SINGLE-EMITTER — everything → A, all three scenes** (first-try rig =
  one synth on port A · ch1; content on B/C/D could be silent = unforgivable first impression). Scene 3's
  "epic" from one-wire means: density · OCT register spread · HARMONIZE blooms · CHANCE shimmer · ARRIVE-drift
  B-morphs · rhythmic interlock. **Factory content DECLARES ITS RIG** — multi-emitter features (CLAIM/FLATTEN/
  ALT/cable-splits) live in FEATURE-DEMO presets whose names state prerequisites ("CLAIM & SPACE — route A+B").
- **OPERATIONS:** SAVE AS (named — the app's FIRST TEXT INPUT) · overwrite USER entries only · LOAD = one
  undoable step, immediate, voices closed via the transition machinery (a session act, no arm ceremony) ·
  DELETE user entries (undo-covered, no confirmations).
- **SURFACE:** a folder glyph in the header → a sheet (factory · user · SAVE AS on top).
- **LIVE PRESET PREVIEWS:** tapping a browser row TRANSIENT-LOADS the preset — the user's live input plays
  through it, sweep running, sheet open; tap another = switch preview; LOAD = commit (the one undoable step);
  **dismiss = restore the prior working state EXACTLY** (the staging transient-restore pattern at document
  scale; the fullState-exclusion discipline applies — a host autosave mid-preview persists the RESTORED state,
  not the preview). Each row = a mini-grid thumbnail (scene-1 colour blocks) + name + scene-count dots.
- The COLOUR SHELF (tier-② sounds-travel-separately) stays deferred, not dead.

## 4. FIELD BUGS + RULINGS — item 4 (2026-07-27)
- **(a) BUG — dropout at scene start (intermittent):** silence when the playhead starts the scene. SUSPECTS:
  ① wrap-boundary ORDERING (new scene's snapshot publishes AFTER column 1 derives → column 1 plays stale/empty,
  recovers at column 2) · ② the transition close-all catching the NEW scene's just-started voices.
  **DISCRIMINATOR: does it repro on SELF-RESTART (tap current chip)? yes → transition ordering; only on real
  switches → snapshot publish.** → investigate + a targeted RouterTest of the wrap-transition ordering. (Ties
  to multi-scene S2's arm-at-pass switch, where publish-vs-derive ordering bites.)
- **(b) RULING — the FADER-KILL:** vel-0 on the wire is a NOTE-OFF (engine floor of 1 is correct), but the
  slider's BOTTOM = suppress emission entirely: GUI maps full travel 0–127; 1–127 = override; **0 = no marks,
  no notes** (the DJ fader-down). Also check the GUI travel inset (can the thumb reach the floor?).
- **(c) DIRECTIVE — INVISIBLE = FROZEN:** all TimelineView/Canvas rendering (flow, sweeps, marks, emblems)
  pauses when the view isn't visible/foregrounded; resumes on appearance; **audio engine untouched**. The
  budget law's final clause.
- **(d) DIRECTIVE — SCROLL + TEACH:** the UI renders at its DESIGNED size; the AU viewport SCROLLS when the host
  gives less; a ONE-TIME hint when the window is well under design size ("works best expanded — full-screen
  button"). No more squeezed layouts; the window is a camera on the instrument's body.

## 5. THE COG PAGE — item 6b (DIRECTIVE; SUPERSEDES the spanners of item 5 AND the ⋯ of item 6)
- **SUPERSEDED — never build:** the per-band ⚙ spanners (item 5) and the ⋯ settings glyph (item 6). One door.
- **The ⚙ cog, top-right → a full-screen SETTINGS page** hosting **MIDI I/O config**: a MIDI INPUT section (per
  receiver: CABLE · CHANNEL · latch mode CHORD|ADD) + a MIDI OUTPUT section (per emitter: CHANNEL). **The roles
  (CLAIM/FLATTEN/ALT/OCT) STAY ON THE STRIPS** (performance structure, not rig config). CELL-level intake stays
  at the route panel's head (different noun).
- **CONSEQUENCE — THE STRIPS GO SINGLE-FACE FOREVER:** config in the page ⇒ the EDIT faces (cable/channel
  steppers, the CHORD|ADD segment) LEAVE the strips; the perform face is the only face; the console's face-swap
  doctrine retires.
- **THE LAW: the page NEVER STOPS THE ENGINE** — it opens as an OVERLAY on the running instrument (audio/render
  continue, MIDI flows, latches hold); every change applies LIVE (cable/channel edits republish immediately);
  dismiss returns to uninterrupted performance. Config is something you do TO the music, not instead of it.
- **Birth tenants** (no empty launch): VISUAL INTENSITY (OFF·SUBTLE·SHOWCASE, finally homed) · the DIAG toggle
  (graduating from the thumbnail corner) · about/version · the expand-hint reset. Labeled empty future sections:
  capture/Time-Machine prefs · controller mapping · external plugins. Presets STAY at their folder glyph.
- **ADMISSION LAW:** the page holds GLOBALS + SET-ONCE RARITIES only — anything touched during play, or per-scene,
  lives on the main surface or its object's own door. Rig config is exactly "set-once."

## 6. EDIT-MODE RETIREMENT CHECKLIST — item 5 (the tenants relocate, then the toggle dies)
cell editing → the verbs ✓ · undo/redo → GRID CONTROLS ✓ · scene save/curation → the +/drag strip ✓ · strip
config → **THE COG PAGE** (not spanners) · column config → nothing until column-ON/multi-scene. **When the cog
page ships ⇒ the EDIT toggle dies; the header slims to the arrangement bar (logo · chips · cog).**

## 1'. (dup) GUI de-intimidation — re-ferried; already logged in design-ferry-modeless-2026-07-27.md.
