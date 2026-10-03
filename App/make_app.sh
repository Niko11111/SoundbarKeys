#!/bin/zsh
# Builds SoundbarKeys.app and installs it to /Applications.
# Signs with an "Apple Development" certificate if one is available (keeps the Accessibility
# permission across rebuilds); otherwise ad-hoc.
#
# App icon: Resources/AppIcon.icon (Icon Composer format, Liquid Glass) is compiled with actool
# from Xcode. If Xcode is not available, the last compiled files in Resources/CompiledIcon/ are used.
set -euo pipefail
cd "${0:A:h}"

swift build -c release

APP=build/SoundbarKeys.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SoundbarKeys "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"

# --- App icon
XCODE=$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -1)
ACTOOL="$XCODE/Contents/Developer/usr/bin/actool"
if [[ -n "$XCODE" && -x "$ACTOOL" ]]; then
    rm -rf Resources/CompiledIcon && mkdir -p Resources/CompiledIcon
    # actool resolves relative paths from the .icon folder → use absolute paths
    DEVELOPER_DIR="$XCODE/Contents/Developer" "$ACTOOL" "$PWD/Resources/AppIcon.icon" \
        --compile "$PWD/Resources/CompiledIcon" --platform macosx --minimum-deployment-target 26.0 \
        --app-icon AppIcon --output-partial-info-plist "$PWD/build/icon-partial.plist" \
        --output-format human-readable-text >/dev/null
    echo "Icon compiled with actool ($XCODE)"
else
    echo "Xcode not found – using the precompiled icon from Resources/CompiledIcon"
fi
cp Resources/CompiledIcon/Assets.car Resources/CompiledIcon/AppIcon.icns "$APP/Contents/Resources/"

# --- Sign
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
codesign --verify --verbose=1 "$APP"

# --- Install
DEST=/Applications/SoundbarKeys.app
pkill -x SoundbarKeys 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto "$APP" "$DEST"
touch "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true
echo "Installed: $DEST (signed with: ${IDENTITY:-ad-hoc})"
