# ANALYSIS → Paul + Code — THE STANDALONE APP (2026-08-22:
# effort · requirements · why now)

## The good news first: the engine needs ZERO changes
The transducer is f(state, input, beat) — pure. Standalone = the
same engine with a different BEAT SOURCE and different MIDI
plumbing. The App target already exists as the AUv3's container;
this fills it.

## The build list (Code-days, the house convention)
1. **The driver + transport (~2–3d)**: a near-silent AVAudioEngine
   session provides the sample-accurate render thread (the
   standard MIDI-app trick — also unlocks BACKGROUND running via
   the audio entitlement). An internal transport: play/stop ·
   BPM · beat position — the derive-law makes driving it trivial.
2. **CoreMIDI (~2–3d)**: OUT — four virtual sources named A–D
   (the wires become visible ports in every other app — the
   1:1 map is a gift); IN — a virtual destination + source
   picker feeding the doors (Network/Bluetooth MIDI arrive free;
   Paul's Launchpad bridge plugs straight in).
3. **Ableton Link (~1–2d)**: LinkKit (free license). Our
   beat-based engine maps perfectly — Link's beat IS our beat;
   the pass aligns to Link's quantum. Start/Stop sync = one
   toggle more.
4. **App chrome (~2–3d)**: a transport bar · port pickers ·
   the settings that AUM used to own (sample-rate irrelevant —
   we're MIDI-only). Everything else is the existing UI.
5. **Timing polish + device pass (~2–3d)**.
**Total: ~2 weeks of Code-days.** iPad-only v1; iPhone later;
hosting other AUs = NOT this (stays the parked chain-tail
question).

## "Anything else?" — the checklist
Background-audio entitlement (item 1 covers) · state persistence
(fullState → documents — exists) · SMF import/export (exists) ·
Bluetooth/Network MIDI (CoreMIDI freebies) · Link Start/Stop
(optional toggle). Nothing exotic remains.

## WHY NOW — Paul's testability instinct, confirmed and extended
- **The beta pool explodes**: AUv3-only TestFlight requires
  testers to own a host; standalone = anyone with the link
  plays. The demo path and the crash-report path both simplify
  (our process, not a host's sandbox).
- **Iteration speed**: Xcode → app directly; UI tests
  (XCUITest) become possible — they barely are inside a host.
  Screenshots/marketing captures stop needing AUM staging.
- **Link now = the standalone jams immediately** (the
  two-handed performer + a Link'd drum machine = the demo
  video).
- **The store**: an AUv3-only listing markets a screenshot of
  someone else's app. The standalone IS the product page.
- Cost honesty: a second run-mode to maintain — but purity
  means ONE engine, two drivers; the delta stays tiny forever.

## Recommendation
Yes — schedule the ~2-week spike after the current queue
settles. Phasing: ① driver + transport + CoreMIDI OUT (playable
alone) → ② MIDI IN → ③ Link → ④ chrome. The AU stays the power
context; the standalone becomes the front door, the test rig,
and the beta funnel in one build.
— design-side Claude
