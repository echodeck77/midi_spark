#!/bin/sh
# Ableton Link sync (2026-10-24 ferry): downloads LinkKit (the iOS-specific C SDK Ableton distributes for
# Link — NOT the open-source cross-platform `Ableton/link` repo, which is GPL-licensed and wrong for a
# closed-source app) and vendors just the .xcframework into Fourfold/Vendor/, gitignored.
#
# Run this ONCE per machine before building the Fourfold scheme (xcodegen generate picks up the new
# project.yml framework dependency; the framework itself never goes in git — see .gitignore and the
# status log for why: this repo is public, and LinkKit's own license forbids redistributing the SDK).
#
# Re-run after bumping LINKKIT_VERSION below to update; verifies the download against the known sha256
# before unzipping, so a corrupted or substituted download is rejected rather than silently vendored.
set -e
cd "$(dirname "$0")/.."

LINKKIT_VERSION="LinkKit-4.1.3"
LINKKIT_SHA256="526be70a4b776c3935f8d8b4054dd44bf2bf68cb384c41b0100fa60608fd53bf"
LINKKIT_URL="https://github.com/Ableton/LinkKit/releases/download/${LINKKIT_VERSION}/LinkKit.zip"

VENDOR_DIR="Fourfold/Vendor"
FRAMEWORK_DIR="${VENDOR_DIR}/LinkKit.xcframework"

if [ -d "$FRAMEWORK_DIR" ]; then
    echo "fetch-linkkit: ${FRAMEWORK_DIR} already present — delete it first to re-fetch."
    exit 0
fi

mkdir -p "$VENDOR_DIR"
TMP_ZIP="$(mktemp -t linkkit).zip"
trap 'rm -f "$TMP_ZIP"' EXIT

echo "fetch-linkkit: downloading ${LINKKIT_VERSION} (~105 MB)..."
curl -sS -L -o "$TMP_ZIP" "$LINKKIT_URL"

ACTUAL_SHA256="$(shasum -a 256 "$TMP_ZIP" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$LINKKIT_SHA256" ]; then
    echo "fetch-linkkit: SHA256 MISMATCH — expected $LINKKIT_SHA256, got $ACTUAL_SHA256. Refusing to unzip." >&2
    exit 1
fi

echo "fetch-linkkit: checksum verified, extracting LinkKit.xcframework..."
unzip -q "$TMP_ZIP" "LinkKit.xcframework/*" -d "$VENDOR_DIR"

echo "fetch-linkkit: done — ${FRAMEWORK_DIR}"
echo "fetch-linkkit: run 'xcodegen generate' next if this is the first fetch on this machine."
