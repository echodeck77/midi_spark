//  Models.swift
//  MidiSpark — document model per spec v2.8 §9.
//  Colour = the treatment · Cell = the patch point · Preset = host fullState (reserved word).

import Foundation

// MARK: - Vocabulary

enum ProcessorType: String, Codable, CaseIterable {
    case arp = "ARP", ratchet = "RATCHET", passgate = "PASSGATE"
    case strum = "STRUM", chance = "CHANCE", harmonize = "HARMONIZE"
    // §12: type IDs are append-only. Never reorder, never reuse.
}

enum ArpPattern: String, Codable, CaseIterable { case up = "UP", down = "DOWN", upDown = "UP-DN", random = "RANDOM", asPlayed = "AS PLAYED" }
enum ArpPhase: String, Codable, CaseIterable { case retrig = "RETRIG", legato = "LEGATO", free = "FREE" }   // §3.5
enum StepRate: String, Codable, CaseIterable {
    case r2_1 = "2/1", r1_1 = "1/1", r1_2 = "1/2", r1_2d = "1/2.", r1_4 = "1/4", r1_8 = "1/8"
    var beats: Double {
        switch self { case .r2_1: 8; case .r1_1: 4; case .r1_2: 2; case .r1_2d: 3; case .r1_4: 1; case .r1_8: 0.5 }
    }
}
enum ArpRate: String, Codable, CaseIterable {
    case r1_4 = "1/4", r1_8 = "1/8", r1_8t = "1/8T", r1_16 = "1/16", r1_16t = "1/16T", r1_32 = "1/32"
    var beats: Double {
        switch self { case .r1_4: 1; case .r1_8: 0.5; case .r1_8t: 1.0/3.0; case .r1_16: 0.25; case .r1_16t: 1.0/6.0; case .r1_32: 0.125 }
    }
}
enum Bus: String, Codable, CaseIterable { case a = "A", b = "B", c = "C", d = "D"
    var cable: UInt8 { UInt8(Bus.allCases.firstIndex(of: self)!) }
}
enum StrumDir: String, Codable, CaseIterable { case up = "UP", down = "DOWN", alternate = "ALT" }   // §3 STRUM
enum TapAction: String, Codable, CaseIterable {
    case alt = "ALT", byp = "BYP", mute = "MUTE"
}
enum Quant: String, Codable { case off = "OFF", step = "STEP", pass = "PASS" }                              // §6.8

let colourIDs: [String] = ["gold","orange","vermilion","wine","magenta","blush","purple","violet",
                           "indigo","azure","cyan","teal","mint","green","chartreuse","bronze"]

// MARK: - Colour (the treatment) — §1/§9

struct ColourParams: Codable, Equatable {
    // Superset of per-type params; only the active type's fields are meaningful. §12.0: append-only.
    var pattern: ArpPattern? = .up
    var rate: ArpRate? = .r1_16
    var octaves: Int? = 1
    var gate: Double? = 0.6
    var phase: ArpPhase? = .retrig
    var count: Int? = 3            // ratchet
    var ramp: Double? = 0.5        // ratchet
    var passes: [Bool]? = [true, true, true, true]  // passgate
    var strumDir: StrumDir? = .up  // strum
    var spread: Double? = 0.1      // strum: chord stagger in BEATS (0…1)
    var curve: Double? = 0         // strum: timing curve −1…1 (0 = linear)
    var velTilt: Double? = 0       // strum: velocity tilt −1…1 (0 = flat)
    var probability: Double? = 1   // chance: pass-through probability 0…1 per note-on
    // harmonize (§3): up to 3 added voices, each an interval −24…+24 st (0 = voice OFF), plus a
    // velocity scale 0.1…1 applied to the ADDED voices (root stays full). B overrides the intervals.
    var harmIntervals: [Int]? = [0, 0, 0]
    var harmVelScale: Double? = 0.8
}

struct Colour: Codable, Equatable {
    var colourID: String
    var type: ProcessorType
    // v3.0 (delta §7): per-Colour OUT CH is REMOVED — channel is a property of the WIRE (busChannels),
    // not the treatment. Old docs carrying an `outChannel` key decode fine (Codable ignores unknown keys).
    var transpose: Int = 0         // −24…+24, accumulates in chains, clamped — the ACTIVE type's transpose
    var morph: Double = 0          // §3.2 — the per-colour macro AUParameter — the ACTIVE type's morph
    var paramsA: ColourParams = ColourParams()   // procA — the A face
    // delta item 8 (TWO-PROCESSOR Colours): procB — this Colour's OWN second face. paramsB is REAL storage
    // again (resolved with fallback A, so a sparse procB inherits A's fields). A cell's `alt` flag flips to
    // procB; `morph` (below) is the position toward it. B-less ⇒ typeB == nil ⇒ b = a, no morph.
    var paramsB: ColourParams = ColourParams()
    // delta item 8: procB's processor TYPE, or nil = B-less (the natural encoding — old docs decode nil).
    // Same type as A ⇒ FULL morph glide; different ⇒ SWAP (binary flip at t≥0.5). B is sourced ONLY when
    // this is non-nil, so a pre-pair doc's stale paramsB stays inert.
    var typeB: ProcessorType? = nil
    // delta item 8: procB's transpose — STORED (COPY A→B + round-trip) but render-INERT in v1 (SnapColour
    // carries a single transpose; both faces sound with A's, matching the old pair behavior). Making it
    // render-live is a future increment (SnapColour.transposeB + effectiveTranspose + 400+i addresses).
    // Optional (append-only §12.0) → old docs decode nil; read via `transposeBResolved`.
    var transposeB: Int? = nil
    // LEGACY (delta §9 item 5, retired by item 8): the old morph PARTNER — an index 0…15 or nil. DECODE-ONLY
    // now: `migrateColourPairsIfNeeded` copies the partner into procB, then the render ignores this. Kept
    // (never deleted) so an older build re-loading a migrated doc still reads the pair (lossless downgrade).
    var altColour: Int? = nil
    // Per-TYPE stash of TRANSPOSE (spec revision): each processor type keeps its own transpose, so
    // switching type never leaks a pitch. Optional → v2 docs decode as nil (all-zero).
    var transposeByType: [Int]? = nil
    var morphByType: [Double]? = nil   // LEGACY: morph is now a single per-Colour scalar (toward partner), not per-type
    // §9 item 1 the ON TRIGGER SYSTEM (GUI iteration 1, 2026-07-26): per-Colour trigger assignments,
    // STORED INERT — no engine execution yet. Optional so pre-ON docs decode as nil → OnConfig() defaults.
    var on: OnConfig? = nil
    /// The ON config, nil-safe (missing ⇒ all-"—"/unchecked). Non-persisting read helper.
    var onResolved: OnConfig { on ?? OnConfig() }
    // Cells/desk overhaul C1: an OPTIONAL Colour NAME (the user's word). Optional → old docs decode nil.
    var name: String? = nil
    /// The custom name if set, else the TYPE name (today's label). Never empty.
    var nameResolved: String { (name.flatMap { $0.isEmpty ? nil : $0 }) ?? type.rawValue }
    // Cells/desk overhaul D1: whether this Colour is DEFINED (a palette chip) vs an undefined "+" slot. Optional
    // → old docs decode nil ⇒ DEFINED (all 16 as today). Non-persisting read helper below.
    var defined: Bool? = nil
    var isDefined: Bool { defined ?? true }

