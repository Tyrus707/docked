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
# The licence texts and the GPL source travel inside the app, as THIRD-PARTY.md promises.
cp LICENSE THIRD-PARTY.md "$APP/Contents/Resources/"; cp -R Licences GPL-source "$APP/Contents/Resources/"
if [ -n "$PAYLOAD" ]; then
  cp "$PAYLOAD" "$APP/Contents/Resources/tools.tar.xz"
  plutil -insert DSPayloadSHA256 -string "$(shasum -a 256 "$PAYLOAD" | cut -c1-64)" "$APP/Contents/Info.plist"
  # What the carried tools were really built for decides where converting works; the rest of Docked goes further back.
  M=$(xz -dc "$PAYLOAD" | tar -xOf - tools/.tools-minimum 2>/dev/null || echo 27.0); plutil -insert DSToolsMinimum -string "$M" "$APP/Contents/Info.plist"
else cp setup.sh ENGINE_PIN "$APP/Contents/Resources/"; fi   # also an update (SLIM=1) for a Mac that already has the tools
codesign --force --sign - "$APP"
du -sh "$APP"
