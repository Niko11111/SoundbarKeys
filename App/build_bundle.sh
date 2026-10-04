#!/bin/zsh
# Builds build/SoundbarKeys.app (unsigned). Shared by make_app.sh (local install) and make_dmg.sh.
#
#   build_bundle.sh            native architecture
#   build_bundle.sh universal  Apple Silicon + Intel
#
# App icon: Resources/AppIcon.icon (Icon Composer format, Liquid Glass) is compiled with actool
# from Xcode. If Xcode is not available, the last compiled files in Resources/CompiledIcon/ are used.
set -euo pipefail
cd "${0:A:h}"

if [[ "${1:-}" == "universal" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
    ARCH_FLAGS=()
fi
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR=$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)

APP=build/SoundbarKeys.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SoundbarKeys" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"

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

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/SoundbarKeys"))"
