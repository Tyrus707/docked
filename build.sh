#!/bin/zsh
# build.sh [app] [payload]: the app; with a payload (Bundle/make.sh), it carries the conversion tools.
set -eu
APP="${1:-Docked.app}"; PAYLOAD="${2:-}"; case "$APP" in /*) ;; *) APP="$PWD/$APP";; esac
cd "$(dirname "$0")"
# The engine pin lives in ENGINE_PIN; the app's own copy must say the same
[ "$(sed -n 's/^let pinnedEngine = "\(.*\)"/\1/p' Sources/Core.swift) $(sed -n 's/^let pinnedEngineDate = "\(.*\)"/\1/p' Sources/Core.swift)" = "$(awk '$1=="commit"{c=$2} $1=="date"{d=$2} END{print c, d}' ENGINE_PIN)" ] || { echo "Sources/Core.swift and ENGINE_PIN name different engines. Run bump-engine.sh."; exit 1; }
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
B=$(mktemp -d); for a in arm64 x86_64; do swiftc -swift-version 5 -O -whole-module-optimization -parse-as-library -target $a-apple-macos13.0 Sources/*.swift -o "$B/$a"; done
lipo -create "$B/arm64" "$B/x86_64" -output "$APP/Contents/MacOS/Docked"
strip -x "$APP/Contents/MacOS/Docked"
cp Info.plist "$APP/Contents/"; cp "Art/${LOGO:-docked}.icns" "$APP/Contents/Resources/AppIcon.icns"
# With Xcode 26 or later, add the icon that follows light, dark and tinted; anything else keeps AppIcon.icns
XC="${DEVELOPER_DIR:-$(xcode-select -p)}"; xcrun --find actool >/dev/null 2>&1 || XC=/Applications/Xcode.app/Contents/Developer
if [ -z "${LOGO:-}" ] && DEVELOPER_DIR="$XC" xcrun --find actool >/dev/null 2>&1; then
  if DEVELOPER_DIR="$XC" xcrun actool Art/Docked.icon --compile "$B" --app-icon Docked --platform macosx --target-device mac --minimum-deployment-target 13.0 --output-partial-info-plist "$B/icon.plist" --errors --warnings >"$B/actool.log" 2>&1 && [ -f "$B/Assets.car" ] && plutil -extract CFBundleIconName raw "$B/icon.plist" >/dev/null 2>&1; then
    cp "$B/Assets.car" "$APP/Contents/Resources/"; plutil -replace CFBundleIconName -string Docked "$APP/Contents/Info.plist"
  else echo "Skipped the light, dark and tinted icon:"; cat "$B/actool.log"; fi
fi
# The licence texts and the GPL source travel inside the app, as THIRD-PARTY.md promises.
cp LICENSE THIRD-PARTY.md "$APP/Contents/Resources/"; cp -R Licences GPL-source "$APP/Contents/Resources/"
if [ -n "$PAYLOAD" ]; then
  cp "$PAYLOAD" "$APP/Contents/Resources/tools.tar.xz"
  plutil -insert DSPayloadSHA256 -string "$(shasum -a 256 "$PAYLOAD" | cut -c1-64)" "$APP/Contents/Info.plist"
  # What the carried tools were really built for decides where converting works; the rest of Docked goes further back.
  M=$(xz -dc "$PAYLOAD" | tar -xOf - tools/.tools-minimum 2>/dev/null || echo 27.0); plutil -insert DSToolsMinimum -string "$M" "$APP/Contents/Info.plist"
elif [ "${SLIM:-}" = 1 ]; then cp setup.sh ENGINE_PIN "$APP/Contents/Resources/"   # an update for a Mac that already has the tools
else cp setup.sh ENGINE_PIN "$APP/Contents/Resources/"; fi
codesign --force --sign - "$APP"
du -sh "$APP"
