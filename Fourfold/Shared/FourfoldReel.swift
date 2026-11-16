//  FourfoldReel.swift — REEL V3, the paged looper (2026-11-16, `Docs/reel-v3-paged-looper.md` §1/§3). ONE page of the session
//  tape as a full-size roll: opening the reel shows the LIVE page drawing itself (notes appear at the sweep); the open page is
//  ARMED, and at its boundary the engine flips to LOOPING it — the frame lights, the pill flips LIVE→TAPE, and the notes light
//  up as the replay head re-strikes them. ‹ › (and a swipe) page through the tape, instantly and phase-matched; paging forward
//  onto the live page is the hand-back. ×½/×2 change the page width (1…32 bars). No play or loop buttons — looping is the
//  reel's natural state. KEEP stars the shown page; EXPORT exports it. The minimap is a locator only (tap to jump, no handles).
//  The pure maths live in `ReelScreen.swift` (`reelV3*`); this file only paints and wires. GEOMETRY IS DEVICE-OWED.
//  (Phase-3's overview/tape/close-up stack, the drag-handle selection and START/PLAY/LOOP are gone — superseded by this screen.)

import SwiftUI
import UIKit

/// A share sheet for the REEL export (SMF files).
struct FourfoldShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct FourfoldReelBrowser: View {
    weak var au: FourfoldAudioUnit?
    let size: CGSize
    let playing: Bool
    let tempo: Double
    let onClose: () -> Void

    // Palette (plan §tokens / `Docs/fourstep-design-tokens.md`).
    private static let ground = Color(hex: 0x15161A)
    private static let panel = Color(hex: 0x2A2D34)
    private static let ink = Color(hex: 0xDFE3EA)       // frames + text
    private static let dim = Color(hex: 0x6E737C)
    static let laneHues: [Color] = [Color(hex: 0xF25959), Color(hex: 0x59BFF2), Color(hex: 0xF2BF40), Color(hex: 0x8CD973)]   // A B C D
    private func laneColor(_ lane: Int) -> Color { Self.laneHues[max(0, min(3, lane))] }

    // §PHASE 3: 4/4 is assumed for the bar maths until the host time signature is polled (flagged device-owed; most sessions are 4/4).
    private let beatsPerBar: Double = 4

    // The page.
    @State private var pageBars: Double = ReelV3Metrics.defaultPageBars
    @State private var page = ReelV3Page(index: 0, startBeat: 0, endBeat: ReelV3Metrics.defaultPageBars * 4)
    @State private var armedOnce = false               // the open page has been seeded + armed
    @State private var stagedCompleteKey = -1          // page.index whose full content has been topped up into the engine
    @State private var lastArmedEnd = -1.0             // the tape end the armed page was last staged at (re-arm only when it grew)
    // Polled engine state.
    @State private var reelState = 0                   // 0 live · 1 armed · 2 replaying (uiReelState)
    @State private var sessionEnd = 0.0                // beats
    @State private var posLive = 0.0                   // the render-published positions (session beats)
    @State private var posReplay = 0.0
    @State private var polledAt = Date.distantPast     // the sweep interpolates between polls
    @State private var pageNotes: [ReelDeck.Note] = []
    @State private var mapNotes: [ReelDeck.Note] = []
    @State private var lastMapEnd = -10.0
    @State private var keeps: [ReelKeep] = []
    @State private var reelShareURLs: [URL] = []
    @State private var reelShowShare = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let poll = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        let L = reelV3Layout(size: size)
        ZStack(alignment: .topLeading) {
            Self.ground.ignoresSafeArea()
            if sessionEnd <= 0 {
                emptyState
            } else {
                minimapView(L.minimap)
                rollView(L.roll)
                if !keeps.isEmpty { keepsStrip(y: L.controlBar.minY - 34, width: size.width) }
            }
            controlBar(L.controlBar)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onAppear { au?.reelSetBrowsing(true); refresh() }
        .onDisappear { au?.reelStopReplay(); au?.reelSetBrowsing(false) }   // §1.7: close = back to live, as the session would have been
        .onReceive(poll) { _ in refresh() }
        .onChange(of: reelState) { s in
            UIAccessibility.post(notification: .announcement,
                                 argument: s == 2 ? "Looping \(reelV3PageLabel(page, beatsPerBar: beatsPerBar).lowercased())" : "Live")
        }
        .sheet(isPresented: $reelShowShare) { FourfoldShareSheet(urls: reelShareURLs) }
    }