    /// delta item 8: does this Colour have a second processor (procB)? Drives morph/ALT availability + greying.
    var hasProcB: Bool { typeB != nil }
    /// procB's transpose, nil-safe (missing ⇒ 0). Render-inert in v1; kept for COPY A→B + round-trip.
    var transposeBResolved: Int { transposeB ?? 0 }

    /// Switch the processor type, giving each type its own TRANSPOSE. Stash the active transpose under the
    /// old type, restore the new type's. Idempotent for a no-op switch. `morph` is a single per-Colour
    /// scalar (the position toward the partner, delta §9 item 5) — NOT per-type — so a type switch leaves
    /// it untouched. `transpose` remains the live (AUParameter- and snapshot-facing) value for this type.
    mutating func switchType(to newType: ProcessorType) {
        guard newType != type else { return }
        let n = ProcessorType.allCases.count
        func sized(_ a: [Int]?) -> [Int] { var v = a ?? []; if v.count < n { v += Array(repeating: 0, count: n - v.count) }; return v }
        var tStash = sized(transposeByType)
        let oldIdx = ProcessorType.allCases.firstIndex(of: type) ?? 0
        let newIdx = ProcessorType.allCases.firstIndex(of: newType) ?? 0
        tStash[oldIdx] = transpose      // save the active transpose under the old type
        transpose = tStash[newIdx]      // restore the new type's own transpose
        type = newType
        transposeByType = tStash
    }
}

// MARK: - ON trigger config (§9 item 1) — per-Colour; GUI iteration 1 stores it INERT (no engine yet).
// Enums are String-raw so their rawValue IS the chip label. Append-only (never reorder/reuse the strings).

enum OnTap: String, Codable, CaseIterable { case none = "—", alt = "ALT", mute = "MUTE", solo = "SOLO EMITTERS", fill = "FILL", replay = "REPLAY" }
enum OnTapWhen: String, Codable, CaseIterable { case now = "NOW", step = "STEP", pass = "PASS", lap = "LAP" }
enum OnTapFor: String, Codable, CaseIterable { case retap = "RETAP", onePass = "1 PASS", oneLap = "1 LAP" }
enum OnHold: String, Codable, CaseIterable { case none = "—", alt = "ALT", freeze = "FREEZE", sliceCycle = "SLICE-CYCLE", morphScrub = "MORPH-SCRUB", oct = "OCT" }
enum OnHoldRelease: String, Codable, CaseIterable { case spring = "SPRING", latch = "LATCH" }
enum SliceSize: String, Codable, CaseIterable { case half = "½", quarter = "¼", eighth = "⅛", sixteenth = "1⁄16" }
enum OnArrive: String, Codable, CaseIterable { case none = "—", altAlternate = "ALT-ALTERNATE", morphDrift = "MORPH-DRIFT", dice = "DICE", emitterRotate = "EMITTER-ROTATE" }
enum DriftMode: String, Codable, CaseIterable { case loop = "↻", pingpong = "⇄" }
enum OnLeave: String, Codable, CaseIterable { case none = "—", exitStab = "EXIT STAB", ringChop = "RING·CHOP" }

/// The five ON rows for one Colour. All fields defaulted (none/unchecked), so `OnConfig()` is "unassigned".
/// Every field non-Optional with a default — the whole struct is written together; `Colour.on` is the
/// Optional that gives old-doc compatibility. (A FUTURE schema change here must add fields as Optional or
/// custom-decode, or bump formatVersion — this version reads only what it wrote.)
struct OnConfig: Codable, Equatable {
    // ON TAP
    var tap: OnTap = .none
    var tapWhen: OnTapWhen = .now
    var tapFor: OnTapFor = .retap
    // ON HOLD
    var hold: OnHold = .none
    var holdRelease: OnHoldRelease = .spring
    var sliceSize: SliceSize = .quarter        // shown only when hold == .sliceCycle
    var octUp: Bool = true                     // OCT direction ± (shown only when hold == .oct)
    // ON ARRIVE
    var arrive: OnArrive = .none
    var arriveEvery: Int = 1                   // 1…4
    var driftPct: Int = 10                     // ±n% (shown only when arrive == .morphDrift)
    var driftMode: DriftMode = .pingpong       // ↻ / ⇄ (shown only when arrive == .morphDrift)
    // ON LEAVE
    var leave: OnLeave = .none
    // ON SCENE (independent checklist facets)
    var sceneEntrance: Bool = false
    var entrancePass: Int = 1                  // 1…16
    var sceneExit: Bool = false
    var exitPass: Int = 1                      // 1…16
    var sceneResetMorph: Bool = false
    var sceneAutoArm: Bool = false             // always greyed this iteration (no RECORD type)

    /// True when nothing is assigned anywhere — the whole section reads "unassigned".
    var isEmpty: Bool { self == OnConfig() }

