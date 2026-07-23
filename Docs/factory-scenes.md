# Factory scenes 1–16 — the scene selector's contents

PURPOSE: the scene strip's sixteen slots ship with these scenes. They are a
curriculum disguised as a record: each slot is a PIECE first and a lesson
second, and routing enters the story progressively — Part I never routes,
Part II goes vertical, Part III plays the whole graph. They replace the
test-session buttons in the strip for release builds (TestSessions T1–T17
remain loadable via the diagnostic panel — these are NOT those; never merge).

IMPLEMENTATION: `SceneFactory.swift` returning the sixteen documents. Field
names per Models.swift; numbering below is 1-based for humans (C1–C8, R1–R8) —
convert to 0-based in code. Notation: `⇐MIDI` inputRow=nil, `⇐MIDI ch5`
+inputChannel=5, `⇐R2` inputRow=row2, `→A B` buses, `(B: …)` the ALT state,
`Tn` transpose. Unlisted params take type defaults. Bus channels default
[1,2,3,4] unless stated. Every scene loads with zero warnings except where a
warning is the lesson (slot 15). EAR-VERIFY every LISTEN line before
shipping — scenes are content, and content ships tested.

## THE STANDING RIG (patch once, play everything)

Four sounds, four jobs. Patch these in AUM and all sixteen scenes work;
scenes note deviations only where one earns its keep.

- **A — THE VOICE.** Polyphonic pluck or keys: medium-fast attack, medium
  decay, expressive velocity (an analog-poly pluck, a DX-style EP, a bright
  Rhodes). Carries the primary line in nearly every scene.
- **B — THE FLOOR.** Monophonic bass: sub-weighted, slight drive, happy with
  long gates (a Model-D-style mono, an acid mono with the resonance behaving).
  Where a scene sends chords to B, a dark low pad also works.
- **C — THE AIR.** Shimmer: a delay-and-reverb-heavy lead or bright pad,
  something that blurs beautifully (a supersaw pad at low mix, a plucked
  bell into a long tail). C is always the part you'd mix quietest and miss most.
- **D — THE PULSE.** Percussive: a drum synth/sampler listening omni, or a
  plucked perc patch with almost no sustain. D is texture and punctuation,
  not melody — until scene 16 argues otherwise.

Multitimbral alternative: point ONE multitimbral synth (or a recorder) at
the **All** cable — channels 1–4 arrive pre-separated. Scene 13 makes this
a set-piece.

---

# PART I — ONE WIRE (scenes 1–5: nothing routes; every cell hears the keys)

## 1 · FIRST LIGHT
GLOBAL: step 1/2, swing 50. SOUNDS: A only.
COLOURS: gold = ARP UP 1/16, 1 oct, gate 60.
GRID: C1R1 gold ⇐MIDI →A.
PLAY: hold a Cmaj7 low enough to shimmer, then move ONE inner note and hold
again. LISTEN: one bright bar-opening gesture, then seven steps of silence —
the silence is the instrument showing you the grid is time. Moving one held
note reshapes the phrase without replaying anything. TEACHES: cells, columns,
the pass; the held chord as the score.

## 2 · FOUR ON THE FLOOR (OF EIGHT)
GLOBAL: step 1/2, swing 50. SOUNDS: A only.
COLOURS: gold = ARP UP 1/16, 1 oct.
GRID: C1R1, C3R1, C5R1, C7R1 — all gold ⇐MIDI →A.
PLAY: a minor triad; try lifting and re-striking between columns 4 and 5.
LISTEN: on-off-on-off — the rests swing as hard as the notes. This is the
scene that proves placement IS rhythm. TEACHES: instances; painting the same
Colour into a groove.

## 3 · CALL AND ANSWER
GLOBAL: step 1/2, swing 50. SOUNDS: A voice, B floor (here B plays LOW keys —
if your bass mono chokes on chords, drop a dark poly on B for this one).
COLOURS: gold = ARP UP 1/16 · azure = ARP DOWN 1/16, T−12.
GRID: C1–C4 R1 gold ⇐MIDI →A · C5–C8 R1 azure ⇐MIDI →B.
PLAY: a spread minor 9 (root low). LISTEN: the question rises on the voice,
the answer falls an octave down on the floor — two synths trading fours from
one pair of hands. TEACHES: Colour identity; two emitters as two performers.

## 4 · STAIRCASE
GLOBAL: step 1/2, swing 50. SOUNDS: A only — one sound, so the harmony
change is unmistakably the GRID's doing.
COLOURS: gold = ARP UP 1/16 T0 · mint = same T+5 · azure = same T+7 ·
violet = same T+12.
GRID: C1,C2 gold · C3,C4 mint · C5,C6 azure · C7,C8 violet — all R1 ⇐MIDI →A.
PLAY: a bare fifth. The grid supplies the rest. LISTEN: I → IV → V → octave
across the bar, no fingers moved — a chord progression made of TRANSPOSE.
Then hold a full minor chord and hear the same staircase turn melancholy.
TEACHES: per-Colour transpose as harmony; the same scene recolours with
what you feed it.

