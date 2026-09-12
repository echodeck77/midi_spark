# Ferry playback + colour unification

**Decisions (Paul 2026-09-13):** Refactor 1 = **Option A (collapse)**. Refactor 2 = **by POSITION**.
**Refactor 1 is BUILT** (see below). **Refactor 2 is NOT built** — it is fundamentally a *visual*
consistency change (which palette each surface shows), and cannot be verified off-device, so it is
handed to Paul's eye with the exact changes rather than recoloured blind.

Status: written 2026-09-12 off the four-agent adversarial review; updated 2026-09-13.
The three quick bugs (stuck-solo, re-tap-discards-edits, header-STOP-desync) are already fixed
separately — this doc is the two deeper *unification* refactors that remove the root causes of the
confusion, and the **decisions only Paul can make** before either is built.

The review found that almost every "confusing for a user" problem traces to ONE of two root causes:
the UI has **more than one source of truth** for (A) *what is playing* and (B) *what colour a machine
is*. Each refactor collapses one of those to a single authority.

---

## Refactor 1 — ONE authority for "what is playing"

### The problem
Playback state lives in TWO places that drift apart:
- `buildPlayColOn: [Bool]` — the per-ferry play-layer on/off (persisted, per column).
- `buildVoiceOwner: BuildWorkshopVoice` (`.none/.chain/.part`) — the active on-bench voice; the
  **active ferry sounds via `.part` (the staging step-sequencer)**, NOT via `buildPlayColOn`.

