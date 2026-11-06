//  InputsGoldenTests.swift — INPUTS + HARMONY ferry (2026-11-06) §10 test 1: golden renders captured BEFORE any change. The default document and every factory preset, through the FOURFOLD chain (`FourfoldCompose`, the path the AU publishes),
//  32 bars at 120 BPM in 480-frame windows, under the page's MIDI mode ADD, REPLACE and ROOT (which become each lane's fallback mode, ferry 1.1) and four hold scenarios — nothing held; a held C-major triad with OCTAVES KEEP; the same with
//  OCTAVES IGNORE; the triad held for 8 bars then released (ROOT latches its transpose) — hashing every message in emission order (sample, cable, status+channel, note, velocity). With FREEZE 0, SUSTAIN off and SLIP 0 (every
//  factory document: none sets any) the stream must stay bit-identical after the ferry: a changed hash here is a bug, not a re-baseline. CAPTURED on origin/main 4cb3c12, before the ferry.

import XCTest

private final class InputsGoldenEmitter: MIDIEmitter {
    var h: UInt64 = 0xcbf29ce484222325
    var events = 0, ons = 0
    private func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        mix(UInt64(bitPattern: sampleTime)); mix(UInt64(cable)); mix(UInt64(b0)); mix(UInt64(b1)); mix(UInt64(b2))
        events += 1
        if b0 & 0xF0 == 0x90 && b2 > 0 { ons += 1 }
    }
}

final class InputsGoldenTests: XCTestCase {
    enum Hold: String, CaseIterable { case none = "nothing held", keep = "held, KEEP", ignore = "held, IGNORE", released = "held 8 bars then released" }

