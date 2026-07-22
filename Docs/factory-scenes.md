# Factory scenes 1–16 — the scene selector's contents

PURPOSE: the scene strip's sixteen slots ship with these scenes. They are a
curriculum: each slot is musical on its own AND introduces exactly one new
capability; slot 16 uses nearly everything. They replace the test-session
buttons in the strip for release builds (TestSessions T1–T16 remain loadable
via the diagnostic panel — these are NOT those; do not merge them).

IMPLEMENTATION: `SceneFactory.swift` returning the sixteen documents (one
scene each until multi-scene documents exist). Field names per the repo's
Models.swift; numbering below is 1-based for humans (columns C1–C8, rows
R1–R8) — convert to 0-based in code. Notation: `⇐MIDI` inputRow=nil,
`⇐MIDI ch5` inputRow=nil + inputChannel=5, `⇐R2` inputRow=row2, `→A B` buses,
`(B: …)` the Colour's ALT state, `Tn` transpose. Unlisted params take the
Colour-type defaults. Bus channels default [1,2,3,4] unless stated.
Every scene must load with zero warnings except where a warning is the lesson
(slot 15). Verify each by ear against its LISTEN line before shipping.

---

## 1 · FIRST LIGHT
The instrument's "hello": one arp, one step, mostly silence.
GLOBAL: step 1/2, swing 50.
COLOURS: gold = ARP UP 1/16, 1 oct, gate 60.
GRID: C1R1 gold ⇐MIDI →A.
LISTEN: a held chord arpeggiates for one step in eight, then seven steps of
silence. The grid IS time. TEACHES: cells, columns, the pass.

## 2 · FOUR ON THE FLOOR (OF EIGHT)
Rhythmic placement — the same voice, four rooms.
GLOBAL: step 1/2, swing 50.
COLOURS: gold = ARP UP 1/16, 1 oct.
GRID: C1R1, C3R1, C5R1, C7R1 — all gold ⇐MIDI →A.
LISTEN: on-off-on-off across the bar; rests are notes. TEACHES: columns as
rhythm; painting the same Colour many times (instances).

## 3 · CALL AND ANSWER
Two voices trade fours.
GLOBAL: step 1/2, swing 50.
COLOURS: gold = ARP UP 1/16 · azure = ARP DOWN 1/16.
GRID: C1–C4 R1 gold ⇐MIDI →A · C5–C8 R1 azure ⇐MIDI →B.
LISTEN: rising phrase answers falling phrase; A and B are different synths.
TEACHES: Colour identity; two emitters.

## 4 · STAIRCASE
Melody from transposition — one chord climbs.
GLOBAL: step 1/2, swing 50.
COLOURS: gold = ARP UP 1/16 T0 · mint = same T+5 · azure = same T+7 ·
violet = same T+12.
GRID: C1,C2 gold · C3,C4 mint · C5,C6 azure · C7,C8 violet — all R1 ⇐MIDI →A.
LISTEN: the held chord walks I–IV–V–octave over the bar without touching the
keys. TEACHES: per-Colour transpose as harmony.

## 5 · THE LIMP
Swing plus ratchets — groove enters.
GLOBAL: step 1/2, **swing 62**.
COLOURS: gold = ARP UP 1/16 · vermilion = RATCHET ×3 1/8.
GRID: C1,C3,C5,C7 R1 gold ⇐MIDI →A · C2,C4,C6,C8 R1 vermilion ⇐MIDI →A.
LISTEN: lopsided strut; the ratchet stutters land late and heavy. Drag the
SWING slider live. TEACHES: swing as step-phase warp; RATCHET.

## 6 · CHAIN OF COMMAND
The first vertical: process the processor.
GLOBAL: step 1/2, swing 50.
COLOURS: violet = ARP UP-DN 1/8, 2 oct (no buses — a pure engine) ·
vermilion = RATCHET ×2 1/16.
GRID: C1–C8: R1 violet ⇐MIDI (no buses) · R2 vermilion ⇐R1 →A.
LISTEN: the arp is audible ONLY through the ratchet chopping it; mute R1's
column feeders (column-button MUTE) and hear children revert to raw chord.
TEACHES: references; sound leaves only through cells with emitters; reroute.

## 7 · TWO HANDS
Input channel filters — the grid splits the keyboard.
GLOBAL: step 1/2, swing 50. (Set a keyboard/split to send ch1 and ch2.)
COLOURS: gold = ARP UP 1/16 · wine = ARP DOWN 1/4, 1 oct, gate 90.
GRID: all C1–C8: R1 gold ⇐MIDI **ch1** →A · R2 wine ⇐MIDI **ch2** →B.
LISTEN: left-hand bass (ch2) walks slow and long on B; right-hand chord (ch1)
sparkles on A; neither hears the other. TEACHES: IN CH filters;
multi-controller play.

