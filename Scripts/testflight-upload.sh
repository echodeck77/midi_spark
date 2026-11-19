#!/bin/sh
# Archive Fourfold (the app + its embedded FourfoldAU extension) and upload it to TestFlight / App Store Connect.
#
# PREREQUISITES (one-time, your side):
#   1. A PAID Apple Developer Program membership, and this Mac's Xcode signed into that Apple ID
#      (Xcode ▸ Settings ▸ Accounts). On a fresh paid enrolment, run an archive once in Xcode's
#      Organizer so it creates the "Apple Distribution" certificate, OR let `-allowProvisioningUpdates`
#      below create it (needs the API key).
#   2. If the paid team ID differs from the current one, set it in project.yml (DEVELOPMENT_TEAM) and in
#      Scripts/ExportOptions.plist (teamID), then `xcodegen generate`.
#   3. An App Store Connect app record for com.paulbarrett.Fourfold must exist (create it in App Store
#      Connect, or Xcode creates it on the first Organizer distribute).
#   4. An App Store Connect API key (.p8) with "App Manager" (or higher) access. Set:
#        export ASC_KEY_ID=XXXXXXXXXX
#        export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#        export ASC_KEY_PATH=/absolute/path/to/AuthKey_XXXXXXXXXX.p8
#
# THEN:  sh Scripts/testflight-upload.sh          (bumps the build, archives, uploads)
#        sh Scripts/testflight-upload.sh --no-bump (keep the current build number)
set -e
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API key id)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect issuer id)}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH (path to the AuthKey_*.p8)}"
[ -f "$ASC_KEY_PATH" ] || { echo "ASC_KEY_PATH not found: $ASC_KEY_PATH"; exit 1; }

DEV="DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"
ARCHIVE="build/Fourfold.xcarchive"

if [ "$1" != "--no-bump" ]; then sh Scripts/bump-build.sh; fi
sh Scripts/bump-build.sh show
xcodegen generate

echo "== archiving (Release) =="
env $DEV xcodebuild -project MidiSpark.xcodeproj -scheme Fourfold \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$ASC_KEY_PATH" \
  clean archive

echo "== exporting + uploading to App Store Connect =="
env $DEV xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist Scripts/ExportOptions.plist \
  -exportPath build/Fourfold-export \
  -allowProvisioningUpdates \
  -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$ASC_KEY_PATH"

echo "== done — the build is processing in App Store Connect / TestFlight =="
