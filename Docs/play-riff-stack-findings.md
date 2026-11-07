# PLAY RIFF / PLAY STACK ferry — findings (§0 map)

Ratified Paul 2026-11-07. Fourfold only. The lane card's play tile → PLAY RIFF (toggles the riff part), the SOLO tile → PLAY STACK (toggles the notes part). Lane PLAY stays on MIX's strip; solo stays on MIX, per part. One decode fold (lane solo → part solo) — **already present**. No engine path change; golden byte-identical.

Audited against the raw ferry text. Where it disagreed with the code, source wins (reported in §10 of the status log / below).

## §0.1(a) the top row

- Assembled in `EuclidLaneBox.body` — a shared HStack, `Fourfold/UI/EuclidLaneUI.swift:157-219` — built for the lane card by `laneCometRow` / `laneCometRowBody` (`EuclideousPage.swift:2373-2450`), driven `width: innerWidth, height: cometRowH(44)`.
- **PLAY tile:** `EuclidCompactPlayButton` (`EuclidLaneUI.swift:245-268`), fixed **44 × 44**, corner **radius 9** (`RoundedRectangle(cornerRadius: 9 * s)` `:263`), plate `#2A2D34`; ON = `EuclidPlayTriangle().fill(accent)`, OFF = a 13×13 `accent@0.4` rect. Tap `onToggle` → wired `onToggleEnabled: { edit(idx){ $0.enabled = !($0.enabledResolved) } }` (`EuclideousPage.swift:2423`). Field **`EuclidLine.enabled`** (`Models.swift:291`) / `enabledResolved` (`Models.swift:1009`, default true). Undo: `edit(idx)` → `onEdit` (`EuclideousPage.swift:1542`), coalesce per lane-bits (`FourfoldRootView.swift:228-243`).
- **SOLO tile:** `soloButton(idx, accent)` (`EuclideousPage.swift:2700`) → `EuclideousSoloPressable` (`LaneSoloPainter.swift:56`), 44 × 44 radius 9; injected into `EuclidLaneBox` as the `soloButton:` AnyView (rendered after the comet bar, `EuclidLaneUI.swift:198-201`).
- **COMET STRIP:** `EuclidCometBar` (`EuclidLaneUI.swift:275+`), width computed `innerWidth − leadReserve − badgeReserve` (`:187`), NOT a fixed CGRect; not passed the solo button.
- **Lock badge:** `EuclideousLockBadge` (`EuclideousLock.swift:476-496`), 34 × 34, sp4 before SOLO; `cometStripWidth(innerWidth:withBadge:)` gives the strip width. Drawn only when both soloButton and lockBadge exist (`EuclidLaneUI.swift:198-200`).
- Frames at the references (card coords, row y 10 h 44): **landscape 380.67 × 301** → play x10, comet x60 w260.67 (224.67 with badge), SOLO x326.67, badge x288.67 y15; **portrait 387 × 301.67** → SOLO x333, comet w267 (231), badge x295. From `EuclideousLaneCardMetrics` (`Derivations.swift:4599`, inset 10 / cometRowH 44 / rowGap 6) + `EuclideousLockBadge`. All from card size → holds across every page layout.
- Other PLAY writer: MIX's strip play tile (`EuclidCompactPlayButton` reused in the MIX band, same `enabled` field + undo). **No host parameter or MIDI-learn on PLAY** (see (d)).

## §0.1(b) riffOn / notesOn

