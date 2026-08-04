# Test procedures — device verification playbook

Claude Code cannot hear MidiSpark or see AUM. Every engine change is verified by
the human on the iPad, guided by these procedures. Keep them updated as features
land; when asking the human to test, quote the relevant procedure by name.

## Standing AUM setup

- MidiSpark as a MIDI Processor; keyboard → MidiSpark input.
- MidiSpark declares FIVE outputs once v0.5 lands: ALL + A–D (before that: four).
- Four synth channels: MidiSpark A → Synth1, B → Synth2, C → Synth3, D → Synth4
  (any AUv3 instruments; distinct patches so buses are tellable apart).
- **AUM MIDI monitor nodes** on MidiSpark's input and on output A (add B when
  testing fan-out). The monitor is the truth for timing/pairing claims.
- MidiSpark's plugin UI open. (The in-plugin diagnostics panel was REMOVED at the
  GUI reconcile — the AUM MIDI monitor is now the sole source of truth for
  voice/pairing/timing claims. Test sessions load from the DEV LOADER, which shows
  in the plugin UI in **portrait** only.)

## Bridge regression (run after ANY kernel change) — 2 minutes

Hold a chord, transport playing:
- B1 Morph Gold 0→1 sweep: rate LADDER-STEPS (never glides); gate audibly shifts.
- B2 Morph Master: same effect patch-wide; individual morph positions preserved.
- B3 Swing 66: even/odd limp at the step level; **at exactly 50, timing
  indistinguishable from before** (monitor timestamps if in doubt).
- B4 Sync torture: tempo change mid-hold, loop a bar, relocate — no drift,
  no stuck notes. Stop with keys held — no stuck notes.

## Canned test sessions (loaded from the DEV LOADER — portrait plugin UI)

**NUMBERING AUTHORITY: the repo.** `TestSessions.swift` carries T1–T17
(processor + migration coverage beyond this document). The repo's numbering WINS — map
the cases below by INTENT, not by number; where an old session covers the
same intent under the old model, re-express it in place; where a case below
is new (reference graphs, filter+stamp, ALL cable, cycles), APPEND with the
next free number. First act of the migration survey: reconcile and update
THIS document to the repo's final numbering. Numbers below are provisional.

Each lists: the grid it builds → what correct behaviour sounds/reads like.

**T1 — single ARP.** Gold ARP at (col 0, row 0), bus A.
→ Ascending 1/16 arp on Synth1 only, only while column 0 is active (1 step in 8).
Monitor A: clean on/off pairs, silence for the other 7 steps.

**T2 — reference chain.** Col 0: gold ARP (row 0, no letters) → cyan cell
(row 1, inputRow:0, bus A).
→ Sound leaves ONLY through row 1. Row 0 alone must be silent on every bus.
Output reflects processing of the parent's sounding set.

**T3 — sibling source tap** (replaces the old +SRC merge). As T2 plus a third
cell (row 2, inputRow:null → MIDI IN, bus A).
→ Bus A carries processed-feed AND source-derived streams together — the old
"+SRC" musical intent expressed as siblings. Verify both streams well-paired
on the monitor.

**T4 — fan-out.** One ARP cell with buses A and B both lit.
→ Identical simultaneous streams on Synth1 and Synth2; monitors A and B show
duplicate events, independently well-paired.

**T5 — muted-parent reroute.** As T2 but the parent (row 0) muted.
→ Row 1 reverts to MIDI IN (v3.0-delta §1 reroute rule): plays as if
unreferenced; restores on unmute; zero stuck notes across both transitions.
Visual checks: the AUM monitor, and the cell's FROM header flare (the
in-plugin diag panel is gone).

