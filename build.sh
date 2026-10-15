#!/bin/bash
# Builds build/StopSpotlightShortcut.app. `./build.sh install` also copies it to /Applications
# and launches it.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=StopSpotlightShortcut
APP="build/$APP_NAME.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
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