    private func box(for s0: PluginState, mode: MidiMode, octaves: MidiOctaves) -> SnapshotBox {
        var st = s0
        st.euclideousSameNoteGuard = false   // the pre-guard stream, as the other goldens pin
        var plan = st.sourcePlanResolved; plan.midiMode = mode; plan.midiOctaves = octaves; st.euclideousSourcePlan = plan
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        let input = FourfoldCompose.Input(lines: st.euclideousLinesResolved, riff: st.euclideousRiffResolved, riffs: st.riffsResolved,
                                          activeRiff: st.activeRiffResolved, soloMask: st.euclideousSoloMaskResolved,
                                          locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        return SnapshotBuilder.build(from: st)
    }

    private func render(_ s: PluginState, mode: MidiMode, hold: Hold) -> (hash: UInt64, events: Int, ons: Int) {
        let b = box(for: s, mode: mode, octaves: hold == .ignore ? .ignore : .keep)
        let pool = NotePool()
        let notes: [UInt8] = [60, 64, 67]
        if hold != .none { for n in notes { pool.noteOn(n, velocity: 100, channel: 0) } }
        let router = Router(); var diag = KernelDiag(); let e = InputsGoldenEmitter()
        let sr = 48_000.0, tempo = 120.0, frames: UInt32 = 480
        let totalFrames = Int(32 * 4 * 60.0 / tempo * sr)
        var done = 0, beat = 0.0, ts = 0.0, released = false
        while done < totalFrames {
            if hold == .released, !released, beat >= 32 { for n in notes { pool.noteOff(n) }; released = true }
            let n = UInt32(min(Int(frames), totalFrames - done))
            router.process(box: b, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: n, out: e, diag: &diag)
            done += Int(n); beat += Double(n) * tempo / 60.0 / sr; ts += Double(n)
        }
        router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        return (e.h, e.events, e.ons)
    }

    private var documents: [(name: String, make: () -> PluginState)] {
        [("(default)", { PluginState.makeInit() })] + EuclideousPresets.all.map { ($0.name, $0.make) }
    }

    /// "document|scenario|mode" → (hash, events, note-ons).
    private let golden: [String: (UInt64, Int, Int)] = [
        "(default)|nothing held|ADD": (16404598349816740809, 1024, 512),
        "(default)|nothing held|REPLACE": (16404598349816740809, 1024, 512),
        "(default)|nothing held|ROOT": (16404598349816740809, 1024, 512),
        "(default)|held, KEEP|ADD": (5810583246765842761, 1024, 512),
        "(default)|held, KEEP|REPLACE": (15983343368842896601, 1024, 512),
        "(default)|held, KEEP|ROOT": (6221366943037184081, 1024, 512),
        "(default)|held, IGNORE|ADD": (11082826744638529977, 1024, 512),
        "(default)|held, IGNORE|REPLACE": (16748119929840287353, 1024, 512),
        "(default)|held, IGNORE|ROOT": (6221366943037184081, 1024, 512),
        "(default)|held 8 bars then released|ADD": (9392255904225292261, 1024, 512),
        "(default)|held 8 bars then released|REPLACE": (6802371384323426473, 1024, 512),
        "(default)|held 8 bars then released|ROOT": (6221366943037184081, 1024, 512),
        "STRIDE WALK|nothing held|ADD": (11576466095373199533, 1152, 576),
        "STRIDE WALK|nothing held|REPLACE": (11576466095373199533, 1152, 576),
        "STRIDE WALK|nothing held|ROOT": (11576466095373199533, 1152, 576),
        "STRIDE WALK|held, KEEP|ADD": (4941413961264373045, 1152, 576),
        "STRIDE WALK|held, KEEP|REPLACE": (14068717035436632097, 1152, 576),
        "STRIDE WALK|held, KEEP|ROOT": (4441917779350537765, 1152, 576),
        "STRIDE WALK|held, IGNORE|ADD": (11516998082110839773, 1152, 576),
        "STRIDE WALK|held, IGNORE|REPLACE": (6600280939737731593, 1152, 576),
        "STRIDE WALK|held, IGNORE|ROOT": (4441917779350537765, 1152, 576),
        "STRIDE WALK|held 8 bars then released|ADD": (17793607250531376449, 1152, 576),
        "STRIDE WALK|held 8 bars then released|REPLACE": (16184099701836820961, 1152, 576),
        "STRIDE WALK|held 8 bars then released|ROOT": (4441917779350537765, 1152, 576),
        "MIRROR WALK|nothing held|ADD": (5604410597497768781, 1536, 768),
        "MIRROR WALK|nothing held|REPLACE": (5604410597497768781, 1536, 768),
        "MIRROR WALK|nothing held|ROOT": (5604410597497768781, 1536, 768),
        "MIRROR WALK|held, KEEP|ADD": (17587072312325070501, 1536, 768),
        "MIRROR WALK|held, KEEP|REPLACE": (13158369797340424205, 1536, 768),
        "MIRROR WALK|held, KEEP|ROOT": (8994713573969960477, 1536, 768),
        "MIRROR WALK|held, IGNORE|ADD": (11960801664390986213, 1536, 768),
        "MIRROR WALK|held, IGNORE|REPLACE": (18117511525684215533, 1536, 768),
        "MIRROR WALK|held, IGNORE|ROOT": (8994713573969960477, 1536, 768),
        "MIRROR WALK|held 8 bars then released|ADD": (11991529511985280041, 1536, 768),
        "MIRROR WALK|held 8 bars then released|REPLACE": (9295959681481210541, 1536, 768),
        "MIRROR WALK|held 8 bars then released|ROOT": (8994713573969960477, 1536, 768),
        "PENDULUM|nothing held|ADD": (10529798635770861077, 1024, 512),
        "PENDULUM|nothing held|REPLACE": (10529798635770861077, 1024, 512),
        "PENDULUM|nothing held|ROOT": (10529798635770861077, 1024, 512),
        "PENDULUM|held, KEEP|ADD": (5674093713025947149, 1024, 512),
        "PENDULUM|held, KEEP|REPLACE": (8020251982411740629, 1024, 512),
        "PENDULUM|held, KEEP|ROOT": (9044714189069637909, 1024, 512),
        "PENDULUM|held, IGNORE|ADD": (12397885214145526893, 1024, 512),
        "PENDULUM|held, IGNORE|REPLACE": (12687123247921683981, 1024, 512),
        "PENDULUM|held, IGNORE|ROOT": (9044714189069637909, 1024, 512),
        "PENDULUM|held 8 bars then released|ADD": (1584925176078619929, 1024, 512),
        "PENDULUM|held 8 bars then released|REPLACE": (8579005937616274381, 1024, 512),
        "PENDULUM|held 8 bars then released|ROOT": (9044714189069637909, 1024, 512),
        "PING-PONG LEAD|nothing held|ADD": (758997673563978889, 1568, 784),
        "PING-PONG LEAD|nothing held|REPLACE": (758997673563978889, 1568, 784),
        "PING-PONG LEAD|nothing held|ROOT": (758997673563978889, 1568, 784),
        "PING-PONG LEAD|held, KEEP|ADD": (6487574056831416737, 1568, 784),
        "PING-PONG LEAD|held, KEEP|REPLACE": (12696224362306960897, 1568, 784),
        "PING-PONG LEAD|held, KEEP|ROOT": (3293883928417968929, 1568, 784),
        "PING-PONG LEAD|held, IGNORE|ADD": (11217967545932307193, 1568, 784),
        "PING-PONG LEAD|held, IGNORE|REPLACE": (5930016834164314081, 1568, 784),
        "PING-PONG LEAD|held, IGNORE|ROOT": (3293883928417968929, 1568, 784),
        "PING-PONG LEAD|held 8 bars then released|ADD": (9083613011939681541, 1568, 784),
        "PING-PONG LEAD|held 8 bars then released|REPLACE": (18103491545399970169, 1568, 784),
        "PING-PONG LEAD|held 8 bars then released|ROOT": (3293883928417968929, 1568, 784),
        "DRUNKEN WALK|nothing held|ADD": (8330349297940242505, 1152, 576),
        "DRUNKEN WALK|nothing held|REPLACE": (8330349297940242505, 1152, 576),
        "DRUNKEN WALK|nothing held|ROOT": (8330349297940242505, 1152, 576),
        "DRUNKEN WALK|held, KEEP|ADD": (6391371830639514825, 1152, 576),
        "DRUNKEN WALK|held, KEEP|REPLACE": (10261827498002298217, 1152, 576),
        "DRUNKEN WALK|held, KEEP|ROOT": (17418392200043753297, 1152, 576),
        "DRUNKEN WALK|held, IGNORE|ADD": (16883936945065655057, 1152, 576),
        "DRUNKEN WALK|held, IGNORE|REPLACE": (5100692423759945233, 1152, 576),
        "DRUNKEN WALK|held, IGNORE|ROOT": (17418392200043753297, 1152, 576),
        "DRUNKEN WALK|held 8 bars then released|ADD": (4715871527168190673, 1152, 576),
        "DRUNKEN WALK|held 8 bars then released|REPLACE": (18280776037246676101, 1152, 576),
        "DRUNKEN WALK|held 8 bars then released|ROOT": (17418392200043753297, 1152, 576),
        "RANDOM GARDEN|nothing held|ADD": (18207121117227069245, 1792, 896),
        "RANDOM GARDEN|nothing held|REPLACE": (18207121117227069245, 1792, 896),
        "RANDOM GARDEN|nothing held|ROOT": (18207121117227069245, 1792, 896),
        "RANDOM GARDEN|held, KEEP|ADD": (11094577514255666629, 1792, 896),
        "RANDOM GARDEN|held, KEEP|REPLACE": (12342826140144093285, 1792, 896),
        "RANDOM GARDEN|held, KEEP|ROOT": (9294229652927739493, 1792, 896),
        "RANDOM GARDEN|held, IGNORE|ADD": (9381610299367420853, 1792, 896),
        "RANDOM GARDEN|held, IGNORE|REPLACE": (2982519137411378573, 1792, 896),
        "RANDOM GARDEN|held, IGNORE|ROOT": (9294229652927739493, 1792, 896),
        "RANDOM GARDEN|held 8 bars then released|ADD": (6294834188780149661, 1792, 896),
        "RANDOM GARDEN|held 8 bars then released|REPLACE": (17913346648564150005, 1792, 896),
        "RANDOM GARDEN|held 8 bars then released|ROOT": (9294229652927739493, 1792, 896),
        "OCTAVE COLUMN|nothing held|ADD": (7846656301270683413, 2560, 1280),
        "OCTAVE COLUMN|nothing held|REPLACE": (7846656301270683413, 2560, 1280),
        "OCTAVE COLUMN|nothing held|ROOT": (7846656301270683413, 2560, 1280),
        "OCTAVE COLUMN|held, KEEP|ADD": (12347037978995313477, 2560, 1280),
        "OCTAVE COLUMN|held, KEEP|REPLACE": (6769777248402906085, 2560, 1280),
        "OCTAVE COLUMN|held, KEEP|ROOT": (18388416365316993717, 2560, 1280),
        "OCTAVE COLUMN|held, IGNORE|ADD": (15930347429933749381, 2560, 1280),
        "OCTAVE COLUMN|held, IGNORE|REPLACE": (14428180124853390213, 2560, 1280),
        "OCTAVE COLUMN|held, IGNORE|ROOT": (18388416365316993717, 2560, 1280),
        "OCTAVE COLUMN|held 8 bars then released|ADD": (16016832308269218101, 2560, 1280),
        "OCTAVE COLUMN|held 8 bars then released|REPLACE": (6865522475804212381, 2560, 1280),
        "OCTAVE COLUMN|held 8 bars then released|ROOT": (18388416365316993717, 2560, 1280),
        "KOTEKAN|nothing held|ADD": (8755829686395397057, 2048, 1024),
        "KOTEKAN|nothing held|REPLACE": (8755829686395397057, 2048, 1024),
        "KOTEKAN|nothing held|ROOT": (8755829686395397057, 2048, 1024),
        "KOTEKAN|held, KEEP|ADD": (8393456998199786213, 2048, 1024),
        "KOTEKAN|held, KEEP|REPLACE": (2421890415842952413, 2048, 1024),
        "KOTEKAN|held, KEEP|ROOT": (1260032528825652361, 2048, 1024),
        "KOTEKAN|held, IGNORE|ADD": (9405004605598341269, 2048, 1024),
        "KOTEKAN|held, IGNORE|REPLACE": (1790352134267675853, 2048, 1024),
        "KOTEKAN|held, IGNORE|ROOT": (1260032528825652361, 2048, 1024),
        "KOTEKAN|held 8 bars then released|ADD": (15502938904509043557, 2048, 1024),
        "KOTEKAN|held 8 bars then released|REPLACE": (11625557927259965433, 2048, 1024),
        "KOTEKAN|held 8 bars then released|ROOT": (1260032528825652361, 2048, 1024),
        "FIVE AGAINST EIGHT|nothing held|ADD": (1501553662223737, 1256, 628),
        "FIVE AGAINST EIGHT|nothing held|REPLACE": (1501553662223737, 1256, 628),
        "FIVE AGAINST EIGHT|nothing held|ROOT": (1501553662223737, 1256, 628),
        "FIVE AGAINST EIGHT|held, KEEP|ADD": (3298886382283204093, 1256, 628),
        "FIVE AGAINST EIGHT|held, KEEP|REPLACE": (12503759102118858981, 1256, 628),
        "FIVE AGAINST EIGHT|held, KEEP|ROOT": (11089173778542677497, 1256, 628),
        "FIVE AGAINST EIGHT|held, IGNORE|ADD": (16204396746316020549, 1256, 628),
        "FIVE AGAINST EIGHT|held, IGNORE|REPLACE": (6382180196684074701, 1256, 628),
        "FIVE AGAINST EIGHT|held, IGNORE|ROOT": (11089173778542677497, 1256, 628),
        "FIVE AGAINST EIGHT|held 8 bars then released|ADD": (4874875221246619709, 1256, 628),
        "FIVE AGAINST EIGHT|held 8 bars then released|REPLACE": (10970376711023693353, 1256, 628),
        "FIVE AGAINST EIGHT|held 8 bars then released|ROOT": (11089173778542677497, 1256, 628),
        "MIRRORED PITCH|nothing held|ADD": (3030724652048653613, 896, 448),
        "MIRRORED PITCH|nothing held|REPLACE": (3030724652048653613, 896, 448),
        "MIRRORED PITCH|nothing held|ROOT": (3030724652048653613, 896, 448),
        "MIRRORED PITCH|held, KEEP|ADD": (7917750127668525037, 896, 448),
        "MIRRORED PITCH|held, KEEP|REPLACE": (7566938529909331765, 896, 448),
        "MIRRORED PITCH|held, KEEP|ROOT": (2582076381420392293, 896, 448),
        "MIRRORED PITCH|held, IGNORE|ADD": (18178422623269302149, 896, 448),
        "MIRRORED PITCH|held, IGNORE|REPLACE": (12469089933315515309, 896, 448),
        "MIRRORED PITCH|held, IGNORE|ROOT": (2582076381420392293, 896, 448),
        "MIRRORED PITCH|held 8 bars then released|ADD": (16877921381234578105, 896, 448),
        "MIRRORED PITCH|held 8 bars then released|REPLACE": (1385538583007587845, 896, 448),
        "MIRRORED PITCH|held 8 bars then released|ROOT": (2582076381420392293, 896, 448),
        "FIFTH ABOVE|nothing held|ADD": (812048237271447365, 1280, 640),
        "FIFTH ABOVE|nothing held|REPLACE": (812048237271447365, 1280, 640),
        "FIFTH ABOVE|nothing held|ROOT": (812048237271447365, 1280, 640),
        "FIFTH ABOVE|held, KEEP|ADD": (5731262618919878237, 1280, 640),
        "FIFTH ABOVE|held, KEEP|REPLACE": (12738365326988901421, 1280, 640),
        "FIFTH ABOVE|held, KEEP|ROOT": (16810169741683976645, 1280, 640),
        "FIFTH ABOVE|held, IGNORE|ADD": (4213685949487173805, 1280, 640),
        "FIFTH ABOVE|held, IGNORE|REPLACE": (7666204918899910941, 1280, 640),
        "FIFTH ABOVE|held, IGNORE|ROOT": (16810169741683976645, 1280, 640),
        "FIFTH ABOVE|held 8 bars then released|ADD": (9327724512057076325, 1280, 640),
        "FIFTH ABOVE|held 8 bars then released|REPLACE": (11077853640862552509, 1280, 640),
        "FIFTH ABOVE|held 8 bars then released|ROOT": (16810169741683976645, 1280, 640),
        "HELD BREATH|nothing held|ADD": (2523232541607937989, 80, 40),
        "HELD BREATH|nothing held|REPLACE": (2523232541607937989, 80, 40),
        "HELD BREATH|nothing held|ROOT": (2523232541607937989, 80, 40),
        "HELD BREATH|held, KEEP|ADD": (17853329910382017621, 80, 40),
        "HELD BREATH|held, KEEP|REPLACE": (4572657998734499541, 80, 40),
        "HELD BREATH|held, KEEP|ROOT": (7242857819671873269, 80, 40),
        "HELD BREATH|held, IGNORE|ADD": (379066240528510789, 80, 40),
        "HELD BREATH|held, IGNORE|REPLACE": (6789521321350425773, 80, 40),
        "HELD BREATH|held, IGNORE|ROOT": (7242857819671873269, 80, 40),
        "HELD BREATH|held 8 bars then released|ADD": (13915065885287985881, 80, 40),
        "HELD BREATH|held 8 bars then released|REPLACE": (15731169026487947029, 80, 40),
        "HELD BREATH|held 8 bars then released|ROOT": (7242857819671873269, 80, 40),
        "STUTTER FILL|nothing held|ADD": (13383790700140715913, 3600, 1800),
        "STUTTER FILL|nothing held|REPLACE": (13383790700140715913, 3600, 1800),
        "STUTTER FILL|nothing held|ROOT": (13383790700140715913, 3600, 1800),
        "STUTTER FILL|held, KEEP|ADD": (17684813643519563649, 3600, 1800),
        "STUTTER FILL|held, KEEP|REPLACE": (523586668478314457, 3600, 1800),
        "STUTTER FILL|held, KEEP|ROOT": (374574512578920297, 3600, 1800),
        "STUTTER FILL|held, IGNORE|ADD": (15145355356662016489, 3600, 1800),
        "STUTTER FILL|held, IGNORE|REPLACE": (11981907502296059385, 3600, 1800),
        "STUTTER FILL|held, IGNORE|ROOT": (374574512578920297, 3600, 1800),
        "STUTTER FILL|held 8 bars then released|ADD": (7167484233557569861, 3600, 1800),
        "STUTTER FILL|held 8 bars then released|REPLACE": (8274925178761040409, 3600, 1800),
        "STUTTER FILL|held 8 bars then released|ROOT": (374574512578920297, 3600, 1800),
        "CALL AND HOLD|nothing held|ADD": (3852253280451818553, 832, 416),
        "CALL AND HOLD|nothing held|REPLACE": (3852253280451818553, 832, 416),
        "CALL AND HOLD|nothing held|ROOT": (3852253280451818553, 832, 416),
        "CALL AND HOLD|held, KEEP|ADD": (2252889707138412593, 832, 416),
        "CALL AND HOLD|held, KEEP|REPLACE": (16165081954205294157, 832, 416),
        "CALL AND HOLD|held, KEEP|ROOT": (17555706486785587801, 832, 416),
        "CALL AND HOLD|held, IGNORE|ADD": (16763723208853211385, 832, 416),
        "CALL AND HOLD|held, IGNORE|REPLACE": (16567925041646232733, 832, 416),
        "CALL AND HOLD|held, IGNORE|ROOT": (17555706486785587801, 832, 416),
        "CALL AND HOLD|held 8 bars then released|ADD": (16750641322791111181, 832, 416),
        "CALL AND HOLD|held 8 bars then released|REPLACE": (14415026626584526105, 832, 416),
        "CALL AND HOLD|held 8 bars then released|ROOT": (17555706486785587801, 832, 416),
        "LONG TAIL|nothing held|ADD": (15397211412526389809, 304, 152),
        "LONG TAIL|nothing held|REPLACE": (15397211412526389809, 304, 152),
        "LONG TAIL|nothing held|ROOT": (15397211412526389809, 304, 152),
        "LONG TAIL|held, KEEP|ADD": (7091941721064415841, 304, 152),
        "LONG TAIL|held, KEEP|REPLACE": (4881535593276605481, 304, 152),
        "LONG TAIL|held, KEEP|ROOT": (7244399527141206937, 304, 152),
        "LONG TAIL|held, IGNORE|ADD": (2194780965172661225, 304, 152),
        "LONG TAIL|held, IGNORE|REPLACE": (13730193298932824753, 304, 152),
        "LONG TAIL|held, IGNORE|ROOT": (7244399527141206937, 304, 152),
        "LONG TAIL|held 8 bars then released|ADD": (1641381361278425693, 304, 152),
        "LONG TAIL|held 8 bars then released|REPLACE": (8743251090389286913, 304, 152),
        "LONG TAIL|held 8 bars then released|ROOT": (7244399527141206937, 304, 152),
        "GAPPED GROOVE|nothing held|ADD": (9714295268515749101, 1024, 512),
        "GAPPED GROOVE|nothing held|REPLACE": (9714295268515749101, 1024, 512),
        "GAPPED GROOVE|nothing held|ROOT": (9714295268515749101, 1024, 512),
        "GAPPED GROOVE|held, KEEP|ADD": (10068800245553378065, 1024, 512),
        "GAPPED GROOVE|held, KEEP|REPLACE": (3056252480858566913, 1024, 512),
        "GAPPED GROOVE|held, KEEP|ROOT": (2697308471156419485, 1024, 512),
        "GAPPED GROOVE|held, IGNORE|ADD": (2563228799392324729, 1024, 512),
        "GAPPED GROOVE|held, IGNORE|REPLACE": (7859392982972453001, 1024, 512),
        "GAPPED GROOVE|held, IGNORE|ROOT": (2697308471156419485, 1024, 512),
        "GAPPED GROOVE|held 8 bars then released|ADD": (14641362741814656737, 1024, 512),
        "GAPPED GROOVE|held 8 bars then released|REPLACE": (15757602013443340773, 1024, 512),
        "GAPPED GROOVE|held 8 bars then released|ROOT": (2697308471156419485, 1024, 512),
        "EARLY BLOOM|nothing held|ADD": (3922373848500958037, 528, 264),
        "EARLY BLOOM|nothing held|REPLACE": (3922373848500958037, 528, 264),
        "EARLY BLOOM|nothing held|ROOT": (3922373848500958037, 528, 264),
        "EARLY BLOOM|held, KEEP|ADD": (14706456658884921181, 528, 264),
        "EARLY BLOOM|held, KEEP|REPLACE": (3888355358112475525, 528, 264),
        "EARLY BLOOM|held, KEEP|ROOT": (3888355358112475525, 528, 264),
        "EARLY BLOOM|held, IGNORE|ADD": (4648910603937301997, 528, 264),
        "EARLY BLOOM|held, IGNORE|REPLACE": (3922373848500958037, 528, 264),
        "EARLY BLOOM|held, IGNORE|ROOT": (3888355358112475525, 528, 264),
        "EARLY BLOOM|held 8 bars then released|ADD": (1104026633035170321, 528, 264),
        "EARLY BLOOM|held 8 bars then released|REPLACE": (17860874043522462197, 528, 264),
        "EARLY BLOOM|held 8 bars then released|ROOT": (3888355358112475525, 528, 264),
        "SCALE WALK|nothing held|ADD": (1312682223219900669, 1280, 640),
        "SCALE WALK|nothing held|REPLACE": (1312682223219900669, 1280, 640),
        "SCALE WALK|nothing held|ROOT": (1312682223219900669, 1280, 640),
        "SCALE WALK|held, KEEP|ADD": (18257920096646117325, 1280, 640),
        "SCALE WALK|held, KEEP|REPLACE": (10573582639704638277, 1280, 640),
        "SCALE WALK|held, KEEP|ROOT": (52334885296996509, 1280, 640),
        "SCALE WALK|held, IGNORE|ADD": (7277372902646693677, 1280, 640),
        "SCALE WALK|held, IGNORE|REPLACE": (14293917071213324565, 1280, 640),
        "SCALE WALK|held, IGNORE|ROOT": (52334885296996509, 1280, 640),
        "SCALE WALK|held 8 bars then released|ADD": (14229986431764291013, 1280, 640),
        "SCALE WALK|held 8 bars then released|REPLACE": (6438251162167254737, 1280, 640),
        "SCALE WALK|held 8 bars then released|ROOT": (52334885296996509, 1280, 640),
        "ARPEGGIO LADDER|nothing held|ADD": (2493566053396262733, 4096, 2048),
        "ARPEGGIO LADDER|nothing held|REPLACE": (2493566053396262733, 4096, 2048),
        "ARPEGGIO LADDER|nothing held|ROOT": (2493566053396262733, 4096, 2048),
        "ARPEGGIO LADDER|held, KEEP|ADD": (15028064168758528653, 4096, 2048),
        "ARPEGGIO LADDER|held, KEEP|REPLACE": (14161141563817245309, 4096, 2048),
        "ARPEGGIO LADDER|held, KEEP|ROOT": (18409386287962157869, 4096, 2048),
        "ARPEGGIO LADDER|held, IGNORE|ADD": (18272513027641811421, 4096, 2048),
        "ARPEGGIO LADDER|held, IGNORE|REPLACE": (17836275723183535389, 4096, 2048),
        "ARPEGGIO LADDER|held, IGNORE|ROOT": (18409386287962157869, 4096, 2048),
        "ARPEGGIO LADDER|held 8 bars then released|ADD": (6737327559451707885, 4096, 2048),
        "ARPEGGIO LADDER|held 8 bars then released|REPLACE": (11952300665447933981, 4096, 2048),
        "ARPEGGIO LADDER|held 8 bars then released|ROOT": (18409386287962157869, 4096, 2048),
        "BACKWARDS GLANCE|nothing held|ADD": (2910552856854418121, 1280, 640),
        "BACKWARDS GLANCE|nothing held|REPLACE": (2910552856854418121, 1280, 640),
        "BACKWARDS GLANCE|nothing held|ROOT": (2910552856854418121, 1280, 640),
        "BACKWARDS GLANCE|held, KEEP|ADD": (8021304670992595901, 1280, 640),
        "BACKWARDS GLANCE|held, KEEP|REPLACE": (8770494353823325553, 1280, 640),
        "BACKWARDS GLANCE|held, KEEP|ROOT": (18152707640009668577, 1280, 640),
        "BACKWARDS GLANCE|held, IGNORE|ADD": (2125269849170269549, 1280, 640),
        "BACKWARDS GLANCE|held, IGNORE|REPLACE": (17601088838063598953, 1280, 640),
        "BACKWARDS GLANCE|held, IGNORE|ROOT": (18152707640009668577, 1280, 640),
        "BACKWARDS GLANCE|held 8 bars then released|ADD": (1683130929852879293, 1280, 640),
        "BACKWARDS GLANCE|held 8 bars then released|REPLACE": (6507532437435586145, 1280, 640),
        "BACKWARDS GLANCE|held 8 bars then released|ROOT": (18152707640009668577, 1280, 640),
    ]

    func testEveryDocumentRendersTheSameStreamUnderEveryModeAndHold() {
        XCTAssertEqual(EuclideousPresets.all.count, 20)
        for (name, make) in documents {
            for hold in Hold.allCases {
                for mode in MidiMode.allCases {
                    let key = "\(name)|\(hold.rawValue)|\(mode.rawValue)"
                    // the document as the app now opens it (lanes carry their own sources, the four switches read true)…
                    var migrated = make(); migrated.migrateLegacyRoutingIfNeeded(); migrated.normalizeSourcesAtLoad()
                    let got = render(migrated, mode: mode, hold: hold)
                    guard let want = golden[key] else { XCTFail("CAPTURE \"\(key)\": (\(got.hash), \(got.events), \(got.ons)),"); continue }
                    XCTAssertEqual(got.events, want.1, "\(key): message count")
                    XCTAssertEqual(got.ons, want.2, "\(key): note-on count")
                    XCTAssertEqual(got.hash, want.0, "\(key): the message stream must be bit-identical (FREEZE 0, SUSTAIN off, SLIP 0)")
                    // …and the un-migrated one (a path that never normalised: the engine still ANDs the switches), on the held KEEP scenario
                    if hold == .keep {
                        let raw = render(make(), mode: mode, hold: hold)
                        XCTAssertEqual(raw.hash, want.0, "\(key): the un-migrated document plays the same")
                    }
                }
            }
        }
    }
}