**T6 — channel filter + stamp.** Two cells, both FROM MIDI: cell 1 filter
IN CH 1, bus A (ch stamp 5); cell 2 filter IN CH 2, bus B (default stamp 2).
Keyboard sending on ch 1, then ch 2, then both (split/layer if available).
→ Ch-1 playing sounds only cell 1's stream, emitted stamped ch 5 on cable A;
ch-2 only cell 2's on cable B ch 2; both = both. No origin channel survives
anywhere. Change a stamp live: re-stamps with no stuck notes. Set cell 1 to
OMNI: it now hears everything.

**T7 — collision policy (§7).** A sustained identity cell and a same-pitch ARP,
same bus + channel (build: identity type row 0 bus A; ARP row 1 bus A, pool
arranged so pitches overlap — single held note is easiest).
→ **Zero dropouts** in the sustained note across arp hits; every arp strike
re-articulates; monitor A shows exactly ONE note-off after the last holder
releases. No off "holes" mid-step.

**T8 — PHASE modes.** Three ARP variants: RETRIG in two separate columns;
LEGATO across a 2-column run (8-note pattern, verify it completes ONCE across
the run, no repeated/skipped indices; gap restarts at 0); FREE with pattern
length coprime to the step (successive passes catch different slices; loop the
host — slices stay consistent with the derivation, no drift).

**T9 — fan-out tree.** One ARP parent (row 0, no letters); rows 1 and 2 both
inputRow:0 with different treatments, buses A and B respectively; row 3
inputRow:1 (a grandchild), bus C.
→ Three simultaneous streams derived from ONE engine: A and B audibly share
melodic material (same parent sounding set) under different processing; C
processes row 1's output. Mute row 0: ALL THREE revert to source-derived
behaviour at once. This is acceptance items 29 + 30.

**T10 — the ALL cable.** Load T9 (fan-out, buses A/B/C, stamps 1/2/3).
Host shows FIVE MidiSpark outputs. Patch synths to A, B, C individually AND
one omni synth + monitor to ALL.
→ Individual cables behave exactly as before. ALL carries all three streams
simultaneously, distinguished by channels 1/2/3. Set two emitters to the
SAME channel: their streams merge on ALL with correct off-pairing (no early
cutoffs); the desk shows the shared-channel note; individual cables remain
unaffected. Everything holds while patching channels live — no stuck notes
on either the individual cables or ALL.

**T11 — cycles and backward taps.** (a) Two cells referencing each other
(row 2 → row 4, row 4 → row 2), both with buses lit.
→ TOTAL SILENCE on all cables while playing with keys held — a closed loop
has no entry. No CPU spike, no stuck notes, diag voice count stays 0 for
both. (b) Backward tap: row 1 ← MIDI IN (arp); row 0 references row 1,
bus B. → Row 0 emits a processed version of row 1's stream (unit-delay
sampling — musically indistinguishable). Repatch row 0 back to MIDI IN
live: clean transition.

## Perform layer (P-series) — §6.1/6.2, mode + live tap

Interaction tests, not canned grids — build on any occupied scene (scene 14 ALT
EGO is designed for P2). Header carries the EDIT·PERFORM toggle; in PERFORM a cell
TAP flips it to/from its B-state (ALT). (The ALT/BYP/MUTE tap-action selector and
column-key mute were REMOVED pending the perform spec — see P3/P4.)

**P1 — mode gating.** In EDIT: tapping a cell body paints/recolours, FROM/OUT
headers open popovers, long-press opens the clear/copy menu. Toggle to PERFORM
(chip goes cyan): the whole pad is ONE tap target — no popovers, no menu. Toggle
back: EDIT behaviours return intact.

**P2 — live ALT flip.** Load scene 14, chord held, transport playing, mode PERFORM.
Tap a cell → it flips to its B-state (breathing ring activates) and the sound
changes (e.g. gold B rate). Tap again → back to A. No stuck notes across flips.

**P3 / P4 — REMOVED from the UI.** Live BYP, live MUTE, and column-key mute were
taken out (`3e816ee`) while the perform feature is undecided. The engine still reads
`Cell.bypassed`/`muted` (and `SceneState.tapAction`), so these procedures return
verbatim if the controls are re-added — do not re-number around them.

