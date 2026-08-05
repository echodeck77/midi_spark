# Dear Paul — what changed & how to test it (2026-08-04 → 05)

**Summary:** This batch replaces the old emitter page with THE RACK — a per-emitter treatment matrix reached from a
clean strip "RACK" button, with eight live treatments (OWNS · KEY · TURNS · MONO · FENCE · CURVE · POCKET ·
CONVERSATION) gated by a two-tier "is the board in the path" switch. It also fixes two device bugs (a fully-bypassed
cell going silent, and the column loop dying on the EDIT↔GRID switch), reworks TURNS, adds an in-app manual ("?"),
and tidies FENCE — the full per-item checklist is below.

> **Where to build from.** The RACK, its 8 treatments, and the crash/stability fix are on **`main`**. The FENCE UX
> tidy, per-note TURNS, the two bug fixes, and the in-app manual are on the branch **`feat/multiple_features`**
> (not merged — build that branch to test them, or merge it first). Each item below is tagged **[main]** or
> **[branch]**. Cross-reference the `RK-*` procedures in `Docs/test-procedures.md` for the fuller scripts.
>
> Golden rule throughout: if a note ever hangs or PANICS climbs, note exactly what triggered it — that's a bug.

---

## 1. THE RACK — the new emitter panel [main]

### 1a. The strip went clean
**Change:** each MIDI-OUTPUT strip now shows only **OCT± · velocity · LIVE · SOLO · RACK**. The old CLAIM/DUCK/ALT
buttons are gone from the strip.
**Test:** look at the four output strips — confirm the five tenants above and no leftover role buttons. Flag if the
RACK button is cramped in the narrow band.

### 1b. The RACK button
**Change:** **tap** RACK toggles whether that emitter's treatments apply (lit cyan = board in the signal path;
outlined = raw wire). **Long-press** RACK opens the matrix.
**Test:** short-tap flips lit↔outlined (does NOT open the matrix); long-press opens it (and must NOT also flip the
toggle). Try on each emitter.

### 1c. The matrix draws INSIDE the grid
**Change:** opening the matrix replaces only the 8×8 cell area — the **chevron column-key row stays above it and
both L/R row-select rails stay beside it**; the strips/master stay live around it.
**Test:** open the matrix and confirm the chevron row + both rails are still visible framing it. Confirm it closes
on **DONE**, on the **PERFORM/EDIT toggle**, and on a **scene switch**.

### 1d. The two-tier gate (the key idea)
**Change:** the matrix toggles say which treatments are *armed*; the strip RACK says whether the board is *in the
path*. RACK off ⇒ that emitter is a raw wire regardless of the matrix.
**Test:** arm OWNS on A so B is suppressed (see 2a). Turn A's **RACK off** → B's note returns (raw) and A's matrix
column header reads **RAW**. RACK back on → suppression returns. **LIVE stays senior** — LIVE-off silences
completely whether the rack is in path or raw; RACK-off ≠ silent (the emitter still sounds, just unprocessed).
**One reading to confirm by ear:** RACK-off is a *full-column* bypass — it also stops that emitter's OWNS/KEY acting
on others (those are its pedals). Tell me if you'd expect it to keep affecting others while raw.

### 1e. The readout
**Change:** tapping a matrix **column header** shows that emitter's one-line "social sentence" (only true clauses).
**Test:** arm a couple of treatments on A, tap A's header — confirm it reads e.g. "OWNS 3 classes · CURVE +30".

---

## 2. THE EIGHT TREATMENTS [main unless noted]

Rig for the "over-others" ones: two cells of the **same pitches on different emitters** (a held chord → A, an arp of
the same notes → B) is the workhorse.

### 2a. OWNS (the old CLAIM) — [main]
**Change:** while A owns a pitch class it's sounding, matching notes on other emitters are withheld; the **LEAK**
knob lets them bleed back as quieter shadows.
**Test:** OWNS on A → the held pitch on B is withheld (monitor B). Raise A's LEAK → B returns at reduced velocity.

### 2b. KEY (the old DUCK) — [main]
**Change:** while A sounds, other emitters' NEW notes arrive quieter (by the **AMOUNT**); already-sounding notes
don't lurch; 100% ≈ a keyed gate.
**Test:** KEY on A, amount ~50 → B/C/D's new notes drop in velocity while A plays; watch a target's velocities.

