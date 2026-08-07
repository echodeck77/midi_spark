# Acceptance Criteria — THE DIN ICON (the MIDI plug mark)

_Captured from the ferry `SPEC-din-icon.md` (design-side Claude, 2026-08-07). No SF Symbol exists for DIN — a
custom SwiftUI `Shape`. **BUILT (filled variant)** as `DINPlug` (`AUExtension/EditPage.swift`), placed in the flow
diagram's receiver box (left = MIDI IN) + emitter box (right = MIDI OUT). Outline variant + the other usages below
are owed._

## THE GEOMETRY (unit circle r = 1, centre 0,0; notch at 12:00)
- **SOCKET RING**: circle r 1.0, stroke weight w.
- **KEY NOTCH**: a small rect at 12:00 — width 0.28, height 0.18, sitting ON the ring (outer edge flush), centred on
  top. (Filled variant: the notch is a NOTCH — subtract it from the disc.)
- **FIVE PINS**: small radially-oriented stadium slots at clock 2·4·6·8·10 (a 180° arc facing the notch, 45° apart;
  simplest: angles from top = ±60°, ±120°, 180°). Each pin: length 0.30, width 0.14, CENTRE at radius 0.55, long
  axis pointing at the centre. Round caps.

## WEIGHTS + SIZES
- **OUTLINE variant** (headers, cog rows): stroked ring + filled pins + a key tab. **BUILT** (`dinMark(outline:true)`).
- **FILLED variant** (chips, the flow's receiver/emitter boxes): solid disc, notch subtracted, pins knocked out
  (holes) — reads at 12pt. **BUILT** (`DINPlug` filled with the even-odd rule).
- Ink follows context (the ink/dim tokens); never hue-tinted — it's a mark, not a status.

## IN vs OUT (the photo's own answer)
The socket is IDENTICAL both ways — differentiate by LABEL, as hardware does ("IN" / "OUT"), which the flow's boxes
already carry ("R1: MIDI IN" / "A: MIDI OUT"). Optional later: a tiny arrow beside the socket (▸ entering for IN,
exiting for OUT) if a label-free context ever needs it — not now.

## USAGE
The receivers/emitters boxes in the flow **(done)** · the cog's door rows · FROM·MIDI IN / TO·MIDI OUT section
headers · anywhere the manual draws a port. One Shape, two variants, every size.

## IMPLEMENTATION NOTE (as built)
`DINPlug: Shape` — disc + notch + 5 pins in one path, `fill(ink, style: FillStyle(eoFill: true))` so the notch/pins
are holes. The notch is inset a hair from the top edge (fully inside the disc) so even-odd gives a clean bite rather
than a chimney tab. The OUTLINE variant (stroked ring + filled pins) is not yet built.
