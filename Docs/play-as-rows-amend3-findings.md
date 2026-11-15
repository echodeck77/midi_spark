# PLAY AS ROWS Amendment 3 — findings (map before the build)

Paul 2026-11-15, ratified. Builds on PLAY AS ROWS (2026-11-11) + amend 1 (2026-11-13) + amend 2 (2026-11-15) + STACK RANKS GREY (2026-11-15), all landed on `main`. Display-only (no engine/stored-field change; golden byte-identical). Mapped against source.

## §0.1(a) WHEN RIFF — TWO INDEPENDENT FLAGS ⇒ §C4.2
`notesWhen: UInt8? = 0b11` — bit 0 PLAYS, bit 1 RESTS (`Models.swift:707-711`); `notesWhenResolved` forces 0b11 when 0; `notesPlaysResolved`/`notesRestsResolved` `:976-978`. The UI `whenRiffRow` (`EuclideousPage.swift:5707`) renders them as ONE segmented control — two `notesSegment`s `:5714-5715` (each toggling its own bit with a "can't turn the last off" guard). **Both draw selected on lanes 2/4 because a two-bit field (default 0b11 = both on) is shown as a segmented control**, which reads as a broken either/or. ⇒ §C4.2: two separate toggle tiles, each lit from its own flag.

## §0.1(b) the RANKS row
`ranksTilesRow` `EuclideousPage.swift:5525`; label "RANKS" `:5533`; eight tiles `:5535` (`notesRankTile:5555`); REPEAT button `:5543` / `notesRepeatButton:5592` (opens `notesRepeatPopup`). Layout `EuclideousPlayAsRowsLayout` (`PlayAsRowsUI.swift:9`): `labelW 55`, `tile 26`, `tileGap 3`, `subGap 4`, `repeatW 56`; `rankLabel` x0×55, tiles from x 59, `repeatButton` right-aligned `:47`. Under the number: the GREY bar (`StackRankPalette.colour(rank)`, `tile*0.4` × 3) `:5561` AND the role mark (`notesRoleMark`, #1B1D22 dots/bar) `:5563/:5582` — the collision. Sounding ring: INSIDE (1.5 pt border + 1 pt inset, `:5566-5573`), per stack-grey 4.3 (tiles 3 pt < 7).

## §0.1(c) the REPEAT pop-up
`notesRepeatPopupCard` `:5613` (title "REPEAT" `:5628`); `repeatGridCell:5662`. An UNLIT column: cells dead `#131518` `:5669`, tap `guard lit else { return }` (no-op) `:5671`, `.accessibilityHidden(!lit)` `:5672`. Header number `lit ? lane100 : #5A5E66` `:5664`.

## §0.1(d) the rank toggle + addedOrder
`euclideousToggleLitPosition(&line, position:)` (`Derivations.swift:5545`): sets `notesOn`, toggles the position in `litOrderResolved` (**= addedOrder, no separate field** — `Models.swift:779`), appends at the end when lighting. Called by the tile tap (`:5575`) AND the STACK grid tap (`euclideousStackCellToggle`→it, `:7599`) — one shared store/undo. The role (`setNotesRankRole`) is a separate field, untouched by the toggle, so a rank that comes back on keeps its role (§C1.4/§C2.5).

## Measurements / contradictions (source wins)
- **§C1.3 new tile width** = (fullWidth − labelW(55) − subGap(4) − 7·tileGap(3))/8 = (fullWidth − 80)/8. innerWidth = cardWidth − 20 (`EuclideousLaneCardMetrics.inset 10`, `Derivations.swift:4868`): landscape 380.67 → inner 360.67 → **tile ≈ 35.08**; portrait 387 → inner 367 → **tile ≈ 35.88** (from 26). Gap 3 + height 26 unchanged (C1.3). The grey bar's "% of the tile's width" must use the ACTUAL (wider) tile width, not the 26 constant. Sounding ring stays INSIDE (gap 3 < 7).
- **§C2.2 colour:** current dead cell is `#131518`; spec says live `#1E2025` — using the spec's.
- **§C4** is the two-flags branch (§C4.2), NOT §C4.1.
