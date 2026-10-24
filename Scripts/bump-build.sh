#!/bin/sh
# Raise the BUILD number for a TestFlight / App Store upload. The app and its embedded AU extension read the same CURRENT_PROJECT_VERSION (project.yml, the FourfoldEngine template), so they can never disagree;
# App Store Connect refuses an upload whose build number is not higher than the last one for that version.
#   sh Scripts/bump-build.sh         raise it by one
#   sh Scripts/bump-build.sh 12      set it to 12
#   sh Scripts/bump-build.sh show    print MARKETING_VERSION (the user-visible 0.1.0) and the build number
# The user-visible version (MARKETING_VERSION) is edited by hand in the same place when a release deserves a new one.
set -e
cd "$(dirname "$0")/.."
python3 - "$1" <<'PY'
import re, sys
arg = sys.argv[1] if len(sys.argv) > 1 else ''
s = open('project.yml').read()
m = re.search(r'CURRENT_PROJECT_VERSION: "(\d+)"', s); v = re.search(r'MARKETING_VERSION: "([^"]+)"', s)
if not m or not v: sys.exit('bump-build: CURRENT_PROJECT_VERSION / MARKETING_VERSION not found in project.yml')
if arg == 'show': print('version %s, build %s' % (v.group(1), m.group(1))); sys.exit()
new = int(arg) if arg.isdigit() else int(m.group(1)) + 1
open('project.yml', 'w').write(s.replace(m.group(0), 'CURRENT_PROJECT_VERSION: "%d"' % new, 1))
print('bump-build: version %s, build %s -> %d' % (v.group(1), m.group(1), new))
PY
if [ "$1" != show ]; then xcodegen generate > /dev/null && echo "bump-build: project regenerated"; fi