**P5 — audition (§6.4 / delta §5), ALL types.** Transport **STOPPED**, hold a chord.
Press-and-hold (~0.3s) a cell → its processor sounds **ALONE** against the held chord on its
lit buses, ignoring its FROM wiring (source-forced), passgate all-open; the **raw chord
passthrough stops** while held. Release → no stuck notes. By type:
- **ARP** → arpeggiates at host tempo, phase from the press. **RATCHET** → re-strikes the chord.
- **HARMONIZE** → the added voices sound (hear the chord it builds). **CHANCE** → the passed
  subset sounds (deterministic — same notes for the whole hold). **PASSGATE** → the chord
  sustains (all-open). **STRUM** → the chord **rolls in** over the spread, then sustains (hold a
  wide voicing to hear the roll clearly).
- **Chord-hold + strum track the keys LIVE**: add a key while holding → it joins; release one →
  it drops, the rest keep sounding (the "patch-and-listen" loop).
Press **play** while holding → audition auto-releases, sequencing takes over. Hold with **no
keys down** → silence.

(DEFERRED — no procedure yet: APPLY latch, column audition, popover-live
audition; cell-hold isolate/solo — provisional pending the TOUCH design pass.
Stutter/loop is now SPEC'D as the delta §5b column-subset lap — its T-intent
is below; engine work per CLAUDE.md NEXT.)

**T-intent — emitter toggles (§6a; number per repo authority).** Load the T10
setup (three streams, stamps 1/2/3, synths on Emit A/B/C + omni monitor on
All). While a chord is held and playing: disable B.
→ Cable B silent IMMEDIATELY (clean offs); All loses exactly B's stream; A/C
untouched; B's cells still derive (children routed elsewhere still sound).
Re-enable B → its stream returns at the next articulation, not mid-note.
Shared-channel case: set two emitters to the SAME channel, disable one → All
keeps the survivor's notes with no early offs. Hammer all four toggles
rapidly during play → zero stuck notes anywhere, All always equals the
enabled sum. EDIT mode: the toggle pad still enables/disables; the DEDICATED
per-emitter CH stepper (▲/▼, wrapping 1–16) below each toggle edits the channel
(a7 — this replaced the a2 caption popover); changing a channel live re-stamps
cleanly (T6 semantics).

