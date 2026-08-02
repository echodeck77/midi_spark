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

## C — EDITING: THE MODE ROW (manual select-set + transactional staging)
_Supersedes the earlier AUTO-twin/DETACH model (INSTRUCTIONS-edit-page-mode-row):
twins now only ADVERTISE; the SELECTION decides what edits._
**C0. The mode row**
- Below the grid sits a big row: LEFT a radio trio **EDIT · MUTE · CLEAR** (EDIT
  is the default on entry); RIGHT **APPLY · CANCEL**, greyed until the session is
  dirty. The page is one transaction: edits + births + clears preview LIVE, then
  APPLY commits them as ONE undo step, CANCEL reverts everything since the set
  opened. The controls (the inspector) show ONLY in EDIT mode.
**C1. EDIT — a manual selection set**
- Tapping any cell (occupied or empty, twin or not) adds it to the set (white
  ring); the FIRST is the ANCHOR (drives the inspector + breadcrumb). A 2nd tap
  on any OTHER selected cell removes it; the ANCHOR needs a LONG PRESS to drop
  (protects the context). Every edit (chain slot, input, output, colour, chop)
  writes through to EVERY selected cell in one step; the header reads **"N
  SELECTED"**. Divergent controls read MIXED.
**C2. Twins PULSE (advertise, not auto-edit)**
- Cells whose config equals a selected cell's — colourID + chain + input +
  output + source-shaping (split/vel/chop), perform state ignored — PULSE a
  dashed ring to invite inclusion. They are NOT auto-included and NOT auto-edited;
  the user taps to add them. Non-matching occupied cells recede.
**C3. Newborn = born audible passthrough**
- Tapping an EMPTY cell births it as part of the transaction (CANCEL removes it):
  born AUDIBLE — input R1 → Emitter A, an EXPLICIT empty chain (the source flows
  through untreated). The empty chain is NEVER a "PASS" slot — CHAIN shows a "+
  ADD PROCESSOR" invitation + a friendly type selector. Engine: empty chain ⇒
  identity (a single true-bypass hold-tail).
**C4. MUTE — immediate**
- In MUTE mode a tap toggles that cell's mute at once (loud-mute: dimmed + marked)
  — post-derivation output suppression, its own undo step, OUTSIDE the transaction.
**C5. CLEAR — transactional removal**
- In CLEAR mode a tap MARKS a cell for removal (dashed red ring + ✕, dimmed);
  retap reinstates. APPLY deletes the marked set in one step; CANCEL reinstates all.
**C6. Column looping**
- The edit page's column buttons drive the SAME laneMask as the perform-side
  column-hold: toggling columns loops exactly the toggled subset (the audition
  loop for the session). Cleared on leaving the page.

## D — THE EDIT PAGE (the assembly surface)
**D1. Signal-path order**
- Given EDIT armed and a cell pointed, then the page reads top-to-bottom:
  **IDENTITY · FROM · MIDI IN · CHAIN · TO · SYNTHS**. The scroll IS the signal.
**D2. Identity + colour**
- IDENTITY shows the swatch + name. The swatch is tappable → a 16-hue popover;
  picking re-tints the whole selection live. COLOUR + LABEL are editable here.
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
**D6. The grid is the selection surface (mode-aware — see §C)**
- EDIT: tap builds the selection set (empty tap BIRTHS a passthrough); long-press
  drops the anchor. MUTE: tap toggles mute. CLEAR: tap marks for removal. There is
  no foot DELETE and no APPLY TO… — removal is CLEAR mode, cross-cell edits are the
  select-set. Empty EDIT selection → "Tap cells to edit — or tap an empty space to
  create one."

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
- A TRIGGERS section on the EDIT page (tap/hold/arrive); SAVE-TO-LIBRARY + the
  full breadcrumb beside DONE.
- Audition previews the cell's RESOLVED HEAD (override/template-aware); a full
  multi-slot serial preview is owed — but audition is PARKED until TRIGGERS land.
- Cell/colour NAME editing on the EDIT page (read-only label today).
- MIXED-set markers on divergent controls are minimal (the edit still writes
  through); the anchor is not yet visually distinct from the other selected cells
  (both wear the white ring); chip drag-to-scrub not added; the DIN glyph is an SF
  approximation.

## Done since ratification
- **THE MODE ROW wave** (INSTRUCTIONS-edit-page-mode-row) — §C rewritten above,
  superseding auto-twin/DETACH: mode row (EDIT·MUTE·CLEAR ‖ APPLY·CANCEL) +
  transactional session (`AU.beginEditSession`/`applyEditSession`/`cancelEditSession`,
  session-aware `editScene`); manual select-set (`editSel`, anchor = first,
  long-press to drop) editing through `AU.editCells`/`withChainCells`; twins PULSE;
  newborn passthrough (empty chain → builder emits a bypassed identity hold-tail);
  MUTE immediate; CLEAR transactional (`removeMarks` render + APPLY-deletes);
  column-loop row → `setLaneMask`. Removed APPLY TO…/foot DELETE + `EditScope.row/.column`.
