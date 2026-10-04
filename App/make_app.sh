#!/bin/zsh
# Builds SoundbarKeys.app for this Mac and installs it to /Applications.
# Signs with an "Apple Development" certificate if one is available (keeps the Accessibility
# permission across rebuilds); otherwise ad hoc. For a download for others use make_dmg.sh.
set -euo pipefail
cd "${0:A:h}"

./build_bundle.sh
APP=build/SoundbarKeys.app

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
codesign --verify --verbose=1 "$APP"

DEST=/Applications/SoundbarKeys.app
pkill -x SoundbarKeys 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
touch "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
echo "Installed: $DEST (signed with: ${IDENTITY:-ad-hoc})"