- `EuclidLine.riffOn: Bool?` (`Models.swift:384`) → `riffOnResolved` (`:435`). `EuclidLine.notesOn: Bool?` (`:583`) → `notesOnResolved` (`:1063`). The notes part's EFFECTIVE on = `euclideousNotesLayerIsOn` = `notesOnResolved && euclideousNotesHaveSelection` (a lit selection) — `Derivations.swift:5024/5031`.
- ONE off-predicate: `euclideousMixLayerIsOff(_ line, notes:)` (`Derivations.swift:5019`) — riff ⇒ `!riffOnResolved`, notes ⇒ `!euclideousNotesLayerIsOn`. The tab glyphs, MIX pad, lane strip and card all read it.
- Writers (all funnel `edit(idx)` → `onEdit`, one undo idiom): the RIFF tab tile `riffCard` (`EuclideousPage.swift:3860`, direct `riffOn` write); RIFF direction buttons (`:4050`); the NOTES strip (`:4297`, direct `notesOn` write, **no auto-light**); the shared funnel **`cardBackToggle(idx, part)`** (`:2637`) used by MIX v1/v2 toggles (`toggleOn` → `:2545`) and the card-back TURN-ON pill — it **auto-lights rank 1 when NOTES turns on** so the layer actually reads on.
- **Decision:** both PLAY buttons tap `cardBackToggle(idx, .riff/.notes)` — the same funnel MIX's toggles use (§3.1 lists MIX's toggle as a co-writer), so PLAY STACK makes the notes audible (auto-light), and PLAY RIFF == the riff tile's write. One undo step (§2.6).
- The lamp "on" = `!euclideousMixLayerIsOff(line, notes:)` — the exact predicate the tab glyphs use (§3.1 "reads the same field").
- The tab STRIP is not a writer (`EuclideousLaneViewStrip.onSelect` selects a tab; its glyphs display state).

## §0.1(c) the note feed (the flash)

- NoteRoll (`NoteRollRing.swift`): `NoteRollNote.outs` (bits 0–3 = outputs; **0 = routed nowhere**, `isSilent`), per-part arrays `parts[8]`, drained on the 30 Hz poll (`FourfoldRootView.swift:934`, `NoteRollLive`). This is the authoritative "reached ≥1 emitter" signal, accounting for routing and output mute.
- EMITTER TOKEN's `euclideousMixLineActivity(notes:output:nowBeat:tempo:)` (`MixPanel.swift:385`) is 1 while a note of the part sounds on that output then a **150 ms linear fade**, read from `outs`. **Reuse it per part** (max over the four outputs) → the lamp flashes on each note-on the part sends to ≥1 emitter, fading over 150 ms, and a routed-nowhere part never flashes.
- The PULSE feed (`EuclideousPulseFeed` / `euclideousPulseEnvelopes`, τ 0.16 s) carries a wall-clock onset + velocity but **not** a clean routed-nowhere bit (`riffDest/notesDest == -1` means "unspecified", not "silent"), so it is NOT used for the flash gate.
- Latency ≈ one poll (≤ 33 ms). Reduce Motion (§2.5): full glow for 100 ms, no fade — a separate path (newest note-on age < 0.1 s ⇒ full, else 0).

## §0.1(d) solo masks, the fold, host params

- Latched lane `euclideousSoloMask` (`Models.swift:3667`); held lane `euclideousSoloHeld` (UI only, `FourfoldRootView.swift:1151`); latched part `euclideousPartSoloMask` (`:3671`, bit 2n riff / 2n+1 notes); held part (`:1153`).
- Predicates read **both masks as a union**: `euclideousPartAudible` / `euclideousPartSoloSilences` / `euclideousLaneSilencedBySolo` / `euclideousLaneMayStrike` (`Derivations.swift:9098-9112`); the header states "a lane bit is exactly its two part bits".
- **`normalizeSoloAtLoad` (`Models.swift:3675`) ALREADY does the §5 fold:** `euclideousSoloFold` OR-s both part bits (2n, 2n+1) for every latched lane bit into `euclideousPartSoloMask`, then sets `euclideousSoloMask = nil`; idempotent; called at every load (`FourfoldAudioUnit.swift:754`, `PresetStore.swift:32`). Proven by `PartSoloTests.swift:217-226`. The lane SOLO tile tap already folds-then-flips and zeros the lane mask (`FourfoldRootView.swift:450-457`), as does the MIX S button (`:473-475`). So §5 is **verify + report**, not new code; §5.4 (Router bit-identical with both lane masks 0) is already how the engine runs.
- **§5.3 consequence:** once the card's SOLO tiles are gone, `euclideousSoloHeld` (the held LANE mask) has **no writer left** — it stays 0. The field stays decodable.
- **No host parameter or MIDI-learn on lane solo or lane play.** The param tree (`FourfoldAudioUnit.swift:432-464`) is only stepRate (0) / swing (1) / transpose (100+i) / macro (400+i); no solo/enabled/play address; no MIDI-learn table of ours (`:456` comment). §5.5 is a no-op.

