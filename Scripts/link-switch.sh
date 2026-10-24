#!/bin/sh
# Ableton Link on/off for the Fourfold APP (Paul, 2026-10-24: OFF until after release).
#   sh Scripts/link-switch.sh on     fetch LinkKit (checksum-verified, gitignored), un-comment the `#LINK ` lines in project.yml, xcodegen generate
#   sh Scripts/link-switch.sh off    comment them back out, xcodegen generate  (the vendored SDK, if any, stays on disk — it is gitignored)
#   sh Scripts/link-switch.sh        say which it is now
# Only the lines between `# LINK-BEGIN` and `# LINK-END` markers in project.yml are touched. The Swift code is behind `#if FOURFOLD_LINK`, which the `on` lines define.
# Switching on ALSO needs, for a real device: the restricted multicast entitlement approved for the App ID (developer.apple.com), and the device checks in
# Docs/euclideous-device-verification-debt.md. Do not commit project.yml / the .xcodeproj in the `on` state before release.
set -e
cd "$(dirname "$0")/.."
python3 - "$1" <<'PY'
import re, sys
mode = sys.argv[1] if len(sys.argv) > 1 else ''
lines = open('project.yml').read().split('\n')
inside = False; n = 0; active = 0
for i, l in enumerate(lines):
    if '# LINK-BEGIN' in l: inside = True; continue
    if '# LINK-END' in l: inside = False; continue
    if not inside or not l.strip(): continue
    if mode == 'on' and re.match(r'^\s*#LINK ', l): lines[i] = re.sub(r'#LINK ', '', l, count=1); n += 1
    elif mode == 'off' and not re.match(r'^\s*#LINK ', l): lines[i] = '#LINK ' + l; n += 1   # the marker goes at column 0, the line keeps its own indentation: on = strip the marker
    if not re.match(r'^\s*#LINK ', lines[i]): active += 1
if mode in ('on', 'off'):
    open('project.yml', 'w').write('\n'.join(lines)); print('link-switch: %d line(s) changed' % n)
else:
    print('Ableton Link is', 'ON' if active else 'OFF', 'in project.yml')
PY
[ "$1" = on ] && sh Scripts/fetch-linkkit.sh
[ "$1" = on ] || [ "$1" = off ] && { xcodegen generate >/dev/null && echo "link-switch: xcodegen generated the project (Link $1)"; }
exit 0