## 8 · THE FAN
One engine, three treatments — the tree.
GLOBAL: step 1/2, swing 50.
COLOURS: violet = ARP AS-PLAYED 1/8, 2 oct (no buses) ·
vermilion = RATCHET ×3 1/16 · magenta = CHANCE 65% · azure = ARP UP 1/16.
GRID: C1–C8: R1 violet ⇐MIDI · R2 vermilion ⇐R1 →A · R3 magenta ⇐R1 →B ·
R4 azure ⇐R2 →C.
LISTEN: three synths share one melodic brain — A chops it, B gambles on it,
C re-arpeggiates the chopped version (a grandchild). Mute R1: the whole tree
falls back to the raw chord at once. TEACHES: fan-out; depth; shared source.

## 9 · EVERY OTHER TIME
The pass dimension — music longer than the bar.
GLOBAL: step 1/2, swing 50.
COLOURS: gold = ARP UP 1/16 · teal = PASS (passes every 2nd) · wine = PASS
(passes every 4th) T−12, gate 100.
GRID: C1–C8 R1 gold ⇐MIDI →A · C1,C5 R2 teal ⇐MIDI →B ·
C1 R3 wine ⇐MIDI →C.
LISTEN: A is constant; B breathes in every second pass; C tolls a sub-octave
once every four bars. Watch the PASS dots. TEACHES: PASSGATE; 2- and 4-bar
form from a 1-bar grid.

## 10 · DICE MUSIC
Generative — the same scene never plays twice.
GLOBAL: step 1/2, swing 54.
COLOURS: magenta = CHANCE 70% · blush = CHANCE 35% T+12 · gold = ARP RANDOM
1/16 · vermilion = RATCHET ×4 1/16.
GRID: C1–C8 R1 gold ⇐MIDI (no buses) · C1–C8 R2 magenta ⇐R1 →A ·
C2,C4,C6,C8 R3 blush ⇐R1 →B · C4,C8 R4 vermilion ⇐R2 →A.
LISTEN: a familiar shape that never repeats exactly; sparse octave ghosts on
B; occasional double-gambled ratchet bursts. TEACHES: CHANCE; probability as
arrangement.

## 11 · LONG WALK
Phase modes — phrases longer than a step.
GLOBAL: step 1/2, swing 50.
COLOURS: violet = ARP UP 1/16, 2 oct, **phase LEGATO** ·
teal = ARP UP-DN 1/8T, 1 oct, **phase FREE** · gold = ARP UP 1/16 (RETRIG).
GRID: C1–C4 R1 violet ⇐MIDI →A (a 4-column run) · C5–C8 R2 teal ⇐MIDI →B ·
C5–C8 R1 gold ⇐MIDI →A.
LISTEN: the violet phrase unfolds ONCE across four columns (never restarting
per step); the teal triplet figure drifts against the grid, catching a
different slice each pass; gold restarts crisply every step for contrast.
TEACHES: RETRIG vs LEGATO vs FREE.

## 12 · UNDERTOW
Deep water — a four-stage chain with a bright tap.
GLOBAL: step 1/1, swing 50.
COLOURS: indigo = ARP UP 1/8, 2 oct (no buses) · magenta = CHANCE 80% ·
vermilion = RATCHET ×2 1/16 · wine = PASS gate 100 T−12 ·
chartreuse = ARP UP 1/32, 1 oct, T+12.
GRID: C1–C8: R1 indigo ⇐MIDI · R2 magenta ⇐R1 · R3 vermilion ⇐R2 →A ·
R4 wine ⇐R1 →B · R5 chartreuse ⇐R3 →C.
LISTEN: A is the chain's end product (arp→gambled→chopped); B doubles the raw
engine an octave down, slow and heavy; C is a glittering ×2-speed shadow of
the CHAIN OUTPUT — a great-grandchild. TEACHES: depth; taps at every stage.

## 13 · TWO ROOMS
Routing as arrangement — one grid, a whole rig.
GLOBAL: step 1/2, swing 50. BUS CHANNELS: A=1, B=2, C=3, D=10.
COLOURS: gold = ARP UP 1/16 · wine = ARP AS-PLAYED 1/2 T−24 gate 100 ·
azure = ARP UP-DN 1/16T T+12 · bronze = RATCHET ×3 1/8.
GRID: C1–C8 R1 gold ⇐MIDI →A · C1–C8 R2 wine ⇐MIDI →B ·
C3,C7 R3 azure ⇐MIDI →C · C4,C8 R4 bronze ⇐R1 →D.
LISTEN: four destinations with four jobs — keys, bass drone, sparkle, and a
percussive chop on D/ch10 (point it at a drum synth). Then patch ONE synth
omni to the ALL cable instead: the entire arrangement arrives on one wire,
channel-split. TEACHES: emitters/channels/cables; the ALL output.