## §0.1(e) dims + exemptions

- One 42 % (`EuclideousLaneDimStyle.opacity`, ease 0.15 s). On the card: solo-silenced dim (`soloSilenced(idx)` → tab content `EuclideousPage.swift:2490`, play button `EuclidLaneUI.swift:161`, whole comet strip `:196`); LANES-mute dim (`:609`, stands down under solo, `suppressMuteDim`); the no-hit dim is MIX-only; part-off dim lives in the tab bodies / card backs. **Never dims:** the SOLO tile (`:112-113`, `EuclideousPage.swift:2475`), the card ground/border (`:2495`), the lock badge (`:2648/2904`), the riff toggle (`:3995`).
- **§4.2:** the play button DIMS today — PLAY RIFF must take over the SOLO tile's never-dim exemption (remove the lead-tile dim).
- **§4.1 is NEW:** today the strip dims only on solo/mute; "both parts off (`euclideousMixLayerIsOff` both true) → comet strip 42 %, still walking" is added, eased 0.15 s, OR-ed into the strip's dim (one 42 %, never stacked). A silenced/muted lane already keeps walking (`EuclideousPage.swift:5749`), so adding opacity doesn't stop the animation.

## §0.1(f) glyph state on a part's on/off control

- `HocketGlyphSpec` (`Derivations.swift:10126-10152`) draws: `.offLook` / `.filled` (playing) / `.outline` (resting/away) + `awayDisc` (7 pt) + `carriedRing`. States from `HocketPartView.Play` {playing, resting, away(bus)} + `carrying`.
- Drawn on: the tab-strip glyphs (`EuclideousLaneStripHocketGlyph` `LaneViewStripPainter.swift:37-78`, always); MIX part toggles + card-back pill (`HocketPartGlyph`, only when a rule is lit). The RIFF/NOTES tab TILES show on/off by **card colour only** (no hocket glyph).
- **§3.2:** these four states (playing / resting-hollow / away-disc / carrying-ring) will **not fit** the 5.5 × 6 triangle lamp; the lamp shows on/off + the note flash only. The hocket state stays on the tab-strip glyph (always visible) and MIX. Reported, not replicated on the lamp (§3.2 "report anything that doesn't fit").

## §0.1(g) mode card faces

- **RANDOM** card (`EuclideousRandomCardView`, `RandomModePainter.swift:85-94`) draws a PLAY (`EuclidCompactPlayButton`) top-left + SOLO (`soloButtonView`, the card's own `soloButton(idx,accent)`) top-right. §1.4 applies: these become PLAY RIFF / PLAY STACK.
- **LOCK** card face (`EuclideousLockCardView`, `LockModePainter.swift`) draws no play/SOLO row (number / title / status / 88×88 padlock). Only the lock BADGE (in the normal card) matters. Unaffected.

## §0.2 what is hidden / what stays
- `EuclidCompactPlayButton` and `EuclideousSoloPressable` STAY (hidden-not-deleted) — MIX's strip reuses the play view; the lane SOLO tile's code stays compiled. Every stored field (`enabled`, `euclideousSoloMask`, `euclideousSoloHeld`, `euclideousPartSoloMask`) stays decodable. Nothing deleted.
