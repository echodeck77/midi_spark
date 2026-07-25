# 8x8 State — Terminology (the glossary; ratify then never flip again)
Principle: **three metaphors, one per layer, each stops at its boundary.**
WIRE = radio · MUSIC = paint · ARRANGEMENT = theatre · TIME = motion.
Blessed term in caps; ✂ = variants killed on sight.

## THE WIRE LAYER — radio
- **RECEIVER** (R1–R4) — a named input: cable × channel (+ latch, range…).
  ✂ "input", "in port", "MIDI in" (as nouns; fine as verbs/prose).
- **EMITTER** (A–D) — a named output: cable + channel stamp.
  ✂ "output", "out", "bus" (engine code may keep busEnabled etc.; UI never).
- **CABLE** — a physical/host port, in or out. **CHANNEL** — MIDI channel.
- **CLAIM / LEAK / FLIP / FLATTEN / ALT(pair)** — emitter ROLES (plain
  English; the wire layer's social register — deliberate, no metaphor).
- **MASTER** — the sum stage. **INSERT** — the one Colour on a wire.

## THE MUSIC LAYER — paint
- **THE GRID** — the 8×8 surface. ✂ "main grid", "colour grid", "matrix".
- **CELL** — a populated position (a cell WEARS a Colour; you PAINT cells).
  An unpopulated position = an **EMPTY**. 
- [RETIRED before ratification: "SKETCH" — the faded/unreviewed state was
  removed from the app entirely (`b90783b`); every creation arrives
  confirmed. "GHOST" remains engine-reserved — no UI ever calls a cell a
  ghost.]
- **COLOUR** (16) — a treatment: name + PROCESSOR + settings (+ ALT pair).
  ✂ "preset" (reserved for the future library), "patch", "slot".
- **PROCESSOR** — the type inside a Colour (ARP, RATCHET…). Its params =
  **SETTINGS**. ✂ "engine", "effect", "mode" (for types).
- **ALT** — a Colour's partner; **MORPH** — the glide between a compatible
  pair. **PALETTE** — the 16-chip picker.
- **THE STAMP** — the ONE clipboard/template object (written by commits,
  COPY, staging edits; read by paste, drag-create, staging).
  ✂ "session template", "clipboard", "buffer" — one object, one name.
- **PHRASE** — a RECORD Colour's captured content. ✂ "clip", "loop",
  "sample" (DAW baggage; a phrase is what it musically is).
- **REFERENCE** — a cell listening to a row (⇐R n). A referencing cell's
  source cell = its **PARENT**; downstream = **CHILDREN**. ✂ "chain",
  "wire", "patch cable" (there is no wiring layer — flow is transient).

## THE ARRANGEMENT LAYER — theatre
- **SCENE** (16) — an arrangement unit (the music; the RIG is the document).
- **THE STRIP** — the scene slots. **STAGING** — the create/configure
  session (flashing SELECTED SET; user-ratified name). ✂ "cell edit mode"
  as a synonym — staging IS the mode's name.
- **NOTES** — a scene's/document's text. **THE SONG** — you know the one.
- **ON** — the trigger system (ON TAP / HOLD / ARRIVE / LEAVE / SCENE).

## TIME — motion
- **STEP** — the duration unit (the header rate). **COLUMN** — the place
  (1–8; column keys). A column occupies a step; they are not synonyms.
- **PASS** — one trip across the grid. **LAP** — the held-subset cycle
  (§5b). **PLAYHEAD** — the arrow + sweeps. **WRAP** — the return to
  column 1 (scene switches fire at the wrap).

## Engine-only terms (never UI copy)
voice, voice table, GHOST (a CLAIM reservation voice — why cells can't be
"ghosts"), refcount, snapshot, derivation, emitted tuple, lingerer.

## The desk & modes
- **THE DESK** — the panel column(s): PALETTE/COLOUR box, PROCESSOR
  (selector + SETTINGS), RECEIVERS, EMITTERS panels. 
- **EDIT / PERFORM** — the two faces. **HOLD** — the global latch.
  **THE TIME MACHINE** — working title (rename at shipping).

## Style rules
1. One name per thing; variants are typos. 2. Metaphors never cross layers
("the receiver plays a scene" = two layers, rewrite it). 3. Engine terms
never surface in UI. 4. New features name themselves within their layer's
metaphor or in plain English — never a fourth metaphor.
