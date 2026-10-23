#!/bin/sh
# Fourfold's own off-device tests: the FourfoldTests target (macOS, host-less) compiles Fourfold's engine COPY (Fourfold/Engine) and Fourfold/Tests — nothing from 8x8 State's AUExtension/ or Tests/.
# Membership is by FILE, so there is no classifier and no list to rot. Pass xcodebuild args to narrow it, e.g.:   sh Scripts/run-fourfold-tests.sh -only-testing:FourfoldTests/RouterTests
# The sound oracle for engine changes is separate (it needs the simulator): sh Scripts/fourfold-harness/run.sh --golden   and   diff Scripts/fourfold-harness/golden.txt build/fourfold-harness/golden.txt
set -e
cd "$(dirname "$0")/.."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
    -project MidiSpark.xcodeproj -scheme FourfoldTests \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/FourfoldDD "$@"
