#!/bin/sh
# Fast inner-loop test run for Euclideous/FourStep-scoped engine changes — NOT a replacement for
# the full suite before shipping (see Docs/claude-playbook.md's "Running only Euclideous-relevant
# tests" section for the line between the two). Regenerates its test list from Scripts/
# classify_euclideous_tests.py on every run, so it can't go stale the way a hand-written list would.
set -e
cd "$(dirname "$0")/.."

ONLY_TESTING=""
while IFS= read -r line; do
    ONLY_TESTING="$ONLY_TESTING -only-testing:$line"
done <<EOF
$(python3 Scripts/classify_euclideous_tests.py --xctest)
EOF

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project MidiSpark.xcodeproj -scheme MidiSparkTests \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
    $ONLY_TESTING
