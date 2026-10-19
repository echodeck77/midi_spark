#!/usr/bin/env python3
"""
Classifies MidiSparkTests functions by product relevance: Euclideous/FourStep (the 4-lane
engine) vs 8x8 State (the on-hold wider grid/rooms/ferries/macros/scenes product) vs shared
infra with no dependency on either's specific logic.

WHY THIS EXISTS: several 8x8-State-only symbols collide, by name only, with the Euclideous
feature — `ProcessorType.euclid`/`euclidPulses`/`euclidPick` is the standalone EUCLID driver
in the 8x8 grid's processor roster, NOT the EuclidLine-based Euclideous page; `ProcessorType.riff`
is a similarly-named but distinct 8x8-State processor. Naive substring matching on "euclid"/"riff"
misclassifies both. See the exclusions below — each one was found by reading an actual
misclassified test, not guessed.

Regenerate this classification by RUNNING this script, not by hand-editing a stored list — test
files change often enough that a frozen list silently rots. See Docs/claude-playbook.md's
"Running only Euclideous-relevant tests" section for how this is used.

Usage:
    python3 Scripts/classify_euclideous_tests.py            # human-readable summary
    python3 Scripts/classify_euclideous_tests.py --xctest   # one MidiSparkTests/Class/method
                                                              # per line, for -only-testing:
"""
import re
import os
import sys

TESTS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Tests")

# Whole files that are 100% Euclideous/FourStep — always run entirely, no per-test filtering.
EXCLUSIVE_FILES = {
    "FXTabTests.swift",
    "LanesGridTests.swift",
    "RestartChainsTests.swift",
}

# Mixed files worth scanning function-by-function: the shared engine (Router/Derivations) plus
# the composition seam where Euclideous's row is pinned alongside 8x8-State scenes.
MIXED_FILES = {
    "RouterTests.swift",
    "DerivationsTests.swift",
    "EffectiveParamsTests.swift",
    "SnapshotBuilderTests.swift",
    "BuildSceneLogicTests.swift",
    "MigrationTests.swift",
}

# Files that exercise ONLY the Machine/ProcessorSlot/chain-based 8x8-State processor roster, or
# are generic product-agnostic infra Euclideous's EuclidLine path never touches. Skipped entirely
# for Euclideous-focused fast iteration. (Still run by the full suite before shipping.)
SKIP_FILES = {
    "AcceptanceArpTests.swift", "AcceptanceGatesSpecialTests.swift",
    "AcceptanceRatchetStrumTests.swift", "AcceptanceTuttiLengthTests.swift",
    "AcceptanceTests.swift", "AcceptanceWeaveTests.swift", "AcceptanceGeneratorsTests.swift",
    "AcceptanceFactoryLibraryTests.swift", "RoomsLatticeTests.swift", "SceneFactoryTests.swift",
    "MacroAuthoringTests.swift", "ColourTypeSwitchTests.swift", "Row8Tests.swift",
    "BuildSelfTestMetaTests.swift", "DiceTests.swift", "FuzzTests.swift", "ReelDeckTests.swift",
    "MidiFileTests.swift", "PresetStoreTests.swift",
}

# Case-SENSITIVE: PascalCase "Euclid<Capital>..." types are exclusive to Euclideous (EuclidLine,
# EuclidLineMask, EuclidHitStep, EuclidFooterState, EuclidRiffOnRest, ...) EXCEPT the three below,
# which are deliberately-separate 8x8-State EUCLID-processor enums (Models.swift ~1127-1197: "a
# DEDICATED enum, not a reuse of RiffDir" / "not a reuse of EuclidPick") — confirmed by reading
# their declarations, not assumed from the name.
_EUCLID_PROCESSOR_TYPES = r"Dir\b|NoteSel\b|Pick\b"
POS_CS = re.compile(
    r"\bEuclid(?!" + _EUCLID_PROCESSOR_TYPES + r")[A-Z]\w*|\bRiffWrap\b|\bRiffDir\b|\brunEuclidLine\b"
)

# Case-insensitive but unambiguous regardless of case — no 8x8-State symbol collides with these.
POS_CI = re.compile(
    r"euclideous|riffOctave|riffLock\b|riffStride|riffLength|riffPositions|riffDirection|"
    r"riffRotate|riffInvert|riffOnRest|activeRiff|\briffs\b|FourStep|fourfold|"
    r"LanesPanelPainter|FXPanelPainter|restartRhythmBars|restartMelodyPasses|"
    r"muteCells16|muteUnit\b|mixOutRow",
    re.IGNORECASE,
)

