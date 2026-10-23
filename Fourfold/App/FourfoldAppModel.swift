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

    private var lastSaved: Data?
    private let selfTest = FourfoldSelfTest()

    init() {
        let d = UserDefaults.standard
        tempo = FourfoldTransportClock.clamped((d.object(forKey: "fourfold.tempo") as? Double) ?? 120)
        var built: FourfoldEngine?; var err: String?
        do { built = try FourfoldEngine() } catch { err = "AUDIO ENGINE: \(error.localizedDescription)" }
        engine = built; launchError = err
        restoreState()
        engine?.setTempo(tempo)
        // `--autoplay`: start the transport at launch (the simulator harness and UI tests have no way to tap PLAY).
        if CommandLine.arguments.contains("--autoplay") { setPlaying(true) }
        // `--midi-selftest`: check the CoreMIDI shell in-process and print the result to stderr (FourfoldSelfTest).
        if CommandLine.arguments.contains("--midi-selftest"), let engine { selfTest.run(engine: engine) }
        if let engine { selfTest.stateTest(engine: engine) }
    }

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
