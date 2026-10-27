//  FourfoldUndoProbe.swift — UNDO AUDIT (2026-10-25, Docs/pending-tasks.md "UNDO AUDIT"): a TEST-ONLY seam.
//  With the launch argument `--undo-probe` the page carries one 3 × 3 pt, all-but-invisible accessibility element ("Undo probe") whose VALUE says, in one line, whether the page's undo state, the document and the render input agree:
//    snap=<hash of the page's undo snapshot> doc=<the same fields read back from the AU document> agree=<snap == doc> stage=<the chain the page last published == the document's lanes> parts=<one short hash per snapshot field> play=<lane PLAY flags>
//    box=<the snapshot the render thread holds == one freshly built from what the AU was given> undo=<steps back> redo=<steps forward> resyncs=<times the 4 Hz poll found the page ≠ the document> pend=<queued random rolls> lanes=<steps/hits/offset per lane>
//  Without the argument it draws and publishes nothing. It reads only; it never writes the document, the stack or the engine.

import SwiftUI

struct FourfoldUndoProbe: View {
    @ObservedObject var m: FourfoldModel
    weak var au: FourfoldAudioUnit?
    static let enabled = ProcessInfo.processInfo.arguments.contains("--undo-probe")

    static func fnv(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }
    private func short(_ v: UInt64) -> String { String(v, radix: 16).suffix(8).description }

    var body: some View {
        if Self.enabled {
            // Re-read every 0.25 s as well as on a model change: the render snapshot is published one runloop turn AFTER an edit, so a reading taken the instant `m` changes saw the box one edit behind (`box=0`) and nothing re-ran the
            // body once it caught up. Only the `box=` term could be affected; the page / document / stage terms are synchronous.
            TimelineView(.periodic(from: Date(), by: 0.25)) { _ in
                Rectangle().fill(Color.white.opacity(0.01)).frame(width: 3, height: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("undoProbe")
                    .accessibilityLabel("Undo probe")
                    .accessibilityValue(describe())
                    .allowsHitTesting(false)
                    .onAppear { FourfoldUndoProbeHost.install(au: au) }
            }
        }
    }

    private func describe() -> String {
        guard let au else { return "no au" }
        // The lanes' PLAY/STOP flags are reported separately (`play=`) and left out of the hashes: `euclideousApply` deliberately never restores them (§7.3), which would otherwise hide every OTHER difference behind that one.
        func noPlay(_ ls: [EuclidLine]) -> [EuclidLine] { ls.map { var x = $0; x.enabled = nil; if var mk = x.mask { mk.enabled = nil; x.mask = mk }; return x } }
        let snap = EuclideousUndoSnapshot(lines: noPlay(m.euclideousLines), riff: m.euclideousRiff, resetSpanBars: m.euclideousResetSpanBars, keyRoot: m.euclideousKeyRoot, keyType: m.euclideousKeyType,
                                          chordSets: m.euclideousChordSets, activeChordSet: m.euclideousActiveChordSet, noteSource: m.euclideousNoteSource, sourcePlan: m.euclideousSourcePlan, riffs: m.euclideousRiffs,
                                          activeRiff: m.euclideousActiveRiff, lanesSeq: m.euclideousLanesSeq, riffsSeq: m.euclideousRiffsSeq, fx: m.euclideousFX, holdLatchMode: m.euclideousHoldLatchMode, hocketRules: m.hocketRules)   // the same twelve mirrors `euclideousSnapshot()` reads
        let doc = EuclideousUndoSnapshot(lines: noPlay(au.uiEuclideousLines()), riff: au.uiEuclideousRiff(), resetSpanBars: au.uiEuclideousResetSpanBars(),
                                         keyRoot: au.uiEuclideousKeyRoot(), keyType: au.uiEuclideousKeyType(), chordSets: au.uiEuclideousChordSets(), activeChordSet: au.uiActiveChordSet(),
                                         noteSource: au.uiEuclideousNoteSource(), sourcePlan: au.uiEuclideousSourcePlan(), riffs: au.uiEuclideousRiffs(), activeRiff: au.uiEuclideousActiveRiff(),
                                         lanesSeq: au.uiEuclideousLanesSeq(), riffsSeq: au.uiEuclideousRiffsSeq(), fx: au.uiEuclideousFX(), holdLatchMode: au.uiEuclideousHoldLatchMode(), hocketRules: au.uiHocketRules())
        let staged = m.registeredChain.first.map { noPlay($0.params.euclidLines ?? []) == doc.lines } ?? false
        let box = au.probeBoxAgreement()
        let lanes = snap.lines.map { "\($0.steps)/\($0.pulses)r\($0.rotate)" }.joined(separator: ",")
        let pend = (0..<12).filter { $0 < m.euclideousPendingRolls.count && m.euclideousPendingRolls[$0] != nil }.count
        func h(_ x: Any) -> String { String(Self.fnv(String(describing: x)) & 0xFFFF, radix: 16) }
        let parts = [h(snap.lines), h(snap.riff), h(snap.resetSpanBars), h(snap.keyRoot), h(snap.keyType), h(snap.chordSets), h(snap.activeChordSet), h(snap.noteSource), h(snap.sourcePlan), h(snap.riffs), h(snap.activeRiff),
                     h(snap.lanesSeq), h(snap.riffsSeq), h(snap.fx), h(snap.holdLatchMode), h(snap.hocketRules)].joined(separator: ",")
        let play = m.euclideousLines.map { $0.enabledResolved ? "1" : "0" }.joined()
        return "snap=\(short(Self.fnv(String(describing: snap)))) doc=\(short(Self.fnv(String(describing: doc)))) agree=\(snap == doc ? 1 : 0) stage=\(staged ? 1 : 0) box=\(box ? 1 : 0) parts=\(parts) play=\(play) "
             + "undo=\(m.euclideousUndo.past.count) redo=\(m.euclideousUndo.future.count) resyncs=\(m.probeResyncs) pend=\(pend) voices=\(au.kernelDiagnostics().activeVoiceCount) lanes=\(lanes)"
    }
}

/// What an AUv3 HOST does behind the page's back, triggered from a UI test by a Darwin notification (so no on-screen control is needed): the host's preset menu sets `currentPreset` (→ `loadFactoryPreset`), a project load sets
/// `fullState`. Neither goes through a page funnel. Only installed when the app was launched with `--undo-probe`.
enum FourfoldUndoProbeHost {
    static weak var au: FourfoldAudioUnit?
    static var launchState: [String: Any]?
    private static var installed = false
    static let loadPreset = "com.outliermidi.fourfold.undoprobe.hostLoadPreset"
    static let restoreLaunch = "com.outliermidi.fourfold.undoprobe.hostRestoreLaunch"
    static func install(au: FourfoldAudioUnit?) {
        guard !installed, let au else { return }
        installed = true
        self.au = au
        launchState = au.fullState
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for name in [loadPreset, restoreLaunch] {
            CFNotificationCenterAddObserver(center, nil, { _, _, n, _, _ in
                DispatchQueue.main.async {
                    switch n?.rawValue as String? {
                    case FourfoldUndoProbeHost.loadPreset: FourfoldUndoProbeHost.au?.loadFactoryPreset(named: "FIVE AGAINST EIGHT")
                    case FourfoldUndoProbeHost.restoreLaunch: if let s = FourfoldUndoProbeHost.launchState { FourfoldUndoProbeHost.au?.fullState = s }
                    default: break
                    }
                }
            }, name as CFString, nil, .deliverImmediately)
        }
    }
}
