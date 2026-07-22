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
- MidiSpark's plugin UI open (the diagnostic panel) — report its numbers when asked.

## Bridge regression (run after ANY kernel change) — 2 minutes

Hold a chord, transport playing:
- B1 Morph Gold 0→1 sweep: rate LADDER-STEPS (never glides); gate audibly shifts.
- B2 Morph Master: same effect patch-wide; individual morph positions preserved.
- B3 Swing 66: even/odd limp at the step level; **at exactly 50, timing
  indistinguishable from before** (monitor timestamps if in doubt).
- B4 Sync torture: tempo change mid-hold, loop a bar, relocate — no drift,
  no stuck notes. Stop with keys held — no stuck notes.

## Canned test sessions (loaded from the diagnostic panel)

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
Visual checks: diag panel, and the cell's FROM header flare once the grid is
reconciled.

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

## UI size checkpoints (GUI reconciliation gate)

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

"T_n: PASS/FAIL — [what was heard] — monitor: [anything odd] — diag panel:
[voices / refcounts / effColumn / emitted count]". Screenshots of the monitor
beat transcription when timing is disputed.
