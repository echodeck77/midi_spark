#!/bin/bash
# FOURFOLD screenshots of the REAL standalone app on every iPad the simulator offers (Scripts/fourfold-harness/screenshots.sh).
# A UI test (Fourfold/UITests) launches the app playing, rotates the iPad through all four orientations and attaches a screenshot of each; this script runs it on every available iPad simulator and exports the pictures to
#   build/screens/<ipad name>/<picture>.png      — then LOOK at them (layout, clipping, legibility). It judges nothing itself.
#   sh Scripts/fourfold-harness/screenshots.sh [name-filter]      e.g.  sh Scripts/fourfold-harness/screenshots.sh mini
set -e
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
OUT="$PWD/build/screens"; rm -rf "$OUT"; mkdir -p "$OUT"
FILTER=${1:-}
xcodebuild build-for-testing -project MidiSpark.xcodeproj -scheme FourfoldUITests -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUT/dd" CODE_SIGNING_ALLOWED=NO > "$OUT/build.log" 2>&1 \
  || { grep "error:" "$OUT/build.log" | head; echo "BUILD FAILED (see $OUT/build.log)"; exit 1; }
xcrun simctl list devices available | grep -i "ipad" | grep -i "$FILTER" | sed -E 's/^ *(.*) \(([0-9A-F-]{36})\) \(.*$/\2|\1/' | while IFS='|' read -r UDID NAME; do
  SLUG=$(echo "$NAME" | tr -c 'A-Za-z0-9\n' '-' | sed 's/-*$//')
  echo "== $NAME"
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
  xcodebuild test-without-building -project MidiSpark.xcodeproj -scheme FourfoldUITests -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$OUT/dd" -only-testing:FourfoldUITests/FourfoldScreenshotTests \
      -resultBundlePath "$OUT/$SLUG.xcresult" CODE_SIGNING_ALLOWED=NO > "$OUT/$SLUG.log" 2>&1 || echo "   tests reported FAILURES on $NAME (see $OUT/$SLUG.log)"
  mkdir -p "$OUT/$SLUG"
  xcrun xcresulttool export attachments --path "$OUT/$SLUG.xcresult" --output-path "$OUT/$SLUG" > /dev/null 2>&1 || echo "   could not export attachments for $NAME"
  python3 - "$OUT/$SLUG" <<'PY'
import json, os, sys, shutil, subprocess
d = sys.argv[1]
try: m = json.load(open(os.path.join(d, 'manifest.json')))
except Exception as e: print('   no manifest', e); sys.exit()
n = 0
for t in m:
    for a in t.get('attachments', []):
        src = os.path.join(d, a['exportedFileName']); name = a.get('suggestedHumanReadableName', a['exportedFileName']).split('_0_')[0]
        ext = os.path.splitext(src)[1] or '.png'
        dst = os.path.join(d, name.replace('/', '-').replace(' ', '-') + ext)
        shutil.copy(src, dst); os.remove(src); n += 1
        # iOS captures the screen in its fixed PORTRAIT frame, so the rotated shots come out sideways: turn them upright
        turn = {'2-landscape-left': '270', '4-landscape-right': '90', '3-portrait-upside-down': '180', '8-back-2-landscape-left': '270', '8-back-4-landscape-right': '90', '8-back-3-portrait-upside-down': '180', '8-back-5-routed-and-off': '270', '8-back-6-flipped-back': '270'}.get(name)
        if turn: subprocess.run(['sips', '-r', turn, dst], capture_output=True)
print('  ', n, 'pictures')
PY
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
done
echo "pictures in $OUT/<ipad>/"
