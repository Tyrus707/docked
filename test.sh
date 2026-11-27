#!/bin/zsh
set -eu
cd "$(dirname "$0")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# One engine pin: ENGINE_PIN, and the app's copy of it
[ "$(sed -n 's/^let pinnedEngine = "\(.*\)"/\1/p' Sources/Core.swift) $(sed -n 's/^let pinnedEngineDate = "\(.*\)"/\1/p' Sources/Core.swift)" = "$(awk '$1=="commit"{c=$2} $1=="date"{d=$2} END{print c, d}' ENGINE_PIN)" ] || { echo "FAIL: Sources/Core.swift and ENGINE_PIN name different engines"; exit 1; }
# Everything but the windows: the tests build it with their own main. A new file goes here, or in APP_ONLY when it only makes sense inside the app.
SRC=(); for n in Core Notify Builder Review Estimate Place Install Originals Pipeline LibraryData Meta Consoles Disc Lookup Retro RetroExtras Organize Artwork Queue Cleanup Extras Notes Smart Navigate Update Arrive Phone Xcode Engine Verify GameSettings Offload GameData Compat Friends Health Links Netplay Keychain Streaming StreamingInstall StreamingProcess StreamingAPI StreamingPermissions TVDisplay SMM2Courses SMM2Crypto; do SRC+=("Sources/$n.swift"); done
APP_ONLY=" Offloading PlayTracker Power Spotlight Theme "   # plus every file that imports SwiftUI
for f in Sources/*.swift; do n=$(basename "$f" .swift); grep -q '^import SwiftUI' "$f" && continue; [[ " ${SRC[*]} " == *" $f "* || "$APP_ONLY" == *" $n "* ]] || { echo "FAIL: $f is in neither test.sh SRC nor APP_ONLY"; exit 1; }; done
swiftc -swift-version 5 -target ${ARCH:-arm64}-apple-macos13.0 "${SRC[@]}" Tests/main.swift -o "$T/tests"
# Two small throwaway disk images stand in for other disks.
hdiutil create -quiet -size 1200m -type SPARSE -fs APFS -volname DSBig "$T/big"; hdiutil create -quiet -size 40m -type SPARSE -fs APFS -volname DSSmall "$T/small"
mkdir "$T/mb" "$T/ms"; hdiutil attach -quiet -nobrowse -mountpoint "$T/mb" "$T/big.sparseimage"; hdiutil attach -quiet -nobrowse -mountpoint "$T/ms" "$T/small.sparseimage"
trap 'hdiutil detach -quiet -force "$T/mb"; hdiutil detach -quiet -force "$T/ms"; chmod -R u+w "$T"; rm -rf "$T"' EXIT
mkdir "$T/root"; BIGVOL="$T/mb" SMALLVOL="$T/ms" DOCKED_ROOT="$T/root" DOCKED_STREAMING="$T/streaming" "$T/tests"
# With the engine installed: the same code against the real engine. Its own checkout and Python are only read; everything else is temporary.
if [ -d "$HOME/Docked/engine" ] && [ -d "$HOME/Docked/venv" ]; then
  swiftc -swift-version 5 -target ${ARCH:-arm64}-apple-macos13.0 "${SRC[@]}" Tests/integration/main.swift -o "$T/itests"
  mkdir "$T/real"; ln -s "$HOME/Docked/engine" "$T/real/engine"; ln -s "$HOME/Docked/venv" "$T/real/venv"
  DOCKED_ROOT="$T/real" DOCKED_STREAMING="$T/streaming" "$T/itests"
fi
# With a payload: the same checks using only the carried tools, with Homebrew and any other Docked install blocked.
if [ -n "${PAYLOAD:-}" ]; then
  mkdir "$T/all"; tar -xJf "$PAYLOAD" -C "$T/all"
  printf '(version 1)(allow default)(deny file-read* file-write* (subpath "/opt/homebrew") (subpath "/usr/local") (subpath "%s/Docked") (subpath "/Library/Developer/CommandLineTools"))' "$HOME" > "$T/block.sb"
  DOCKED_ROOT="$T/all" sandbox-exec -f "$T/block.sb" "$T/itests"
fi
./Tests/queue/run.sh
