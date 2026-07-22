# Migration: chain routing → graph routing (spec v3.0-delta)

(Filename says "tree" for historical reasons; the model is a reference GRAPH —
any-row references, cycles legal-and-silent. Do not rename the file; links
point here.)

The router EXISTS and WORKS under the old model (▾ stack flag, srcMix union,
feeder = row above). This document is the plan for migrating it to the v3.0
model (receiver-picked `inputRow` references — any row, cycles legal — no unions). It is a
MIGRATION, not a rewrite: the goal is the smallest diff that satisfies the
delta spec while keeping the test suite green at every commit.

## Rule zero: survey before editing

The implementation may not match router-design.md exactly. Before changing
anything, grep and READ every site that touches the old model:
`stack`, `srcMix`, `structFed`, `liveFed`, `usesSource`, `chainsBelow`,
`noDestination`, feeder/`r - 1` derivations, fullState encode/decode,
SnapshotBuilder fields, TestSessions builders (T1–T16 — numbering authority,
see test-procedures preamble), Derivations.swift (the pure core), and the
Tests/ unit suite (42 tests) — the suite's current shape IS part of the survey.
Produce the list in the PR description. Anything NOT on that list must not
change in this migration.

## What does NOT change (guard rail — do not "improve" these)

Voice table, refcount/collision policy, transpose stamping (channel handling
changes ONLY in commit 5, nowhere earlier), the FIVE BUILT PROCESSORS
(ARP/RATCHET/PASSGATE/STRUM/CHANCE — the migration changes what they are FED,
never what they DO; HARMONIZE stays identity, out of scope),
PHASE formulas, swing warp, morph/override resolution, transport derivation,
column transitions, snapshot acquire/publish mechanics, parameter routes,
diag plumbing. If a migration edit seems to require touching these, stop and
re-read the delta — it almost certainly doesn't.

## Verification order (cheapest first, always)

1. **Unit tests** (Tests/, macOS, off-device): the pure core is where
   parentOf/resolvedParent, the input-channel filter, stamp mapping, and
   cycle-silence are all unit-testable. EXTEND the 42-test suite with the
   new-model cases in the same commit as each change; all green before any
   build hits the iPad.
2. **Canned sessions** on device (per test-procedures, post-reconciliation
   numbering).
3. **Human ears** in AUM (the reporting template).

## The five real changes

1. **Schema/state.** CellState: add `inputRow: Int` (sentinel −1 = MIDI IN;
   avoid Optional in the render path). Keep decode of old keys FOREVER:
   loader migration maps old documents → new model:
   `fed(r) := row r−1 occupied && its stack == true` → `inputRow = r − 1`,
   else −1; `srcMix` is dropped (no equivalent; debug-log when seen).
   Encoder writes ONLY the new schema. The user has saved AUM sessions in the
   old format — migration on load is mandatory, not optional. Bump a schema
   version field if one exists; add one if not.

2. **Snapshot precompute.** SnapshotBuilder resolves per cell:
   `resolvedParent` (= inputRow if that row is occupied AND ≠ r, else −1;
   downward values are legal — see delta §1 cycle/delay semantics)
   and `isTapped` (any OTHER cell's resolvedParent == this row). The render
   thread never scans for either.

3. **Input derivation (the heart).** Replace feeder-of-r−1 logic with:
   `p = resolvedParent(cell)`; if `p >= 0 && !muted(p)` → input = sounding
   set of row p; else → source pool. Delete the srcMix union branch entirely.
   STRUCTURAL CONSEQUENCE: chain code may only retain the PREVIOUS row's
   sounding set during the column pass; the graph model requires the sounding
   VOICES of ALL rows of the active column to stay addressable for the whole
   pass (a cell may reference any other row). Rows 0→7 remains the evaluation
   order, run against PERSISTENT voice state: upward references read this-pass
   values, downward references read the referenced cell's voices as they
   stand (unit delay). Cycles need NO handling: closed loops receive no entry
   and stay silent (delta §1).

4. **noDestination.** Was local (`no buses && no effective ▾`); becomes
   `no buses && !isTapped` — read the precomputed flag, don't rescan.

5. **Tests.** Reconcile against the repo's T1–T16 by INTENT (repo numbering
   wins; update test-procedures.md as part of the survey commit): re-express
   the model-dependent sessions (chain → reference chain, +SRC → sibling tap,
   muted-feeder → muted-parent; any processor sessions that chain cells
   likewise get inputRow forms), APPEND the new-model cases (fan-out graph
   with grandchild + all-children-revert; cycle silence + backward tap; the
   channel filter+stamp case and the ALL-cable case land with commit 5).
   Sessions whose musical content is model-independent need only mechanical
   field renames. Mirror every derivation-level case in the UNIT suite too.

