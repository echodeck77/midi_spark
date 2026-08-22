# THE STOREFRONT SPLIT + the catalog picker — design ruling

**Ferried in from design-side Claude; absorbed 2026-08-22 (authored 2026-08-20).
Front-end ruling — supersedes the one-seat interface rulings for TUTTI/RTC/etc.
ENGINE HALVES STAND; interface halves reverse. Codable type names NEVER rename (the law).
Not yet built. Companion to `AcceptanceCriteria-velocity-processor.md`; the engine-truth
inventory it depends on is being compiled Code-side (see the outbox reply).**

---

# INSTRUCTIONS → Code — ONE ENGINE, MANY DOORS: the storefront
# split + the catalog picker (Paul, 2026-08-20 — supersedes the
# one-seat interface rulings for TUTTI/RTC/etc.; engine halves
# STAND, interface halves reverse. Author's glass outranks roster
# economy.)

## 1. THE STOREFRONT SPLIT (front-end only; Codable types never
## rename — the law)
Multi-mode stages become MULTIPLE PICKER ENTRIES — each card
opens the stage PRE-SET to its mode, showing ONLY that mode's
face (the mode radio demotes to a small in-panel chip, or hides;
Paul's glass picks). Nothing lives in a sub-tab, because each
storefront IS its mode. The split list:
- **MOD → five cards** (the biggest offender): SHAPE → "LFO" ·
  FOLLOW → "FOLLOWER" · STEPS → "STEP MOD" · STRIKE → "HIT
  ENVELOPE" · EXTERN → "CC IN" (names = Paul's call; these are
  leans, plain per the no-metaphors ruling).
- **TUTTI → two**: "TUTTI COIN" · "TUTTI PATTERN" (or Paul's
  plainer names — "SOLO/CHORD COIN"?).
- **RATCHET → three**: RATCHET · RATCHET COIN · RATCHET PATTERN.
- **WEAVE → four** (LADDER · HARMONIC · DRAWN · EUCLID as cards).
- VELOCITY/BURST inherit the pattern when they land (SCALE and
  PATTERN as separate cards from day one).
