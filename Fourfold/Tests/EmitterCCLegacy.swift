//  EmitterCCLegacy.swift — test helper (CC tab, amendment 1): the old TRAVEL (STEP · GLIDE · FALL) and TIME expressed as the new hold-then-ramp settings, so the engine and trace tests written against the old controls keep proving the SAME behaviour:
//  STEP = hold the hit's value for the whole gap · GLIDE(t) = hold 100 − t, ramp t to NEXT (linear) · FALL(t) = ramp t from the hit to REST (linear). The production model has none of these names.

import XCTest

enum EmitterCCTravel: CaseIterable { case step, glide, fall }

extension EmitterCC {
    /// An emitter configured the way the removed controls did: `mode` (default RIFF, as the old default), `travel` (STEP), `time` (50 %).
    static func legacy(on: Bool = false, ccNumber: Int = 74, mode: EmitterCCValueMode = .riff, high: Int = 127, low: Int = 0, travel: EmitterCCTravel = .step, time: Int = 50, muteValue: Int = 0, passes: Int = 1) -> EmitterCC {
        switch travel {
        case .step: return EmitterCC(on: on, ccNumber: ccNumber, valueMode: mode, high: high, low: low, hold: 100, ramp: 0, to: .rest, curve: .lin, muteValue: muteValue, passes: passes)
        case .glide: return EmitterCC(on: on, ccNumber: ccNumber, valueMode: mode, high: high, low: low, hold: 100 - time, ramp: time, to: .next, curve: .lin, muteValue: muteValue, passes: passes)
        case .fall: return EmitterCC(on: on, ccNumber: ccNumber, valueMode: mode, high: high, low: low, hold: 0, ramp: time, to: .rest, curve: .lin, muteValue: muteValue, passes: passes)
        }
    }
}