6. **Channels: filter in, stamp out (delta §7/§7b — its own follow-up commit
   after the tree migration).** THREE moves: (a) per-Colour `outChannel`
   REMOVED (ColourState, panel, snapshot; loader drops it with a log — no
   automatic lifting, the human re-sets bus channels once); (b) INHERIT
   removed: pool entries and sounding sets lose the channel field everywhere
   EXCEPT the raw source pool, where per-cell `inputChannel` filters
   (0 = OMNI default) at source-derivation only; (c) document gains
   `busChannels[4]` (defaults [1,2,3,4]); there is NO outputMode. The AU
   declares FIVE outputs (ALL + A–D, cables 0–4); emission maps each
   (bus) → TWO events: (bus+1, busChannels[bus]) and (0, busChannels[bus]).
   Refcount keys on the EMITTED tuple, so the ALL duplicate and any
   shared-channel merge are ordinary refcount cases. Nothing upstream of
   emission changes besides the pool-entry slimming, which is deletion, not
   redesign.

## Sequencing (each commit leaves the suite green)

1. Schema: add `inputRow` + loader migration + version bump; router still
   reads the old fields. Verify: old saved session loads, T1–T8 pass
   unchanged; a round-trip (load old → save → load) is stable.
2. Snapshot: add resolvedParent/isTapped precompute + diag exposure
   (show resolvedParent per occupied row in the panel). No behaviour change.
3. Router flip: derivation reads resolvedParent; per-row sounding sets kept
   for the column pass; srcMix branch deleted; noDestination flipped.
   Verify: T1 (must be indistinguishable from pre-migration — single unfed
   cells don't exercise the change), T2, T5, then T9.
4. Cleanup: remove `stack`/`srcMix` from CellState and all writers; decode
   path keeps reading them for migration only, clearly commented as such.
   Full suite T1–T9 + T11 + bridge regression B1–B4 + the 10-minute soak.
   Tag `v0.4-graph-routing`.
5. Channels + ALL cable (change 6) as a follow-up: T10 green, tag `v0.5-outputs`.

## Verification emphasis (ask the human)

The migration's highest-risk moments are load-time conversion and the
reroute:
- Load every EXISTING saved AUM session the human still has; each must play
  identically to memory (chains → equivalent references).
- T5 and T9's mute transitions are the stuck-note hotspots: mute/unmute
  repeatedly at speed while holding a chord; the refcount invariant check
  must stay silent.

## After the engine: GUI reconciliation (the grid EXISTS — this is now part
of the plan, sequenced LAST)

A SwiftUI grid has been built against the OLD model/visuals. Do not touch it
during engine commits 1–5 beyond keeping it compiling. Then:
6. **UI survey** (rule zero again): catalogue what the grid binds (schema
   fields, gestures, visual generation — it likely predates v56). List before
   editing.
7. **Reconcile** to `Docs/midispark-preview-v56.html` per ui-port-guide:
   new schema bindings (inputRow/inputChannel/busChannels), four-row cell,
   FROM + emitter popovers, three-box desk (COLOUR/PROCESSOR/EMITTERS) +
   SCENE strip (wired to TestSessions in dev builds), watermarks, playheads
   per the one-clock rule. Human verifies each visual
   claim against the mockup side-by-side on the iPad.

## Explicitly out of scope

Launchpad, any engine work beyond the changes above, drag-and-drop colour
assignment and the hold cell-menu (delta §5 — a later UI pass), and any
resurrection of ▾ semantics "for compatibility" — old documents are converted
at load, not honoured at runtime.
