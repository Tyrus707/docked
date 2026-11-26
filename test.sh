#!/bin/zsh
set -eu
cd "$(dirname "$0")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# One engine pin: ENGINE_PIN, and the app's copy of it
[ "$(sed -n 's/^let pinnedEngine = "\(.*\)"/\1/p' Sources/Core.swift) $(sed -n 's/^let pinnedEngineDate = "\(.*\)"/\1/p' Sources/Core.swift)" = "$(awk '$1=="commit"{c=$2} $1=="date"{d=$2} END{print c, d}' ENGINE_PIN)" ] || { echo "FAIL: Sources/Core.swift and ENGINE_PIN name different engines"; exit 1; }
swiftc -swift-version 5 -target ${ARCH:-arm64}-apple-macos13.0 Sources/Core.swift Sources/Builder.swift Sources/Review.swift Sources/Estimate.swift Sources/Place.swift Sources/Install.swift Sources/Originals.swift Sources/Pipeline.swift Sources/LibraryData.swift Sources/Meta.swift Sources/Consoles.swift Sources/Disc.swift Sources/Lookup.swift Sources/Retro.swift Sources/RetroExtras.swift Sources/Organize.swift Sources/Artwork.swift Sources/Queue.swift Sources/Cleanup.swift Sources/Extras.swift Sources/Notes.swift Sources/Smart.swift Sources/Navigate.swift Sources/Update.swift Sources/Arrive.swift Sources/Phone.swift Sources/Xcode.swift Sources/Engine.swift Sources/Verify.swift Sources/GameSettings.swift Sources/Offload.swift Sources/GameData.swift Sources/Compat.swift Sources/Friends.swift Tests/main.swift -o "$T/tests"
# Two small throwaway disk images stand in for other disks.
hdiutil create -quiet -size 1200m -type SPARSE -fs APFS -volname DSBig "$T/big"; hdiutil create -quiet -size 40m -type SPARSE -fs APFS -volname DSSmall "$T/small"
mkdir "$T/mb" "$T/ms"; hdiutil attach -quiet -nobrowse -mountpoint "$T/mb" "$T/big.sparseimage"; hdiutil attach -quiet -nobrowse -mountpoint "$T/ms" "$T/small.sparseimage"
trap 'hdiutil detach -quiet -force "$T/mb"; hdiutil detach -quiet -force "$T/ms"; chmod -R u+w "$T"; rm -rf "$T"' EXIT
mkdir "$T/root"; BIGVOL="$T/mb" SMALLVOL="$T/ms" DOCKED_ROOT="$T/root" "$T/tests"
# With the engine installed: the same code against the real engine. Its own checkout and Python are only read; everything else is temporary.
if [ -d "$HOME/Docked/engine" ] && [ -d "$HOME/Docked/venv" ]; then
  swiftc -swift-version 5 -target ${ARCH:-arm64}-apple-macos13.0 Sources/Core.swift Sources/Builder.swift Sources/Review.swift Sources/Estimate.swift Sources/Install.swift Sources/Pipeline.swift Sources/Consoles.swift Sources/Disc.swift Sources/Lookup.swift Sources/Retro.swift Sources/RetroExtras.swift Sources/Organize.swift Sources/Queue.swift Sources/Place.swift Sources/Originals.swift Sources/Extras.swift Sources/Notes.swift Sources/Smart.swift Sources/LibraryData.swift Sources/Meta.swift Sources/Phone.swift Sources/Xcode.swift Sources/Engine.swift Sources/Update.swift Sources/Offload.swift Tests/integration/main.swift -o "$T/itests"
  mkdir "$T/real"; ln -s "$HOME/Docked/engine" "$T/real/engine"; ln -s "$HOME/Docked/venv" "$T/real/venv"
  DOCKED_ROOT="$T/real" "$T/itests"
fi
# With a payload: the same checks using only the carried tools, with Homebrew and any other Docked install blocked.
if [ -n "${PAYLOAD:-}" ]; then
  mkdir "$T/all"; tar -xJf "$PAYLOAD" -C "$T/all"
  printf '(version 1)(allow default)(deny file-read* file-write* (subpath "/opt/homebrew") (subpath "/usr/local") (subpath "%s/Docked") (subpath "/Library/Developer/CommandLineTools"))' "$HOME" > "$T/block.sb"
  DOCKED_ROOT="$T/all" sandbox-exec -f "$T/block.sb" "$T/itests"
fi
./Tests/queue/run.sh
