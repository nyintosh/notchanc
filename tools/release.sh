#!/bin/bash
# Builds, signs (Developer ID), notarizes and publishes a release.
# Usage: tools/release.sh 1.0.0
# Needs: a Developer ID Application cert for BC8RBD2A8Y, the Sparkle key "notchanc" in the
# login keychain, `gh` signed in as nyintosh, and a clean, pushed main branch.
set -euo pipefail
cd "$(dirname "$0")/.."

V=${1:?usage: tools/release.sh VERSION}
BUILD=$(( $(git rev-list --count HEAD) + 1 ))   # +1: the appcast commit below
ASC_KEY="${ASC_KEY:?set ASC_KEY to the App Store Connect .p8 path}"
ASC_ID="${ASC_ID:?set ASC_ID to the App Store Connect key ID}"
ASC_ISSUER="${ASC_ISSUER:?set ASC_ISSUER to the App Store Connect issuer ID}"
AUTH=(-authenticationKeyPath "$ASC_KEY" -authenticationKeyID "$ASC_ID" -authenticationKeyIssuerID "$ASC_ISSUER")
OUT=build/release
DMG=$OUT/updates/NotchANC-$V.dmg
NOTES=$OUT/updates/NotchANC-$V.md   # named after the DMG, so generate_appcast puts it in the update window
SPARKLE=build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin

[ -z "$(git status --porcelain)" ] || { echo "Commit your changes first."; exit 1; }
rm -rf "$OUT" && mkdir -p "$OUT/dmg" "$OUT/updates"
awk "/^## \\[$V\\]/{f=1;next} /^## /{f=0} f" CHANGELOG.md > "$NOTES"
[ -s "$NOTES" ] || { echo "Add a [$V] section to CHANGELOG.md first."; exit 1; }

xcodebuild -scheme NotchANC -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/dd -archivePath "$OUT/NotchANC.xcarchive" \
  MARKETING_VERSION="$V" CURRENT_PROJECT_VERSION="$BUILD" \
  -allowProvisioningUpdates "${AUTH[@]}" archive
xcodebuild -exportArchive -archivePath "$OUT/NotchANC.xcarchive" -exportOptionsPlist tools/ExportOptions.plist \
  -exportPath "$OUT/export" -allowProvisioningUpdates "${AUTH[@]}"

cp -R "$OUT/export/NotchANC.app" "$OUT/dmg/"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname NotchANC -srcfolder "$OUT/dmg" -format UDZO -ov "$DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --key "$ASC_KEY" --key-id "$ASC_ID" --issuer "$ASC_ISSUER" --wait
xcrun stapler staple "$DMG"
spctl -a -vv -t install "$DMG"

# Adds this release to appcast.xml; earlier entries are kept.
"$SPARKLE/generate_appcast" --account notchanc --embed-release-notes -o appcast.xml \
  --download-url-prefix "https://github.com/nyintosh/notchanc/releases/download/v$V/" "$OUT/updates"

git add appcast.xml
git commit -m "Release $V"
git tag -s -m "NotchANC $V" "v$V"
git push origin main "v$V"
gh release create "v$V" "$DMG" --title "NotchANC $V" --notes-file "$NOTES"