    // MARK: data — the 0.25 s poll drives the page lifecycle (§2: arm while filling, top-up after the flip)

    private func refresh() {
        guard let au else { return }
        let rs = au.uiReelState(); if rs != reelState { reelState = rs }
        let pos = au.reelLivePositions()
        posLive = pos.live; posReplay = pos.replay; polledAt = Date()
        let end = au.reelSessionEndBeat()
        if end < sessionEnd - 1e-6 { armedOnce = false }                    // the tape shrank (a reset): re-seed on its next growth
        if abs(end - sessionEnd) > 1e-9 { sessionEnd = end }
        if end > 0, !armedOnce {                                            // the tape exists (or just started): seed on the LIVE page and arm it
            armedOnce = true
            goLive(livePage)                                                // the write head = max(render-published live, drained end) — before the first playing window only `end` is real
        }
        guard armedOnce else { return }
        if rs != 2 {
            // The live/armed page fills: re-stage it when the tape grew — but never within ~0.6 s of the boundary, so a fresh
            // arm can't race the engine's flip (the post-flip top-up completes the tail; it sits a whole page from the seam).
            let secondsToBoundary = (page.endBeat - pos.live) / max(1, tempo) * 60
            if end > lastArmedEnd + 1e-9, secondsToBoundary > 0.6 {
                au.reelArmPage(startBeat: page.startBeat, endBeat: page.endBeat)
                lastArmedEnd = end
            }
            pageNotes = au.reelNotesInRange(fromBeat: page.startBeat, toBeat: page.endBeat)
            stagedCompleteKey = -1
        } else if stagedCompleteKey != page.index {
            au.reelTopUpPage(startBeat: page.startBeat, endBeat: page.endBeat)
            pageNotes = au.reelNotesInRange(fromBeat: page.startBeat, toBeat: page.endBeat)
            if end >= page.endBeat - 1e-9 { stagedCompleteKey = page.index }
        }
        if end - lastMapEnd > 2 || end < lastMapEnd {                       // the minimap's density (throttled whole-session read)
            mapNotes = au.reelNotesInRange(fromBeat: 0, toBeat: end); lastMapEnd = end
        }
        let k = au.reelKeeps(); if k != keeps { keeps = k }
    }

    /// The sweep line's beat, interpolated between polls so it moves smoothly (wraps in the page while looping, clamps while live).
    private func sweepBeat(now: Date) -> Double {
        let base = reelState == 2 ? posReplay : liveWriteHead
        guard playing else { return min(max(base, page.startBeat), page.endBeat) }
        let b = base + min(now.timeIntervalSince(polledAt), 0.6) * tempo / 60.0
        if reelState == 2 {
            let span = max(0.0001, page.spanBeats)
            let ph = ((b - page.startBeat).truncatingRemainder(dividingBy: span) + span).truncatingRemainder(dividingBy: span)
            return page.startBeat + ph
        }
        return min(max(b, page.startBeat), page.endBeat)
    }

    // MARK: navigation (§1.3/§1.4) — every move is instant and phase-matched; forward onto the live page = the hand-back

    /// The write head's page. `posLive` is the render-published position (fresh while playing); before the first playing
    /// window it is 0, so the drained tape end stands in — else opening while stopped would seed page 0, not the real end.
    private var liveWriteHead: Double { max(0, max(posLive, sessionEnd)) }
    private var livePage: ReelV3Page { reelV3Page(at: liveWriteHead, bars: pageBars, beatsPerBar: beatsPerBar) }

    private func step(_ delta: Int) { jump(to: reelV3Step(page, by: delta, bars: pageBars, beatsPerBar: beatsPerBar, liveBeat: liveWriteHead)) }

