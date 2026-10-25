//  FourfoldStackProbe.swift — STACK BUDGET GUARD (2026-10-25, after `FourfoldAU-2026-10-25-213535.ips`): a TEST-ONLY seam, the third stack overflow of this class (2026-10-13, 10-21, 10-25).
//  The AU extension's main thread has a 1 MB stack and the page builds its views by eager, nested calls (`pageBody` → `laneCard` → `tabContent` → a tab's builder); in a Debug build every
//  `some View` temporary is a stack slot, so a few more controls could tip it over — and nothing but a device run could see it. `note()` samples how deep the main thread's stack is at a few
//  places on the deep chains (every `EuclideousStackBreak` body, and `lockLocked`, which every lane control calls); the largest sample is shown by `FourfoldStackProbeView`, one all-but-invisible
//  accessibility element ("Stack probe", value "deepest=NNN KB"), which `FourfoldStackBudgetTests` reads after walking every tab. Debug builds only, and only with the launch argument `--stack-probe`;
//  without it `note()` is one boolean test. It reads the stack pointer; it never writes the document, the engine or any state the page draws from.

import SwiftUI
import Darwin

enum FourfoldStackProbe {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--stack-probe")
    private static var deepest = 0

    @inline(__always) static func note() {
        #if DEBUG
        if enabled { record() }
        #endif
    }

    #if DEBUG
    @inline(never) private static func record() {
        guard pthread_main_np() != 0 else { return }
        var marker = 0
        let sp = withUnsafeMutablePointer(to: &marker) { Int(bitPattern: $0) }
        let top = Int(bitPattern: pthread_get_stackaddr_np(pthread_self()))
        deepest = max(deepest, top - sp)
    }
    #endif

    static var deepestKB: Int { deepest / 1024 }
}

struct FourfoldStackProbeView: View {
    var body: some View {
        if FourfoldStackProbe.enabled {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                Rectangle().fill(Color.white.opacity(0.01)).frame(width: 3, height: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("stackProbe")
                    .accessibilityLabel("Stack probe")
                    .accessibilityValue("deepest=\(FourfoldStackProbe.deepestKB) KB")
                    .allowsHitTesting(false)
            }
        }
    }
}
