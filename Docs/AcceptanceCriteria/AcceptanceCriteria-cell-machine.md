# AcceptanceCriteria — THE CELL MACHINE (the setup model of record)
_Ratifies the cell-machine redesign (`_dear_claude_code/PROPOSAL-cell-machine.md`)
as built + device-verified, 2026-08-02. Supersedes the two-processor "Colour"
treatment: a cell is a little machine you assemble. Retires A/B morph and
grid-chaining. Where this conflicts with the older §5 cell-editor spec, this wins._

## A — THE MODEL
**A0. A cell OWNS its treatment**
- A cell holds a serial CHAIN of up to 8 processor SLOTS (type + params +
  per-slot bypass). The chain — not a shared Colour — is the cell's sound.
- Colour survives as a **template + tag**: a shared default chain the cell
  starts from, and the palette hue/identity. It is no longer the treatment.
**A1. Three-tier resolution (render)**
- Given a cell, then its effective chain is: its own `processors` (per-cell
  override) → else its colour's `templateChain` → else the colour's legacy
  single processor. A fresh cell FOLLOWS its colour's template until edited.
**A2. Retired**
- A/B MORPH is gone (no blend; Codable fields + param addresses stay reserved
  for old-doc/automation decode). GRID-CHAINING (cell-hears-cell / `inputRow`)
  is gone — chains live inside cells; `inputRow` decodes inert on old sessions.

## B — SERIAL EXECUTION
**B1. The chain runs in series**
- Given a held chord and a multi-slot chain, then slot 1 processes the chord,
  slot 2 processes slot 1's OUTPUT, … the TAIL emits to the buses. Only the
  tail sounds; upstream stages feed the next.
**B2. Full note-set, all types, any position**
- Then every processor works in any slot, N deep, pool-correct: `harmonize→arp`
  arps ALL the harmonized voices; `gate→ratchet` re-strikes the gated chord;
  `gate→harmonize` holds the harmonized chord. Tick tails (arp/ratchet/strum)
  and hold tails (gate/chance/harmonize/bypassed) both run. A closed gate
  anywhere empties the set downstream.
**B3. Per-slot bypass**
- Then a bypassed slot is true-bypass — the note set passes through untouched.
- (Known: a mid-chain ratchet/strum passes the note SET but not its own rhythm
  — a downstream stage samples the set per-beat. Accepted as inherent.)

## C — EDITING: TWIN GROUPS (identical cells edit together)
**C0. The ruling**
- Cells own their config; there is NO scope mode. Identical cells edit together
  automatically; deliberate broader pushes are one-shot actions.
**C1. Twins are DERIVED**
- Two cells are TWINS when their config is equal — colourID + chain + input
  (receiver) + output (buses) + source-shaping (split/vel/chop); perform state
  (alt/muted) is ignored. No groups to create or maintain.
**C2. Point → the set lights**
- When the user points a cell in EDIT, then it wears a solid white ring, its
  twins wear a dashed white ring, non-twin occupied cells dim, and the header
  states **"EDITING N IDENTICAL CELLS"** (live count).
**C3. Edit → the whole set, one undo**
- Then every edit (chain slot, input, output, colour, chop) applies to the whole
  twin set in ONE undoable step — identical cells stay identical.
**C4. DETACH is the only divergence**
- Given the twin set, when the user taps **EDIT THIS ONE**, then the next edit
  applies to the pointed cell alone; its config diverges → it leaves the set.
**C5. APPLY TO… survives**
- Deliberate broader pushes stay as a one-shot foot action (twins / all ‹colour›
  / row) via the shipped applyToScope path. No lingering mode.

## D — THE EDIT PAGE (the assembly surface)
**D1. Signal-path order**
- Given EDIT armed and a cell pointed, then the page reads top-to-bottom:
  **IDENTITY · FROM · MIDI IN · CHAIN · TO · SYNTHS**. The scroll IS the signal.
**D2. Identity + colour**
- IDENTITY shows the swatch + name + the twin count/DETACH. The swatch is
  tappable → a 16-hue popover; picking re-tints the cell + its twins live.
**D3. Input / output wear what they are**
- FROM · MIDI IN is a receiver radio (R1–R4 + NONE) in the receiver identity
  hues (slate/purple/green/tan). TO · SYNTHS shows the emitter toggles with
  their channel tags, left-aligned.
**D4. The chain**
- CHAIN is a vertical stack of 50%-width slot boxes, head→tail, each
  `[emblem · TYPE ▾ · BYPASS]`; enum params are VALUE CHIPS (tap = picker),
  GATE a slider; `[+ ADD]` up to 8. The stack runs in series (D-caption).
**D5. Quiet + calm**
- Empty cells are near-silent (no chevrons — a bare faint rect). Section
  headers are large, spacing generous, content max-width bounded; pending
  features simply don't render (no dev annotations).
**D6. The grid is a position picker**
- When EDIT is armed: tap an EMPTY cell → CREATE a cell (brush/template default)
  + point it; tap an OCCUPIED cell → point it. REMOVE is a compact red button at
  the page FOOT — never a grid gesture. Empty + no pointed cell → the invitation
  "Choose a cell to edit — or tap an empty space to create one."

## E — THE CELL LIBRARY
**E1. Save "machine minus routing"**
- When the user SAVEs a cell to the library, then its chain (materialised) +
  colour + source-shaping travel; input/output are wired fresh on stamp.
- Stored app-level (cross-session), one Codable cell per file.
**E2. Stamp**
- When the user STAMPs a library cell, then a "STAMPING ‹name› — tap cells" mode
  arms; each grid tap drops the saved cell (routing blank), overwriting.
**E3. Factory cells**
- Then a read-only FACTORY set (Bloom `harmonize→arp` · Stutter `gate→ratchet` ·
  Cascade `arp→strum`) ships so the library isn't empty first-run — STAMP only.

## Owed (not yet built)
- A TRIGGERS section on the EDIT page (tap/hold/arrive) + the LOOP/TEST pinned
  strip; SAVE-TO-LIBRARY + the full breadcrumb beside DONE.
- Audition now previews the cell's RESOLVED HEAD (override/template-aware, no
  longer the raw Colour A face); a full multi-slot serial preview (the tail over
  the composed chain) is still owed.
- Cell/colour NAME editing on the EDIT page (read-only label today).
- Twin-count header sits in CHAIN (not IDENTITY); chip drag-to-scrub; the DIN
  glyph is an SF approximation; DELETE targets the pointed cell only (by design).

## Done since ratification
- **APPLY TO…** (C5) is wired: a foot Menu (ALL ‹colour› / THIS ROW / THIS
  COLUMN) stamps the pointed cell's full config onto the scope → targets become
  twins (`EditScope.row`/`.column` + `AU.applyCellToScope`).
