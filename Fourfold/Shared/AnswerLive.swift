//  AnswerLive.swift
//  ANSWER ferry (2026-11-02): what the live ANSWER / POOL displays read. The Router publishes each lane's running cycle (phase, unit, progress) and the pool it is choosing from through the existing 30 Hz poll; the CYCLE row's phase bar and the POOL tab's
//  NOW row observe this object — never the page body — so a playhead moving at 30 Hz does not re-run the page. (Only a lane's PHASE changing, once a unit, reaches the page: `FourfoldModel.euclideousAnswerPhases`.)

import SwiftUI

final class AnswerLiveModel: ObservableObject {
    @Published private(set) var status: [EuclideousAnswerLaneStatus] = Array(repeating: EuclideousAnswerLaneStatus(), count: 4)
    @Published private(set) var pools: [EuclideousLanePoolStatus] = Array(repeating: EuclideousLanePoolStatus(), count: 4)
    func update(status s: [EuclideousAnswerLaneStatus], pools p: [EuclideousLanePoolStatus]) {
        if s != status { status = s }
        if p != pools { pools = p }
    }
    func status(lane: Int) -> EuclideousAnswerLaneStatus { lane >= 0 && lane < status.count ? status[lane] : EuclideousAnswerLaneStatus() }
    func pool(lane: Int) -> EuclideousLanePoolStatus { lane >= 0 && lane < pools.count ? pools[lane] : EuclideousLanePoolStatus() }
}