## 5 · THE LIMP
GLOBAL: step 1/2, **swing 62**. SOUNDS: A voice, D pulse (vermilion moves to
D — the ratchets are percussion this time).
COLOURS: gold = ARP UP 1/16 · vermilion = RATCHET ×3 1/8.
GRID: C1,C3,C5,C7 R1 gold ⇐MIDI →A · C2,C4,C6,C8 R1 vermilion ⇐MIDI →D.
PLAY: minor triad, low; lean on velocity. LISTEN: the arp walks upright,
the ratchet stutters drag their heels — a strut. Ride the SWING slider live
from 50 to 70 and back: the whole room changes gait. TEACHES: swing as
step-phase warp; RATCHET; the desk as a performance surface.

# PART II — GOING VERTICAL (scenes 6–10: cells start listening to cells)

## 6 · CHAIN OF COMMAND
GLOBAL: step 1/2, swing 50. SOUNDS: A voice.
COLOURS: violet = ARP UP-DN 1/8, 2 oct (NO buses — a pure engine) ·
vermilion = RATCHET ×2 1/16.
GRID: C1–C8: R1 violet ⇐MIDI (silent) · R2 vermilion ⇐R1 →A.
PLAY: sustained major 7, mid-register. LISTEN: you never hear the arp
itself — only the ratchet chewing it. **This is the first routed sound in
the curriculum**: row 1 thinks, row 2 speaks. Mute column feeders live and
hear children fall back to the raw chord — the reroute rule as a fill.
TEACHES: references; silence of the unemitted; sound leaves only through
lit emitters.

## 7 · TWO HANDS
GLOBAL: step 1/2, swing 50. SOUNDS: A voice (right hand), B floor (left).
Set your keyboard split: left zone ch2, right zone ch1.
COLOURS: gold = ARP UP 1/16 · wine = ARP AS-PLAYED 1/4, gate 90, T−12.
GRID: C1–C8: R1 gold ⇐MIDI **ch1** →A · R2 wine ⇐MIDI **ch2** →B.
PLAY: left hand walks roots and fifths slowly; right hand holds colour tones
and swaps them mid-bar. LISTEN: a two-piece band — the bass ignores your
chord hand, the chord hand ignores the bass, and the groove is the
disagreement. TEACHES: input-channel filters — routing at the FRONT door.

## 8 · THE FAN
GLOBAL: step 1/2, swing 50. SOUNDS: A voice, B air-quiet, C air.
COLOURS: violet = ARP AS-PLAYED 1/8, 2 oct (no buses) ·
vermilion = RATCHET ×3 1/16 · magenta = CHANCE 65% · azure = ARP UP 1/16, T+12.
GRID: C1–C8: R1 violet ⇐MIDI · R2 vermilion ⇐R1 →A · R3 magenta ⇐R1 →B ·
R4 azure ⇐R2 →C.
PLAY: sus4 chord, resolve it when the C-line finally lands somewhere sweet.
LISTEN: one melodic brain, three mouths — A chops it, B gambles on it, and C
re-arpeggiates THE CHOPPED VERSION an octave up (a grandchild — routing has
depth now, not just direction). Mute R1: the whole family falls silent back
to your raw chord in one gesture. TEACHES: fan-out; generations; one source
of truth feeding a section.

