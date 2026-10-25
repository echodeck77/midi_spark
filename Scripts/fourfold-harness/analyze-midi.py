#!/usr/bin/env python3
# FOURFOLD soak — retrospective "listen" (2026-10-25). Reads the standard MIDI file the soak captured (the All
# output's own note stream, Scripts/fourfold-harness/soak.sh) and reports anomaly metrics — the open-ended
# "look out for unexpected behaviour" pass the live stuck-note checker can't do. The soak feeds RANDOM input, so
# there is no "correct" reference to diff against: this flags OUTLIERS (zero-length / stuck-long notes, polyphony
# floods, density spikes, orphan events, velocity/channel oddities), not exact correctness. stdlib only.
#
#   python3 Scripts/fourfold-harness/analyze-midi.py build/fourfold-harness/soak-session.mid
import sys, struct
from collections import Counter, defaultdict

# Thresholds for the ⚠ flags — tuned to "obviously wrong for this app", not hair-triggers. The soak's own tempo
# roams 60–200 BPM and patterns reach 16 steps, so a legitimately long HOLD note can run a few seconds.
ZERO_MS = 5.0              # a note shorter than this is effectively zero-length
STUCK_MS = 12_000.0        # longer than this is suspiciously long for any pattern note
FLOOD_POLYPHONY = 40       # more keys on at once than any musical use of 4 lanes + MIDI-in chords should reach
DENSITY_PER_S = 400        # note-ons in a 1 s window above this reads as a runaway, not music


def read_vlq(b, p):
    v = 0
    while True:
        c = b[p]; p += 1
        v = (v << 7) | (c & 0x7F)
        if not (c & 0x80):
            return v, p


