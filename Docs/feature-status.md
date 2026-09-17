# 8x8 State — feature status (redirect · 2026-08-16)

This file used to carry a third, hand-maintained status list. It only ever drifted, so it no longer
tracks status. **The live status lives in three current places:**

- **CLAUDE.md → "Current status"** — the BACKWARD log (what landed, with commit refs).
- **`Docs/pending-tasks.md`** — the FORWARD checklist (what's open).
- **`Docs/codebase-review-2026-08-16.md`** — the whole-repo review (subsystem reads, bug table, §12 action list).

## Current reality (correcting the worst old fossils)
- **32 processor types** (2026-09-16), not 6: arp · ratchet · passgate · strum · chance · harmonize · echo · euclid ·
  burst · cascade · drone · shift · humanize · mod · glide · tutti · length · weave · split · octave · transpose ·
  channel · nudge · dest · muteMatrix · riff · tap · hocket · avoid · chords · velocity · deal (grouped in the storefront
  catalog as MELODY/HARMONY/RHYTHM/DYNAMICS/CONTROL/TIME/UTILITY/ROUTING).
- **MACROS shipped and are on `main`** (M0–M4 + the canonical authoring flow).
- **THE RACK shipped** (per-emitter treatment matrix) — but only **OWNS/claim · KEY/duck · TURNS** are engine-backed
  today; mono/fence/curve/pocket/conversation are rendered as dimmed "coming" seats (RackMatrix.swift). (The older
  "all eight live" note did not survive the rooms/rack rework.)
- **CONTROLLER ROUTING shipped** (per-door CONTROLLERS→[A·B·C·D], re-stamped).
- **THE BUILD page shipped** — the primary workshop surface (palette → staging → play).
- The **EDIT/PERFORM face**, the **cell-editor page**, AND the **tab shell** were all RETIRED — **BUILD is the sole
  surface** (2026-08-21); the header carries just **RACK · RECORD** config buttons (RATE moved to the ferry-settings
  card; MIDI IN/OUT are reached from the machine-column strips; ROW 8 is currently unreachable).
- **Colours are ID-based + unlimited ephemeral** (registry + hue override + GC), not the old fixed-16 model.
- **FREE-RUN CLOCK** (2026-08-25): a held chord plays the sequence even when the host transport is stopped.
- Recent removals worth knowing: the door-level **BYPASS toggle**, **MPE merge**, **A/B morph** (render-dead), and the
  **reference-chord audition fallback** are all gone.
