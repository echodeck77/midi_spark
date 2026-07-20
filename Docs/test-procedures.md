# Test procedures — device verification playbook

Claude Code cannot hear MidiSpark or see AUM. Every engine change is verified by
the human on the iPad, guided by these procedures. Keep them updated as features
land; when asking the human to test, quote the relevant procedure by name.

## Standing AUM setup

- MidiSpark as a MIDI Processor; keyboard → MidiSpark input.
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

## Canned test sessions (T1–T8; loaded from the diagnostic panel)

Each lists: the grid it builds → what correct behaviour sounds/reads like.

**T1 — single ARP.** Gold ARP at (col 0, row 0), bus A.
→ Ascending 1/16 arp on Synth1 only, only while column 0 is active (1 step in 8).
Monitor A: clean on/off pairs, silence for the other 7 steps.

**T2 — chain.** Col 0: gold ARP (row 0, ▾ on, no letters) → cyan cell (row 1, bus A).
→ Sound leaves ONLY through row 1 (spec §2.3). Row 0 alone must be silent on
every bus. With row 1 as identity/ARP, output reflects processing of the feed.

**T3 — +SRC merge.** As T2 but row 1 has +SRC on.
→ Row 1's input = feed ∪ source: audibly denser than T2 with the same chord.

**T4 — fan-out.** One ARP cell with buses A and B both lit.
→ Identical simultaneous streams on Synth1 and Synth2; monitors A and B show
duplicate events, independently well-paired.

**T5 — muted-feeder reroute.** As T2 but the feeder (row 0) muted.
→ Row 1 reverts to SOURCE input (§2.1): plays as if unchained. Diag panel is the
visual check until the wiring UI exists.

**T6 — OUT CH stamping.** Two cells: one Colour INHERIT, one OUT CH = 5, both bus A.
→ Monitor A shows the first on the keyboard's original channel, the second on
ch 5. (Synth1 set to omni to hear both.)

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

## Milestone gates

- Router commits 1–6 map to T-cases per docs/router-design.md; run the bridge
  regression at each.
- `v0.3-router` tag requires: T1–T8 pass + B1–B4 pass + 10-minute soak
  (chord held, tempo/loop changes, test-session switching mid-play) with zero
  stuck notes and stable memory (Xcode gauge).
- Acceptance items (spec §11) formally close only when testable end-to-end;
  note partial coverage honestly (e.g. item 4 is "engine-verified via T2/T5,
  UI-verified at step 5").

## Reporting template (what the human sends back)

"T_n: PASS/FAIL — [what was heard] — monitor: [anything odd] — diag panel:
[voices / refcounts / effColumn / emitted count]". Screenshots of the monitor
beat transcription when timing is disputed.

## Verification log (device-confirmed results; newest first)

Record each device pass/fail here so the doc reflects what is actually proven,
not just what the plan expects. Cases not listed have NOT been run yet.

### 2026-07-20 — router commits 0–3

| Case | Result | Commit | Notes |
|---|---|---|---|
| B1–B4 (bridge regression) | PASS | 4242982 | run after the alt-seam + test-session groundwork |
| Panel: snapshot gen +1 per session load | PASS | 4242982 | rebuild coalescing intact (one publish per load) |
| T1 (single ARP) | PASS | 98ce8a9 | arp on bus A only while column 0 active — 1 step in 8, silence elsewhere |
| T6 (OUT CH), INHERIT half | PASS | ca1e359 | held on a non-default channel → arp emits on that channel; panel EMIT shows it |
| B4 (sync torture / no stuck notes) | PASS | 98ce8a9 | re-run after the note-off rewrite: tempo/loop/relocate + stop-with-keys-held, zero stuck notes |

### 2026-07-20 — router commits 4–5b (chains)

| Case | Result | Commit | Notes |
|---|---|---|---|
| T1 (single ARP) | PASS | 6942a76 | regression through the Router extraction + poly voice table |
| T2 (chain, mirror) | PASS | 6942a76 | arp emitted from row 1; row 0 silent (feeds, no letter lit) |
| T3 (+SRC merge) | PASS | 6942a76 | denser than T2: mirrored arp + held source chord, both bus A |
| T5 (muted-feeder reroute) | PASS | 6942a76 | feeder muted → row 1 holds the SOURCE chord; feed dark |
| T6 (OUT CH), full | PASS | 6942a76 | both halves now live: INHERIT on original ch + OUT CH on ch 5 |

Note: T6's OUT CH = n half is now exercised (two unfed arps on bus A), upgrading
the earlier INHERIT-only pass to a full T6.

**Not yet verified** (blocked on the commit that implements them):
- T4, T7 (fan-out, collision refcount) — commit 6.
- T8 (PHASE modes) — commit 7.
- `v0.3-router` gate (T1–T8 + B1–B4 + 10-min soak) — not yet met.