### 2c. TURNS (the old ALT) — [main] + a new mode [branch]
**Change:** the TURNS emitters take turns playing the **incoming notes from any cell** (not just one cell's fan-out).
Two independent cells (one → A, one → B, both TURNS) now pool and alternate. **COUNT** = dwell. **[branch]** The
TURNS **detail strip** now has a global **HAND-OFF: PER MOMENT | PER NOTE** toggle.
**Test (main):** two cells → A and → B, TURNS on both, COUNT 1 → they alternate lap by lap (not both at once); the
note timing is unchanged, only the emitter alternates. **Test (branch):** flip to **PER NOTE** — at a simultaneous
strike only ONE emitter plays (leftmost) and the other note is **dropped, not delayed a tick**; PER MOMENT sends
simultaneous notes to the one holder (both sound on it).

### 2d. MONO — [main]
**Change:** forces one note per emitter; a new note steals per **PRIORITY** (tap the chip: LAST → LOW → HIGH).
**Test:** feed an emitter a chord with MONO on → only one note sounds at a time (great for glide synths). LAST =
newest wins, LOW = lowest, HIGH = highest. Confirm no two notes down at once and nothing hangs when the chord
changes. (Chords re-strike at onset — a little churn is expected for now.)

### 2e. FENCE — [main], tidied [branch]
**Change:** notes outside a per-emitter **LO…HI** window are **DROP**ped, **CLAMP**ed, or octave-**FOLD**ed back in
(tap the policy chip to cycle). **[branch]** Turning FENCE on now **seeds a sensible default (CLAMP · C2–C6)** so it
acts immediately, and the **LO/HI steppers now sit in a RANGE row right under the FENCE row** (each column under its
emitter) — not at the bottom.
**Test:** FENCE on an emitter, set a window narrower than your part, play above/below it → DROP = notes vanish,
CLAMP = snap to the bound, FOLD = jump by octaves back inside. Confirm the RANGE row is directly under FENCE.

### 2f. CURVE — [main]
**Change:** a per-emitter velocity re-map — the bipolar knob makes it hit **harder (+)** or **softer (−)**; 0 =
linear.
**Test:** CURVE on, play a dynamic passage → the output velocities bend the way the knob says (monitor). RACK-off
suspends it; the master fader still overrides.

### 2g. POCKET — [main]
**Change:** a per-emitter timing feel — the knob pushes the output a few ms **ahead (−)** or lays it **back (+)**.
**Test:** POCKET on, dial the knob → that emitter's note timestamps shift vs the others on the monitor. RACK-off
suspends it; nothing should hang. (Small offsets are exact; very large ones near a buffer edge clamp.)

### 2h. CONVERSATION (LEAD/STANCE) — [main]
**Change:** one emitter is the **LEAD** (tap a column's top cell — radio, tap again to clear); each other emitter's
**STANCE** admits its notes only **WITH** the lead's sound or **AGAINST** its silences (or **FREE**).
**Test:** make A the LEAD; set B's stance WITH → B plays only while A sounds; AGAINST → B plays only in A's gaps.

### 2i. Knob feel — [main]
**Change:** the rotary knobs are **less sensitive** (more finger-travel per unit) — should feel less twitchy.
**Test:** drag any knob (LEAK/AMOUNT/CURVE/POCKET) and confirm it's controllable, not jumpy.

---

## 3. TWO DEVICE BUGS FIXED [branch]

### 3a. A fully-bypassed cell now plays the passthrough
**Change:** a cell whose whole chain is bypassed (one slot's BYPASS on, or all slots) now plays the raw MIDI input
(the same as an empty/newborn cell), at any chain depth. It used to go silent / wrong.
**Test:** make a cell with one processor (e.g. an ARP), toggle that slot's BYPASS → the cell should play the held
chord untreated (not silence, not the arp). Try with a longer chain, all slots bypassed → same. A partial bypass
(one active slot) is unaffected.

### 3b. The column loop survives the page switch
**Change:** a column loop armed on the EDIT page now **keeps playing when you switch to the GRID page**, and the
looping column shows the loop glyph on both pages. It used to stop on the switch.
**Test:** on the EDIT page, loop a column via the column selector; switch to the main GRID page → the loop keeps
playing and the column key shows the loop indicator.

---

## 4. IN-APP MANUAL — the "?" [branch]

**Change:** a **"?" in the top-right** (next to the cog) opens the manual **scrolled to the control you last
touched**, with that entry highlighted.
**Test:** touch a control (say a receiver strip, or the header PERFORM/EDIT toggle), tap "?" → the manual opens at
the relevant place; DONE closes it. *Known scope:* the header controls anchor individually; the receivers/grid/
emitters/master/verbs/clock currently anchor at the **section** level (the rack matrix itself isn't in the manual
yet, so touching it lands on the grid section) — tell me if you want finer per-control anchoring.

---

## 5. STABILITY [main]

**Change:** fixed three more render↔main-thread shared-buffer races in the 4 Hz UI poll (the `_swift_release_dealloc`
crash class) — same family as the earlier header-dot crash.
**Test:** run a busy session (chords held, tempo/loop changes, scene switching, the rack matrix open) for ~10
minutes and confirm no crash and stable memory (Xcode gauge). Not a visible feature — a stability check.

---

## 6. FOLLOW-UP CHECK OWED — the SEAL vs different emitters [main]

**Background:** you reported that a cell → **A** and a cell → **B** (same emitter *count*, different one) drew the
**same seal**, while A+B vs A differed as expected. I added a unit test — `testSealDistinguishesWhichSingleEmitter`
— and it **passes**: A/B/C/D each produce a distinct hash *and* a distinct drawn maze, and the live-edit path
(changing the emitter) does refresh the seal. So in the current code the encoding + redraw are both correct; the
build you saw it on likely predated the fix, or the mazes differ but read alike at cell size.

**Your task (next time you have the device):**
1. On a fresh `main` build, make **one cell → A** and **another cell → B** (same everything else), and eyeball their
   seal glyphs.
2. If they now look **different** → resolved, nothing more to do (tell me and I'll close it).
3. If they **still look identical**, note:
   - **which surface** — the small grid-cell face, the big EDIT-page identity plate, or both;
   - whether it **self-corrects** if you tap away and back, or switch PERFORM↔EDIT / pages;
   - (handy check) do the **bus dots** on the cell change between A and B? Those are the direct "which output"
     indicator, separate from the maze.
4. Send me that, and I'll either chase the specific renderer or make the output difference more visually pronounced.

## Commits with NO device-visible change (for completeness)
Internal only — nothing to test on device: the `feat/multiple_features` **docs** commit + the manual-Why merge +
macro-panel capture + CLAUDE.md flags; the **CELL TURNS** experiment that was reverted the same day (net zero); and
the **chaos-mode / oracle** harness commits (DEBUG-build dev tooling — a simulated-MIDI soak tester, not part of
normal play). The **seal** change was investigation + a regression test only — the reported "different outputs share
a seal" turned out to already be correct, so there's nothing new to see there.
