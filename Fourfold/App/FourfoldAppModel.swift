//  FourfoldAppModel.swift
//  FOURFOLD Step 3 (2026-10-23): the standalone app's model — owns the engine (the AU + its host), the transport the UI shows, and the session file. There is no host to persist the AU's state, so the app does: `fullState`
//  (the same document AUM would save) goes to Application Support every few seconds while it changes and whenever the app leaves the foreground, and comes back at launch.

import Foundation
import SwiftUI

final class FourfoldAppModel: ObservableObject {
    let engine: FourfoldEngine?
    @Published var playing = false
    @Published var tempo: Double
    let launchError: String?

    #if FOURFOLD_LINK   // ABLETON LINK is OFF until after release — see `Docs/standalone-plan.md` "Ableton Link" for the switch
    // ABLETON LINK (2026-10-24 ferry): `linkEnabled` is Fourfold's OWN on/off (ABLLinkSetActive) —
    // persisted like `tempo` above. `linkConnected`/`linkPeerCount` mirror the session's live state,
    // updated only from the main-thread callbacks registered in `init` below; nothing here is polled.
    @Published var linkEnabled = false
    @Published var linkConnected = false
    @Published var linkPeerCount = 0
    #endif

    private var lastSaved: Data?
    private let selfTest = FourfoldSelfTest()
    private let soak = FourfoldSoak()

    init() {
        let d = UserDefaults.standard
        tempo = CommandLine.arguments.contains("--fresh") ? 120 : FourfoldTransportClock.clamped((d.object(forKey: "fourfold.tempo") as? Double) ?? 120)
        var built: FourfoldEngine?; var err: String?
        do { built = try FourfoldEngine() } catch { err = "AUDIO ENGINE: \(error.localizedDescription)" }
        engine = built; launchError = err
        if !CommandLine.arguments.contains("--fresh") { restoreState() }   // `--fresh`: UI tests start from the factory document, never from the last session
        engine?.setTempo(tempo)
        #if FOURFOLD_LINK
        linkEnabled = d.bool(forKey: "fourfold.linkEnabled")
        if let link = engine?.link {
            engine?.setLinkActive(linkEnabled)
            // Context-free closure literals (per ABLLink.h's own convention, mirrored from Ableton's
            // LinkHut sample) — Swift converts these to C function pointers; `self` travels via the
            // opaque context pointer instead of a capture. All four fire on the main thread.
            ABLLinkSetSessionTempoCallback(link, { tempo, context in
                Unmanaged<FourfoldAppModel>.fromOpaque(context!).takeUnretainedValue().setTempo(tempo)
            }, Unmanaged.passUnretained(self).toOpaque())
            ABLLinkSetStartStopCallback(link, { isPlaying, context in
                Unmanaged<FourfoldAppModel>.fromOpaque(context!).takeUnretainedValue().setPlaying(isPlaying)
            }, Unmanaged.passUnretained(self).toOpaque())
            ABLLinkSetIsConnectedCallback(link, { isConnected, context in
                Unmanaged<FourfoldAppModel>.fromOpaque(context!).takeUnretainedValue().linkConnected = isConnected
            }, Unmanaged.passUnretained(self).toOpaque())
            ABLLinkSetNumPeersCallback(link, { numPeers, context in
                Unmanaged<FourfoldAppModel>.fromOpaque(context!).takeUnretainedValue().linkPeerCount = Int(numPeers)
            }, Unmanaged.passUnretained(self).toOpaque())
            linkConnected = ABLLinkIsConnected(link)
            linkPeerCount = Int(ABLLinkNumPeers(link))
        }
        #endif
        // `--autoplay`: start the transport at launch (the simulator harness and UI tests have no way to tap PLAY).
        if CommandLine.arguments.contains("--autoplay") { setPlaying(true) }
        // `--midi-selftest`: check the CoreMIDI shell in-process and print the result to stderr (FourfoldSelfTest).
        if CommandLine.arguments.contains("--midi-selftest"), let engine { selfTest.run(engine: engine) }
        if let engine { selfTest.stateTest(engine: engine) }
        // `--soak <seconds> [--soak-seed N]`: a long randomised stress run of the live app that checks for stuck notes (FourfoldSoak; Scripts/fourfold-harness/soak.sh).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--soak"), let engine {
            let secs = (i + 1 < args.count ? Double(args[i + 1]) : nil) ?? 300
            let seed = args.firstIndex(of: "--soak-seed").flatMap { $0 + 1 < args.count ? UInt64(args[$0 + 1]) : nil }
            let fault = args.firstIndex(of: "--soak-fault").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 0
            soak.run(engine: engine, seconds: secs, seed: seed, faultEvery: fault)
        }
    }

    #if FOURFOLD_LINK
    /// ABLETON LINK: toggles Fourfold's own participation. Does NOT touch "Start Stop Sync enabled" —
    /// per ABLLink.h there is no setter for that; only `FourfoldLinkSettingsView`'s real Link settings
    /// screen can turn it on, which is why that screen is reachable from the LINK button, not optional.
    func setLinkEnabled(_ on: Bool) {
        linkEnabled = on
        engine?.setLinkActive(on)
        UserDefaults.standard.set(on, forKey: "fourfold.linkEnabled")
    }
    #endif
    func setPlaying(_ on: Bool) { playing = on; engine?.setPlaying(on) }
    func togglePlaying() { setPlaying(!playing) }
    func setTempo(_ bpm: Double) {
        let t = FourfoldTransportClock.clamped(bpm.rounded())
        tempo = t; engine?.setTempo(t)
        UserDefaults.standard.set(t, forKey: "fourfold.tempo")
    }

    // MARK: session file

    private var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fourfold", isDirectory: true)
        return dir.appendingPathComponent("session.state")
    }

    /// Write the AU's full state if it changed since the last write.
    func saveState() {
        guard let state = engine?.au.fullState,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: false), data != lastSaved else { return }
        let url = stateURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: url, options: .atomic)) != nil { lastSaved = data }
    }

    private func restoreState() {
        guard let au = engine?.au, let data = try? Data(contentsOf: stateURL),
              let state = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSData.self, NSDate.self, NSNull.self], from: data) as? [String: Any] else { return }
        au.fullState = state
        lastSaved = data
    }
}