    private func jump(to p: ReelV3Page) {
        guard let au, p != page else { return }
        if p.index >= livePage.index { goLive(livePage); return }
        page = p; stagedCompleteKey = -1
        au.reelShowPage(startBeat: p.startBeat, endBeat: p.endBeat)
        pageNotes = au.reelNotesInRange(fromBeat: p.startBeat, toBeat: p.endBeat)
    }

    private func goLive(_ p: ReelV3Page) {                                  // the hand-back + the next arm (open, page-forward, pill)
        guard let au else { return }
        page = p; stagedCompleteKey = -1; lastArmedEnd = -1
        au.reelArmPage(startBeat: p.startBeat, endBeat: p.endBeat)
        pageNotes = au.reelNotesInRange(fromBeat: p.startBeat, toBeat: p.endBeat)
    }

    private func halve() {
        let ph = reelState == 2 ? posReplay : liveWriteHead
        let (nb, np) = reelV3Halve(bars: pageBars, page: page, playheadBeat: ph, beatsPerBar: beatsPerBar)
        guard nb != pageBars else { return }
        pageBars = nb; applyWidth(np)
    }
    private func doubleWidth() {
        let (nb, np) = reelV3Double(bars: pageBars, page: page, beatsPerBar: beatsPerBar)
        guard nb != pageBars else { return }
        pageBars = nb; applyWidth(np)
    }
    private func applyWidth(_ np: ReelV3Page) {
        guard let au else { return }
        page = np; stagedCompleteKey = -1; lastArmedEnd = -1
        if reelState == 2 { au.reelRetilePage(startBeat: np.startBeat, endBeat: np.endBeat) }   // looping: the playhead's tape position maps into the new grid
        else { au.reelArmPage(startBeat: np.startBeat, endBeat: np.endBeat) }                   // live: the armed boundary moves to the new page's end
        pageNotes = au.reelNotesInRange(fromBeat: np.startBeat, toBeat: np.endBeat)
    }

    // MARK: keep + export (phase 4's model; the PAGE is the selection)

    private func addKeep() {
        guard let au, sessionEnd > 0 else { return }
        au.reelSetKeeps(reelAddKeep(au.reelKeeps(), startBeat: page.startBeat, endBeat: page.endBeat, beatsPerBar: beatsPerBar, at: Date()))
        keeps = au.reelKeeps()
    }
    private func removeKeep(_ i: Int) { guard let au else { return }; au.reelSetKeeps(reelRemoveKeep(au.reelKeeps(), at: i)); keeps = au.reelKeeps() }
    private func loadKeep(_ k: ReelKeep) { jump(to: reelV3Page(at: k.startBeat, bars: pageBars, beatsPerBar: beatsPerBar)) }

