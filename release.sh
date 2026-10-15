#!/bin/bash
# Builds a Developer ID signed, notarized DMG in build/ for a GitHub release.
#
# Needs a "Developer ID Application" certificate in the keychain and notarytool credentials
# stored under $NOTARY_PROFILE (default: StopSpotlightShortcut):
#   xcrun notarytool store-credentials StopSpotlightShortcut --apple-id <Apple ID> --team-id <Team ID>
#
# SIGNING_IDENTITY=- ./release.sh makes an ad-hoc signed, un-notarized DMG to test the packaging.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=StopSpotlightShortcut
APP="build/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="build/$APP_NAME-$VERSION.dmg"
NOTARY_PROFILE=${NOTARY_PROFILE:-StopSpotlightShortcut}
IDENTITY=${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | head -n 1)}

if [[ -z "$IDENTITY" ]]; then
    echo "No \"Developer ID Application\" certificate in the keychain." >&2
    exit 1
fi
NOTARIZE=true
[[ "$IDENTITY" == "-" ]] && NOTARIZE=false
if $NOTARIZE && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "No notarytool credentials named \"$NOTARY_PROFILE\". Store them with:" >&2
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id <Team ID>" >&2
    exit 1
fi
SIGN=(codesign --force --sign "$IDENTITY")
$NOTARIZE && SIGN+=(--timestamp)

notarize() {
    local result status
    result=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
    status=$(plutil -extract status raw -o - - <<<"$result")
    if [[ "$status" != Accepted ]]; then
        echo "Notarizing $1 failed ($status). Details:" >&2
        echo "  xcrun notarytool log $(plutil -extract id raw -o - - <<<"$result") --keychain-profile $NOTARY_PROFILE" >&2
        exit 1
    fi
}

./build.sh
"${SIGN[@]}" --options runtime "$APP"

if $NOTARIZE; then
    # Staple the app as well as the DMG, so it passes Gatekeeper offline once copied out.
    ditto -c -k --keepParent "$APP" "build/$APP_NAME.zip"
    notarize "build/$APP_NAME.zip"
    xcrun stapler staple "$APP"
fi

STAGING=build/dmg
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Stop Spotlight Shortcut" -srcfolder "$STAGING" -fs HFS+ -format UDZO -quiet "$DMG"
"${SIGN[@]}" "$DMG"

if $NOTARIZE; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
    echo "Ad-hoc signed and not notarized: for testing only." >&2
fi
echo "Built $DMG"
