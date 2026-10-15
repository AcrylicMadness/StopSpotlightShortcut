#!/bin/bash
# Builds build/StopSpotlightShortcut.app (universal, ad-hoc signed). `./build.sh install` also
# copies it to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=StopSpotlightShortcut
APP="build/$APP_NAME.app"

# actool (which compiles the Icon Composer icon) and universal builds need Xcode, not just the
# Command Line Tools.
if ! xcrun --find actool >/dev/null 2>&1 && [[ -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --target-device mac \
    --app-icon AppIcon --output-partial-info-plist build/AppIcon-partial.plist \
    --errors --warnings >/dev/null
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    # Quit a running copy first; it turns the Spotlight shortcut back on as it exits.
    if pkill -x "$APP_NAME"; then
        while pgrep -x "$APP_NAME" >/dev/null; do sleep 0.2; done
    fi
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "Installed and launched /Applications/$APP_NAME.app"
fi
