# SPEC → Code — LOCK (Paul, 2026-08-13: "store the MIDI as it
# passes... replay on the next pass" — built thesis-safe)

## THE MECHANISM: FREEZE THE QUESTION, NOT THE ANSWER
- **LOCK snapshots the cell's INPUTS**: {the effective pool at
  lock-moment · a phase/seed ANCHOR (the lock beat)}. The cell
  keeps DERIVING — against the frozen pool, phases and seeds
  computed relative to the anchor — so every pass repeats
  EXACTLY (seeded CHANCE included). **Zero notes stored**: a pool
  snapshot + one beat number (tiny, Codable, fullState-trivial).
  Audibly a recording; architecturally the latch's sibling. The
  thesis holds: the instrument still contains no notes.
- **UNLOCK** = the live pool re-attaches (boundary-deferred;
  never-lurch governs the seam). Lock on a silent pool = locks
  silence (legal; the tell shows it).

## THE GRID GESTURE + THE TELL
- **Long-press a cell (play grid or staging) → LOCK toggles**; the
  cell wears the 🔒/FROST tell (the mosaic dims toward frost —
  chrome-quiet: frozen looks frozen). Scenes capture lock states.
- Locked cells IGNORE door changes, latch edits, chord moves —
  **combining locked cells with MIDI passing through** (Paul's
  words) = frozen phrases as the bed, live derivation over them:
  the left hand moves the harmony, the locked bass keeps its
  figure. The duet's third texture.