## 14 · ALT EGO
Every Colour has a second self — the TAP ALT layer as composition.
GLOBAL: step 1/2, swing 50.
COLOURS (all with designed B states):
gold = ARP UP 1/16 (B: DOWN 1/32, 2 oct) ·
azure = ARP UP-DN 1/8 (B: RANDOM 1/16T) ·
vermilion = RATCHET ×2 1/8 (B: ×4 1/16) ·
magenta = CHANCE 90% (B: 40%).
GRID: C1,C2 R1 gold ⇐MIDI →A · C3,C4 R1 azure ⇐MIDI →A ·
C5,C6 R1 vermilion ⇐R? — no: ⇐MIDI →B · C7,C8 R1 magenta ⇐MIDI →B ·
C5,C6 R2 gold ⇐R1 →A.
PERFORM: set TAP: ALT; flip cells live; hold a column button to stutter a
flipped bar. LISTEN: the scene has two personalities per cell — base is
polite, B is wired. TEACHES: A/B, the tap layer, breathing rings (and the
seed bed for MORPH when the desk returns).

## 15 · THE LOOP THAT ISN'T
Graph freedom — including the legal dead loop.
GLOBAL: step 1/2, swing 50.
COLOURS: gold = ARP UP 1/16 · azure = ARP DOWN 1/8 · purple = RATCHET ×3 1/8 ·
teal = PASS.
GRID: C1–C4: R2 gold ⇐MIDI →A · **R1 azure ⇐R2 →B** (a BACKWARD tap —
child above its parent) · C6,C7: **R3 purple ⇐R5 →C · R5 teal ⇐R3 →C**
(a two-cell CYCLE: both lit, both silent, forever).
LISTEN: C1–C4 works upside-down (proof position ≠ hierarchy); C6–C7 emits
NOTHING despite lit emitters — the closed loop has no door. The
no-input/dead-loop indication (when designed) points here. TEACHES: any-row
references; why cycles are silent; the grid tells the truth.

## 16 · PACIFIC
The showcase. Named for the obvious reason.
GLOBAL: step 1/2, swing 57. BUS CHANNELS: A=1 B=2 C=3 D=4.
COLOURS: violet = ARP UP 1/16, 2 oct, LEGATO (no buses) ·
gold = ARP UP 1/16 (B: 1/32) · vermilion = RATCHET ×3 1/16 (B: ×4) ·
magenta = CHANCE 60% · wine = PASS every 2nd, T−12, gate 100 ·
azure = ARP UP-DN 1/16T, T+12, FREE · teal = PASS gate 100 ·
mint = HARMONIZE (see note) T+7.
GRID:
C1–C4 R1 violet ⇐MIDI — the LEGATO lead engine, one phrase over four columns
C1–C4 R2 gold ⇐R1 →A · C1–C4 R3 wine ⇐MIDI →B
C5,C6 R1 violet ⇐MIDI (second run) · C5,C6 R2 magenta ⇐R1 →A
C5–C8 R4 azure ⇐MIDI →C (the drifting triplet shimmer, FREE phase)
C7,C8 R1 gold ⇐MIDI →A · C7,C8 R2 vermilion ⇐R1 →A (the build)
C2,C6 R6 teal ⇐MIDI →D · C4,C8 R6 mint ⇐MIDI →D (pad room on D)
PERFORM: TAP ALT on C7,C8 during the last bar of a 4-pass phrase; hold
column 8 for the stutter out.
NOTE: mint uses HARMONIZE — BUILT as of v0.6-processors; the cell harmonises
for real. (Historical: this scene was designed to degrade gracefully before
that.)
LISTEN: a four-bar piece from one held chord — legato lead over a
half-time sub, chance-frayed edges, a shimmer that never lands the same way,
and a ratchet build into the turnaround. TEACHES: everything at once;
this is the demo.

---

## Acceptance for this document
- All sixteen load without code changes beyond SceneFactory; all six
  processors are available (v0.6).
- Slot 15's cycle and backward tap are INTENTIONAL — any "fix" is a bug.
- Ear-verify each LISTEN line; scenes are content, and content ships tested.
- Strip = SIXTEEN slots (delta §6 updated; the 8-slot mockup strip predates
  this document).