## 9 · EVERY OTHER TIME
GLOBAL: step 1/2, swing 50. SOUNDS: A voice, B air, C floor (the toll wants
weight — swap C to a sub-heavy patch, or send it to B's synth on ch2).
COLOURS: gold = ARP UP 1/16 · teal = PASS (every 2nd pass) ·
wine = PASS (every 4th pass) T−12, gate 100.
GRID: C1–C8 R1 gold ⇐MIDI →A · C1,C5 R2 teal ⇐R1 →B ·
C1 R3 wine **⇐R1** →C.
PLAY: minor 9, held across four full passes — patience is the instrument here.
LISTEN: the constant stream on A; every second pass, B briefly doubles the
ARP (not the chord — teal taps row 1 now); once every four bars, C tolls the
arp's own notes an octave down like a bell remembering the melody. A 1-bar
grid composing 4-bar form. TEACHES: the pass dimension; PASSGATE on a
ROUTED source — structure and routing in one gesture.

## 10 · DICE MUSIC
GLOBAL: step 1/2, swing 54. SOUNDS: A voice, B air (octave ghosts), D pulse.
COLOURS: magenta = CHANCE 70% · blush = CHANCE 35% T+12 ·
gold = ARP RANDOM 1/16 (no buses) · vermilion = RATCHET ×4 1/16.
GRID: C1–C8 R1 gold ⇐MIDI · C1–C8 R2 magenta ⇐R1 →A ·
C2,C4,C6,C8 R3 blush ⇐R1 →B · C4,C8 R4 vermilion ⇐R2 →D.
PLAY: any chord you love; then STOP playing and just listen to four passes.
LISTEN: a shape you recognise that never repeats — the RANDOM arp deals,
the CHANCE cells fold or call, and twice a bar the ratchet double-gambles
what already survived one coin-flip. Generative, but never random-sounding:
the harmony is still your held hand. TEACHES: probability as arrangement;
chained chance (a gamble on a gamble).

# PART III — THE GRAPH (scenes 11–16: any row, any direction, the whole board)

## 11 · LONG WALK
GLOBAL: step 1/2, swing 50. SOUNDS: A voice, B voice-dark (RETRIG contrast
line — same patch family as A, darker preset), C air.
COLOURS: violet = ARP UP 1/16, 2 oct, **LEGATO** · teal = ARP UP-DN 1/8T,
**FREE**, T+12 · gold = ARP UP 1/16 (RETRIG, the control group) ⇐ see grid.
GRID: C1–C4 R1 violet ⇐MIDI →A (a 4-column run) ·
C1–C4 R2 gold **⇐R1** →B · C5–C8 R2 teal ⇐MIDI →C.
PLAY: a slow-changing progression — hold, breathe, move two notes, hold.
LISTEN: the violet phrase unfolds ONCE across four columns, never
restarting; underneath it, gold RETRIGs crisply every step — but it's
re-arpeggiating the LEGATO line itself, discipline imposed on a wanderer.
Then the teal triplets drift in on the far side, FREE, catching a different
slice every pass. Three relationships with time, audibly side by side.
TEACHES: RETRIG vs LEGATO vs FREE; processing a phrase (reference to a run).

## 12 · UNDERTOW
GLOBAL: step 1/1, swing 50. SOUNDS: A voice, B floor, C air.
COLOURS: indigo = ARP UP 1/8, 2 oct (no buses) · magenta = CHANCE 80% ·
vermilion = RATCHET ×2 1/16 · wine = PASS gate 100 T−12 ·
chartreuse = ARP UP 1/32, 1 oct, T+12.
GRID: C1–C8: R1 indigo ⇐MIDI · R2 magenta ⇐R1 · R3 vermilion ⇐R2 →A ·
R4 wine ⇐R1 →B · R5 chartreuse ⇐R3 →C.
PLAY: low minor 11, held like a pedal tone; half-time feel (step 1/1 makes
the bar twice as wide — swim, don't sprint).
LISTEN: A is the end of a three-stage digestion (arp → gambled → chopped);
B doubles the raw engine an octave down, heavy and sure; C is a glittering
great-grandchild running at ×4 the speed of anything else, spray off the
top of the wave. Every stream is the same chord at a different depth.
TEACHES: chain depth; tapping every stage; TIME as arrangement (step 1/1).

## 13 · TWO ROOMS
GLOBAL: step 1/2, swing 50. BUS CHANNELS: A=1, B=2, C=3, D=10.
SOUNDS: the full rig, plus D explicitly = a DRUM synth listening on ch10.
COLOURS: gold = ARP UP 1/16 · wine = ARP AS-PLAYED 1/2 T−24 gate 100 ·
azure = ARP UP-DN 1/16T T+12 · bronze = RATCHET ×3 1/8.
GRID: C1–C8 R1 gold ⇐MIDI →A · C1–C8 R2 wine ⇐MIDI →B ·
C3,C7 R3 azure ⇐MIDI →C · C4,C8 R4 bronze ⇐R1 →D.
PLAY: big chord, both hands, and let the ROUTING be the performance: this
scene is for touring the mixer.
LISTEN: four destinations, four jobs — keys, a tectonic bass drone, sparkle
at the edges, and the arp's own rhythm chopped into drum triggers on ch10.
THEN the set-piece: patch ONE multitimbral synth (or a recorder) omni to the
**All** cable — the entire arrangement arrives on one wire, pre-split by
channel. TEACHES: emitters/channels/cables; the All output; the wire as a
place music lives.

## 14 · ALT EGO
GLOBAL: step 1/2, swing 50. SOUNDS: A voice, B pulse-adjacent (the CHANCE
cells on B want a patch that speaks fast — a plucked perc or muted stab).
COLOURS (all with designed B states):
gold = ARP UP 1/16 (B: DOWN 1/32, 2 oct) · azure = ARP UP-DN 1/8
(B: RANDOM 1/16T) · vermilion = RATCHET ×2 1/8 (B: ×4 1/16) ·
magenta = CHANCE 90% (B: 40%).
GRID: C1,C2 R1 gold ⇐MIDI →A · C3,C4 R1 azure ⇐MIDI →A ·
C5,C6 R1 vermilion ⇐MIDI →B · C7,C8 R1 magenta ⇐MIDI →B ·
C5,C6 R2 gold ⇐R1 →A.
PLAY: set TAP: ALT and make the GRID the keyboard — hold a chord with one
hand and flip cells with the other; hold a column key to stutter a flipped
bar. LISTEN: every Colour has a polite self and a wired self; the piece is
the argument between them. Note C5/C6's gold cell re-arpeggiates the
RATCHET — flip the ratchet to ×4 and its child gets busier too: ALT states
propagate DOWN the graph. TEACHES: A/B as composition; the tap layer;
inheritance of character through references.

## 15 · THE LOOP THAT ISN'T
GLOBAL: step 1/2, swing 50. SOUNDS: A voice, B floor, C anything — C will
never sound, and that's the lesson.
COLOURS: gold = ARP UP 1/16 · azure = ARP DOWN 1/8 T−12 · purple = RATCHET
×3 1/8 · teal = PASS.
GRID: C1–C4: R2 gold ⇐MIDI →A · **R1 azure ⇐R2 →B** (a BACKWARD tap — the
child lives ABOVE its parent) · C6,C7: **R3 purple ⇐R5 →C · R5 teal ⇐R3 →C**
(a two-cell CYCLE: both lit, both silent, forever).
PLAY: something pretty on C1–C4 and total indifference toward C6–C7.
LISTEN: the left half works upside-down — proof that position is geography,
not hierarchy; the bass line is a DOWNWARD echo of a cell below it. The
right half emits NOTHING despite lit emitters: a closed loop has no door,
and the grid is honest about it (the dead-loop indication, when designed,
points here). TEACHES: any-row references; why cycles are silent; trust
the grid, not your assumptions.

## 16 · PACIFIC
GLOBAL: step 1/2, swing 57. BUS CHANNELS: A=1 B=2 C=3 D=4.
SOUNDS: the standing rig at full attention — A voice bright, B floor deep,
C air with the longest tail you own, D a warm pad or vibraphone-ish poly
(D graduates from percussion to HARMONY for the finale).
COLOURS: violet = ARP UP 1/16, 2 oct, LEGATO (no buses) ·
gold = ARP UP 1/16 (B: 1/32) · vermilion = RATCHET ×3 1/16 (B: ×4) ·
magenta = CHANCE 60% · wine = PASS every 2nd, T−12, gate 100 ·
azure = ARP UP-DN 1/16T, T+12, FREE · teal = PASS gate 100 ·
mint = HARMONIZE T+7.
GRID:
C1–C4 R1 violet ⇐MIDI — the LEGATO lead engine, one phrase over four columns
C1–C4 R2 gold ⇐R1 →A · C1–C4 R3 wine ⇐MIDI →B
C5,C6 R1 violet ⇐MIDI (second run) · C5,C6 R2 magenta ⇐R1 →A
C5–C8 R4 azure ⇐MIDI →C (the drifting shimmer, FREE)
C7,C8 R1 gold ⇐MIDI →A · C7,C8 R2 vermilion ⇐R1 →A (the build)
C2,C6 R6 teal ⇐MIDI →D · C4,C8 R6 mint ⇐MIDI →D (the pad room — mint
HARMONIZEs at +7, so D breathes in fifths)
PLAY: Am9, held for four full passes; lift to Fmaj7 as pass four turns; TAP
ALT on C7,C8 for the final bar; hold column key 8 to stutter out.
LISTEN: a four-bar piece from one held chord — a legato lead over a
half-time sub, chance-frayed edges, a shimmer that never lands twice, a pad
room answering in fifths, and a ratchet build into the turnaround. Named
for the obvious reason; make it earn the name. TEACHES: everything at once —
this is the demo, the tutorial's diploma, and track one.

---

## Acceptance for this document
- All sixteen load without code changes beyond SceneFactory; all six
  processors are available (v0.6).
- Slot 15's cycle and backward tap are INTENTIONAL — any "fix" is a bug.
- The routing arc is structural: Part I contains ZERO references; the first
  routed sound in the curriculum is scene 6's ratchet. Keep it that way
  through any future edits.
- Ear-verify every LISTEN line with the STANDING RIG patched as described;
  scenes are content, and content ships tested.
- Strip = SIXTEEN slots (delta §6; the 8-slot mockup strip predates this).
- Scene LISTEN lines that invoke column MUTE (6, 8) assume mute's
  reintroduction via the perform-v2/TOUCH pass (removed at `3e816ee`);
  they are release-content instructions, not current-build ones.
