//  FourfoldApp.swift
//  FOURFOLD Step 3 (2026-10-23): the standalone app's entry point. The app is the AU's host (FourfoldEngine) and shows the same page the extension does; the embedded AUv3 extension is what AUM loads.

import SwiftUI

@main
struct FourfoldApp: App {
    init() {
        PresetStore.useDocumentsFolder = true
        if CommandLine.arguments.contains("--soak") { SessionTape.defaultChunkEvents = 256; SessionTape.defaultPoolSize = 48; SessionTape.defaultResidentChunks = 3 }   // a soak is minutes long: shrink the tape so it spills to its file and reads back many times
    }   // before anything reads the preset list — see `PresetStore.useDocumentsFolder`
    var body: some Scene {
        WindowGroup { FourfoldAppView() }
    }
}
