# FourStep — design tokens

What's actually in the shipped UI, not a proposal. Pull values from here first; when in doubt,
the source file wins over this doc. A browsable version with live colour swatches lives at
[the published artifact](https://claude.ai/code/artifact/02c30eff-1b28-4ef7-bb4b-9a3613824a9b) —
this file is the durable copy; update this one, the artifact is a rendering of it.

Two provenance tags are used throughout:
- **\[verified]** — read directly from current source, with a file:line citation.
- **\[consolidated]** — consistent across many ferries and the ratified mockup in
  `Docs/euclideous-status-log.md`, not individually re-diffed against every current call site.

## Core palette [consolidated]

| Token | Hex | Usage |
|---|---|---|
| Ground | `#15161A` | Page background; the RIFFS panel's own dark ground. |
| Panel (unselected) | `#2A2D34` | Card fill; unselected tab/chip fill. **\[verified — EuclideousPage.swift:1586, `patternUnselectedFill`]** |
| Text | `#F2F4F7` | Primary text on dark. |
| Muted | `#AAB0BA` | Secondary text, unselected labels. |
| Ink | `#0D0F14` | Text drawn on a light/selected fill. |
| Select / editing fill | `#DFE3EA` | The "this is selected / this is the editing tab" solid light fill. |
| Static mark | `#3A3E47` | Neutral reference lines/dots — a rest, a zero line, a tick. |
| Warn | `#FFB454` | "NO OUT" and other amber warning states — never used for an active lane. |

## Lane accents [verified — EuclideousPage.swift:661–664, 1577–1579]

Four lanes, three opacity tiers each on ONE hue per lane (`lane100` = 1.0 opacity, `lane40` =
0.4, `lane20` = 0.2) — not four separate colour triads. Hex values below are the 8-bit rounding of
the actual `Color(red:green:blue:)` floats in `laneAccents`.

| Lane | Hex | 100% (active/selected) | 20% (standard "selected choice" fill) |
|---|---|---|---|
| 1 | `#F25959` (coral) | solid fill | 20% opacity of the same hue |
| 2 | `#59BFF2` (cyan) | solid fill | 20% opacity of the same hue |
| 3 | `#F2BF40` (amber) | solid fill | 20% opacity of the same hue |
| 4 | `#8CD973` (green) | solid fill | 20% opacity of the same hue |

## Spacing scale [verified — EuclideousPage.swift:675–677]

The only three legal gap values anywhere on the Euclideous page — no other literal spacing value
should appear in new layout code.

| Token | Value | Usage |
|---|---|---|
| `sp4` | 4pt | Inside a card — between pads, segmented buttons, rows. |
| `sp8` | 8pt | Between lane cards; padding inside every card/panel, all 4 sides. |
| `sp16` | 16pt | Page margins; gap between header / lane grid / riff panel. |

## Type conventions [consolidated]

Exact point sizes have been retuned across many ferries and would go stale here immediately —
these are the conventions that have held constant, not fixed numbers. Read actual sizes from
source.

- **Header chips** — heavy, letter-spaced, uppercase monospace.
- **Truncate, never shrink** — no `.minimumScaleFactor` anywhere on this page; a label that
  doesn't fit truncates. Standing house rule, not a one-off — don't add a scale factor to make
  text "fit."
- **Value vs. label** — a control's current value is always visually heavier/brighter than its
  own name; the name is context, the value is what's read at a glance.

## Component patterns

**Selected choice** — selected: lane-20 fill · 1px lane-100 border · full-strength text.
Unselected: `#2A2D34` fill · no border · muted text. Used for direction, riff walk, source
choice, active OUT toggles.

**Step / hit cell** — hit: `#DFE3EA` fill, ink text. Rest: panel fill, dashed mark-colour border,
no text. A rest is drawn as a dim, *present* cell, never a true gap — a blank/invisible rest has
been reported as "the note vanished" rather than "off" more than once; keep it visible.

**Lane strip (LANE STRIP ferry 2026-10-21) [verified — LaneStripPainter.swift `EuclideousStripPalette`]** — track cell (hit) `#28292D` = the riff grid's empty cell as composited (white 8% over its 3.5% panel on the page ground; the ferry said `#24262C`); chip `#DCDCDD` = the riff grid's note cell (white 85%; the ferry said `#DFE3EA`), ink label `#0D0F14` 7pt heavy; rhythm rest `#1A1C21` + 1pt dashed `#3A3E47` (3 on, 2 off); gap = the cell + a 1pt lane-100 ring @ 45%; grey chip `#6B707A`; hollow (REPEAT) chip = a 1pt dashed lane-100 stroke; key (notes play) `#30343C` / border `#454A54`, label `#CBCCCE`; key (unlit) `#17191E` / `#202329`; current chip = the chip + the arrow's lane gradient (95% → 55%). Playhead: lane-100 @ 14% + a 2pt lane-100 @ 85% leading edge.

## Keeping this honest

Committed to dark-only — this documents the real shipped instrument, which has no light theme.
Re-verify the `[consolidated]` rows against source the next time colour/spacing work touches
Euclideous; promote them to `[verified]` once rechecked, or correct them here if they've drifted.
