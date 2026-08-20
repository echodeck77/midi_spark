# INSTRUCTIONS → Code — THE CONFIG SHEETS: doors · wires · the
# rack (Paul, 2026-08-20 — the legacy MIDI IN/OUT tabs RETIRE;
# nothing replaces them as tabs)

## THE STRUCTURE (the reframe: latch is not a page — it's the
## door's heart)
Three SHEETS, each launched by TAPPING ITS SUBJECT on the bottom
I/O console (config lives at the thing; the console is the map;
the banner stays performance-sacred; bottom-left stays reserve):
- **THE DOOR SHEET** — tap an in-strip's name chip (A–D).
- **THE WIRE SHEET** — tap an out-strip's chip.
- **THE RACK SHEET** — tap the rack's own chip (by the
  out-strips, per the two-verbs ruling).
Global rarities (MPE etc.) remain in the existing ⚙ cog.

## THE DOOR SHEET (the important one)
- Identity: cable · channel (OMNI/1–16) · nickname (optional,
  small — the system name A–D never changes).
- **THE MODE RADIO — LATCH · HOLD · REPLAY · KEYS** (one choice
  per door; Paul's four):
  - **LATCH** — notes TOGGLE in/out of the pool (press adds,
    press again removes; the ADD lineage). CLEAR = double-tap the
    strip's mode badge.
  - **HOLD** — CHORD DETECTION: a strike REPLACES the pool with
    the detected chord (the CHORD lineage; the strike-grouping
    window stays internal/default).
  - **REPLAY** — ★ THE DOOR LOOP AS A MODE: the door's input ring
    records always (retro by default — never arm); **PASSES: 1 ·
    2 · 4 · 8** selects how much history loops as the LIVING
    INPUT. This is the door-loop ferry's v1 shipping shape —
    reconcile with that walk, don't double-build. Overdub +
    playback transforms remain the ferry's later riders.
  - **KEYS** — the on-screen keyboard (typed pool; OCT± lives
    here; typing is latch-natured by construction).
- Per-door OCT± and velocity stay on the sheet (the strips keep
  their faders/S·M — performance stays on the console).

## THE WIRE SHEET
Channel · OCT± · (later: the wire's rack-tail settings). Rack
MEMBERSHIP stays a MARK on the strip itself, as ruled — the sheet
never duplicates it.

## THE RACK SHEET
The SETUPS radio (RACK 1–4, relocated here per the two-verbs
ruling) · the membership MATRIX (read-write mirror of the strip
marks) · the rack's treatment stack. One home for the rack's
whole truth.

## THE CONSOLE'S NEW DUTY — badges tell the mode
Each in-strip wears its MODE BADGE (**LATCH · HOLD · RPLY·4 ·
KEYS**) — the door's behaviour visible at the console, always
(display ⊇ offer). Tap the badge = open the sheet (config);
double-tap = the mode's quick act (LATCH: clear · REPLAY:
re-catch). No blind mode-cycling — four modes are too many to
flip unseen.
— design-side Claude

## §2 — SPACE-PREMIUM RESOLUTION (Paul, 2026-08-20: the strips
## keep every seat; HOLD is the opener)
- **TAP = the act · HOLD = the sheet** (the two-depth law — the
  macro/LOCK grammar, applied to the console). No new controls;
  the config-opener costs zero pixels.
- **The CH chip keeps both jobs**: label + **BLOCK toggle** (tap
  = block/unblock incoming; blocked = dimmed + struck — the door
  closed, visibly). Hold = the sheet.
- **The MODE badge is fully dynamic** — label AND tap-act follow
  the mode:
  - **LATCH** — tap: CLEAR the pool.
  - **HOLD** — tap: clear + await the next chord.
  - **RPLY·n** — tap: **RE-CATCH** (grab the last n passes NOW —
    the door loop's performance gesture, sheet-free).
  - **KEYS** — tap: raise/dismiss the keyboard popover.
  Hold any badge = the door sheet (where the mode radio + PASSES
  + channel live).
- Supersedes §1's "tap badge = sheet" — the acts outrank; the
  sheet moves behind the hold. Manual line: "Tap a door to use
  it; hold it to change what it is."

## §3 — THE FIFTH MODE: FILE (Paul, 2026-08-20)
- The door radio grows: **LATCH · HOLD · REPLAY · KEYS · FILE**.
  FILE = a loaded .mid loops as the LIVING INPUT.
- **THE LAW: A FILE IS A CABLE.** File events enter the door as
  ordinary incoming MIDI — the CH filter, BLOCK toggle, OCT,
  velocity all apply unchanged. Zero new plumbing downstream.
- **Playback**: beat-locked to the host clock (ticks→beats;
  tempo-agnostic, replay-safe: f(file, beat)); loops at the
  file's length, bar-aligned. **The badge act: tap = play/pause**
  (the dynamic-act table extends; hold = the sheet, where the
  file picker + name live).
- **Import**: the Files picker / share sheet (symmetric with the
  reel's export). Storage — copy-in vs bookmark — Code's call;
  flag document size if copy-in.
- **Kinship**: FILE and REPLAY are siblings (recorded input as
  the living input — one chosen, one remembered); the door-loop
  ferry's playback transforms (rate/transpose/quantize) apply to
  both when they land.
- **The circle, noted**: the reel's own SMF exports re-import as
  door material — capture the answer, feed it back as a question.
  The instrument can now listen to itself.
