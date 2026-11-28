#!/bin/zsh
set -eu
cd "$(dirname "$0")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# One engine pin: ENGINE_PIN, and the app's copy of it
[ "$(sed -n 's/^let pinnedEngine = "\(.*\)"/\1/p' Sources/Core.swift) $(sed -n 's/^let pinnedEngineDate = "\(.*\)"/\1/p' Sources/Core.swift)" = "$(awk '$1=="commit"{c=$2} $1=="date"{d=$2} END{print c, d}' ENGINE_PIN)" ] || { echo "FAIL: Sources/Core.swift and ENGINE_PIN name different engines"; exit 1; }
# The in-game browser is an engine patch, not a separate app. It must still fit the pinned engine.
if [ -d "$HOME/Docked/engine" ]; then ./CourseBrowser/apply.sh --check "$HOME/Docked/engine" "$(awk '$1=="commit"{print $2}' ENGINE_PIN)" >/dev/null || { echo "FAIL: the Course Browser patch no longer applies"; exit 1; }; fi
# Docked's macOS File menu is the only way in. No in-game key, no second menu item.
if grep -qiE 'F6|keyCode|setAssign|dm_course_browser_request|front_mac' CourseBrowser/engine-patches/*.patch; then echo "FAIL: the engine patch still has an in-game shortcut or a second host file"; exit 1; fi
if ! grep -q 'DM_COURSE_BROWSER' CourseBrowser/engine-patches/*.patch || ! grep -q 'g_cb_wanted = 1; g_cb_retry = 20;' CourseBrowser/engine-patches/*.patch; then echo "FAIL: the engine patch has no menu-launched browser hook"; exit 1; fi
if ! grep -q 'Super Mario Maker 2 Course Browser…' Sources/App.swift; then echo "FAIL: the macOS File menu has no Course Browser launch"; exit 1; fi
if grep -q 'Course Browser…' Sources/Saves.swift; then echo "FAIL: the Saves menu still opens the browser; use the File menu only"; exit 1; fi
# Everything but the windows: the tests build it with their own main. A new file goes here, or in APP_ONLY when it only makes sense inside the app.
SRC=(); for n in Core Notify Builder Review Estimate Place Install Originals Pipeline LibraryData Meta Consoles Disc Lookup Retro RetroExtras Organize Artwork Queue Cleanup Extras Notes Smart Navigate Update Arrive Phone Xcode Engine Verify GameSettings Offload GameData Compat Friends Health Links Netplay Keychain Streaming StreamingInstall StreamingProcess StreamingAPI StreamingPermissions TVDisplay SMM2Courses SMM2Crypto SMM2CoursePreview CourseBrowserBridge; do SRC+=("Sources/$n.swift"); done
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
  grep -q 'DM_COURSE_BROWSER' "$T/all/tools/engine/dm/host/hle_web.c" && ! grep -qiE 'F6|keyCode|dm_course_browser_request' "$T/all/tools/engine/dm/host/hle_web.c" && ! grep -q 'dm_course_browser_request' "$T/all/tools/engine/dm/host/front_mac.m" || { echo "FAIL: the payload engine has no menu-only in-game Course Browser"; exit 1; }
  printf '(version 1)(allow default)(deny file-read* file-write* (subpath "/opt/homebrew") (subpath "/usr/local") (subpath "%s/Docked") (subpath "/Library/Developer/CommandLineTools"))' "$HOME" > "$T/block.sb"
  DOCKED_ROOT="$T/all" sandbox-exec -f "$T/block.sb" "$T/itests"
fi
./Tests/queue/run.sh
