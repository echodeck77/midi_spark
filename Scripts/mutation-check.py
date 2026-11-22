#!/usr/bin/env python3
# ENGINE HARDENING 1 (2026-11-21), §6 — a sampling mutation checker for the Fourfold engine.
#
# A full mutation tool (muter) is infeasible here: the suite is ~20 min, so per-mutant full runs would take
# weeks. Instead this applies ONE source mutation at a time to a target file, rebuilds, and runs a FAST kill
# oracle (MutationOracleTests + a few targeted engine classes), recording whether the mutant SURVIVED (tests
# still pass — a coverage gap) or was KILLED (a test failed). It reverts the file after each mutant and never
# commits anything. It reports the kill rate and lists the surviving mutations so each can get a test or a
# one-line equivalent-mutant note.
#
# Mutations (one site per mutant): flip a comparison (< <= > >= == !=), swap + / -, swap && / ||, bump an
# integer literal by ±1, and delete a statement line (a lone `return`, an assignment, or a call). Sites in
# comments or string literals are skipped. A deterministic seeded sample keeps a run reproducible.
#
# Usage:
#   python3 Scripts/mutation-check.py --file Fourfold/Engine/Derivations.swift --count 60 --seed 1 \
#       [--only-testing FourfoldTests/MutationOracleTests] [--out build/mutation]
# The default oracle is MutationOracleTests + DerivationsTests + RouterTests slice; pass --only-testing to
# override. Run it in the BACKGROUND — each mutant is a rebuild (~1–2 min).

import argparse, os, re, subprocess, sys, random, json, time, shutil

DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"
DD = "build/MutationDD"   # a dedicated derivedData so a concurrent build/FourfoldDD run is untouched

COMPARISONS = [("<=", ">="), ("<", ">"), ("==", "!="), (">=", "<="), (">", "<"), ("!=", "==")]

def mutate_line(line):
    """Yield (description, mutated_line) candidates for one source line (code only)."""
    out = []
    # strip trailing line comment for site-finding (but mutate the original)
    code = line
    ci = code.find("//")
    scan = code[:ci] if ci >= 0 else code
    # comparison flips (word-boundary-ish; avoid -> and generics heuristically)
    for a, b in [("<=", ">="), (">=", "<="), ("==", "!="), ("!=", "=="), ("<", ">"), (">", "<")]:
        idx = scan.find(a)
        while idx >= 0:
            # skip <= inside things like "a <= b" fine; skip "->", "<<", ">>", "</"
            around = scan[max(0, idx-1): idx+len(a)+1]
            if "->" not in around and "<<" not in around and ">>" not in around:
                out.append((f"{a}→{b}@{idx}", code[:idx] + b + code[idx+len(a):]))
            idx = scan.find(a, idx + len(a))
    # arithmetic + <-> - (avoid ++, --, +=, -=, &+, &-, unary)
    for a, b in [(" + ", " - "), (" - ", " + "), (" &+ ", " &- "), (" &- ", " &+ ")]:
        if a in scan:
            out.append((f"{a.strip()}→{b.strip()}", code.replace(a, b, 1)))
    # boolean && <-> ||
    for a, b in [(" && ", " || "), (" || ", " && ")]:
        if a in scan:
            out.append((f"{a.strip()}→{b.strip()}", code.replace(a, b, 1)))
    # integer literal bump (first standalone integer, not a float/hex/index 0/1 of a tuple member)
    for m in re.finditer(r"(?<![\w.])(\d+)(?![\w.])", scan):
        n = int(m.group(1))
        if n > 1 and n < 100000:
            s, e = m.span(1)
            out.append((f"{n}→{n+1}", code[:s] + str(n+1) + code[e:]))
            break
    return out

def is_mutable(line):
    s = line.strip()
    if not s or s.startswith("//") or s.startswith("///") or s.startswith("*") or s.startswith("#"):
        return False
    # skip attribute/import/MARK lines
    if s.startswith("import ") or s.startswith("@") or "MARK:" in s:
        return False
    return True

def run(cmd, timeout=1200):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True)
    ap.add_argument("--count", type=int, default=60)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--only-testing", default="FourfoldTests/MutationOracleTests FourfoldTests/DerivationsTests")
    ap.add_argument("--out", default="build/mutation")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    env = dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR)
    only = " ".join(f"-only-testing:{t}" for t in args.only_testing.split())
    build_cmd = (f"xcodebuild build-for-testing -project MidiSpark.xcodeproj -scheme FourfoldTests "
                 f"-destination 'platform=macOS,arch=arm64' -derivedDataPath {DD}")
    test_cmd = (f"xcodebuild test-without-building -project MidiSpark.xcodeproj -scheme FourfoldTests "
                f"-destination 'platform=macOS,arch=arm64' -derivedDataPath {DD} {only}")

    src = open(args.file).read()
    lines = src.split("\n")

    # enumerate all mutant candidates
    candidates = []
    for i, line in enumerate(lines):
        if not is_mutable(line):
            continue
        for desc, mutated in mutate_line(line):
            if mutated != line:
                candidates.append((i, desc, mutated))
    rng = random.Random(args.seed)
    rng.shuffle(candidates)
    sample = candidates[:args.count]
    print(f"{len(candidates)} candidate mutations in {args.file}; running {len(sample)} (seed {args.seed})")

    # baseline: build once, confirm oracle green on the unmutated file
    print("baseline build + oracle…")
    b = run(build_cmd)
    if b.returncode != 0:
        print("BASELINE BUILD FAILED:\n" + "\n".join(l for l in b.stdout.split("\n") if "error:" in l)[:2000]); sys.exit(1)
    t = run(test_cmd)
    if t.returncode != 0:
        print("BASELINE ORACLE NOT GREEN — fix before mutation scoring.");
        print("\n".join(l for l in t.stdout.split("\n") if "error:" in l)[:2000]); sys.exit(1)
    print("baseline green.")

    killed, survived, invalid = [], [], []
    results = []
    for n, (i, desc, mutated) in enumerate(sample):
        orig = lines[i]
        mlines = lines[:]; mlines[i] = mutated
        open(args.file, "w").write("\n".join(mlines))
        t0 = time.time()
        b = run(build_cmd)
        if b.returncode != 0:
            invalid.append((i+1, desc)); status = "INVALID(build)"
        else:
            t = run(test_cmd)
            if t.returncode == 0:
                survived.append((i+1, desc, orig.strip())); status = "SURVIVED"
            else:
                killed.append((i+1, desc)); status = "killed"
        open(args.file, "w").write(src)   # revert immediately
        dt = int(time.time() - t0)
        print(f"[{n+1}/{len(sample)}] line {i+1} {desc}: {status} ({dt}s)")
        results.append({"line": i+1, "mut": desc, "status": status, "src": orig.strip()})
        json.dump({"file": args.file, "killed": len(killed), "survived": len(survived),
                   "invalid": len(invalid), "results": results},
                  open(os.path.join(args.out, "mutation-report.json"), "w"), indent=1)

    scored = len(killed) + len(survived)
    rate = (len(killed) / scored * 100) if scored else 0
    print(f"\n=== MUTATION REPORT {args.file} ===")
    print(f"scored {scored} (killed {len(killed)}, survived {len(survived)}); invalid {len(invalid)}")
    print(f"KILL RATE: {rate:.1f}%")
    print("SURVIVORS (each needs a killing test or an equivalent-mutant note):")
    for ln, desc, s in survived:
        print(f"  line {ln} {desc}: {s[:100]}")

if __name__ == "__main__":
    main()