The header transport, the ferry PLAY buttons, and `composeScene` don't all read the same one, so:
- the header couldn't see/stop the active ferry (STOP-won't-stop — now patched);
- opening a stopped ferry force-sets `.part` → it auto-sounds while its PLAY button reads OFF (#2, still open);
- `buildPlayColHasContent` (the START-ALL gate) reads the **retired** `buildPlaySel`/`buildPlayColLen`
  path, not `buildFerryParts` — so START-ALL often starts no ferries (still open).

### THE DECISION Paul must make
Is "the bench part is sounding" the **same thing** as "this ferry is ON in the play grid", or **two
separate states** (an *audition* of the bench part vs a *committed* play-grid on-state)?

- **Option A — COLLAPSE (recommended).** A ferry is simply *playing* or *not*, tracked by
  `buildPlayColOn[t]` alone. The ACTIVE ferry, when on, renders via the staging sequencer (visible
  sweep); background ferries render via the flatten — but both derive their on/off from the *same*
  `buildPlayColOn`. There is no separate "audition the bench part" state. Mental model for the user:
  *"A ferry is playing or it isn't. Its PLAY button toggles it. The header STOP stops everything."*
  Simplest to reason about; kills #1/#2/#6 outright.
- **Option B — KEEP TWO, one authority.** Preserve a distinct "preview the bench part while stopped"
  audition, but make a single accessor the *only* reader/writer, and make the header + free-run gate
  both consult it. More states to explain to the user, but preserves silent-preview-on-open if that's
  wanted.

### BUILT (2026-09-13, Option A)
`buildVoiceOwner` now holds only `.none`/`.chain`; `buildStagingPlaying` is DERIVED
(`= buildActiveFerryPlaying = buildPlayColOn[active]`); `buildWorkshopVoice` composes the two so the
truth strips still read `.part`. Removed every independent `.part` write (buildActivateFerry,
buildSetFerryPlay, buildSelectStagingVoice). `buildTogglePlayGrid` routes through the one
`buildSetFerryPlay` path (choke:false for the bulk start) so START-ALL flattens ferries and STOP stops
the derived staging voice too. Opening a ferry no longer auto-plays. iOS builds; macOS suite green.
DEVICE-owed: the STOP/START/open feel. Deferred nuance: `buildTogglePlayColumn` (the retired play-cell
tap at 3256) still uses the old `buildPlayColHasContent` gate — inert for ferries, left alone.

### Original build plan (assuming Option A) — for reference
1. Make `buildVoiceOwner == .part` a **derived** view of `buildPlayColOn[activeFerry]`, not an
   independently-set flag. Remove the direct `buildVoiceOwner = .part` writes in `buildActivateFerry`
   (2098) and `buildSelectStagingVoice` (3907); opening a ferry no longer auto-sounds it. (`.chain`
   stays a separate SELECT-room audition concern.)
2. `buildStagingPlaying` becomes `roomsRoom == .part && activeFerry on` (derived), so the part-grid
   playhead + free-run gate follow the one truth.
3. Fix `buildPlayColHasContent` to recognise `buildFerryParts[c] != nil` so START-ALL starts ferries;
   arbitrate active(staging) vs background(flatten) for the active ferry in ONE place so it can never
   double-play.
4. Revert the interim `buildPlayPlaying`/`buildTogglePlayGrid` patches (from the quick-fix commit) to
   read the now-single truth — they become trivial again.
5. Re-verify: START/STOP ALL, per-ferry PLAY, one-shot expiry, move/delete, free-run-while-stopped.

### Risk
Touches `composeScene`'s play-layer branch (active-vs-background arbitration) — the one place a
double-play or silence could regress. Needs the RouterTests-style off-device pass on `composeScene`
plus a device ear-check.

---

## Refactor 2 — ONE rule for "what colour is a machine"

### The problem
Three palettes are used inconsistently per surface:
- `machineHue`/`machineHexes` — by machine **id** (the machine keeps its colour wherever it appears).
- `ferryHexes`/`buildFerryHex` — by **ferry position**, row-shaded.
- `partRowHexes`/`partPosHue` — by **row position**.

So the SAME logical object shows different colours on different surfaces:
- a part row is `partPosHue` on SELECT but `partFerryHue` on PART (#8);
- on SELECT the machine box/chain/card wear the **active ferry's** colour while the auditioned cell
  greys — nothing wears the colour of the machine you're hearing (#9);
- committed SELECT cells freeze the ferry hue at commit time (#11);
- `MachineBinding` — the documented single-source-of-truth meant to keep hue + play state from
  diverging — is now **dead code** (`buildMachineBinding` has zero callers), so the guarantee is void.

Two lifecycle defects sit under the same theme:
- **No GC** — `buildGCColours` was removed; ephemeral `b<n>` machines leak all session (#12).
- **Global hue table** — `machineHueOverride` is a process-global `var` while the registry is
  per-instance `@State`; two plugin instances collide and an undo in one wipes the other's colours (#13).

### DECISION (Paul 2026-09-13): **by POSITION** — the ferry/row slot defines the colour.
So the ferry-position palette (`buildFerryHex`/`ferryShadeHex`, shaded by row) is the ONE truth, and
every "this machine/part" surface must resolve through it. The remaining work is VISUAL (which shade
lands where) — hence device-owed. Concrete changes, each a small edit Paul can eyeball + tune:

1. **Row-selector split (#8) — `roomsSideChip` (BuildPage.swift ~2461).** Today the SELECT rail
   (`part:false`) uses `partPosHue`/`partPosFill`/`partPosFrame` (fixed row-position rainbow) while the
   PART rail (`part:true`) uses `partFerryHue`/`partFerryFill` (active-ferry, row-shaded). By-position ⇒
   make BOTH use the ferry-based recipe (drop the `part ? … : partPos…` ternaries). ⚠ CHECK ON DEVICE:
   the code comment calls the split deliberate — confirm the SELECT rail *should* wear the active ferry's
   colour (semantically it's the ferry you'd build into), or that the two rails genuinely mean the same
   rows. If they mean different things, keep them distinct and this isn't a bug.
2. **SELECT box wears ferry colour while the audition greys (#9) — `buildMachineHue`/`buildSelectGrey`.**
   Under by-position this is arguably CORRECT (the box wears the active ferry's slot colour; the browse
   cell greys because it isn't yet placed). Decide: keep as-is (position-consistent) OR make the box wear
   the auditioned cell's colour until commit. Device call.
3. **One accessor.** Route every "this machine" hue read (machine box, chain boxes, play button, part
   cell, ferry, both row selectors) through a single `buildResolvedHue` (or revive `MachineBinding` —
   which is already unit-tested — as that accessor), resolving by ferry-position. Then the card/box/play
   button can't diverge again. Delete the direct `machineHue`/`buildFerryHex`/`partPosHue` calls at those
   sites.

### (superseded) THE earlier decision framing
Is a machine's colour **by identity** or **by position**?
- **By IDENTITY** — a machine keeps its own hue everywhere it appears (box, chain, cell, ferry, both
  room selectors). "This blue arp is blue wherever I see it."
- **By POSITION** — the ferry/row *slot* defines the colour; whatever part sits in slot 0 is red.
  Paul's recent commits (e.g. e354a9d "a selector is always selected; wears its pre-allocated colour")
  lean this way for the ferry world.

Whichever is chosen, it must be **the same rule on every surface** — that is the whole fix. The
current pain is the *mix*.

### Build plan
1. **Pick the law** (identity or position) — the one decision above.
2. Introduce a single accessor `buildResolvedHue(for:)` (or revive `MachineBinding` as the authority)
   and route EVERY hue read through it — the ~12 surfaces (machine box, chain boxes, play button,
   part cell, ferry, SELECT-grid cell, both row selectors, emitter strip is already consistent,
   constellation). Delete the direct `machineHue`/`buildFerryHex`/`partPosHue` calls at those sites.
3. Make the SELECT and PART **row selectors** read the same source (fixes #8).
4. Decide the **audition treatment**: either the box/chain wear the *auditioned machine's* colour
   (fixes #9 — recommended), or keep grey but grey *all* surfaces together. No half-grey state.
5. **Lifecycle:** move `machineHueOverride` (+ the transpose table) into per-instance `@State`; make
   undo **merge** rather than replace the whole dict (fixes #13). Add a bounded GC / reclaim of
   orphaned `b<n>` machines on row-overwrite / clear / TRY-AGAIN (fixes #12).
6. Delete the dead `MachineBinding`/`buildMachineBinding` if not revived as the authority (#3-reflection),
   and delete the stale long-press-seed comments (BuildPage.swift:1934, 2055).

### Risk
Mostly mechanical (routing reads through one accessor) once the law is chosen. The lifecycle moves
(#12/#13) are behavioural — GC must use a correct liveset (the old bug class was freeing a live
colour), and the per-instance table move needs a save/reload round-trip test.

---

## Suggested sequencing
1. **Refactor 1 first** (playback) — it's the more acute "the app feels broken" problem and is
   self-contained.
2. **Refactor 2 next** (colour) — larger surface but lower urgency; do it in the order: pick the law →
   single accessor → lifecycle (#12/#13) → delete dead code.

Each refactor is one device-verifiable landing. Both want Paul's decision (Option A/B for #1; identity
/position for #2) before code.