    // Collapsed-row summaries (the accordion shows these). "" ⇒ the row is unassigned (render a dim "＋").
    var tapSummary: String {
        guard tap != .none else { return "" }
        return "\(tap.rawValue) · \(tapWhen.rawValue) · \(tapFor.rawValue)"
    }
    var holdSummary: String {
        guard hold != .none else { return "" }
        var s = "\(hold.rawValue) · \(holdRelease.rawValue)"
        if hold == .sliceCycle { s += " · \(sliceSize.rawValue)" }
        if hold == .oct { s += " · \(octUp ? "+" : "−")" }
        return s
    }
    var arriveSummary: String {
        guard arrive != .none else { return "" }
        var s = arrive.rawValue
        if arrive == .morphDrift { s += " \(driftMode.rawValue) \(driftPct)%" }
        s += " · every \(arriveEvery)"
        return s
    }
    var leaveSummary: String { leave == .none ? "" : leave.rawValue }
    var sceneSummary: String {
        var parts: [String] = []
        if sceneEntrance { parts.append("ENTER \(entrancePass)") }
        if sceneExit { parts.append("EXIT \(exitPass)") }
        if sceneResetMorph { parts.append("RESET MORPH") }
        if sceneAutoArm { parts.append("AUTO-ARM") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Cell (the patch point) — §1.1: cells share nothing.

/// §cell-edit D — CHORD SPLIT: which of a MIDI-IN cell's held source notes it takes. ALL (default) · TOP n ·
/// BOTTOM n · KEY RANGE (a split note + a side). On the ascending source list every mode is a contiguous
/// window (RANGE HIGH = the ≥split suffix, LOW = the <split prefix), resolved by `chordSplitWindow`.
enum SplitMode: String, Codable, CaseIterable { case all = "ALL", top = "TOP", bottom = "BOTTOM", range = "RANGE" }
struct ChordSplit: Codable, Equatable {
    var mode: SplitMode = .all
    var n: Int = 2            // TOP/BOTTOM: how many notes
    var note: Int = 60       // RANGE: the split point (MIDI note)
    var high: Bool = true    // RANGE: side — true = notes ≥ split (HIGH), false = notes < split (LOW)
}

/// §cell-edit D — VELOCITY WINDOW: a MIDI-IN cell admits only source notes whose velocity is in [floor, ceil].
/// The default (1…127) admits everything; it gates at the source boundary, BEFORE the chord split selects.
struct VelWindow: Codable, Equatable {
    var floor: Int = 1       // 1…127
    var ceil: Int = 127      // 1…127 (≥ floor)
}

/// §cell-edit F — CHOP ("destination sequence"): per pass-column, where this cell's output goes — MAIN (its own
/// emitters) · REDIRECT (its emitters PLUS the shared `alt` set) · MUTE (silent, note-off at the slice edge).
/// 8 slots = the 8 grid columns. Default (all MAIN, empty alt) = no effect. [Model+UI here; the routing ENGINE
/// is a separate increment.]
enum ChopSlot: String, Codable { case main = "MAIN", redirect = "REDIR", mute = "MUTE" }
struct Chop: Codable, Equatable {
    var slots: [ChopSlot] = Array(repeating: .main, count: 8)
    var alt: Set<Bus> = []
}

struct Cell: Codable, Equatable {
    var colourID: String
    var stack: Bool = false        // v2 LEGACY (▾) — decode-only after commit 3; removed at commit 4
    var buses: Set<Bus> = [.a]     // sound leaves ONLY through a lit letter (§2.3)
    var srcMix: Bool = false       // v2 LEGACY (+SRC) — no v3 equivalent; dropped on migration
    var alt: Bool = false
    var bypassed: Bool = false
    var muted: Bool = false
    // v3.0 (delta §1/§2): the cell's single input reference. nil = MIDI IN; else the referenced row
    // in the same column (any row; cycles legal-and-silent). Optional → old docs (no key) decode as
    // nil and are filled by migrateLegacyRoutingIfNeeded(); the render path uses SnapCell's Int
    // sentinel, not this.
    var inputRow: Int? = nil
    // v3.0 (delta §7): input-channel filter for a MIDI-IN cell. 0 = OMNI (default); 1–16 = only notes
    // arriving on that channel. Applies at the source boundary only (referenced parents aren't filtered).
    // LEGACY after RECEIVERS (delta §9 item 11): the filter now lives on the Receiver a cell subscribes
    // to. Kept for migration (synthesizeReceiversIfNeeded reads it) + as the fallback when a doc has no
    // receivers; not dropped until a later formatVersion (parallel to `stack`/`srcMix`).
    var inputChannel: Int = 0
    // delta §9 item 11: the RECEIVER a MIDI-IN cell subscribes to (0–3). Consulted ONLY when inputRow ==
    // nil; nil = the default receiver (0 = Receiver 1). Row-referencing cells ignore it. The cell's
    // effective source filter is resolved from this receiver at build time (SnapCell.inputChannel).
    var inputReceiver: Int? = nil
    // §cell-edit D CHORD SPLIT (per-cell): which held source notes this cell takes. Optional → old docs decode
    // as nil = ALL (no split). Applies at the source boundary (SnapCell mirror drives the render path).
    var chordSplit: ChordSplit? = nil
    var chordSplitResolved: ChordSplit { chordSplit ?? ChordSplit() }
    // §cell-edit D VELOCITY WINDOW (per-cell): admit only source notes with velocity in [floor, ceil]. Optional
    // → old docs decode nil = full range (1…127). Gates at the source boundary, before the chord split.
    var velWindow: VelWindow? = nil
    var velWindowResolved: VelWindow { velWindow ?? VelWindow() }
    // §cell-edit F CHOP (per-cell output sequence). Optional → old docs decode nil = no chop (all MAIN).
    var chop: Chop? = nil
    var chopResolved: Chop { chop ?? Chop() }
}

// MARK: - Receiver (delta §9 item 11) — a shared, named MIDI-input object

/// One of four document-level MIDI receivers. A MIDI-IN cell subscribes to a receiver (FROM RECEIVER n)
/// and inherits its channel filter; the receiver also carries a persisted input-mute (the input twin of
/// the §6a emitter mute) and a per-receiver MPE-merge flag (the "MPE front door" — field only for now;
/// merge semantics are their own later mini-spec). Receiver COLOUR is assigned by index (the fixed
/// infrastructure family), not stored. note-RANGE (register splits) is a later addition — no field yet.
struct Receiver: Codable, Equatable {
    var name: String = ""
    var channel: Int = 0        // 0 = OMNI (default), 1–16 = single wire channel (wire ch = channel − 1)
    var mpeMerge: Bool = false  // per-receiver MPE-merge (the front door); engine semantics deferred
    var muted: Bool = false     // input mute (PERSISTED) — a muted receiver feeds its subscribers nothing
    // §item 11 INPUT CABLES (amendment 2026-07-26): the input cable(s) this receiver reads, as a BITMASK
    // (bit i = cable i+1; cables 1–4). Optional so pre-cable docs decode as nil ⇒ ANY (all cables) — a
    // migration no-op. The v1 stepper writes ANY or a single bit; the bitmask reserves subset-multi later.
    var cable: Int? = nil
    /// The cable bitmask, nil-safe: missing ⇒ ANY (hears every cable). Non-persisting read helper.
    var cableResolved: Int { cable ?? 0b1111 }
    // TWO LATCH MODES (ferry 2026-07-27): the per-receiver latch update rule. false/nil = CHORD (as built,
    // detect-and-replace); true = ADD (note-toggle accumulation — each note-on toggles frozen-pool membership).
    // Persisted rig config. Optional so old docs decode nil ⇒ CHORD. Latch-off releases all in both modes.
    var latchAdd: Bool? = nil
    /// The latch mode, nil-safe: missing ⇒ CHORD (false). Non-persisting read helper.
    var latchAddResolved: Bool { latchAdd ?? false }
}

// MARK: - Scene & document — §9

struct SceneState: Codable, Equatable {
    var cells: [[Cell?]]           // [column][row], 8×8
    // (removed 2026-07: rowBypass/stackMute/stackSolo — dead since v3, never read by any engine path;
    //  old docs that still carry those keys decode fine, Codable just ignores them.)
    var stepRate: StepRate = .r1_2
    var swing: Int = 50            // 50 straight … 75 (§4 v2.3)
    var tapAction: TapAction = .alt
    var quant: Quant = .off        // §6.8
    // master panel: KEY — per-scene master transpose (semitones, clamp ±12), applied to every output note.
    // Optional (append-only) → old scenes decode nil (0). PERSISTED (the key is structure).
    var masterKey: Int? = nil
    var masterKeyResolved: Int { max(-12, min(12, masterKey ?? 0)) }

    static func empty() -> SceneState {
        SceneState(cells: Array(repeating: Array(repeating: nil, count: 8), count: 8))
    }

    /// A scene with no placed cells — the sparse "+" slot on the strip (never destroyed; just absent).
    var isEmpty: Bool { cells.allSatisfy { $0.allSatisfy { $0 == nil } } }

    /// delta §5 drag-and-drop: relocate a cell. Onto an empty slot = MOVE; onto an occupied slot = SWAP.
    /// Both are one swap of the cell structs — fields move AS-IS (MOVES NEVER REWRITE REFERENCES: inputRow
    /// is row-level, so within-row drags stay reference-safe and cross-row drags rewire meaning visibly).
    mutating func swapCells(_ a: (col: Int, row: Int), _ b: (col: Int, row: Int)) {
        guard a.col >= 0, a.col < 8, a.row >= 0, a.row < 8,
              b.col >= 0, b.col < 8, b.row >= 0, b.row < 8,
              (a.col != b.col || a.row != b.row) else { return }
        let tmp = cells[a.col][a.row]
        cells[a.col][a.row] = cells[b.col][b.row]
        cells[b.col][b.row] = tmp
    }
}

struct PluginState: Codable, Equatable {
    var formatVersion: Int = 2     // 2 = v2.x chain routing · 3 = v3.0 graph routing · 4 = + receivers (§migration)
    var colours: [Colour]
    var scenes: [SceneState]       // length 1 in v2.x; scenes are the flagship next feature
    var activeScene: Int = 0
    var morphMaster: Double = 0    // RETIRED (delta §9 item 5): param #300 stays registered (invariant 5)
                                   // but the render no longer applies it — morph is per-Colour only.
    var busChannels: [Int] = [1, 2, 3, 4]   // v3.0 (delta §7): each bus A–D stamps this channel on exit
    // delta §6a: per-emitter enable (the per-output performance mute). Optional so v2/old docs decode as
    // nil → all-enabled (the loader default); the gate lives ONLY at the emission boundary (seam rule 3).
    var busEnabled: [Bool]? = nil
    /// The four enable flags, nil/short-array safe (missing ⇒ enabled). Non-persisting read helper.
    var busEnabledResolved: [Bool] {
        let e = busEnabled ?? []
        return (0..<4).map { $0 < e.count ? e[$0] : true }
    }
    // delta §6a CLAIM: LEGACY single-claimant field (0–3), kept for lossless decode/downgrade. v2 supersedes
    // it with `claimMask`; a doc written by v2 also stamps this to the lowest claimed bus so an OLDER build
    // still reads one claimant. Suppression lives at the emission boundary against the live voice table.
    var claimEmitter: Int? = nil
    // delta §6a CLAIM v2 (2026-07-27): MULTI-claim mask — bit i set ⇒ emitter i claims (SHARED tier, claimants
    // never suppress each other; non-claimants yield the union of all claimants' sounding pitch classes).
    // Persisted. Optional → nil derives from the legacy `claimEmitter` (old docs decode unchanged).
    var claimMask: UInt8? = nil
    /// The claim mask (bits A–D), deriving from the legacy single-claimant field when unset. Non-persisting.
    var claimMaskResolved: UInt8 {
        if let m = claimMask { return m & 0b1111 }
        if let e = claimEmitter, (0..<4).contains(e) { return UInt8(1 << e) }
        return 0
    }
    // delta §6a CLAIM v2 LEAK %: per-claimant bleed — a claimed pitch class passes on non-claimants at this
    // scaled velocity (0 = full suppression = v1; the hole becomes a SHADOW). Persisted. Optional → nil = all 0.
    var claimLeak: [Int]? = nil
    /// The four LEAK amounts (0…100), nil/short-array safe (missing ⇒ 0). Non-persisting read helper.
    var claimLeakResolved: [Int] { let a = claimLeak ?? []; return (0..<4).map { $0 < a.count ? max(0, min(100, a[$0])) : 0 } }
    // emitter role family: FLATTEN — activity ducking. While a FLATTEN emitter has anything sounding, OTHER
    // emitters' NEW note-ons arrive velocity-scaled by its amount (0…100%). Persisted (structure). Optional →
    // old docs decode nil (off). `flattenMask` = which emitters duck; `flattenAmount` = per-emitter amount.
    var flattenMask: UInt8? = nil
    var flattenAmount: [Int]? = nil
    /// The four FLATTEN amounts (0…100), nil/short-array safe (missing ⇒ 0). Non-persisting read helper.
    var flattenAmountResolved: [Int] { let a = flattenAmount ?? []; return (0..<4).map { $0 < a.count ? max(0, min(100, a[$0])) : 0 } }
    // emitter role family: ALT — turn-taking. ALT-lit emitters form ONE group; notes fanning to the group
    // alternate among its members in position order (2 = ping-pong, 3–4 = round-robin). Persisted. `altMask`
    // = the group; `altCount` = per-emitter notes-per-turn (1…8, default 1). Optional → old docs decode nil.
    var altMask: UInt8? = nil
    var altCount: [Int]? = nil
    /// The four ALT counts (1…8), nil/short-array safe (missing ⇒ 1). Non-persisting read helper.
    var altCountResolved: [Int] { let c = altCount ?? []; return (0..<4).map { $0 < c.count ? max(1, min(8, c[$0])) : 1 } }
    // master panel: MUTE — global emission kill (PERSISTED, document-level unlike the per-scene KEY). Optional
    // → old docs decode nil (not muted). The gate lives at the emission boundary (seam rule 3).
    var masterMute: Bool? = nil
    // receiver strip: the THRU pip — a PERSISTED one-of-4 radio (structure persists). Passthrough (CC/PB/AT +
    // stopped-note soundcheck) follows THIS receiver, superseding the hardwired follows-R1 rule. Optional so
    // old docs decode nil ⇒ default R1 (index 0). Mirrors claimEmitter's persist-and-radio shape.
    var thruReceiver: Int? = nil
    // delta §9 item 11: the four document-level MIDI receivers (shared named inputs). Optional so pre-
    // receiver docs decode as nil and get four synthesized by synthesizeReceiversIfNeeded() on load.
    var receivers: [Receiver]? = nil
    /// The four receivers, nil/short-array safe (missing ⇒ OMNI). Non-persisting read helper.
    var receiversResolved: [Receiver] {
        let r = receivers ?? []
        return (0..<4).map { $0 < r.count ? r[$0] : Receiver(name: "\($0 + 1)") }
    }
    /// The THRU-pip receiver index, nil-safe + clamped (missing ⇒ R1). Non-persisting read helper.
    var thruReceiverResolved: Int { min(3, max(0, thruReceiver ?? 0)) }

    /// A copy with one ACTIVE-scene cell forced to `cell` (nil = empty). Used to STRIP the live staging
    /// preview from the encoded preset: the preview is placed into the document transiently (so it sounds
    /// in context), so a host autosave landing mid-hover must encode the RESTORED cell, never the preview.
    /// Bounds-guarded → returns self unchanged for an out-of-range address.
    func restoringCell(col: Int, row: Int, to cell: Cell?) -> PluginState {
        guard activeScene >= 0, activeScene < scenes.count,
              col >= 0, col < 8, row >= 0, row < scenes[activeScene].cells[col].count else { return self }
        var s = self
        s.scenes[activeScene].cells[col][row] = cell
        return s
    }

    // MARK: - MULTI-SCENE (2026-07-27) — the scene strip switches activeScene within one document

    static let maxScenes = 8           // the strip's fixed slot count (8 — leaves the header room for the preset selector)

    /// The active scene index, always in-bounds (clamped; falls back to 0 if the doc is odd). Never crashes.
    var activeSceneResolved: Int { scenes.isEmpty ? 0 : max(0, min(scenes.count - 1, activeScene)) }
    /// The active scene (bounds-safe), for the render + UI.
    var activeSceneState: SceneState { scenes.isEmpty ? .empty() : scenes[activeSceneResolved] }

    /// Extend `scenes` to exactly `n` fixed slots (padding with empty "+" scenes). Idempotent; never shrinks
    /// below the current count. The strip is a fixed 16 slots, so old length-1 docs pad to 16 on load.
    mutating func padScenes(to n: Int = maxScenes) {
        if scenes.isEmpty { scenes = [.empty()] }
        while scenes.count < n { scenes.append(.empty()) }
    }
    /// SAVE-HERE: copy the ACTIVE scene into slot `i` (self-advertising save-as on an empty +), padding first.
    /// Precious-scene law: this is the ONLY write onto a slot; drag SWAPs, never overwrites (see the strip).
    mutating func saveCurrentScene(toSlot i: Int) {
        guard i >= 0, i < Self.maxScenes else { return }
        padScenes(to: max(i + 1, scenes.count))
        scenes[i] = activeSceneState
    }
    /// Switch the active scene to a NON-EMPTY slot. Empty slots aren't playable (they're + save targets).
    mutating func switchScene(to i: Int) {
        guard i >= 0, i < scenes.count, !scenes[i].isEmpty else { return }
        activeScene = i
    }

    // MARK: - S3: drag on the strip = MOVE / SWAP / DELETE (never overwrite — the precious-scene law)

    /// DRAG a scene onto another slot. The model decides: EMPTY target = MOVE (relocate; source empties);
    /// OCCUPIED target = SWAP (exchange). Never an overwrite. The active (playing) scene follows its content.
    mutating func dragScene(from a: Int, to b: Int) {
        guard a != b, scenes.indices.contains(a), scenes.indices.contains(b), !scenes[a].isEmpty else { return }
        if scenes[b].isEmpty { moveScene(from: a, to: b) } else { swapScenes(a, b) }
    }
    /// MOVE onto an empty slot: the scene relocates, the source becomes empty. The active index follows.
    mutating func moveScene(from a: Int, to b: Int) {
        guard a != b, scenes.indices.contains(a), scenes.indices.contains(b), scenes[b].isEmpty else { return }
        let act = activeSceneResolved
        scenes[b] = scenes[a]; scenes[a] = .empty()
        if act == a { activeScene = b }
    }
    /// SWAP two slots (exchange — never overwrite). The active (playing) scene follows its content to its new slot.
    mutating func swapScenes(_ a: Int, _ b: Int) {
        guard a != b, scenes.indices.contains(a), scenes.indices.contains(b) else { return }
        let act = activeSceneResolved
        scenes.swapAt(a, b)
        if act == a { activeScene = b } else if act == b { activeScene = a }
    }
    /// DELETE a scene (the trash). The ACTIVE scene REFUSES — the instrument always has a playing scene.
    /// Returns false (rejected) when the slot is the active one, empty, or out of range — the UI shakes on false.
    @discardableResult mutating func deleteScene(_ i: Int) -> Bool {
        guard scenes.indices.contains(i), i != activeSceneResolved, !scenes[i].isEmpty else { return false }
        scenes[i] = .empty()
        return true
    }

    /// Migrate a legacy (v2.x) document to the v3.0 routing schema, in place. Idempotent and gated
    /// on formatVersion, so it is safe to call on every document entering the AU (load / factory /
    /// test session). Mapping (migration-tree-routing.md §1): a cell fed under the old model — i.e.
    /// the cell ABOVE is occupied and its `stack` is on — references that row (`inputRow = r-1`);
    /// everything else is MIDI IN (nil). `srcMix` has no v3 equivalent and is dropped (logged).
    /// The old `stack`/`srcMix` fields are LEFT in place but are read ONLY by this migration now —
    /// the commit-3 flip made `resolvedParent` the live routing path (the router no longer reads `stack`).
    mutating func migrateLegacyRoutingIfNeeded() {
        if formatVersion < 3 {
            var droppedSrcMix = 0
            for si in scenes.indices {
                for col in scenes[si].cells.indices {
                    for row in scenes[si].cells[col].indices {
                        guard var cell = scenes[si].cells[col][row] else { continue }
                        let aboveStacked = row > 0 && (scenes[si].cells[col][row - 1]?.stack ?? false)
                        cell.inputRow = aboveStacked ? row - 1 : nil
                        if cell.srcMix { droppedSrcMix += 1 }
                        scenes[si].cells[col][row] = cell
                    }
                }
            }
            if droppedSrcMix > 0 {
                print("MidiSpark: migrated v2 document to graph routing; dropped +SRC on \(droppedSrcMix) cell(s) (no v3 equivalent).")
            }
            formatVersion = 3
        }
        synthesizeReceiversIfNeeded()   // delta §9 item 11 — runs for v3 docs too (they have no receivers yet)
        migrateColourPairsIfNeeded()    // delta item 8 — fold each Colour's partner into its own procB
        padScenes()                     // MULTI-SCENE: a fixed 16-slot strip — old length-1 docs pad with empties
    }

    /// delta item 8 (TWO-PROCESSOR Colours): fold the retired pair reference into each Colour's own procB.
    /// Idempotent, gated on formatVersion < 5. For a Colour with a valid `altColour` partner: copy the
    /// partner's type/params/transpose into procB (typeB/paramsB/transposeB), overwriting any stale paramsB.
    /// `altColour` is LEFT in place (decode-only legacy) so an older build re-loading a migrated doc still
    /// reads the pair — lossless downgrade. The new render sources B ONLY from typeB, so keeping altColour is
    /// inert. Reads partner.type/paramsA/transpose (never written here) so in-place mutation is safe.
    mutating func migrateColourPairsIfNeeded() {
        guard formatVersion < 5 else { return }
        var migrated = 0
        for i in colours.indices {
            guard let pi = colours[i].altColour, pi >= 0, pi < colours.count, pi != i else { continue }
            colours[i].typeB = colours[pi].type
            colours[i].paramsB = colours[pi].paramsA
            colours[i].transposeB = colours[pi].transpose
            migrated += 1
        }
        if migrated > 0 {
            print("MidiSpark: migrated \(migrated) Colour pair(s) into internal procB (delta item 8).")
        }
        formatVersion = 5
    }

    /// delta §9 item 11: promote per-cell input-channel filters to four shared RECEIVERS. Idempotent
    /// (gated on `receivers == nil`), runs on every doc entering the AU. Distinct MIDI-IN channel filters
    /// are collected in ORDER OF APPEARANCE → up to 4 receivers (Receiver 1 = the first, usually OMNI 0);
    /// >4 distinct collapse the overflow to Receiver 1 + log. Each MIDI-IN cell is pointed at the receiver
    /// matching its old filter. OMNI (the overwhelming default) → Receiver 1 ⇒ clean, band-free grids.
    mutating func synthesizeReceiversIfNeeded() {
        if receivers == nil {
            var distinct: [Int] = []
            for scene in scenes {
                for col in scene.cells {
                    for maybe in col {
                        guard let cell = maybe, cell.inputRow == nil else { continue }   // MIDI-IN cells only
                        let ch = max(0, min(16, cell.inputChannel))
                        if !distinct.contains(ch) { distinct.append(ch) }
                    }
                }
            }
            if distinct.isEmpty { distinct = [0] }                       // no MIDI-IN cells → a lone OMNI receiver
            let overflow = max(0, distinct.count - 4)
            if overflow > 0 { distinct = Array(distinct.prefix(4)) }
            var recs = distinct.enumerated().map { Receiver(name: "\($0.offset + 1)", channel: $0.element) }
            while recs.count < 4 { recs.append(Receiver(name: "\(recs.count + 1)")) }   // pad to 4 (OMNI)
            receivers = recs
            if overflow > 0 {
                print("MidiSpark: synthesized receivers; \(overflow) overflow input channel(s) collapsed to Receiver 1.")
            }
            formatVersion = max(formatVersion, 4)
        }
        // Point every UNPOINTED MIDI-IN cell at the receiver matching its channel (R1 on no match). This runs
        // ALWAYS (idempotent — only nil cells), so a v3 doc built with receivers PRE-SET but cells left nil is
        // repaired too — else those cells fall to the legacy per-cell filter and bypass receiver MUTE while
        // playing (delta §9 item 11 mute ruling 2026-07-26).
        guard let recs = receivers else { return }
        for si in scenes.indices {
            for col in scenes[si].cells.indices {
                for row in scenes[si].cells[col].indices {
                    guard var cell = scenes[si].cells[col][row],
                          cell.inputRow == nil, cell.inputReceiver == nil else { continue }
                    let ch = max(0, min(16, cell.inputChannel))
                    cell.inputReceiver = recs.firstIndex(where: { $0.channel == ch }) ?? 0   // overflow → R1
                    scenes[si].cells[col][row] = cell
                }
            }
        }
    }

    /// D1: mark a Colour DEFINED iff it is painted in some scene — so a fresh factory/arc ships a SPARSE palette
    /// (only the used Colours as chips; the rest are "+" slots). Old saved docs (`defined == nil`) are untouched.
    mutating func markDefinedFromUsage() {
        let used = Set(scenes.flatMap { $0.cells.flatMap { $0.compactMap { $0?.colourID } } })
        for i in colours.indices { colours[i].defined = used.contains(colours[i].colourID) }
    }

    static func factory() -> PluginState {
        var colours = colourIDs.map { Colour(colourID: $0, type: .arp) }
        // A few designed defaults so the factory session sounds immediately (§6.6). (Old paramsB ALT
        // demos dropped — the pair model sets ALT via a partner Colour; re-author as a follow-up.)
        func idx(_ id: String) -> Int { colourIDs.firstIndex(of: id)! }
        colours[idx("gold")].paramsA.octaves = 2
        colours[idx("cyan")].type = .ratchet
        colours[idx("cyan")].paramsA.count = 4
        colours[idx("vermilion")].type = .passgate
        colours[idx("magenta")].transpose = 12

        var scene = SceneState.empty()
        scene.cells[0][0] = Cell(colourID: "gold")
        scene.cells[2][0] = Cell(colourID: "vermilion")
        scene.cells[2][1] = Cell(colourID: "magenta", buses: [.b], inputRow: 0)   // references row 0 (§1)
        scene.cells[4][0] = Cell(colourID: "gold")
        scene.cells[6][0] = Cell(colourID: "cyan")
        var state = PluginState(colours: colours, scenes: [scene])
        state.formatVersion = 4   // built directly in the v3.0 graph model + receivers
        // Synthesize the four receivers AND POINT every MIDI-IN cell at one — the initial document + store are
        // built straight from factory() (no migrate pass), so without this the cells would keep inputReceiver=nil
        // and bypass receiver MUTE (delta §9 item 11).
        state.synthesizeReceiversIfNeeded()
        // Default routing (2026-07-27): receiver A = OMNI so the instrument works out of the box for the
        // one-keyboard majority (any channel is heard); B/C/D filter ch 2/3/4 so multi-source rigs are ready
        // without stranding the common case. Only the factory default changes here — old-doc migration keeps
        // synthesizing OMNI pads (never invents absent filters).
        for i in state.receivers!.indices { state.receivers![i].channel = i == 0 ? 0 : i + 1 }
        state.padScenes()   // MULTI-SCENE: slot 0 = the designed scene, slots 1–15 empty (+) — the strip is 16
        state.markDefinedFromUsage()   // D1: sparse palette — only the painted Colours are defined chips
        return state
    }

    /// §3b/3c THE DEFAULT ARC — the first-launch state: THREE musical scenes (arps → +elements → EPIC), all
    /// SINGLE-EMITTER (everything → A, ch1) so the first-try one-synth rig is always audible (the minimum-rig
    /// law). Each cell is an independent treatment of the held chord (MIDI-IN via R1/OMNI) summing to A — the
    /// one-chord orchestra. Content is a sensible first cut; ear-tuning happens on device.
    static func defaultArc() -> PluginState {
        var colours = colourIDs.map { Colour(colourID: $0, type: .arp) }
        func set(_ id: String, _ f: (inout Colour) -> Void) { f(&colours[colourIDs.firstIndex(of: id)!]) }
        // The arc's palette: arps at different patterns/rates/octaves + a harmonize bloom + a chance shimmer + a bass.
        set("gold")      { $0.type = .arp; $0.paramsA.pattern = .up;     $0.paramsA.rate = .r1_16; $0.paramsA.octaves = 1 }
        set("cyan")      { $0.type = .arp; $0.paramsA.pattern = .upDown; $0.paramsA.rate = .r1_8 }
        set("azure")     { $0.type = .arp; $0.paramsA.pattern = .up;     $0.paramsA.rate = .r1_16; $0.paramsA.octaves = 2 }  // sparkle up
        set("bronze")    { $0.type = .arp; $0.paramsA.pattern = .up;     $0.paramsA.rate = .r1_8;  $0.transpose = -12 }       // bass octave down
        set("magenta")   { $0.type = .harmonize; $0.paramsA.harmIntervals = [4, 7, 0]; $0.paramsA.harmVelScale = 0.7 }        // + third + fifth bloom
        set("teal")      { $0.type = .chance; $0.paramsA.probability = 0.6 }                                                  // shimmer

        // Scene 1 — a series of arps, an interesting pattern
        var s1 = SceneState.empty()
        s1.cells[0][0] = Cell(colourID: "gold")
        s1.cells[2][0] = Cell(colourID: "cyan")
        s1.cells[4][0] = Cell(colourID: "gold")
        s1.cells[6][0] = Cell(colourID: "azure")

        // Scene 2 — adds elements (a bass octave + a harmonize bloom under the arps)
        var s2 = s1
        s2.cells[0][1] = Cell(colourID: "bronze")
        s2.cells[4][1] = Cell(colourID: "magenta")

        // Scene 3 — EPIC: dense · OCT register spread · harmonize + chance shimmer · rhythmic interlock (all → A)
        var s3 = SceneState.empty()
        for c in [0, 2, 4, 6] { s3.cells[c][0] = Cell(colourID: "gold") }
        for c in [1, 3, 5, 7] { s3.cells[c][0] = Cell(colourID: "azure") }
        s3.cells[0][1] = Cell(colourID: "bronze"); s3.cells[4][1] = Cell(colourID: "bronze")
        s3.cells[2][1] = Cell(colourID: "magenta"); s3.cells[6][1] = Cell(colourID: "magenta")
        s3.cells[3][2] = Cell(colourID: "teal");   s3.cells[7][2] = Cell(colourID: "teal")

        var state = PluginState(colours: colours, scenes: [s1, s2, s3])
        state.formatVersion = 4
        state.synthesizeReceiversIfNeeded()                         // point every MIDI-IN cell at a receiver (R1)
        for i in state.receivers!.indices { state.receivers![i].channel = i == 0 ? 0 : i + 1 }   // A=OMNI, B/C/D=2/3/4
        state.padScenes()                                           // slots 3…7 = +
        state.markDefinedFromUsage()                                // D1: sparse palette — only the arc's Colours are defined
        return state
    }
}

// MARK: - MODELESS EDIT scope (2026-07-27) — scope-after-target: THIS · ALL IDENTICAL · ALL <COLOUR>

extension SceneState {
    enum EditScope { case thisOne, allIdentical, allColour }

    /// The cells an EDIT at `(col,row)` should touch under `scope`, as encoded positions (col*8 + row), sorted.
    /// ALL IDENTICAL = same Colour AND same routing (input source + emitter buses); ALL COLOUR = same Colour.
    /// An empty exemplar ⇒ []. Pure — the counted-chip + flash-set truth behind "EDITING n · ALL GOLD".
    func editScopeTargets(col: Int, row: Int, scope: EditScope) -> [Int] {
        guard col >= 0, col < 8, row >= 0, row < 8, col < cells.count, row < cells[col].count,
              let ex = cells[col][row] else { return [] }
        var out: [Int] = []
        for c in 0..<8 where c < cells.count {
            for r in 0..<8 where r < cells[c].count {
                guard let cell = cells[c][r] else { continue }
                let hit: Bool
                switch scope {
                case .thisOne:      hit = c == col && r == row
                case .allColour:    hit = cell.colourID == ex.colourID
                case .allIdentical: hit = cell.colourID == ex.colourID && cell.inputRow == ex.inputRow
                                        && cell.inputReceiver == ex.inputReceiver && cell.buses == ex.buses
                }
                if hit { out.append(c * 8 + r) }
            }
        }
        return out.sorted()
    }

    /// Apply `edit` to every cell in the EDIT scope — the propagation multiplier the write-armed panel commits.
    mutating func applyToScope(col: Int, row: Int, scope: EditScope, _ edit: (inout Cell) -> Void) {
        for key in editScopeTargets(col: col, row: row, scope: scope) {
            let c = key / 8, r = key % 8
            if var cell = cells[c][r] { edit(&cell); cells[c][r] = cell }
        }
    }

    // MARK: - §11 VERB LOGIC (the testable model ops behind the round verbs; PLACE stamps a Cell directly)

    /// REMOVE — §10b THE INHERIT-ON-DELETE LAW: delete the cell, and its CHILDREN (same-column cells whose
    /// `inputRow` points at this row) INHERIT its input — chain-fed ⇒ re-point to the grandparent; receiver-fed
    /// ⇒ hear the receiver directly. Orphan-silence never happens by accident. One step; the caller records undo.
    /// Remove the cell at (col,row) and re-point every child that read from it (`inputRow == row`) via the given
    /// rule. The two public deletes below differ ONLY in that rule — HEAL reconnects to the victim's parent,
    /// SEVER cuts to MIDI-IN. Shared here so the removal + child-scan lives in one place.
    private mutating func deleteCell(col: Int, row: Int, reparentChild: (_ child: inout Cell, _ victim: Cell) -> Void) {
        guard cells.indices.contains(col), cells[col].indices.contains(row), let victim = cells[col][row] else { return }
        cells[col][row] = nil
        for r in cells[col].indices {
            guard var child = cells[col][r], child.inputRow == row else { continue }
            reparentChild(&child, victim)
            cells[col][r] = child
        }
    }

    /// DELETE = HEAL: children reconnect to the victim's parent (the chain closes up).
    mutating func deleteCellHealing(col: Int, row: Int) {
        deleteCell(col: col, row: row) { child, victim in
            child.inputRow = victim.inputRow                    // inherit the victim's parent (nil = MIDI-IN)
            if victim.inputRow == nil { child.inputReceiver = victim.inputReceiver }
        }
    }

    /// DELETE = SEVER (AcceptanceCriteria 2026-07-29, refined for the null era 2026-07-30): the victim's routing is
    /// CUT — children do NOT reconnect to its parent and do NOT get silently re-pointed at R1 (which would read as
    /// a wiring choice nobody made). They fall to NULL input — no input row, no receiver — so the cut is honest
    /// (no receiver ring / no viz edge). Their own emitters are untouched.
    mutating func deleteCellSever(col: Int, row: Int) {
        deleteCell(col: col, row: row) { child, _ in
            child.inputRow = nil                                // cut the link to the victim
            child.inputReceiver = nil                           // …to NULL input, not R1 — the honest cut
        }
    }

    /// MOVE — §11b: relocate a cell to a target, OVERWRITING an occupied one (undo-covered). MOVES NEVER REWRITE
    /// REFERENCES — the cell's fields (incl. inputRow) travel as-is. No-op onto itself, out of range, or empty source.
    mutating func moveCellTo(from f: (col: Int, row: Int), to t: (col: Int, row: Int)) {
        guard f.col != t.col || f.row != t.row,
              cells.indices.contains(f.col), cells[f.col].indices.contains(f.row),
              cells.indices.contains(t.col), cells[t.col].indices.contains(t.row),
              cells[f.col][f.row] != nil else { return }
        cells[t.col][t.row] = cells[f.col][f.row]
        cells[f.col][f.row] = nil
    }

    // MARK: - §10/11f SPATIAL ROUTING (patch-bay model core; the UI projection lights + taps these)

    /// A CHAIN HEAD (11f) — a root fed by a RECEIVER (`inputRow == nil`); a tree of one counts. A BODY is row-fed.
    func isChainHead(col: Int, row: Int) -> Bool {
        guard cells.indices.contains(col), cells[col].indices.contains(row) else { return false }
        return cells[col][row]?.inputRow == nil && cells[col][row] != nil
    }
    /// ROUTE IN candidate SOURCES for cell X: OCCUPIED cells in the rows ABOVE X (same column). Empties don't light
    /// (nothing to hear). The four RECEIVERS are always candidates too — the UI adds them alongside these.
    func routeInSourcesAbove(col: Int, row: Int) -> [Int] {
        guard cells.indices.contains(col), row > 0 else { return [] }
        return (0..<row).filter { cells[col][$0] != nil }
    }
    /// ROUTE OUT graft targets for cell X: CHAIN HEADS in the rows BELOW X (same column). Heads light; bodies don't (11f).
    func graftHeadsBelow(col: Int, row: Int) -> [Int] {
        guard cells.indices.contains(col) else { return [] }
        return ((row + 1)..<cells[col].count).filter { isChainHead(col: col, row: $0) }
    }
    /// All occupied cells BELOW `row` in the column — the DEST candidates for multi-cell routing (each can be
    /// re-rooted to read from the focus above it). AcceptanceCriteria 2026-07-29: routing spans ALL cells above
    /// AND below the focus, not only chain heads.
    func routeOutTargetsBelow(col: Int, row: Int) -> [Int] {
        guard cells.indices.contains(col) else { return [] }
        return ((row + 1)..<cells[col].count).filter { cells[col][$0] != nil }
    }
    /// Would feeding (col,row) FROM `sourceRow` create a cycle (sourceRow's input chain already reaches row)? Bounded.
    private func wouldCycle(col: Int, row: Int, feedingFrom sourceRow: Int) -> Bool {
        var cur: Int? = sourceRow, hops = 0
        while let r = cur, hops < 8 { if r == row { return true }; cur = cells[col][r]?.inputRow; hops += 1 }
        return false
    }
    /// ROUTE IN (single-select radio) — feed cell X from a RECEIVER door: inputRow = nil, inputReceiver = r (0–3).
    mutating func routeInReceiver(col: Int, row: Int, receiver: Int) {
        guard cells.indices.contains(col), cells[col].indices.contains(row), var c = cells[col][row] else { return }
        c.inputRow = nil; c.inputReceiver = max(0, min(3, receiver)); cells[col][row] = c
    }
    /// ROUTE IN (single-select radio) — feed cell X from a ROW strictly ABOVE. No-op if not above, empty, or a cycle.
    mutating func routeInRow(col: Int, row: Int, sourceRow: Int) {
        guard cells.indices.contains(col), cells[col].indices.contains(row), sourceRow >= 0, sourceRow < row,
              cells[col][sourceRow] != nil, !wouldCycle(col: col, row: row, feedingFrom: sourceRow),
              var c = cells[col][row] else { return }
        c.inputRow = sourceRow; cells[col][row] = c
    }
    /// ROUTE OUT GRAFT (11f) — graft a CHAIN HEAD below under cell X: the head becomes row-fed by X and its whole
    /// SUBTREE follows (children reference the head's row, unchanged). Only a head grafts; its door assignment drops.
    mutating func graftHeadBelow(headRow: Int, under parentRow: Int, col: Int) {
        guard cells.indices.contains(col), cells[col].indices.contains(headRow), parentRow >= 0, parentRow < headRow,
              var h = cells[col][headRow], h.inputRow == nil,                       // only a head below grafts
              !wouldCycle(col: col, row: headRow, feedingFrom: parentRow) else { return }
        h.inputRow = parentRow; cells[col][headRow] = h
    }
    /// ROUTE OUT emitters — toggle cell X's membership of an emitter bus (multi).
    mutating func toggleEmitter(col: Int, row: Int, bus: Bus) {
        guard cells.indices.contains(col), cells[col].indices.contains(row), var c = cells[col][row] else { return }
        if c.buses.contains(bus) { c.buses.remove(bus) } else { c.buses.insert(bus) }
        cells[col][row] = c
    }
}

// MARK: - Session template / clipboard (delta §5) — one STAMP object

/// The session-scoped TEMPLATE = CLIPBOARD (one stamp object, delta §5): a cell's full config minus its
/// perform state. Written by committing a cell in the editor AND by COPY; read by the empty-cell pre-fill
/// and the split-paste actions. Ephemeral (never persisted). Bootstrap = the desk Colour + ⇐MIDI(R1) →A.
struct StampConfig: Equatable {
    var colourID: String
    var inputRow: Int? = nil        // a row reference; nil = MIDI-IN via the receiver below
    var inputReceiver: Int = 0      // 0–3, used when inputRow == nil
    var buses: Set<Bus> = [.a]

    static func bootstrap(colourID: String) -> StampConfig { StampConfig(colourID: colourID) }
    static func from(_ c: Cell) -> StampConfig {
        StampConfig(colourID: c.colourID, inputRow: c.inputRow, inputReceiver: c.inputReceiver ?? 0, buses: c.buses)
    }
    /// A fresh cell carrying this config (perform state defaulted).
    func makeCell() -> Cell {
        var c = Cell(colourID: colourID); applyRouting(to: &c); return c
    }
    /// Overwrite a cell's ROUTING (input source + output buses) from this config; colour + perform
    /// state untouched. Shared by `makeCell` and the staging live-propagation to the placed cells.
    func applyRouting(to c: inout Cell) {
        c.inputRow = inputRow; c.inputReceiver = inputReceiver; c.buses = buses
    }
}

// MARK: - Undo/redo (delta §5 / a6) — a bounded document-value stack

/// A bounded past/future stack of document VALUES for undo/redo (delta §5). `record` is called BEFORE a
/// mutation with the CURRENT (pre-mutation) value: it pushes onto the past, clears the redo future, and
/// caps the depth. A `coalesceKey` collapses a run of same-key records (a continuous gesture = one step):
/// the FIRST record of the run captures the pre-gesture value, later same-key records don't push again.
/// `undo`/`redo` take the live value and return the value to restore (moving the live one to the other
/// side). Pure and Foundation-only, so it unit-tests off-device; the AU owns the mutation choke point.
struct UndoStack<T: Equatable>: Equatable {
    private(set) var past: [T] = []
    private(set) var future: [T] = []
    private var lastKey: String? = nil
    let cap: Int

    init(cap: Int = 50) { self.cap = max(1, cap) }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func record(_ current: T, coalesceKey: String? = nil) {
        future.removeAll()                                   // a fresh edit invalidates the redo branch
        if let k = coalesceKey, k == lastKey, !past.isEmpty { return }   // same ongoing gesture → don't re-push
        past.append(current)
        if past.count > cap { past.removeFirst() }
        lastKey = coalesceKey
    }

    /// Returns the value to restore (and stashes `current` for redo), or nil if there is nothing to undo.
    mutating func undo(current: T) -> T? {
        guard let prev = past.popLast() else { return nil }
        future.append(current)
        lastKey = nil                                        // the next record starts a fresh coalesce run
        return prev
    }

    /// Returns the value to re-apply (and stashes `current` for undo), or nil if there is nothing to redo.
    mutating func redo(current: T) -> T? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        lastKey = nil
        return next
    }
}
