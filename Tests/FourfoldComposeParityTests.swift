//  FourfoldComposeParityTests.swift
//  FOURFOLD Step 1b (2026-10-23): the Fourfold-only scene composer must place exactly what 8x8 State's `composeSceneMeta` places for the Euclideous cell. This is the BRIDGE between the two products — it lives with the 8x8 tests (MidiSparkTests), because only they compile `BuildSceneLogic`; Fourfold's own tests are Fourfold/Tests/FourfoldComposeTests.swift.

import XCTest

final class FourfoldComposeParityTests: XCTestCase {

    private func input(from doc: PluginState, solo: UInt8 = 0, revs: UInt32 = 0) -> FourfoldCompose.Input {
        FourfoldCompose.Input(lines: doc.euclideousLinesResolved, riff: doc.euclideousRiffResolved, riffs: doc.riffsResolved, activeRiff: doc.activeRiffResolved,
                              mainOutMask: doc.euclideousMainOutMaskResolved, soloMask: solo, locks: doc.euclideousLocksResolved, lockRevs: revs)
    }
    /// What 8x8 State does today: `buildPublishScene`'s Euclideous block into `composeSceneMeta`.
    private func eightByEightScene(_ i: FourfoldCompose.Input) -> SceneState? {
        var p = MachineParams()
        p.euclidLines = i.lines; p.euclideousRiff = i.riff
        p.riffs = i.riffs; p.activeRiff = i.activeRiff
        p.mainOutMask = i.mainOutMask; p.soloMask = i.soloMask
        p.euclideousLocks = i.locks; p.lockRevs = i.lockRevs
        var input = BuildSceneLogic.Input()
        input.euclideousOn = true
        input.euclideousMachineID = "euclideous"
        input.euclideousChain = [ProcessorSlot(type: .euclid, params: p)]
        input.euclideousEmitters = [.a, .b, .c, .d]
        return BuildSceneLogic.composeSceneMeta(input).scene
    }

    func testTheFourfoldSceneEqualsWhatTheEightByEightComposerPlacesForTheDefaultDocument() {
        let i = input(from: PluginState.makeInit())
        XCTAssertEqual(FourfoldCompose.scene(i), eightByEightScene(i))
    }
    func testTheFourfoldSceneEqualsTheEightByEightComposerForEditedLanesRiffsMasksAndLocks() {
        var doc = PluginState.makeInit()
        var lines = doc.euclideousLinesResolved
        lines[0].pulses = 5; lines[0].steps = 13; lines[1].emitterMask = 0b0110; lines[2].rate = .r1_16; lines[3].gate = 0.7
        doc.euclideousLines = lines
        var riffs = doc.riffsResolved
        riffs[1] = EuclideousRiff(steps: 8, ranks: [3, 1, 4, 1, 5, 2, 6, 8])
        doc.riffs = riffs; doc.activeRiff = 1
        doc.euclideousMainOutMask = 0b0101
        var locks = doc.euclideousLocksResolved
        locks[2] = EuclideousLaneLock(on: true, grid: nil, state: nil)
        doc.euclideousLocks = locks
        let i = input(from: doc, solo: euclideousSoloEffective(latched: 0b0010, held: 0b1000), revs: 0x0403_0201)
        XCTAssertEqual(i.soloMask, 0b1010)
        XCTAssertEqual(FourfoldCompose.scene(i), eightByEightScene(i))
    }
}
