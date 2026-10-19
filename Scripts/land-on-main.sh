#!/bin/sh
# LAND THE CURRENT BRANCH ON main AND LEAVE EVERYTHING IN SYNC — run this, don't hand-type the steps (CLAUDE.md "Git workflow", rule 3).
#
# Why a script: `git push origin <branch>:main` moves ONLY origin/main. It does NOT move the local `main` branch, and it does NOT touch the build
# directories Paul actually builds from — so "landed on main" kept looking like "my changes aren't there" (2026-09-26, 09-30, 10-01 and 2026-10-20).
# This does the push AND the catch-up, then prints what it found.
#
#   1. fetch; if the branch is not already on main, require origin/main to be an ancestor of it (else: rebase, rebuild, rerun), then push <branch>:main.
#   2. fast-forward the LOCAL `main` ref to origin/main (ff-only; skipped — and synced via step 3 — if some worktree has main checked out).
#   3. for each build directory: if it is clean (no tracked changes) and strictly BEHIND origin/main, `git -C <dir> merge --ff-only origin/main`.
#      Never forced: a dir with uncommitted work, or ahead of / diverged from origin/main, is REPORTED and left alone.
#   4. print origin/main, local main and every build dir's branch + commit + state.
#
# Run it from your own worktree, on the feature branch, once the build is green. Exit status is non-zero only if the push could not happen.
set -e
cd "$(dirname "$0")/.."

# The directories Paul builds from. They rotate branches as work lands; add a directory here if a new one becomes a build dir.
BUILD_DIRS="/Users/paulbarrett/src/midi_spark /Users/paulbarrett/src/midi_spark-b"

BR=$(git rev-parse --abbrev-ref HEAD)
git fetch origin

if [ "$BR" != "main" ]; then
    if ! git merge-base --is-ancestor origin/main HEAD; then
        echo "origin/main has advanced past $BR — git rebase origin/main, rebuild to confirm it still compiles, then rerun."
        exit 1
    fi
    git push origin "$BR":main
    git fetch origin
fi

# 2. the local main ref
if git worktree list --porcelain | grep -q '^branch refs/heads/main$'; then
    LOCAL_MAIN="checked out in a worktree (synced in step 3)"
else
    git fetch origin main:main 2>&1 | tail -1 || true
    LOCAL_MAIN=$(git rev-parse --short main)
fi

# 3. the build directories
REPORT=""
for d in $BUILD_DIRS; do
    [ -d "$d" ] || continue
    b=$(git -C "$d" rev-parse --abbrev-ref HEAD)
    dirty=$(git -C "$d" status --porcelain --untracked-files=no | wc -l | tr -d ' ')
    behind=$(git -C "$d" rev-list --count HEAD..origin/main)
    ahead=$(git -C "$d" rev-list --count origin/main..HEAD)
    if [ "$behind" -eq 0 ] && [ "$ahead" -eq 0 ]; then
        state="in sync"
    elif [ "$dirty" -ne 0 ]; then
        state="NOT TOUCHED — $dirty file(s) with uncommitted work; $behind behind / $ahead ahead (commits are not what is stale, the work in progress is)"
    elif [ "$ahead" -ne 0 ]; then
        state="NOT TOUCHED — $ahead commit(s) ahead of / diverged from origin/main ($behind behind): needs a human merge or rebase"
    else
        if git -C "$d" merge --ff-only origin/main >/dev/null 2>&1; then
            state="fast-forwarded $behind commit(s)"
        else
            state="NOT TOUCHED — fast-forward refused"
        fi
    fi
    REPORT="$REPORT
  $d  [$b @ $(git -C "$d" rev-parse --short HEAD)]  $state"
done

echo "origin/main: $(git rev-parse --short origin/main)   local main: $LOCAL_MAIN"
echo "build directories:$REPORT"