**T-intent — emitter panel v2 (§6a rev / a7; number per repo authority).** The
EMITTERS panel is now a mode-aware channel-strip mixer (same static frame both
modes — flip EDIT↔PERFORM, the box must not resize). Two new PERFORM controls,
on the T10 setup (three streams on Emit A/B/C + omni monitor on All), chord held
and playing:
(a) VELOCITY OVERRIDE — drag an emitter's vertical fader: every NEW note-on on
that emitter flattens to the fader value (whisper at the bottom, slam at the top),
own cable AND its All copy; the LED ladder shows the set point while touched and
tracks the live meter when idle. RELEASE → that emitter springs back to natural
velocity (no stuck notes, no persisted change — reload the scene and it's gone).
Other emitters are untouched; a DISABLED emitter stays silent under a drag.
(b) CLAIM — tap an emitter's CLAIM radio (amber). While a chord is held: any pitch
the claimant is sounding VANISHES from the other emitters (own cables + their All
contribution) — the claimant keeps it, the others get the residue (unclaimed
pitches still sound). Tap another emitter → the claim moves (RADIO, one at a time);
tap the claimant again → clear. No stuck notes across claim on/off/switch.
OCTAVE CASE (delta §6a pitch-class fix — lands with the mod-12 change):
claim A, hold C3 on A's material → play C4/C5 material routed to B →
ALL C's suppressed on B regardless of octave; a D on B passes. CLAIM
IS PERSISTED (survives reload). MUTED CLAIMANT: disable the claimant's emitter
TOGGLE while it holds the claim → it goes silent itself but STILL reserves its
pitches (a sidechain-style claim — the others stay ducked against a lead you don't
hear); re-enable → it sounds again. Suppression is RATE-INDEPENDENT at every arp
rate for BOTH single-cell fan-out AND separate cells (a persistent silent
ownership "ghost" tracks the claimant even when its audible note is too short to
straddle a render window). KNOWN CAVEAT (accepted, L1): the only soft edge is two
DIFFERENT cells whose SAME-pitch notes both NEWLY onset in the same render window —
suppression then favours the claimant only if its cell is at/above the other in the
column (row order). A claimant note held from a prior window is always
order-independent.

**T-intent — column-subset lap (§5b; number per repo authority).** A scene
with distinct material in every column (scene 4 STAIRCASE is ideal). Playing,
chord held:
(a) hold key 3 → column 3 repeats at step rate; release → the pattern is
exactly where it would have been (verify against a counting loop in AUM).
(b) hold 1+4 → strict alternation; add 6 mid-hold → 1,4,6 rotating (k=3
against 8: the downbeat column CHANGES each pass — the intended polymeter;
verify it rotates rather than resetting).
(c) hold a contiguous 5–8 → the old loop-brace behaviour.
(d) with a PASSGATE scene (9): during any hold, the every-2nd/4th-pass cells
keep their TRUE schedule.
(e) hammer holds on/off across bar lines → zero stuck notes, arrow always on
the sounding column.

## UI size checkpoints (GUI reconciliation gate)

NOTE (2026-07-24): the checkpoint geometry below predates **delta §6d THE
SIX-PANEL LAYOUT** (receivers|emitters band under the grid + right
identity column in landscape; 25/50/25 × 2 band in portrait; settings
inline). Re-run the checkpoints against §6d when the layout lands; the
truncation finding is resolved BY GEOMETRY there.

Screenshot-verify the reconciled UI at: 1024×768 (floor device), 11-inch
(primary), 13-inch (roomy) — both orientations each — plus ONE deliberately
small AUM plugin panel (degradation ladder engages, nothing overlaps or
truncates mid-word, static frames hold within the active rung).

## Milestone gates

- (HISTORICAL: `v0.3-router` shipped under the old chain model.)
- Migration commits map to T-cases per Docs/migration-tree-routing.md
  (post-reconciliation numbering); run the
  bridge regression at each.
- `v0.4-graph-routing` requires: T1–T5 + T7–T9 + T11 pass (T6 in its OLD form)
  + B1–B4 + 10-minute soak (chord held, tempo/loop changes, test-session
  switching mid-play) with zero stuck notes and stable memory (Xcode gauge).
- `v0.5-outputs` requires: T6 (new form) + T10 green on top of the above.
- Acceptance items (spec §11) formally close only when testable end-to-end;
  note partial coverage honestly (e.g. item 4 is "engine-verified via T2/T5,
  UI-verified at step 5").

## Reporting template (what the human sends back)

"T_n: PASS/FAIL — [what was heard] — monitor: [anything odd — voice count from the
AUM monitor, pairing, stuck notes]". Screenshots of the monitor beat transcription
when timing is disputed. (The in-plugin diag panel is gone — the AUM MIDI monitor
supplies all numbers that panel used to.)

## STRIP PASS — the MIDI INPUT + MIDI OUTPUT strips + CLAIM (2026-07-26)

The combined device pass for the receiver strip, the emitter strip, and the CLAIM
gate that unblocks the emitter role family (leak% / FLATTEN / ALT). Load a canned rig
via the HIDDEN DEV LOADER (long-press the "8×8 STATE" logotype ~1.2s → the T-session
overlay + the VOICES/HELD/ECHO/PANICS monitor; DEBUG builds only). **Golden rule: if
PANICS > 0 or a note hangs, record exactly what triggered it — a stuck-note bug.**

- **SP-CLAIM (the gate — run first):** two cells, same pitches, different emitters
  (e.g. held chord → A, arp of the same notes → B). Set CLAIM on A: while A holds a
  pitch, that pitch on B is suppressed (A owns it). Claim another emitter → the first
  releases (radio). A MUTED claimant still reserves. Release all → no stuck notes.
  ✅ CLAIM good ⇒ the role family (leak%/FLATTEN/ALT) is cleared to build.
  **VERIFIED 2026-07-26 (single-claimant CLAIM works on device).**
- **SP-OUT (emitters A–D, MIDI OUTPUT):** MUTE foot toggles output; SOLO isolates
  (glow/dim, clears on stop); slider drag forces velocity (springs back); OCT ± shifts
  the emitter's output octave (clears on stop, out-of-range notes drop).
- **SP-IN (receivers A–D, MIDI INPUT):** THRU pip follows passthrough (muted THRU
  passes nothing); SOLO/OCT/slider as above (input side); LATCH = arm → chord → lift
  (sustains) → new chord replaces → disarm releases (physical holds persist) →
  mute-while-latched silent, unmute returns. Listen hard for stuck notes on every
  LATCH edge (its capture is Kernel-side, off-device tests can't reach it).
- **SP-LABEL:** both bands read A–D, titled MIDI INPUT / MIDI OUTPUT; cell chips A–D.
  Flag if either role column is cramped in the narrow band.

## RACK PASS — the emitter treatment matrix + the two-tier gate (2026-08-04)

Device screen for **THE RACK pass 1** (`AcceptanceCriteria-the-rack.md`; commit `c757f73`). The tabbed emitter
page is GONE — the emitter roles (CLAIM/DUCK/ALT) moved off the strip into a matrix opened from a single RACK
button, and a new per-emitter gate (RACK on/off) decides whether that emitter's armed treatments apply at all.
Only three treatments are wired this pass (OWNS=claim · KEY=duck · TURNS=alt); the rest are dimmed seats.

Reuse the STRIP-PASS rig via the HIDDEN DEV LOADER (long-press the "8×8 STATE" logotype ~1.2s). Two cells of the
SAME pitches on DIFFERENT emitters (held chord → A, arp of the same notes → B) is the workhorse for OWNS/KEY.
**Golden rule unchanged: if PANICS > 0 or a note hangs, record exactly what triggered it — a stuck-note bug.**
Toggle RACK/treatments both STOPPED and mid-HOLD and mid-PLAY; a gate flip must never strand a voice.

- **RK-STRIP (the clean strip — look first):** each MIDI OUTPUT strip shows ONLY OCT± · velocity fader · LIVE ·
  SOLO · **RACK**. No CLAIM/DUCK/ALT buttons remain. RACK reads lit (cyan fill) = board in path, or outlined =
  raw. Flag any leftover role button or a cramped RACK button in the narrow band.
- **RK-TOGGLE (the RACK button grammar):** a short TAP flips RACK lit↔outlined (does NOT open the matrix); a
  LONG-PRESS (~0.5s) opens the matrix (and must NOT also flip the toggle on release). Confirm both, on every
  emitter.
- **RK-GEO (drawn INSIDE the grid — the headline layout ask):** with the matrix open, the **chevron column-key
  row stays visible above it** and **both L/R row-select rails stay visible beside it** (only the 8×8 cell body is
  replaced). The receiver strips, emitter strips, verbs, and master stay LIVE around it. Then confirm all three
  close paths: **DONE**, the **PERFORM/EDIT toggle**, and a **scene switch** each dismiss the matrix. Flag if the
  chevron row or either rail disappears, or the panel spills past the cell area.
- **RK-OWNS (live — equals old CLAIM):** open the matrix; in the OVER OTHERS family, tap OWNS ON for A. While A
  holds a pitch, that pitch on B is withheld (A owns it). Turn A's LEAK knob up → B bleeds back at reduced
  velocity (the shadow), 0% = silent. Same intent as SP-CLAIM; monitor B for the suppression/shadow.
- **RK-KEY (live — the duck):** tap KEY ON for A, turn its AMOUNT knob. While A sounds, B/C/D's NEW note-ons
  arrive quieter (already-sounding notes never lurch); 100% ≈ a keyed gate. Monitor a target emitter's velocities.
- **RK-TURNS (live — turn-taking IN TIME across incoming notes):** the TURNS emitters take turns playing notes from
  ANY cell, handing off per onset MOMENT. Tap TURNS ON for A and B, then use **two independent cells — one → A, one
  → B** (both firing together, e.g. holds in one column). At **COUNT 1** they must ALTERNATE lap by lap — A sounds,
  then B, then A — NOT play together (the count-1 simultaneity bug is fixed). Raise the COUNT knob → each emitter
  DWELLS for that many moments before the turn passes. Confirm the total note count is conserved (each note routes
  to ONE member) and nothing hangs across the hand-off. (A single fan-out cell → A+B still ping-pongs per note.)
- **RK-CURVE (live — velocity re-map, THIS VOICE):** in the matrix, the THIS VOICE family now has a live **CURVE**
  row ("Re-maps velocity (soft↔hard)"). Tap CURVE ON for an emitter and turn its knob: **+** (right) makes it hit
  HARDER (low-velocity notes boosted toward loud), **−** softens, 0 = linear (no change). Play a dynamic passage
  and check the output velocities on the monitor bend the way the knob says; the column-header readout shows
  "CURVE +30". Confirm RACK-off on that emitter suspends the curve (raw velocity), and the master fader still
  overrides it. (FLOOR/CEILING are the dimmed "coming" detail.)
- **RK-GATE (the two-tier law — THE key new behaviour):** arm OWNS on A so B is suppressed (RK-OWNS). Now on the
  STRIP, tap A's **RACK OFF**. B's pitch RETURNS (the wire is raw) and A's matrix column header reads **RAW**.
  RACK back ON → suppression returns. Repeat the flip for KEY (ducking stops/returns) and TURNS (alternation
  stops/returns). **Ruling to feel + confirm (flagged):** RACK-off is a FULL-column bypass — turning A's rack off
  also stops A ducking/owning OTHERS, not just A's own shaping. Confirm that reads right; if you'd expect A to keep
  affecting others while raw, say so (it's a one-line change).
- **RK-LIVE-SENIOR (kill-switch law):** LIVE/SOLO stay senior to RACK. LIVE OFF on an emitter silences it
  completely whether its rack is in path or raw. RACK off ≠ silent (the emitter still sounds, just unprocessed).
- **RK-READ (the readout):** tap a matrix column header → its one-line social sentence shows only TRUE clauses
  ("OWNS · leaks 20%", "KEY: ducks others 40%", "TURNS ×2"); a rack-off column reads "RAW"; a bare emitter reads
  "a plain voice, no pedals armed."
- **RK-DIM (the coming seats):** MONO · FENCE · POCKET · LEAD/STANCE · ECHO · CHOKE · GOVERNOR are present but inert
  (recessive, no response to taps) — CURVE is now LIVE (see RK-CURVE). Touch a LIVE row → the detail strip beneath
  names that row's secondary params as "coming" (OWNS scope/lag · KEY targets/envelope · TURNS rotate/ring · CURVE
  floor/ceiling). Flag any dimmed row that reacts, or a matrix that reflows.
- **RK-PERSIST (state survives — persisted + undoable):** RACK state and the OWNS/KEY/TURNS toggles+chips are
  document state. Set some, then UNDO/REDO (three-finger or header) reverses them one step. Save the AUM session,
  reload → rack + treatments restored. An OLD session (saved before this build) must load with **every rack in
  path** and its existing claim/duck/alt unchanged (the nil-default).

Reporting: use the standard template — "RK-XXX: PASS/FAIL — [what was heard/seen] — monitor: [voice count,
pairing, stuck notes]". The AUM MIDI monitor is the truth for suppression/duck/turn claims; screenshots when a
pairing or velocity is disputed.