    /// Export a beat range as SMF files to the app's "Reel exports" folder (or temp in the extension), uniquely named, then share.
    private func exportRange(_ lo: Double, _ hi: Double) {
        guard let au else { return }
        let files = au.reelExportKeepFiles(fromBeat: lo, toBeat: hi, emitterMask: 0)
        guard !files.isEmpty else { return }
        var dir = FileManager.default.temporaryDirectory
        if PresetStore.useDocumentsFolder {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Reel exports", isDirectory: true)
            if (try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)) != nil { dir = docs }
        }
        let stamp = reelExportStamp(Date())
        var urls: [URL] = []
        for f in files {
            let wanted = reelKeepExportFileName(stamp: stamp, startBeat: lo, endBeat: hi, beatsPerBar: beatsPerBar, label: f.label)
            let name = reelUniqueFileName(wanted, exists: { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) })
            let url = dir.appendingPathComponent(name)
            if (try? f.data.write(to: url)) != nil { urls.append(url) }
        }
        guard !urls.isEmpty else { return }
        reelShareURLs = urls; reelShowShare = true
    }

    // MARK: the minimap — a locator, nothing else (§1.5): page cells, faint per-lane density, the shown page outlined, keeps starred

    private func minimapView(_ r: CGRect) -> some View {
        let bins = max(1, Int(r.width / 3))
        let density = reelOverviewDensity(notes: mapNotes, sessionEndBeat: max(sessionEnd, page.endBeat), bins: bins)
        let total = max(sessionEnd, page.endBeat)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Self.panel.opacity(0.5))
            Canvas { ctx, sz in
                for lane in 0..<4 {                                        // faint stacked density
                    let laneH = sz.height / 4
                    let y0 = CGFloat(lane) * laneH
                    for b in 0..<bins where density[lane][b] > 0 {
                        let x = CGFloat(b) / CGFloat(bins) * sz.width
                        let h = CGFloat(density[lane][b]) * (laneH - 2)
                        ctx.fill(Path(CGRect(x: x, y: y0 + laneH - 1 - h, width: max(1, sz.width / CGFloat(bins) - 0.5), height: h)),
                                 with: .color(laneColor(lane).opacity(0.45)))
                    }
                }
                let w = pageBars * beatsPerBar
                var i = 0                                                  // page-cell borders
                while Double(i) * w < total {
                    let x = CGFloat(Double(i) * w / total) * sz.width
                    ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: sz.height)) },
                               with: .color(.white.opacity(0.08)), lineWidth: 0.5)
                    i += 1
                }
                for k in keeps {                                           // keeps as small stars on their cells
                    let x = CGFloat(min(1, max(0, k.startBeat / total))) * sz.width
                    ctx.draw(Text("★").font(.system(size: 7)).foregroundColor(Self.ink.opacity(0.8)), at: CGPoint(x: x + 4, y: 5), anchor: .center)
                }
                let rect = CGRect(x: 0, y: 0, width: sz.width, height: sz.height)   // the shown page, outlined
                let cell = reelV3MinimapCell(index: page.index, bars: pageBars, beatsPerBar: beatsPerBar, sessionEndBeat: total, rect: rect)
                ctx.stroke(Path(roundedRect: cell.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 2),
                           with: .color(reelState == 2 ? Self.ink : Self.ink.opacity(0.55)), lineWidth: 1.5)
                let lx = CGFloat(min(1, max(0, liveWriteHead / total))) * sz.width  // the live write head
                ctx.stroke(Path { $0.move(to: CGPoint(x: lx, y: 0)); $0.addLine(to: CGPoint(x: lx, y: sz.height)) },
                           with: .color(Self.ink.opacity(0.35)), lineWidth: 1)
            }.padding(1)
        }
        // GESTURE BEFORE OFFSET (the project's rule): attach interactivity to the framed view, THEN offset.
        .frame(width: r.width, height: r.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { g in
            jump(to: reelV3MinimapPage(atX: g.location.x, rect: CGRect(x: 0, y: 0, width: r.width, height: r.height),
                                       bars: pageBars, beatsPerBar: beatsPerBar, sessionEndBeat: sessionEnd, liveBeat: liveWriteHead))
        })
        .offset(x: r.minX, y: r.minY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session map, \(reelV3PageLabel(page, beatsPerBar: beatsPerBar).lowercased()) shown; tap to jump")
    }

    // MARK: the page roll — the whole screen's point (§1.1/§1.2): LIVE draws itself, TAPE lights up

    private func rollView(_ r: CGRect) -> some View {
        let replaying = reelState == 2
        let window = ReelTapeWindow(startBeat: page.startBeat, bars: pageBars)
        let all = pageNotes.map { Int($0.note) }
        let rawLo = all.min() ?? 48, rawHi = all.max() ?? 72
        let lo = (rawLo / 12) * 12, hi = max(lo + 12, ((rawHi + 11) / 12) * 12)
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing && !replaying)) { tl in
            Canvas { ctx, sz in
                let tape = CGRect(x: 0, y: 0, width: sz.width, height: sz.height)
                let rulerH: CGFloat = 16
                let sweep = sweepBeat(now: tl.date)
                func yOf(_ n: Int) -> CGFloat { (1 - CGFloat(n - lo) / CGFloat(hi - lo)) * (sz.height - rulerH - 10) + rulerH + 5 }
                // the panel + the frame: lit ink while LOOPING — the one-glance "replaying, not generating" (§1.2)
                ctx.fill(Path(roundedRect: tape, cornerRadius: 8), with: .color(Self.panel.opacity(replaying ? 0.42 : 0.3)))
                ctx.stroke(Path(roundedRect: tape.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 8),
                           with: .color(replaying ? Self.ink : Self.ink.opacity(0.12)), lineWidth: replaying ? 1.5 : 1)
                // bar ruler
                let barsN = Int(pageBars.rounded())
                let numberEvery = max(1, barsN / 8)
                for bar in 0...barsN {
                    let beat = page.startBeat + Double(bar) * beatsPerBar
                    let x = reelTapeXAtBeat(beat, tape: tape, window: window, beatsPerBar: beatsPerBar)
                    ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: rulerH)); $0.addLine(to: CGPoint(x: x, y: sz.height - 2)) },
                               with: .color(.white.opacity(bar == 0 || bar == barsN ? 0.0 : 0.06)), lineWidth: 0.5)
                    if bar < barsN, bar % numberEvery == 0 {
                        ctx.draw(Text("\(Int(beat / beatsPerBar) + 1)").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(Self.dim),
                                 at: CGPoint(x: x + 3, y: 8), anchor: .leading)
                    }
                }
                // the notes — lane-coloured; while LOOPING the sounding ones light up (the replay head re-striking them)
                for n in pageNotes {
                    let x = reelTapeXAtBeat(n.start, tape: tape, window: window, beatsPerBar: beatsPerBar)
                    let w = max(2, reelTapeXAtBeat(n.end, tape: tape, window: window, beatsPerBar: beatsPerBar) - x)
                    guard x < sz.width, x + w > 0 else { continue }
                    let y = yOf(Int(n.note))
                    let sounding = replaying && sweep >= n.start && sweep < n.end
                    let alpha = sounding ? 1.0 : (0.45 + 0.4 * Double(n.vel) / 127)
                    let c = laneColor(Int(n.cable) - 1)
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: y - 2.5, width: min(w, sz.width - x), height: 5), cornerRadius: 2), with: .color(c.opacity(alpha)))
                    if sounding {
                        ctx.stroke(Path(roundedRect: CGRect(x: x - 1, y: y - 3.5, width: min(w, sz.width - x) + 2, height: 7), cornerRadius: 3),
                                   with: .color(c.opacity(0.7)), lineWidth: 1)
                    }
                }
                // the sweep — LIVE: a pen head with a short trail (notes appear behind it); TAPE: the replay head
                let sx = reelTapeXAtBeat(sweep, tape: tape, window: window, beatsPerBar: beatsPerBar)
                if !replaying, !reduceMotion {
                    ctx.fill(Path(CGRect(x: max(0, sx - 14), y: rulerH, width: min(14, sx), height: sz.height - rulerH - 2)),
                             with: .linearGradient(Gradient(colors: [Self.ink.opacity(0), Self.ink.opacity(0.1)]),
                                                   startPoint: CGPoint(x: max(0, sx - 14), y: 0), endPoint: CGPoint(x: sx, y: 0)))
                }
                ctx.stroke(Path { $0.move(to: CGPoint(x: sx, y: rulerH)); $0.addLine(to: CGPoint(x: sx, y: sz.height - 2)) },
                           with: .color(replaying ? Self.ink : Self.ink.opacity(0.85)), lineWidth: replaying ? 2 : 1.5)
            }
        }
        // GESTURE BEFORE OFFSET (see minimapView). A horizontal swipe pages (§1.3); the buttons do the same.
        .frame(width: r.width, height: r.height)
        .overlay(alignment: .topTrailing) {
            Text(reelV3PageLabel(page, beatsPerBar: beatsPerBar) + (replaying ? " · LOOP" : " · LIVE"))
                .font(.system(size: 8.5, weight: .heavy, design: .monospaced)).tracking(0.8)
                .foregroundColor(replaying ? Self.ink : Self.dim)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Self.ground.opacity(0.7)))
                .padding(6)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 24).onEnded { g in
            if g.translation.width < -40 { step(1) } else if g.translation.width > 40 { step(-1) }
        })
        .offset(x: r.minX, y: r.minY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reelV3SpokenState(page: page, beatsPerBar: beatsPerBar, live: !replaying, armed: reelState == 1))
    }

    // MARK: the control row — ‹ · › · ×½ · width · ×2 · KEEP · EXPORT · pill · ×  (no play, no loop: §1's natural state)

    private func controlBar(_ r: CGRect) -> some View {
        HStack(spacing: 7) {
            ctlButton("chevron.backward", "", a11y: "Previous page") { step(-1) }
            ctlButton("chevron.forward", "", a11y: "Next page") { step(1) }
            ctlButton("minus.magnifyingglass", "×½", a11y: "Halve the page width") { halve() }
            Text(reelV3WidthLabel(bars: pageBars))
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced)).foregroundColor(Self.ink.opacity(0.8))
                .frame(minWidth: 52)
            ctlButton("plus.magnifyingglass", "×2", a11y: "Double the page width") { doubleWidth() }
            Spacer(minLength: 0)
            ctlButton("star", "KEEP", a11y: "Keep \(reelV3PageLabel(page, beatsPerBar: beatsPerBar).lowercased())") { addKeep() }
            ctlButton("square.and.arrow.up", "EXPORT", a11y: "Export \(reelV3PageLabel(page, beatsPerBar: beatsPerBar).lowercased())") { exportRange(page.startBeat, page.endBeat) }
            pillView
            ctlButton("xmark", "", a11y: "Close the reel") { onClose() }
        }
        .padding(.horizontal, 12)
        .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
    }

    private var pillView: some View {
        let tape = reelState == 2
        return Button { if tape { goLive(livePage) } } label: {
            Text(tape ? "TAPE" : "LIVE").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1)
                .foregroundColor(tape ? Color(hex: 0x0D0F14) : Self.ink)
                .frame(width: 64, height: 30)
                .background(RoundedRectangle(cornerRadius: 15).fill(tape ? Self.ink : Self.panel))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(tape ? 0 : 0.15), lineWidth: 1))
        }
        .accessibilityLabel(tape ? "Playing the tape; tap to return to live" : "Live")
    }

    // The keeps as chips (tap a chip to jump to its page; × removes it). Shown only when keeps exist, just above the control bar.
    private func keepsStrip(y: CGFloat, width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("KEEPS").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.5).foregroundColor(Self.dim)
                ForEach(Array(keeps.enumerated()), id: \.offset) { i, k in
                    HStack(spacing: 5) {
                        Text(reelKeepBarLabel(startBeat: k.startBeat, endBeat: k.endBeat, beatsPerBar: beatsPerBar))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(Self.ink)
                            .contentShape(Rectangle()).onTapGesture { loadKeep(k) }
                        Button { removeKeep(i) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(Self.dim) }
                            .accessibilityLabel("Remove keep \(reelKeepBarLabel(startBeat: k.startBeat, endBeat: k.endBeat, beatsPerBar: beatsPerBar))")
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Self.panel))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.1), lineWidth: 1))
                }
            }.padding(.horizontal, 12)
        }
        .frame(width: width, height: 30).offset(x: 0, y: y)
    }

    private func ctlButton(_ icon: String, _ label: String, a11y: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                if !label.isEmpty { Text(label).font(.system(size: 9.5, weight: .heavy, design: .monospaced)).tracking(0.5) }
            }
            .foregroundColor(Self.ink).padding(.horizontal, 11).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 7).fill(Self.panel)).overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.1), lineWidth: 1))
        }.accessibilityLabel(a11y)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "recordingtape").font(.system(size: 36, weight: .light)).foregroundColor(Self.dim)
            Text("Play to start the tape.").font(.system(size: 14, weight: .semibold)).foregroundColor(Self.ink.opacity(0.7))
            Button { onClose() } label: {
                Text("CLOSE").font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1).foregroundColor(Self.dim)
                    .padding(.horizontal, 24).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 6).fill(Self.panel))
            }.padding(.top, 6)
        }
        .frame(width: size.width, height: size.height)
    }
}
