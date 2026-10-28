#!/bin/sh
# Fourfold's QUICK test runs — the cheap path while iterating (CLAUDE.md "Pace and test runs"). The FULL suite is `sh Scripts/run-fourfold-tests.sh` and runs ONCE, right before landing.
#   sh Scripts/run-fourfold-quick.sh [area]
#     fast    (default) every class EXCEPT the three heavy ones (RouterTests ≈3 min, PortsStressTests ≈12 min as of 2026-10-28, HocketGoldenTests ≈2 min) — about a minute with the build; use after almost any change
#     engine  the engine's own classes: RouterTests + HocketRouterTests + NoteRollTests + FourfoldPortsTests + SnapshotBuilderTests + EffectiveParamsTests + MigrationTests   (≈4 min — after a Router / Models change)
#     stress  PortsStressTests only (the seeded fuzzes: stuck notes, channels, ALL = union, roll vs wire)
#     golden  HocketGoldenTests only (the 20 presets × 3 window sizes, byte-identical with no rule lit)
#     layout  PageLayoutTests + CardBackTests + CardBackReviewTests + DerivationsTests + LaneLockTests + ClarityPassTests  (header / page / card-back geometry)
#     reel    the reel and tape classes
#   Anything else is passed to xcodebuild untouched:  sh Scripts/run-fourfold-quick.sh -only-testing:FourfoldTests/FXTabTests
# It prints its own wall time. Docs-only, comment-only and test-only edits need no run at all beyond the class you changed.
set -e
cd "$(dirname "$0")/.."
AREA=${1:-fast}
T=FourfoldTests
only() { for c in "$@"; do printf -- '-only-testing:%s/%s ' "$T" "$c"; done; }
case "$AREA" in
  fast)   ARGS="-skip-testing:$T/RouterTests -skip-testing:$T/PortsStressTests -skip-testing:$T/HocketGoldenTests" ;;
  engine) ARGS=$(only RouterTests HocketRouterTests NoteRollTests EngineReviewTests FourfoldPortsTests SnapshotBuilderTests EffectiveParamsTests MigrationTests) ;;
  stress) ARGS=$(only PortsStressTests) ;;
  golden) ARGS=$(only HocketGoldenTests) ;;
  layout) ARGS=$(only PageLayoutTests CardBackTests CardBackReviewTests DerivationsTests LaneLockTests ClarityPassTests) ;;
  reel)   ARGS=$(only ReelDeckTests ReelExportTests ReelTapeAdapterTests SessionTapeTests TapeStoreTests NoteRollTests) ;;
  full)   echo "That is the full suite — run it ONCE, right before landing: sh Scripts/run-fourfold-tests.sh"; exit 1 ;;
  *)      ARGS="$*" ;;
esac
START=$(date +%s)
LOG=$(mktemp)
# shellcheck disable=SC2086
sh Scripts/run-fourfold-tests.sh $ARGS > "$LOG" 2>&1 || true
grep -E "error: " "$LOG" | sed 's#^.*/Fourfold/##' | sort -u | head -30
grep -E "Executed [0-9]+ tests?, with" "$LOG" | tail -1 | sed 's/^[[:space:]]*//'
if grep -q "TEST SUCCEEDED" "$LOG" && ! grep -qE "Executed 0 tests?," "$LOG"; then RESULT=PASS; else RESULT=FAIL; fi   # zero tests run (a mistyped class name) is a FAIL, never a pass
echo "[$AREA] $RESULT in $(( $(date +%s) - START )) s   (full log: $LOG)"
[ "$RESULT" = PASS ]