def parse_smf(path):
    with open(path, "rb") as f:
        b = f.read()
    if b[0:4] != b"MThd":
        raise SystemExit("not a MIDI file (no MThd)")
    hdr_len = struct.unpack(">I", b[4:8])[0]   # the MThd chunk length (6), which the format/ntrk/div follow
    fmt, ntrk, div = struct.unpack(">HHH", b[8:14])
    ppq = div if div < 0x8000 else 480
    p = 8 + hdr_len   # first byte after the header chunk = the first MTrk
    us_per_quarter = 500_000  # default 120 BPM; updated by a tempo meta
    events = []  # (seconds, status, d1, d2)
    while p < len(b):
        if b[p:p+4] != b"MTrk":
            break
        length = struct.unpack(">I", b[p+4:p+8])[0]
        p += 8
        end = p + length
        tick = 0
        running = None
        sec = 0.0
        tick_at_last_tempo = 0
        sec_at_last_tempo = 0.0
        while p < end:
            dt, p = read_vlq(b, p)
            tick += dt
            sec = sec_at_last_tempo + (tick - tick_at_last_tempo) / ppq * (us_per_quarter / 1_000_000.0)
            status = b[p]
            if status & 0x80:
                p += 1
                running = status
            else:
                status = running
            kind = status & 0xF0
            if status == 0xFF:  # meta
                meta = b[p]; p += 1
                mlen, p = read_vlq(b, p)
                if meta == 0x51 and mlen == 3:  # tempo
                    us_per_quarter = (b[p] << 16) | (b[p+1] << 8) | b[p+2]
                    tick_at_last_tempo = tick; sec_at_last_tempo = sec
                p += mlen
            elif status in (0xF0, 0xF7):  # sysex
                slen, p = read_vlq(b, p); p += slen
            else:
                dlen = 1 if kind in (0xC0, 0xD0) else 2
                d1 = b[p]; d2 = b[p+1] if dlen == 2 else 0
                p += dlen
                events.append((sec, status, d1, d2))
        p = end
    return events


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "build/fourfold-harness/soak-session.mid"
    events = parse_smf(path)
    notes_on = [e for e in events if (e[1] & 0xF0) == 0x90 and e[3] > 0]
    notes_off = [e for e in events if (e[1] & 0xF0) == 0x80 or ((e[1] & 0xF0) == 0x90 and e[3] == 0)]

    print(f"== analyze-midi: {path} ==")
    if not events:
        print("(empty)"); return
    span = max(e[0] for e in events)
    print(f"events={len(events)}  note-ons={len(notes_on)}  note-offs={len(notes_off)}  span={span:.1f}s")

    # ONE chronological sweep: pair ons→offs per (channel, note) for durations, track live polyphony, and — crucially —
    # honour All-Notes-Off (CC 123) / All-Sound-Off (CC 120), which close every key on a channel exactly as a real synth
    # (and the live soak checker) do. Without this, a note closed by an all-notes-off looks like it never ended, and FIFO
    # pairing invents absurd multi-minute "notes" — the first version of this script did exactly that.
    active = defaultdict(list)   # (chan, note) -> list of on-times still sounding
    durations = []
    orphan_off = 0
    poly = 0; peak = 0; peak_at = 0.0
    silence = 0.0; silence_from = 0.0; last_empty = 0.0
    for sec, st, d1, d2 in events:
        kind = st & 0xF0
        ch = st & 0x0F
        if kind == 0x90 and d2 > 0:
            if poly == 0 and sec - last_empty > silence: silence = sec - last_empty; silence_from = last_empty
            active[(ch, d1)].append(sec); poly += 1
            if poly > peak: peak = poly; peak_at = sec
        elif kind == 0x80 or (kind == 0x90 and d2 == 0):
            if active[(ch, d1)]:
                durations.append(sec - active[(ch, d1)].pop(0)); poly -= 1
                if poly == 0: last_empty = sec
            else:
                orphan_off += 1
        elif kind == 0xB0 and d1 in (120, 123):   # all-sound-off / all-notes-off: close every key on this channel
            for key in list(active.keys()):
                if key[0] == ch:
                    for on_t in active[key]: durations.append(sec - on_t); poly -= 1
                    active[key] = []
            if poly <= 0:
                poly = 0; last_empty = sec
    orphan_on = sum(len(v) for v in active.values())

    flags = []
    if durations:
        durations.sort()
        ms = [d * 1000 for d in durations]
        med = ms[len(ms)//2]
        zero = sum(1 for d in ms if d < ZERO_MS)
        stuck = sum(1 for d in ms if d > STUCK_MS)
        print(f"note-length ms: min={ms[0]:.0f} median={med:.0f} max={ms[-1]:.0f}  (zero<{ZERO_MS:.0f}ms={zero}, long>{STUCK_MS/1000:.0f}s={stuck})")
        if zero: flags.append(f"{zero} zero-length note(s) (<{ZERO_MS:.0f}ms) — a hit producing no audible note")
        if stuck: flags.append(f"{stuck} note(s) longer than {STUCK_MS/1000:.0f}s — possible stuck/forgotten note")
    print(f"orphans: note-ons still sounding at the capture's end={orphan_on}  note-offs with no on={orphan_off}  (offs: belt-and-suspenders closes are benign; a handful of ends-still-sounding is just the capture window cutting off)")
    if orphan_on > 8: flags.append(f"{orphan_on} note-on(s) still sounding at the end — more than the capture-window tail should leave; worth a look")

    print(f"peak polyphony={peak} keys at once (at {peak_at:.1f}s)")
    if peak > FLOOD_POLYPHONY: flags.append(f"peak polyphony {peak} > {FLOOD_POLYPHONY} — a note flood, not musical")

    # density: note-ons per 1s window
    per_s = Counter(int(e[0]) for e in notes_on)
    if per_s:
        busiest_s, busiest_n = max(per_s.items(), key=lambda kv: kv[1])
        print(f"busiest second: {busiest_n} note-ons at t={busiest_s}s  (mean {len(notes_on)/max(1,span):.0f}/s)")
        if busiest_n > DENSITY_PER_S: flags.append(f"{busiest_n} note-ons in one second (t={busiest_s}s) > {DENSITY_PER_S} — a density spike")

    print(f"longest silence={silence:.1f}s (from {silence_from:.1f}s)")

    # velocity + channel spread
    vels = [e[3] for e in notes_on]
    if vels:
        print(f"velocity: min={min(vels)} max={max(vels)} mean={sum(vels)/len(vels):.0f}")
    chans = Counter(e[1] & 0x0F for e in notes_on)
    print("note-ons per channel: " + " ".join(f"ch{c+1}={n}" for c, n in sorted(chans.items())))

    print("")
    if flags:
        print("⚠ FLAGS:")
        for fl in flags: print(f"  - {fl}")
    else:
        print("✓ no anomalies flagged (within the thresholds above)")


if __name__ == "__main__":
    main()
