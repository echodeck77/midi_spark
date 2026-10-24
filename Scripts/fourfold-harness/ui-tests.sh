#!/bin/bash
# FOURFOLD UI tests of the REAL standalone app on every iPad the simulator offers (Fourfold/UITests: FourfoldTapTests, FourfoldAccessibilityTests, FourfoldMonkeyTests).
#   sh Scripts/fourfold-harness/ui-tests.sh [ipad-name-filter] [FourfoldUITests/FourfoldTapTests ...]
#   e.g.  sh Scripts/fourfold-harness/ui-tests.sh mini                          all three suites on the iPad mini
#         sh Scripts/fourfold-harness/ui-tests.sh "" FourfoldUITests/FourfoldTapTests     the tap tests on every iPad
# Per iPad: a pass/fail line per test, and every audit report (AUDIT … lines: contrast, missing labels, hit regions, clipped text) printed to build/uitests/<ipad>.audit.txt. Exit 1 if any test failed.
set -e
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
OUT="$PWD/build/uitests"; rm -rf "$OUT"; mkdir -p "$OUT"
FILTER=${1:-}; shift || true
ONLY=""; for t in "$@"; do ONLY="$ONLY -only-testing:$t"; done
[ -n "$ONLY" ] || ONLY="-only-testing:FourfoldUITests/FourfoldTapTests -only-testing:FourfoldUITests/FourfoldAccessibilityTests -only-testing:FourfoldUITests/FourfoldMonkeyTests"
xcodebuild build-for-testing -project MidiSpark.xcodeproj -scheme FourfoldUITests -destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUT/dd" CODE_SIGNING_ALLOWED=NO > "$OUT/build.log" 2>&1 \
  || { grep "error:" "$OUT/build.log" | head; echo "BUILD FAILED (see $OUT/build.log)"; exit 1; }
FAILED=0
xcrun simctl list devices available | grep -i "ipad" | grep -i "$FILTER" | sed -E 's/^ *(.*) \(([0-9A-F-]{36})\) \(.*$/\2|\1/' | while IFS='|' read -r UDID NAME; do
  SLUG=$(echo "$NAME" | tr -c 'A-Za-z0-9\n' '-' | sed 's/-*$//')
  echo "== $NAME"
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
  xcodebuild test-without-building -project MidiSpark.xcodeproj -scheme FourfoldUITests -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$OUT/dd" $ONLY \
      -resultBundlePath "$OUT/$SLUG.xcresult" CODE_SIGNING_ALLOWED=NO > "$OUT/$SLUG.log" 2>&1 || echo "   FAILURES on $NAME (details: $OUT/$SLUG.log)"
  grep -E "^Test Case .* (passed|failed)" "$OUT/$SLUG.log" | sed -E "s/Test Case '-\[FourfoldUITests\.([A-Za-z]+) ([A-Za-z0-9_]+)\]' (passed|failed) \(([0-9.]+) seconds\)\./   \3  \1.\2 (\4 s)/"
  grep -E "error: " "$OUT/$SLUG.log" | sed -E 's/^.*FourfoldUITests\.//' | sort -u | head -12 | cut -c1-230 | sed 's/^/     /'
  mkdir -p "$OUT/$SLUG"
  xcrun xcresulttool export attachments --path "$OUT/$SLUG.xcresult" --output-path "$OUT/$SLUG" > /dev/null 2>&1 || true
  python3 - "$OUT/$SLUG" "$OUT/$SLUG.audit.txt" <<'PY'
import json, os, sys
d, dst = sys.argv[1], sys.argv[2]
try: m = json.load(open(os.path.join(d, 'manifest.json')))
except Exception: sys.exit()
out = []
for t in m:
    for a in t.get('attachments', []):
        name = a.get('suggestedHumanReadableName', '')
        if name.startswith('audit-'):
            try: out.append(open(os.path.join(d, a['exportedFileName'])).read())
            except Exception: pass
if out: open(dst, 'w').write('\n\n'.join(out)); print('   audit reports:', dst, '(%d screens, %d issue lines)' % (len(out), sum(x.count('\n') for x in out) - len(out)))
PY
  xcrun simctl shutdown "$UDID" 2>/dev/null || true
done