Documents load mode-agnostically (a saved TUTTI opens showing its
stored mode's face; the card chosen only sets the DEFAULT).

## 2. THE CATALOG PICKER (the selector as the teacher)
- Each entry: **NAME + one-line plain description** — sourced
  from the friendly-labels pass ("what it does to the sound"),
  extended to cover every card.
- **Grouped by musical intent** (lean, Paul tunes): RHYTHM (ratchets,
  euclid, burst, weave…) · MELODY (arp, riff, cascade, glide…) ·
  HARMONY (harmonize, tutti, split…) · DYNAMICS (velocity,
  humanize…) · CONTROL (LFO, follower, CC in…) · TIME (echo,
  shift, length…).
- Spacious per §7's teaching-surface law: config surfaces may be
  wordy; the picker is one.
- v2 spice, parked: a tiny window-thumbnail per card (the mode's
  characteristic pattern drawn — the catalog you can READ as
  music).

## 3. The panel rider
Every stage panel carries its one-line description as a
sub-header (the §7 teach-in-place law extended from the sheets to
the stages). The author should never need the manual; neither
should anyone else.
— design-side Claude

---

> **✅ PAUL'S FINAL SHAPE 2026-08-22 (settles the same-day back-and-forth — this is what's built):**
> the picker shows the PER-MODE SPLIT cards below (RATCHET/BURST/TUTTI/WEAVE/MOD split; the modes
> are VISIBLE at selection). Each card FIXES its mode on the new slot. The in-editor MODE/SOURCE
> radio is REMOVED — the card decides the mode; to change it you pick a different card. The chosen
> mode is WRITTEN onto the chain box AND the editor title, abbreviated (e.g. "WEAVE HARM", "MOD
> LFO", "RATCHET COIN", "TUTTI PAT", "BURST ONCE"). This realises the design's original storefront
> intent ("each storefront IS its mode; the radio hides") plus Paul's box-label ask. Built:
> `BuildPage.buildCatalog` (31 cards) + `buildProcLabel`; the 5 GridUI mode radios dropped. RIFF +
> VELOCITY stay future/unbuilt. (The card names + blurbs below are the built set.)

# THE RATIFIED CARD SET (design-side, 2026-08-22 — ✅ RATIFIED BY PAUL 2026-08-22; PICKER SIMPLIFIED to one-per-processor, see banner)

**31 cards · 6 groups. Names/one-liners are DISPLAY-LAYER only (Codable IDs frozen).
✅ RATIFIED BY PAUL 2026-08-22 — these names + groups + one-liners are the build target.
Format: CARD NAME — catalog one-liner (also the panel sub-header unless noted).** Reconciled
against the Code-side engine-truth inventory (the drift flags D1–D8 were absorbed — see notes
inline).

**MELODY**
- **ARP** — Walks the held chord one note at a time.
- **CASCADE** — Builds the chord up one note at a time, holding each.
- **STRUM** — Rolls the chord in like a guitar rake.
- **GLIDE** — One sliding voice: small steps bend, big leaps jump. (panel adds: "One slot,
  one output — match BEND RANGE to your synth." — the D6 truth)

**HARMONY**
- **HARMONIZE** — Adds up to three tuned voices to every note.
- **TUTTI COIN** — Flips a coin each step: the whole chord, or one note.
- **TUTTI PATTERN** — Paints the chord's shape per step — full, top two, one note, rest.
  (TUTTI siblings homed together in HARMONY, overriding the RHYTHM lean.)
- **SPLIT** — Keeps only part of the chord: top, bottom, or a range.
- **DRONE** — Holds the chord as a sustained pad. (panel adds the D5 dual truth: "Alone: one
  continuous hold across columns. In a chain: re-strikes each column.")

**RHYTHM**
- **RATCHET** — Re-strikes the whole chord in fast rolls, every step.
- **RATCHET COIN** — Rolls by chance: some steps burst, some hit plain.
- **RATCHET PATTERN** — Paint which steps roll, and how many hits each.
- **BURST** — One accelerating (or slowing) roll per step.
- **BURST COIN** — A roll by chance: some steps fire, some rest.
- **BURST PATTERN** — Paint where rolls start and how far they stretch. (D2: split NOW ✓)
- **EUCLID** — Spreads K hits evenly around the cycle.
- **WEAVE LADDER** — Every note pulses at its own speed: bass slow, top fast.
- **WEAVE HARMONIC** — Note speeds follow the harmonic series: 1×, 2×, 3×…
- **WEAVE DRAWN** — You set each note's pulse speed by hand.
- **WEAVE EUCLID** — Each note gets its own euclidean rhythm, denser on top.
- **PASSES** — Plays only on the laps you choose (1–4). (PASSGATE display remap ✓ kept)
- **CHANCE** — Lets notes through by dice roll — the same roll every loop.

**DYNAMICS**
- **HUMANIZE** — Loosens the timing and softens the hits: a human touch. (D3-honest: late +
  duck only)
- *(future)* **VELOCITY SCALE** — Squeezes or expands how hard notes hit.
- *(future)* **VELOCITY PATTERN** — Paints accents and ghost notes across the bar.

**CONTROL** (shared sub-header on all five: "Moves synth controls — makes no notes of its own.")
- **LFO** (MOD/SHAPE) — A wave moving a synth knob: sweeps and wobbles.
- **FOLLOWER** (MOD/FOLLOW) — Your playing becomes the control: busier = higher.
- **STEP MOD** (MOD/STEPS) — Draw an 8-step pattern that moves a knob.
- **ENVELOPE** (MOD/STRIKE) — A rise-and-fall sweep each time the cell starts. (D4: per-cell-
  entry, so no "per-hit" claim; the "HIT ENVELOPE" lean was withdrawn.)
- **CC IN** (MOD/EXTERN) — Reads an incoming knob and re-ranges it onward.

**TIME**
- **ECHO** — Repeats each note, fading away like a delay.
- **SHIFT** — Drags the whole chord behind the beat: laid-back. (D3 ✓ late-only)
- **LENGTH** — Shapes how long each step rings: staccato to ties.

**Drift dispositions:** D1 RIFF = unbuilt, NOT a card (unratified shelf). D2 BURST = split now.
D3/D4/D5/D6 = copy made honest per flags. D7 = catalog silent on chain-position; the manual owns
the two exceptions. D8 VELOCITY macro-default = DEFERRED (macros stay opt-in; the "DYNAMICS
fader" is a suggested manual binding, not a mechanism). SPLIT/ECHO/EUCLID/LENGTH = one card each
(agreed). SHIFT+LENGTH homed in TIME.

**Ratified 2026-08-22 (Paul):** the whole set — names, groups, one-liners, the CONTROL names
(LFO/FOLLOWER/STEP MOD/ENVELOPE/CC IN) — is approved and is the build target. The picker rework
(grouping + descriptions + the 31-card split, each split card pre-setting its mode) is the
net-new UI, now greenlit. Engine untouched (the split only sets a default mode on add; Codable
IDs frozen). RIFF + VELOCITY remain the two future/unbuilt entries.
