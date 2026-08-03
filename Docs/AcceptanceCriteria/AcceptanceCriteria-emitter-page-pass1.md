# AcceptanceCriteria — EMITTER PAGE · PASS 1 (the shell + today's controls)
_Code's first-pass scope, derived from AcceptanceCriteria-emitter-page.md. Branch: `feature/emitter-page`._

## Thesis
Ship the **information architecture + entry/exit grammar** re-surfacing the emitter controls that ALREADY exist in
the engine, as the labelled full-size page. NO new engine features this pass — new sections appear as dimmed
"coming" seats. This proves the page and the long-press grammar before any engine work.

## IN scope (pass 1)
- **Entry (two-tier):** short-press a role button = toggle (unchanged). LONG-PRESS a role button (CLAIM/DUCK/ALT)
  → the page, pointed at that emitter, scrolled to that section. LONG-PRESS the emitter header → the page at top.
- **Placement:** the page renders IN PLACE OF THE GRID (the middle band yields); the receiver + emitter strips,
  master, controls, and verbs STAY LIVE around it (edit-page geometry). DONE (top-right) restores the grid; the
  PERFORM/EDIT toggle and a scene switch also close it.
- **Header:** A · B · C · D tabs (switch the pointed emitter, lit = pointed) · DONE.
- **Readout line** (live, from existing state): e.g. "CLAIMS · leaks 20% · DUCKS others by 40% · turn of 4".
- **Sections (existing engine only), flat scroll + dividers + section anchors:**
  - **VOICE** — channel (display) · OCT− / OCT+ (the ephemeral output octave nudge). velocity-curve/MONO/FENCE dimmed.
  - **CLAIM** — toggle · LEAK % slider.
  - **DUCK** — toggle · AMOUNT % slider (the FLATTEN engine, ruled-renamed DUCK).
  - **ALT** — toggle · COUNT stepper (1…8).
  - **FEEL · CONVERSATION** + future seats **ECHO · CHOKE · DENSITY** — dimmed "coming" placeholders (present, recessive).
- **Live + undoable** — reuses the existing document-editing callbacks (setClaim/leak, toggleFlatten/amount,
  toggleAlt/count, nudgeEmitterOctave); no transaction.

## OUT of scope (later passes — new engine)
VOICE: velocity curve · MONO (OFF/LAST/LOW/HIGH) · THE FENCE (range + DROP/CLAMP/FOLD). CLAIM: scope CLASS|RANGE ·
release-lag. DUCK: ATTACK/RELEASE envelope · TARGETS multiselect · note-class filter. ALT: ROTATE|DEAL · RING ·
reset-at-pass. FEEL: push/lay-back · humanize. CONVERSATION: LEAD · FREE|WITH|AGAINST. ECHO/CHOKE/DENSITY.

## Verification
Pure UI (no engine change) → covered by the iOS build; the underlying claim/duck/alt paths already have Router
tests. Device pass: long-press CLAIM/DUCK/ALT or the header opens the page at the right spot; tabs switch emitters;
edits apply live and match the strip; DONE / EDIT / scene-switch close it; strips + master stay live around it.
