#!/bin/bash
# FOURFOLD soak: a long randomised stress run of the REAL standalone app in the iOS simulator (random MIDI in, PLAY/STOP, tempo, presets, HOLD/LATCH, note source, lane edits, solo, ALL NOTES OFF) that checks for stuck notes at
# every STOP and at the end (see Fourfold/App/FourfoldSoak.swift). Prints the SOAK lines; the last is SOAK RESULT: PASS or FAIL.
#   SANITIZE=thread|address sh Scripts/fourfold-harness/soak.sh 120 7      # the same run under ThreadSanitizer / AddressSanitizer: any report prints as a SANITIZER line and fails the run
#   sh Scripts/fourfold-harness/soak.sh [seconds=300] [seed] [fault-every-N]     e.g.  sh Scripts/fourfold-harness/soak.sh 600 42      (the 3rd argument injects a lost note-off every N: the run MUST then FAIL — a control for the checker itself)
set -e
cd "$(dirname "$0")/../.."
SECS=${1:-300}; SEED=${2:-}
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
OUT="$PWD/build/fourfold-harness"; mkdir -p "$OUT"
UDID=$(xcrun simctl list devices available | grep -m1 "iPad Pro 11-inch" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$UDID" ] || { echo "no 'iPad Pro 11-inch' simulator found"; exit 1; }
SAN=""; DD="$OUT/appdd"
case "${SANITIZE:-}" in thread) SAN="-enableThreadSanitizer YES"; DD="$OUT/appdd-tsan";; address) SAN="-enableAddressSanitizer YES -enableUndefinedBehaviorSanitizer YES"; DD="$OUT/appdd-asan";; "") ;; *) echo "SANITIZE must be thread or address"; exit 1;; esac
xcodebuild -project MidiSpark.xcodeproj -scheme Fourfold -configuration Debug -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DD" $SAN CODE_SIGNING_ALLOWED=NO build > "$OUT/soak-build.log" 2>&1 \
  || { grep "error:" "$OUT/soak-build.log" | head; echo "BUILD FAILED (see $OUT/soak-build.log)"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
sleep 3
APP="$DD/Build/Products/Debug-iphonesimulator/Fourfold.app"
xcrun simctl terminate "$UDID" com.outliermidi.Fourfold 2>/dev/null || true
xcrun simctl uninstall "$UDID" com.outliermidi.Fourfold 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
ARGS="--soak $SECS"; [ -n "$SEED" ] && ARGS="$ARGS --soak-seed $SEED"; [ -n "$3" ] && ARGS="$ARGS --soak-fault $3"
(xcrun simctl launch --console "$UDID" com.outliermidi.Fourfold $ARGS > "$OUT/soak-console.log" 2>&1 &)
# wait for the result line (or give up well after the run should have ended)
for i in $(seq 1 $((SECS + 60))); do grep -aq "SOAK RESULT" "$OUT/soak-console.log" 2>/dev/null && break; sleep 1; done
xcrun simctl io "$UDID" screenshot "$OUT/soak-shot.png" >/dev/null 2>&1 || true
xcrun simctl terminate "$UDID" com.outliermidi.Fourfold 2>/dev/null || true
SANLINES=$(grep -a -c -E "ThreadSanitizer|AddressSanitizer|runtime error:" "$OUT/soak-console.log" || true)
if [ "${SANLINES:-0}" -gt 0 ]; then echo "SANITIZER: $SANLINES report line(s) in $OUT/soak-console.log:"; grep -a -E "ThreadSanitizer|AddressSanitizer|runtime error:" "$OUT/soak-console.log" | sort | uniq -c | sort -rn | head -12; fi
grep -a -o "SOAK [A-Za-z].*" "$OUT/soak-console.log" || { echo "NO SOAK LINES — the app probably crashed; recent crash reports:"; ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i fourfold | head -3; tail -5 "$OUT/soak-console.log"; }
