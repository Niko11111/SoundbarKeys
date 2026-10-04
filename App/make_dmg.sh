#!/bin/zsh
# Builds build/SoundbarKeys-<version>.dmg for distribution (Apple Silicon + Intel).
#
# Signing:
#   - With a "Developer ID Application" certificate in the Keychain the app is signed with it.
#     If NOTARY_PROFILE names a notarytool keychain profile (xcrun notarytool store-credentials),
#     the DMG is also notarized and stapled: it then opens without any Gatekeeper warning.
#   - Otherwise the app is signed ad hoc. Users have to confirm the first start once
#     (System Settings → Privacy & Security → "Open Anyway"), see README.
#   The personal "Apple Development" certificate is deliberately not used: its name contains the
#   developer's email address, which would end up in every distributed copy.
set -euo pipefail
cd "${0:A:h}"

./build_bundle.sh universal
APP=build/SoundbarKeys.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG=build/SoundbarKeys-$VERSION.dmg

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
NOTARIZED=""
# Notarization requires a secure timestamp; an ad hoc signature has none.
if [[ -n "$IDENTITY" ]]; then TIMESTAMP=--timestamp; else TIMESTAMP=--timestamp=none; fi
codesign --force --options runtime "$TIMESTAMP" --sign "${IDENTITY:--}" "$APP"
codesign --verify --strict --verbose=1 "$APP"

STAGING=build/dmg-staging
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/SoundbarKeys.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "SoundbarKeys $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ -n "$IDENTITY" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        NOTARIZED=", notarized"
    fi
fi

echo "Created $DMG ($(du -h "$DMG" | cut -f1), signed with: ${IDENTITY:-ad-hoc}$NOTARIZED)"
shasum -a 256 "$DMG"
