#!/usr/bin/env python3
"""Stack cost of functions in a DEBUG build of the AU extension (the one Xcode runs on the iPad).

Usage: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Scripts/debug-frame-sizes.py <MidiSparkAU.debug.dylib> '<regex on the DEMANGLED name>'
  e.g. ... '.../Build/Products/Debug-iphoneos/MidiSparkAU.appex/MidiSparkAU.debug.dylib' 'EuclideousPage\\.(rhythm|tabContent|laneCard)'

Prints, largest first: STATIC frame bytes (the prologue's stp/sub sp), DYN = the number of dynamic stack allocations (`mov sp, xN` — each is a temporary whose size is read from type
metadata at run time: an `EuclideousSlider` is ~4 KB, so a closure that holds several costs tens of KB), the function's code size, and its name. The extension's main thread has a 1 MB
stack and the page's eager SwiftUI construction chain nearly fills it in debug (device crash 2026-10-21, `Thread stack size exceeded`): compare a change against the baseline build, and
build any new leaf view in its own function returning `AnyView` (see `EuclideousPage.rhythmUpperZone`).
"""
import re, subprocess, sys

def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    dylib, pat = sys.argv[1], re.compile(sys.argv[2])
    nm = subprocess.run(['xcrun', 'nm', '-n', dylib], capture_output=True, text=True).stdout.split('\n')
    addrs, names = [], []
    for l in nm:
        p = l.split(' ', 2)
        if len(p) == 3 and re.match(r'^[0-9a-f]{16}$', p[0]) and p[1] in 'tT':
            addrs.append(int(p[0], 16)); names.append(p[2])
    dem = subprocess.run(['xcrun', 'swift-demangle', '--simplified'], input='\n'.join(names), capture_output=True, text=True).stdout.split('\n')
    rows = []
    for i, n in enumerate(dem):
        if not pat.search(n):
            continue
        a = addrs[i]; b = addrs[i + 1] if i + 1 < len(addrs) else a + 0x2000
        out = subprocess.run(['xcrun', 'llvm-objdump', '-d', '--no-show-raw-insn', f'--start-address={a:#x}', f'--stop-address={b:#x}', dylib],
                             capture_output=True, text=True).stdout
        size = 0
        for l in out.split('\n')[:60]:
            m = re.search(r'stp\s+x\d+, x\d+, \[sp, #-(0x[0-9a-f]+)\]!', l)
            if m: size += int(m.group(1), 16)
            m = re.search(r'sub\s+sp, sp, #(0x[0-9a-f]+)', l)
            if m: size += int(m.group(1), 16) << (12 if 'lsl #12' in l else 0)
        rows.append((size, len(re.findall(r'mov\s+sp, x\d+', out)), b - a, n[:150]))
    for r in sorted(rows, reverse=True):
        print(*r)

main()
