#!/usr/bin/env python3
"""alloc-sites.py <alloc.txt> <dSYM-or-binary> — turn `run.sh --alloc` output into allocation SITES: each STACK line's image offsets are resolved with `atos` (inlined frames included) to file:line, and the report lists, per source line, how many of the
logged stacks allocated there. (The harness logs the first 512 stacks of each document, so the counts are a sample; the exact totals are on the `allocations=` lines.)"""
import re, subprocess, sys, collections, os
txt, binary = sys.argv[1], sys.argv[2]
rows = []
for l in open(txt):
    m = re.match(r'ALLOC (.*?): STACK x(\d+) size=(\d+) OFFS=([0-9a-f,]*) ', l)
    if m: rows.append((int(m.group(2)), [int(x, 16) for x in m.group(4).split(',') if x]))
if not rows: print('no STACK lines'); sys.exit(0)
env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
base = 0x100000000
def resolve(offs):
    out = subprocess.run(['xcrun', 'atos', '-i', '-arch', 'arm64', '-o', binary, '-l', hex(base)] + [hex(base + o) for o in offs], capture_output=True, text=True, env=env).stdout.split('\n')
    return [x for x in out if x]
sites = collections.Counter(); first = {}
for cnt, offs in rows:
    frames = resolve(offs[:8])
    # the allocating site = the first frame that is in Fourfold's own source (not the Swift stdlib)
    pick = next((f for f in frames if re.search(r'\((Router|Derivations|Kernel|Emission|Snapshot|Models|FourfoldAudioUnit)[A-Za-z]*\.swift:\d+', f)), frames[0] if frames else '?')
    m = re.search(r'([A-Za-z]+\.swift:\d+)', pick); key = m.group(1) if m else pick[:80]
    sites[key] += cnt; first.setdefault(key, re.sub(r' \(in [^)]*\)', '', pick)[:110])
tot = sum(sites.values())
for k, c in sites.most_common(30): print(f'{100*c/tot:5.1f}%  {k:34s} {first[k]}')