## INTERACTIONS (all fall out of the mechanism)
- FOLLOW-mode stages inside a locked cell = KEEP by construction
  (the pool can't move). CC stages: SHAPE/STEPS lock phase to the
  anchor; FOLLOW follows the frozen emission ✓ consistent.
- Colour edits STILL ripple into locked cells (lock freezes
  inputs, not the machine — editing the chain changes the locked
  phrase's derivation; the reticle warns as ever). If Paul wants
  full freeze (machine too), that's a second chip — flag, lean NO
  (one meaning: lock = the inputs).
- The governor, roles, the wire: unchanged — locked output is
  ordinary derivation.

## THE PROCESSOR VERSION: BIRTHSTONED, with the honesty
A mid-chain LOCK STAGE ("freeze the stream at this point, live
modulation after") requires BUFFERING the intermediate stream =
stored notes at stage grain — the trap in miniature. Parked as a
birthstone with that cost named; the cell-level lock covers the
musical want today. Manual line: "Lock keeps the question a cell
was asked; the answer repeats for as long as you hold the ice."
— design-side Claude

## §2 — THE RETRO-CATCH (Paul, 2026-08-13: "catch the magic
## retrospectively" — cheap, because determinism makes the past a
## LOOKUP)
- **The mechanism**: a global ROLLING INPUT LOG — pool-change
  events {beat, delta} + lap indices, last ~32 beats (sparse:
  bytes/minute; no MIDI stored, ever). **DOUBLE-TAP a cell =
  LOCK TO ITS PREVIOUS PASS**: the pool-timeline for that pass
  reconstructs from the log; derivation replays the magic exactly
  (same question ⇒ same answer — seeded chance and self-play
  weather included).
- **Pool-TRAJECTORY locks**: if the pool moved mid-pass, the
  caught lock holds the MOTION (a frozen moving question) —
  something a recorder could never compose with.
- **The two locks, one family**: LONG-PRESS = freeze NOW (§1) ·
  DOUBLE-TAP = catch the LAST pass. Tell: frost + a tiny ↺ on the
  caught kind.
- **Cost sheet**: memory = the event ring (trivial) + per-cell
  anchor; CPU = one log-walk at catch-time, zero ongoing;
  fullState = the ring is transient (locks persist their
  reconstructed snapshot, not the log). Cheap by construction.
- **The honest caveat (v1)**: if SELF-PLAY nudged the cell's
  params BETWEEN the magic and the tap, the nudge persists (the
  retro window covers inputs, not param history). Rare at
  self-play cadence; the fix (per-lap param snapshots for
  self-play-touched cells) is small and waits for the first real
  complaint. Manual line: "Heard it? Double-tap — the instrument
  remembers the question it was asked, and asks it again."

## §3 — THE QUESTION LOG COMPLETES (Paul's two probes, 2026-08-13)
- **Lifecycle, stated plainly**: the log stays ~32 beats forever
  (old history evaporates; session length irrelevant). CATCH does
  ONE log-walk, then **the lock stores its own snapshot** — every
  later pass derives from the lock, never the log. No per-pass
  lookups, no growth.
- **★ THE HOLE, closed: the machine is part of the question.** The
  ring now logs PARAM + CHAIN EDIT events too ({beat, cellId,
  delta}; a RANDOMIZE = one small chain snapshot) — sparse,
  human-rate, bytes. CATCH reconstructs **the machine as it was**
  at the magic pass alongside the pool trajectory: true replay
  through randomizers, mutates, self-play, sync changes. (Tempo is
  free: derivation is beat-based — the phrase is beat-identical at
  any BPM; the anchor keeps phase alignment.)
- **THE TWO DEPTHS (the flagged ruling, lean stated)**:
  - **LOCK (long-press)** = freeze the INPUTS; colour edits still
    ripple (§1 unchanged — lock the question, keep sculpting the
    machine).
  - **CATCH (double-tap)** = freeze the MOMENT — inputs + the
    machine-as-it-was: **detached from live colour edits** (the
    caught sound is sacred; the reticle shows it dashed/detached;
    promotable via LAST TOUCHED like a provisional — catching is
    an implicit frozen fork). Paul confirms the split or collapses
    it.
- Lock weight: a caught lock ≈ one colour's worth of state. Few
  locks, small colours — still cheap.

## §4 — SUPERSESSION: CATCH RECORDS (Paul's "why not capture what
## it emits?" — he's right; owning the over-engineering)
- **THE SPLIT BY DEPTH (final)**:
  - **LOCK (long-press) = FREEZE THE QUESTION** — pool snapshot +
    anchor ONLY (§1, no machine capture). The machine stays LIVE:
    colour edits ripple — "freeze the phrase, keep sculpting the
    gate" — **the one power a recording cannot have.** Cheap by
    construction.
  - **CATCH (double-tap) = RECORD THE EMISSIONS.** Each cell keeps
    a rolling ONE-PASS emission buffer (~a few hundred bytes);
    double-tap PERSISTS it — the caught pass replays verbatim.
    Exact through randomizers, mutates, sync, everything — by
    definition, forever, with zero reconstruction machinery.
- **RETIRED**: §2–§3's question-log ring · param/chain edit
  logging · machine-snapshot locks · catch-time reconstruction.
  (The fifth stale premise of the season: purity architecture
  where a buffer sufficed. Paul's simplicity instinct outranked
  it.)
- **The thesis, addressed plainly**: a caught clip IS stored notes
  — a deliberate, scoped exception: a photograph the user
  explicitly took of something their own hand caused. Kin to the
  fifth row's sequence cells (stored arrangements); possible
  future unification: **caught clips as fifth-row citizens**
  (catch → a clip cell), noted, not ruled.
- Replay/fuzz: a clip is data — trivially deterministic, trivially
  testable. Simpler everywhere it touches.

## §5 — THE CATCH STAGE + THE EDGE CHIP (Paul, 2026-08-13)
- **CATCH manifests as a stage**: double-tap APPENDS **[🔒 CATCH]**
  at the chain's end — an OUTPUT-BOUNDARY occupant (chop's
  neighbour; a pseudo-slot that never consumes the 8; appendable
  even to a full chain). Upstream stages render dim-but-present
  (the machine visibly wearing its photograph); the snake shows
  the frozen frame. **DELETE the stage = unfreeze** — the standard
  gesture, no special vocabulary. LOCK (long-press) stays an
  input-side state per §4 (it freezes the door's side; a stage
  there would be positionally false).
- **THE CAPTURE PIN**: the buffer stores {SOUNDING-AT-START set +
  events} — a pad held into the caught pass exists on every
  replay, not just the first.
- **THE EDGE CHIP — TIE | RESTRIKE** (boundary-crossing sustains
  at the loop wrap):
  - **RESTRIKE (default)**: the wrap re-articulates — off at
    T−1 sample, on at T (the standing ordering trick) — a caught
    clip is a loop, and loops re-attack.
  - **TIE**: the crossing note sustains THROUGH the wrap (the
    off/on pair suppressed; refcounts hold it) — the drone
    survives looping seamlessly.
  - The vocabulary is the wire's own (RESTRIKE's cousin at the
    clip boundary) — one word family, two homes.

## §6 — THE BARS CHIP (Paul, 2026-08-13: recall length, easy reach)
- **The catch stage face wears BARS: 1 · 2 · 4 · 8** — tap cycles
  (one-tap reach; the pseudo-slot reads 🔒 4). The clip loops the
  LAST N BARS ending at the catch moment, bar-aligned; the EDGE
  chip (TIE|RESTRIKE) applies at the N-bar wrap.
- **Non-destructive by construction**: catch persists the MAX
  window (8 bars) from the rolling buffer; BARS selects the
  replayed SLICE — lengthen later and the memory was kept.
- The rolling buffer generalises: last 8 bars of emissions per
  audible cell (KB-class; bounded). A caught clip's N-bar loop =
  its own cycle length — the polymeter law, one more citizen.
