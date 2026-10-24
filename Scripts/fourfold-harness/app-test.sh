#!/bin/bash
# FOURFOLD standalone-app test in the iOS simulator — builds the REAL Fourfold app, launches it playing (--autoplay) with its MIDI self-test (--midi-selftest), and prints what the self-test saw:
# notes out per virtual source (All, Out A…D) with their host-time lead, and a note sent into "Fourfold In" reaching the engine. (The simulator's CoreMIDI does not reach macOS, so the app listens to itself.)
#   sh Scripts/fourfold-harness/app-test.sh
set -e
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
OUT="$PWD/build/fourfold-harness"; mkdir -p "$OUT"
UDID=$(xcrun simctl list devices available | grep -m1 "iPad Pro 11-inch" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "no 'iPad Pro 11-inch' simulator found"; exit 1; }
xcodebuild -project MidiSpark.xcodeproj -scheme Fourfold -configuration Debug -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$OUT/appdd" CODE_SIGNING_ALLOWED=NO build > "$OUT/app-build.log" 2>&1 \
  || { grep "error:" "$OUT/app-build.log" | head; echo "BUILD FAILED (see $OUT/app-build.log)"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
sleep 3
APP="$OUT/appdd/Build/Products/Debug-iphonesimulator/Fourfold.app"
xcrun simctl terminate "$UDID" com.outliermidi.Fourfold 2>/dev/null || true
xcrun simctl uninstall "$UDID" com.outliermidi.Fourfold 2>/dev/null || true   # a clean session each run
xcrun simctl install "$UDID" "$APP"
(xcrun simctl launch --console "$UDID" com.outliermidi.Fourfold --autoplay --midi-selftest --midi-selftest-transport > "$OUT/app-console.log" 2>&1 &)
sleep 16
xcrun simctl io "$UDID" screenshot "$OUT/app-shot.png" >/dev/null 2>&1
xcrun simctl terminate "$UDID" com.outliermidi.Fourfold 2>/dev/null || true
grep -a "^SELFTEST" "$OUT/app-console.log" || echo "no SELFTEST lines (see $OUT/app-console.log)"
# SESSION: launch 1 changes the key root and the app's 3 s autosave writes it; launch 2 (same install) must read it back.
xcrun simctl launch --console "$UDID" com.outliermidi.Fourfold --state-test-write > "$OUT/state-write.log" 2>&1 &
sleep 7; xcrun simctl terminate "$UDID" com.outliermidi.Fourfold 2>/dev/null || true; wait 2>/dev/null || true
(xcrun simctl launch --console "$UDID" com.outliermidi.Fourfold --state-test-read > "$OUT/state-read.log" 2>&1 &)
sleep 5; xcrun simctl terminate "$UDID" com.outliermidi.Fourfold 2>/dev/null || true
grep -ah "^SELFTEST STATE" "$OUT/state-write.log" "$OUT/state-read.log" || echo "no STATE lines"
echo "screenshot: $OUT/app-shot.png"
