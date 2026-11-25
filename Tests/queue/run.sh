#!/bin/zsh
# The queue and clean-up test. Uses nothing of the player's: a throwaway folder, its own settings.
set -eu
cd "$(dirname "$0")/../.."; T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; R="$T/root"; mkdir -p "$R/tools/bin" "$R/tools/engine/scripts" "$R/Games" "$T/src"
cp Tests/queue/engine.py "$R/tools/bin/python3"; chmod 755 "$R/tools/bin/python3"; for t in glslangValidator zstd xcodegen; do cp /usr/bin/true "$R/tools/bin/$t"; done; touch "$R/tools/engine/scripts/build_ipa_from_nsp.py"; sed -n 's/^let pinnedEngine = "\(.*\)"/\1/p' Sources/Core.swift > "$R/tools/.dockside-pin"
cp Sources/*.swift "$T/src/"; sed -i '' 's/^@main struct/struct/' "$T/src/App.swift"; cp Tests/queue/main.swift "$T/src/main.swift"
swiftc -swift-version 5 -target arm64-apple-macos13.0 "$T"/src/*.swift -o "$T/dockedqueuetest" 2>&1 | grep -E 'error:' || true
DOCKSIDE_ROOT="$R" "$T/dockedqueuetest"