# 8x8-State signal: the on-hold product's own UI/feature surface, OR the lowercase EUCLID/RIFF/
# EUCLIDMASK *processor* params (euclidPulses/euclidPick/euclidDir/euclidNoteSel/.riff/.euclidMask)
# — the collision case this whole script exists to catch.
STATE = re.compile(
    r"RoomsLattice|BuildScene|BuildPart|BuildUnassigned|MacroAuthor|SceneFactory|"
    r"RackMatrix|machineHue|machineReg|DestMatrix|TuttiSpan|KillStep|CascadeSpan|"
    r"FerryLaunch|DroneStrike|ColourTypeSwitch|RoomCell|doorGraph|receiverGraph|"
    r"euclidPulses|euclidSteps|euclidRate|euclidSpanN|euclidRotate|euclidMask|EUCLIDMASK|"
    r"euclidPick|euclidInvert|euclidMute|euclidWrap\b|euclidDir\b|euclidNoteSel|"
    r"ProcessorType\.(riff|euclid)\b|type:\s*\.(riff|euclid)\b|case\s+\.?(riff|euclid)\b|"
    r"ProcessorSlot\(type:\s*\.(riff|euclid)\)",
    re.IGNORECASE,
)

FUNC_RE = re.compile(r"\bfunc (test\w*)\s*\(")
CLASS_RE = re.compile(r"\b(?:final\s+)?class (\w+)\s*:\s*XCTestCase")


def extract_funcs_with_class(path):
    """Yields (class_name, func_name, body) using brace-depth matching for function bounds —
    NOT 'next func test line', which bleeds trailing between-test comments into the wrong
    function and caused real misclassifications during development."""
    with open(path) as f:
        lines = f.readlines()
    current_class = None
    i, n = 0, len(lines)
    while i < n:
        cm = CLASS_RE.search(lines[i])
        if cm:
            current_class = cm.group(1)
        fm = FUNC_RE.search(lines[i])
        if not fm:
            i += 1
            continue
        name = fm.group(1)
        depth, started, j = 0, False, i
        body_lines = []
        while j < n:
            line = lines[j]
            body_lines.append(line)
            for ch in line:
                if ch == "{":
                    depth += 1
                    started = True
                elif ch == "}":
                    depth -= 1
            if started and depth == 0:
                break
            j += 1
        body = "".join(body_lines[1:])  # exclude the signature line (test names are free-form English)
        yield (current_class, name, body)
        i = j + 1


def classify_mixed_file(path):
    eucl, state, both, neither = [], [], [], []
    for cls, name, body in extract_funcs_with_class(path):
        hp = bool(POS_CS.search(body)) or bool(POS_CI.search(body))
        hs = bool(STATE.search(body))
        bucket = both if (hp and hs) else eucl if hp else state if hs else neither
        bucket.append((cls, name))
    return eucl, state, both, neither


def main():
    xctest_mode = "--xctest" in sys.argv
    only_testing = []
    summary = []
    selected_total = 0

    for fname in sorted(EXCLUSIVE_FILES):
        path = os.path.join(TESTS_DIR, fname)
        if not os.path.exists(path):
            continue
        cls = CLASS_RE.search(open(path).read()).group(1)
        count = len(FUNC_RE.findall(open(path).read()))
        only_testing.append(f"MidiSparkTests/{cls}")
        selected_total += count
        summary.append(f"{fname}: ALL {count} tests (100% Euclideous/FourStep)")

    for fname in sorted(MIXED_FILES):
        path = os.path.join(TESTS_DIR, fname)
        if not os.path.exists(path):
            continue
        eucl, state, both, neither = classify_mixed_file(path)
        relevant = eucl + both
        selected_total += len(relevant)
        for cls, name in relevant:
            only_testing.append(f"MidiSparkTests/{cls}/{name}")
        summary.append(
            f"{fname}: {len(relevant)} relevant (eucl={len(eucl)} both={len(both)}) / "
            f"{len(state)} state-only / {len(neither)} neither — total {len(eucl)+len(state)+len(both)+len(neither)}"
        )

    skipped_total = 0
    for fname in sorted(SKIP_FILES):
        path = os.path.join(TESTS_DIR, fname)
        if not os.path.exists(path):
            continue
        count = len(FUNC_RE.findall(open(path).read()))
        skipped_total += count
        summary.append(f"{fname}: SKIPPED ({count} tests, 8x8-State-only or product-agnostic infra)")

    if xctest_mode:
        for t in only_testing:
            print(t)
    else:
        print("\n".join(summary))
        print(f"\nTotal tests selected to run: {selected_total}")
        print(f"Total tests skipped: {skipped_total}")


if __name__ == "__main__":
    main()
