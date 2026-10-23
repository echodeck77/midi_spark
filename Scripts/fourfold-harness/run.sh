#!/bin/bash
# FOURFOLD simulator harness — builds a throwaway host app around the FourfoldAU sources, runs it on an iPad simulator, and prints what the AU sent per MIDI cable.
#   sh Scripts/fourfold-harness/run.sh            # the Fourfold page, ~20 s of emulated host playing, then the console summary + a screenshot
#   sh Scripts/fourfold-harness/run.sh --reel     # the page for 15 s, then the REEL pass browser (screenshot at ~25 s)
# The source list is generated from project.yml's FourfoldAU excludes, so the harness can never drift from the real target. Output: build/fourfold-harness/ (gitignored).
set -e
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
OUT="$PWD/build/fourfold-harness"; mkdir -p "$OUT"
UDID=$(xcrun simctl list devices available | grep -m1 "iPad Pro 11-inch" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "no 'iPad Pro 11-inch' simulator found"; exit 1; }
python3 - "$PWD" "$OUT" <<'PY'
import re, sys
root, out = sys.argv[1], sys.argv[2]
yml = open(root + '/project.yml').read()
excl = re.search(r'FourfoldEngine:.*?excludes: \["Info.plist", (.*?)\]\n', yml, re.S).group(1)
open(out + '/project.yml', 'w').write(f'''name: FFHarness
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    iOS: "16.0"
packages:
  Atomics:
    url: https://github.com/apple/swift-atomics
    from: 1.2.0
settings:
  base:
    SWIFT_VERSION: "5.9"
    TARGETED_DEVICE_FAMILY: "2"
targets:
  FFHarness:
    type: application
    platform: iOS
    sources:
      - path: {root}/AUExtension
        excludes: ["Info.plist", {excl}]
      - path: {root}/Fourfold/Shared
      - path: {root}/Scripts/fourfold-harness/Harness
    dependencies:
      - package: Atomics
        product: Atomics
    info:
      path: {out}/Info.plist
      properties:
        UILaunchScreen: {{}}
        "UISupportedInterfaceOrientations~ipad": [UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight]
        UISupportedInterfaceOrientations: [UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.FFHarness
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) FOURFOLD"
''')
PY
( cd "$OUT" && xcodegen generate >/dev/null && xcodebuild -project FFHarness.xcodeproj -scheme FFHarness -configuration Debug -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$OUT/dd" CODE_SIGNING_ALLOWED=NO build > "$OUT/build.log" 2>&1 ) || { grep "error:" "$OUT/build.log" | head; echo "BUILD FAILED (see $OUT/build.log)"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
sleep 4
APP=$(find "$OUT/dd" -name FFHarness.app -path "*iphonesimulator*" | head -1)
xcrun simctl terminate "$UDID" com.example.FFHarness 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
(xcrun simctl launch --console "$UDID" com.example.FFHarness "$@" > "$OUT/console.log" 2>&1 &)
if [ "$1" = "--reel" ]; then sleep 26; else sleep 20; fi
xcrun simctl io "$UDID" screenshot "$OUT/shot.png" >/dev/null 2>&1
xcrun simctl terminate "$UDID" com.example.FFHarness 2>/dev/null || true
echo "---- last host line (notes the AU sent per cable [All, A, B, C, D]) ----"
grep "^HOST beat" "$OUT/console.log" | tail -1
echo "screenshot: $OUT/shot.png"
