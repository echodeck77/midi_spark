# AcceptanceCriteria — RTC (RATCHET) gains the MODE radio (ferry-captured 2026-08-16)

**STATUS: CAPTURED, NOT BUILT.** From `SPEC-rtc-mode-radio.md` (design-side Claude, Paul 2026-08-16: "ratchet
sporadically on arp hits — regular and random"). The TUTTI MODE-radio precedent replicating to its first sibling.
Subordinate to Paul's direct word (direct instructions supersede ferry content).

## RTC — MODE: ALL | COIN | PATTERN
- **ALL** — today's behaviour (every step bursts). Default; migration-invisible.
- **COIN** — a seeded **CHANCE %** per hit: each arp hit rolls ratchet-or-plain (Paul's "random"). Optional
  **COUNT RANGE** (e.g. 2–4): the bursts themselves vary. Seeded per step index — replay-exact.
- **PATTERN** — the 8-slice row holding **PER-SLICE COUNTS**: 0 (plain) · 2 · 3 · 4 — authored trap-rolls
  painted across the bar; pick-then-paint; the **ROTATE gesture** applies (the roll pattern walks). RATE lane per
  the slice family.
- Row 2 reshapes per mode; both configs persist (the TUTTI/CC law). The window shows bursts as clustered ticks — legible.

## The TODAY answer, for the manual (no build required)
Sporadic-at-column-grain is the instrument's own grammar already: mint a ratcheted sibling (row-MUTATE), stack
both as rungs, and THE PICKS ARE THE SPORADICITY — plain·plain·ratchet·plain across columns is regular; re-picking
live is random as the finger. Manual line: "For sometimes-ratchet: two rungs and your picks — or one chip and the coin."
— design-side Claude

## Code note (Code, 2026-08-16)
Highly tractable — this is exactly the machinery just built: COIN = a seeded per-hit chance (like `chancePasses` /
`tuttiIsTutti`, seeded per step/hit index) + an optional count RANGE; PATTERN = an 8-slice per-slice-count paint grid
(like TUTTI PATTERN / LENGTH's slice painters) + ROTATE + a RATE lane. `emitRatchetRow` already strikes the whole
chord per tick; the mode gates whether/how each step bursts. Reuses `WeaveMode`/`TuttiMode`-style enum + the paint
UI + the foldable-param plumbing. See CLAUDE.md status for the TUTTI/LENGTH/WEAVE precedents.
