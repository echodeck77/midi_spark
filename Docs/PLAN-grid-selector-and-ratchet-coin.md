# PLAN — Grid Selector §2/§3 + Ratchet-Coin randomness (Code-side, 2026-08-26)

Two incoming items processed from the ferry channel:
- **`FERRY-select-grid-activated.md`** — the go-signal that the grid-selector §2/§3 items (already in
  `Docs/SPEC-grid-selector.md`) are Paul's *current* wants. RATIFIED; sequencing = Paul's word.
- **`SPEC-ratchet-coin-randomness.md`** — filed to `Docs/`. Four RATCHET-COIN additions. Marked
  "captured, awaiting his word" — so PLANNED here but NOT a build order until Paul confirms.

---

## A · THE GRID (PICK) SELECTOR — §2/§3 (ratified, activated)
The 8×8 chain browser exists (`buildGridSelectorOverlay` + `buildGridSel*` in BuildPage.swift; QUANTIZE
STEP|INSTANT already shipped via `buildGridSelQuantStep`; DEALT = `Dice.rollEnsemble` ×8 = 64 on-demand;
the right column shows the selected chain read-only; COMMIT overwrites the arrival row). The changes,
sequenced smallest→largest, each device-verifiable:

1. **HEADER TOGGLE — EXCLUSIVE ON|OFF** (§2). ON = today (one lit cell, radio). OFF = taps TOGGLE
   (multiple cells lit); all lit cells LAYER into the audition voice collectively (their chains sound
   together against the input), the piece plays on, the governor watches the stack, every lit cell wears
   the live frame. New `@State buildGridSelExclusive`; the audition path rides N ephemeral colours (one
   per lit cell) instead of one. Contained — reuses the existing audition/ephemeral-colour machinery.

2. **PART BUTTONS = THE COMMIT** (§3.2). The page's right-edge 1–8 map to THE PARTS. Tap a cell (audition)
   → tap part N = that chain DEALS to part N (christening/valve laws; one visit builds the band). The
   COMMIT button RETIRES; CANCEL/DONE stays. Replaces `buildGridSelCommit`'s "overwrite the arrival row"
   with a "deal to part N" that routes through the existing part-deploy path; one undo.

3. **LAYERED DEALS** (§2/§3.2 reconciled). EXCLUSIVE-OFF + N lit + a part button → the combination lands
   as that part's ROWS (arrival row then next empties, one undo). Builds on 1+2.

4. **RIGHT COLUMN = BROWSE CONTEXT ONLY** (§3.3). Under the read-only selected chain + its eye, ANOTHER
   instance of the receiver + emitter toggles steers WHICH door feeds / WHICH wire sounds the AUDITION.
   **Pin:** these are audition-only — on deal, the receiving PART's own I/O governs (no second authority).
   New browse-scoped @State (not written to any colour); the audition publish reads them.

5. **PREGEN CORPUS** (§3.1, the biggest). Chains generate IN BULK in the background (seeded, deterministic;
   a pool of hundreds→thousands). DEALT draws 64 INSTANTLY from the pool; RE-DEAL = a fresh shuffle; a
   background queue tops it up. Feeds preset-mining later. RIDER: profile the live-roll slowness first
   (root cost worth knowing even though pregen sidesteps it). Needs an off-main generation queue + a
   corpus store — the one item that's real infrastructure, not a UI slice.

**FLAGGED, NOT RATIFIED (Paul's word):** HOLD a part button = preview that part's current contents (spring
grammar); part buttons wear OCCUPIED (filled) vs EMPTY (hollow) states (banking chip grammar).

**Recommended order:** 1 → 4 → 2 → 3 (the interaction set), then 5 (the corpus) as its own effort. 1/2/3/4
are UI-only (device-eye owed); 5 has an engine/threading component (profileable off-device).

---

## B · RATCHET COIN — SHAPING THE DICE (captured, awaiting Paul's word)
Four additive-Optional fields on the RATCHET-COIN path (`rtcMode == .coin`), all seeded/replay-safe,
nil ⇒ today's behaviour byte-identical. Engine + `sliderLane`/chip UI; verifiable off-device via
RouterTests + fuzz. Filed spec: `Docs/SPEC-ratchet-coin-randomness.md`.

1. **SIZE WEIGHTS** (§1) — a `sliderLane` over the counts 2·3·4·6·8 (bar height = that size's odds);
   REPLACES the SIZE LO/HI rows. New `rtcSizeWeights: [Int]?` (5 weights). Engine: `rtcCoinCount` becomes a
   seeded WEIGHTED pick over {2,3,4,6,8} instead of uniform LO…HI. Reuses the shipped `sliderLane` widget
   (5th consumer). Migrate LO/HI → a flat weight span for display; write the new field on first touch.

2. **REFIRE GAP** (§2) — `rtcGap: Int?` (0–4): after a fire, the coin can't fire for N steps. ⚠ REPLAY-SAFETY:
   this introduces a per-row SEQUENTIAL dependency (the gap depends on the last fire, which depends on prior
   rolls) — NOT a per-step-independent function. Must be realised as a pure deterministic SCAN of the coin
   from the row/loop origin (replay-exact, no accumulated cross-render state), matching the "derived, never
   accumulated" invariant. The scan is bounded (≤ the row's step count). Its sibling MAX-STREAK folds in here.

3. **QUOTA** (§3) — `rtcQuota: Int?` (0=FREE · else ~2/~3/~4): a rough onset budget per row. Same replay-safety
   note as GAP — needs the deterministic per-row scan (count fires so far, cut once the budget's met, seeded).
   GAP + QUOTA share one scan pass.

4. **ODDS FROM: FIXED | VELOCITY** (§4) — `rtcOddsVel: Bool?`: fire-odds scale with the incoming note's
   velocity (soft = clean, accents erupt). One chip; the odds multiply into the existing `rtcCoinFires` roll
   at the per-note velocity. Independent of the scan.

**All four compose** (weights = WHAT size · gap/quota = WHEN/how often · velocity = WHO decides). Downbeat
protection falls out of GAP + ROTATE — no chip. **The real work is the deterministic GAP/QUOTA scan** (2+3);
1 and 4 are contained. Recommend: confirm with Paul, then build 1 (weights, clean win + presentation cleanup)
→ 4 (velocity) → the 2+3 scan (the delicate replay-safe pair) with tests + fuzz.

---

## Sequencing
Both sets are Paul-sequenced. Grid §2/§3 is UI-heavy (device-eye owed per increment); ratchet-coin is
engine (off-device test-verifiable) but awaits Paul's ratification word. Neither blocks the other.
