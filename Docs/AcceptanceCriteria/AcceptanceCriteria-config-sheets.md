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

## §4 — ROWS WEAR THEIR EARS (Paul, 2026-08-20: "the door info
## isn't per row" — the two grains separated)
- **The mismatch, named**: the console = the DOORS' OWN config
  (infrastructure — global, correct as-is). Door OWNERSHIP is
  per-row — and nothing on the rows showed it. Two grains, one
  surface: the felt wrongness.
- **THE ROW DOOR BADGE**: each row's edge wears a small letter
  (A–D, in the door's tint) — per-row ownership always visible.
  The two-depth law applies:
  - **TAP = cycle the row to the next door** (boundary-deferred;
    the input-side twin of the output-swap experiment — "what
    would this row sound like hearing the pads?" in one touch).
  - **HOLD = the row's I/O popover** (door + emitter pickers for
    THAT row; the part-level defaults shown as the inherited
    state).
- **The EYE stays inspection** — it shows, it never sets; the
  badge is the control. Eyes keep their meaning everywhere.
- The console strips + sheets (§1–3) are unchanged: doors
  configured at the console; rows re-eared at the rows. Each
  grain at its own home.

## §5 — CORRECTION (Paul, 2026-08-20: the eye ruling reversed;
## the layer model established)
- **§4's eye refusal is WITHDRAWN.** Paul's intent: the grid eyes
  open A MORE SPACIOUS VERSION of each grid (yet to be built) —
  a view-zoom, not inspection. My "eyes never set" law was the
  window-popup lineage misapplied. Author intent governs.
- **THE LAYER MODEL (Paul's, now the record)**:
  - **The console = the RAW-INPUT layer** — the sliders are the
    material's trim, door-adjacent, pre-derivation. Not a
    performance surface, and correctly so.
  - **The compact grids = PERFORMANCE** — chrome-quiet, no
    config furniture added.
  - **The eye's SPACIOUS VIEW = the detail layer** — where
    per-row door info, row I/O pickers, and (later) seat-grade
    controls get the room they need.
- **§4 revised accordingly**: the ROW DOOR controls live in the
  EXPANDED view (the eye is the access path — Paul's original
  suggestion, correct). The compact grid may carry at most a
  minimal door-tint edge per row (visibility only, no control);
  even that awaits his glass. The two-depth badge grammar from
  §4 transfers into the spacious view intact.

## §6 — THE TWO BUTTONS (Paul, 2026-08-20: the entry points,
## placed)
- **Two stacked buttons, bottom of the page**: **[MIDI CONFIG]**
  on top, **[RACK CONFIG]** below — seated LEFT of the receiver
  strips, RIGHT of the record/reel button, below the MIDI chain
  + emitters panel. The dead corner earns its keep.
- **MIDI CONFIG** → the MIDI sheet: the four DOORS (§1's door
  sheet content — mode radio LATCH·HOLD·REPLAY·KEYS·FILE, cable/
  channel, per-door sections) + the four WIRES. One sheet, both
  sides of the plumbing.
- **RACK CONFIG** → the rack sheet (§1: the setups radio · the
  membership matrix · the treatment stack).
- **Reconciliation**: the buttons are the PRIMARY, discoverable
  entry. §2's strip grammar survives as shortcuts (tap badge =
  the act · hold = jump straight to that door's section of the
  sheet). Visible furniture for finding; gestures for speed.

## §7 — SPACIOUS SHEETS + TRUTHFUL BUTTONS (Paul, 2026-08-20)
- **THE SHEETS ARE THE TEACHING SURFACE**: generous spacing, one
  section per door, and **every mode and control carries its
  plain-English description IN PLACE** (not hidden in tooltips) —
  e.g. "LATCH — notes toggle in and out of the held pool" ·
  "REPLAY — loops the last n passes of what you played" · "FILE —
  a MIDI file plays as this door's input." **Source text = the
  friendly-labels copy pass** (already written; reuse verbatim,
  extend for the new modes). The chrome-quiet law's stated
  exception: set-once surfaces may be wordy — config teaches,
  performance stays silent (the cog precedent).
- **THE BOTTOM BUTTONS BEAR THEIR STATE** (the chip-never-lies
  law):
  - Each strip's LATCH button = the DYNAMIC MODE BADGE (§2
    ratified): **LATCH · HOLD · RPLY·4 · KEYS · FILE** — the
    door's truth, always visible.
  - **[RACK CONFIG] wears the active setup**: "RACK · 2" — which
    configuration is live, readable from across the room; the
    strip RACK marks keep showing membership as ruled.
  - [MIDI CONFIG] stays label-only (no single state to bear;
    the badges beside it carry the per-door truth).

## §8 — NAMING (Paul, 2026-08-20: no metaphors — CANDIDATES ONLY,
## NOTHING RATIFIED; Paul decides)
**"Door" → lean: INPUT.** The strips already say MIDI IN — the
literal name was there all along. Sheet = "MIDI INPUTS"; per-row
badge = "INPUT: A"; the radio = "INPUT MODE" (LATCH · HOLD ·
REPLAY · KEYS · FILE — all already literal). Alternates:
RECEIVER (Paul's prose word; more technical) · SOURCE (collides
with MOD's SOURCE — avoid). "Door" retires to design-side slang.

**"Rack" → lean: OUTPUT CHAIN.** Literal (a processor chain on
the outputs) AND consistent — the sibling of MIDI CHAIN, one
vocabulary at two positions: "play this MIDI chain" per row, an
OUTPUT CHAIN on the wires. Button reads "OUTPUT CHAIN · 2" (the
active setup); membership mark = a chain-link glyph; the four
configs = SETUP 1–4. Alternates: OUTPUT PROCESSORS (zero reuse
of "chain," longer) · OUTPUT FX (rejected — implies audio) ·
BUS (rejected — a metaphor again, and collides with the old bus
dots).

**Knock-ons when decided**: user-facing text only — code
identifiers never rename (the standing law); the §0 "door chips"
in the melody suite become INPUT chips; the door-loop ferry's
prose updates at capture. The buttons: [MIDI CONFIG] stands (or
MIDI SETUP — noting SETUP would then collide with the output
chain's setups; CONFIG is safer).

## §9 — NAMES RATIFIED + THE SHORT FORMS (Paul, 2026-08-20)
- **MIDI INPUT / MIDI OUTPUT** — ratified (the sheets: "MIDI
  INPUTS" / "MIDI OUTPUTS"; per-row badge "INPUT: A"; the radio
  "INPUT MODE"). "Door" retires to design slang.
- **OUTPUT CHAIN** — ratified, with the size ladder:
  - Full contexts (the sheet header, the manual): **OUTPUT CHAIN**.
  - The bottom config button: **OUT CHAIN · 2** (the active setup
    borne, per §7).
  - **The strip button: CHAIN** — on an output strip, context
    supplies the qualifier ("this output's chain"); 5 chars fits
    the old RACK seat. If glass ever finds it colliding with the
    row-level MIDI chain, the fallback = the link glyph (🔗) +
    state, zero words.
  - The four configurations: **SETUP 1–4**.
- Ripple: user-facing text only; identifiers stand (the law).
