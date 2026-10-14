# FourStep — Visual Design Language

*Project Knowledge document for a Claude.ai Project. Upload this file as-is. Companion file:
`fourstep-claude-project-knowledge-product.md` (the product reference).*

This describes what's actually in the shipped UI today — not a style proposal. Use it to keep
design conversation grounded in the real instrument rather than a generic synth/plugin aesthetic.
A short provenance tag marks how sure each section is:

- **\[exact]** — read directly from the app's own source values.
- **\[consistent]** — repeated the same way across the project's own build history; treated as
  settled, though not line-by-line re-checked against the current build on the date of writing.

## The instrument is dark, deliberately

FourStep has no light theme — committed, not an oversight. It's an instrument panel, used in a
dim performance setting as much as a bright one; the dark ground is part of its identity, not a
default that happened to stick.

## Core palette [consistent]

| Role | Hex | Where it shows up |
|---|---|---|
| Ground | `#15161A` | The page's own dark background. |
| Panel / unselected | `#2A2D34` | Card fill; any unselected tab or chip. **[exact]** |
| Primary text | `#F2F4F7` | Default text colour on the dark ground. |
| Muted text | `#AAB0BA` | Secondary text, unselected labels. |
| Ink | `#0D0F14` | Text drawn *on* a light/selected fill — not a text colour on dark. |
| Select / editing fill | `#DFE3EA` | The solid light fill marking "this is the selected / currently-editing" state. |
| Static reference mark | `#3A3E47` | Neutral dots and lines — a rest step, a zero line, a tick mark. |
| Warning amber | `#FFB454` | "No output routed" and similar warning states — never used to mean "active." |

## The four lane colours [exact]

Each of the four lanes has its own accent hue, used consistently wherever that lane's own state
is shown (its selected border, its active toggles, its riff/mask highlights):

| Lane | Hex | Character |
|---|---|---|
| 1 | `#F25959` | Coral / warm red |
| 2 | `#59BFF2` | Cyan / cool blue |
| 3 | `#F2BF40` | Amber / gold |
| 4 | `#8CD973` | Green |

Each lane's own colour is used at three opacity levels on the *same* hue, not as three separate
colours: full strength for an active/selected state, a medium level for an intermediate
highlight, and a low level as the standard "this is the selected choice" fill behind a control.
When proposing new UI, reuse this three-tier idea rather than inventing a second colour system
for emphasis.

## Spacing [exact]

The shipped page uses exactly three spacing values throughout, nothing in between: a small gap
(roughly 4pt) between elements inside one card, a medium gap (roughly 8pt) between cards and as
padding inside a card, and a larger gap (roughly 16pt) for page margins and the space between
major regions (header, the lane area, the riff panel). Any new layout proposal should pick from
this same small set rather than introducing an arbitrary fourth value.

## Type conventions [consistent]

- **Header labels and chips are heavy, letter-spaced, uppercase, and set in a monospaced face** —
  a deliberate, slightly technical/instrument-panel feel, distinct from the body text.
- **Nothing shrinks to fit.** There's a standing rule against auto-shrinking text to make it fit a
  space — a label that's too long truncates instead. Don't propose designs that rely on dynamic
  font scaling to cram text in.
- **A control's current value is always visually heavier or brighter than its own name.** The
  name is context you glance past; the value is the thing you're actually checking.

## Two recurring component shapes

**"Selected choice"** — a control that's currently active gets a low-opacity fill in its relevant
colour, a thin full-strength border in the same colour, and full-strength text. An inactive
version of the same control gets the plain panel fill, no border, and muted text. This single
pattern covers direction pickers, riff-walk pickers, source choices, and active output toggles —
reuse it rather than inventing a new "selected" treatment per control.

**Step / hit cell** — a step that will sound gets the light select fill with dark ink text on it;
a rest gets the plain panel fill with a dashed border in the neutral reference colour, and no
text. A rest is always drawn as a dim but clearly *present* cell — never as truly blank or
invisible. An earlier version of the UI drew rests as faint, barely-visible marks, and it read as
"the note disappeared" rather than "this step is off" — worth remembering as the specific mistake
to avoid if proposing a new way to represent a rest.

## If proposing new screens or features

Anchor new ideas in this same system: the dark ground, the four lane hues at their three opacity
tiers, the small fixed spacing scale, the heavy monospace label convention, and the two component
shapes above. A design idea that introduces a fifth accent colour, a new spacing value, or a
different "selected" treatment should be flagged as a deliberate departure, not slipped in as if
it already matched the existing language.
