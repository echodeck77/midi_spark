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
