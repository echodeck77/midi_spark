# KIT CARD V2 — findings (§0.1 a–h, §11), before any change

Ferry: move the whole KIT editor onto the MODE-tab card (like DRUM CARD V2) — a template ▾ + SAVE row, an
8-rank strip, the DRUM selector + a VEL slider for the selected rank, drag-a-rank-to-copy, CONVERT TO DRUM;
a hand-edited kit shows CUSTOM and becomes the default for every lane that hasn't been changed; SAVE stores a
user template shared app↔AU. file:line on `feature/kit-card-v2` (off `feature/drum-card-v2`). Read-only.

## (a) KIT's rows + heights
`poolTabContent` (EuclideousPage.swift:8169-8209), non-DRUM path: `modeRow` 30 · `poolNowRow` (POOL) ~44 ·
`kitRow` ~30 · `Spacer` · `inputsApplyAllButton` 30. Heights from `euclideousInputsTabLayout` (ideals
44/30/30/44, gap 14→8, floor 30; `EuclideousPoolTabMetrics` Derivations.swift:13719, labelColumn 50, toggleH
26). `kitRow` (8435-8464) = **KIT | [template ▾ 2/3] | EDIT 1/3** (RESET GM already gone). Ferry → KIT's OWN
fixed heights **MODE 34 · KIT 32 · RANKS 44 · NOTE 50 · VEL 30 · APPLY**, no POOL (mirrors DRUM at 8175-8188).
Portrait-ref numbers reported when the card slice lands.

## (b) How far KIT TEMPLATES landed
`kitTemplate: String?` (Models.swift:857); static table `KitTemplates.swift`; `templatePicker`
(KitEditorViews.swift:74-112 — a fixed GM row + APPS|HARDWARE scroll columns, the current row lit, auto-scroll
to current); the GM ▾ button on the card = kitRow's template button (8444-8454, opens the EDITOR + its picker),
in the editor header = `templateButton` (KitEditorViews.swift:124). `onPickTemplate` (8378-8384) writes
notes+names+vel100+kitTemplate, one undo step. The picker currently lives INSIDE the editor overlay → this
ferry lifts it to a standalone card-level overlay.

## (c) The kit editor overlay + open paths
`kitEditorView` (8311-8387) builds `EuclideousKitEditorView` (KitEditorViews.swift:13-339): header (KIT/DRUM
title, OCT −/+ `shiftWell`, SEMI −/+, DRUM button, template button, close), the ▼/▲ copy (`copyBtn`), 8 rank
cells (`ranks`), the NAME `TextField`, the VEL tile, the keyboard (`keyboard`) + the range label
(`octaveButtons`), RESET GM (`onResetGM`). Mounted at EuclideousPage.swift:2069 (z10, catcher z9) and 2299
(scaled). **Open paths:** kitPoolCell tap (8283), kitRow template button (8453, + `kitTemplatePickerOpen=true`),
kitRow EDIT (8460). **KIT→DRUM** = `onMakeDrum` (8361-8365): `edit(lane){ drumNote=notes[rank]; laneMode=.drum }`,
one step (keeps the kit). State to remove: `kitEditor`/`kitEditorNameDraft`/`kitEditorRangeLow`/
`kitEditorPrevNote`/`kitEditorIsDrumPicker` (1111-1115).

## (d) Kit fields + writers + kitNames readers
Models.swift:854-857 `kitNotes/kitNames/kitVel/kitTemplate` (+ resolvers 858-862, decoders 1489-1492). WRITERS:
reset/assign/shift/copy/pickTemplate/toKitFromDrum (EuclideousPage 8304-8591) + APPLY (Derivations 13711).
**kitNames READERS to remove (§1.5):** the editor rank cells (KitEditorViews.swift:192), the selected tile (215),
the NAME field (224); `kitEditorView` seeds/commits (8295/8302/8314/8329/8346/8351/8357/8368/8374); `kitPoolChips`
reads it for a11y only (8259/8285 — draws the NUMBER, 8276). The STACK/riff grid read `kitNotesResolved`
(numbers), never names; `Snapshot.swift:333/445` note kitNames are UI-only, not carried to the engine. §1.5: keep
`kitNames` decodable, write it nowhere.

## (e) CONVERT
DRUM→KIT `euclideousKitFromDrum` (Derivations.swift:13527) → `toKitFromDrum` (8588, currently sets kitTemplate nil
— this ferry makes it "custom" + fires the default-kit rule). KIT→DRUM = `onMakeDrum` (8361), writes
drumNote+laneMode, keeps the kit (= §3.5 CONVERT TO DRUM's action).

## (f) APPLY TO ALL
`euclideousApplyInputsToAll` (Derivations.swift:13706-13716) copies `poolSrcMask`+`midiMode`, ALL kit fields
(`kitOn/kitNotes/kitNames/kitVel/kitTemplate`), drum fields, `laneMode`; NOT canon. §2.4 adds `kitFollowsDefault`.
Lanes are independent today (no live cross-lane kit; the only cross-lane copy is this one-shot) — the default-kit
rule (§2) is NEW behaviour.

## (g) App-level shared storage — NONE today
No `com.apple.security.application-groups` entitlement anywhere. App writes `Documents/Presets`, the AU
`Application Support/Presets` (`PresetStore.directory` PresetStore.swift:46-57; app flips `useDocumentsFolder`
FourfoldApp.swift:9) — SEPARATE sandboxes. `UserDefaults` is `.standard` only (per-process). `PresetStore.swift:7-8`
already flags the App-Group swap as a follow-up. **Decision (Paul 2026-11-26): group-ready, enable later** — a new
`KitTemplateStore` uses `containerURL(forSecurityApplicationGroupIdentifier: "group.com.paulbarrett.Fourfold")` ??
per-process Application Support (nil without the entitlement ⇒ per-process ⇒ builds + works now; enabling the App
Group at the portal later turns on app↔AU sharing with no code change). §8.10/§9 "shared" stays device-owed.

## (h) DRUM CARD V2 pieces to reuse (built, on this branch's parent)
`euclideousDrumScrubNote` (Derivations.swift), `drumField`/`drumChevron`/`drumConvertButton`/`drumStepNote`/
`drumAudition` (EuclideousPage.swift), `euclideousDrumRowFrames` + `DrumSelectorChevron`, `onKitAudition` (the kit
one-shot). The NOTE row reuses these, generalised to edit the SELECTED RANK's note and audition at the rank's
velocity (not drumHigh). **Rank preview (DRUM §4) is NOT built yet** → KIT headphone is interim (pool audition).

## §11.5 — spec vs code
- §3.5 "CONVERT TO DRUM keeps the lane's kit" matches `onMakeDrum` (writes drumNote+laneMode only). No conflict.
- Note names use the ♯ glyph (`euclideousNoteViewName`), not ASCII "#" (carried from DRUM CARD V2).
- §2.5: the default-kit rule meets APPLY TO ALL (copies the fields), presets (whole-doc replace → normalise on
  load), RESETS / lane-copy (don't touch kit) — none conflict; will re-confirm each when the rule lands.
