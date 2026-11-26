#!/bin/zsh
# engine-release.sh: publishes the engine in ENGINE_PIN to players as a signed engine update, so every Docked can update its engine without a new app.
# For Docked's maker, after bump-engine.sh and a conversion or two. Needs: the engine checked out at ~/Docked/engine, gh signed in, and the signing key
# in DOCKED_SIGNING_KEY or in the Keychain (security add-generic-password -s docked-signing-key -a docked -w <key>). The key never goes in the repository.
# It uploads to one release, tagged "engine" and marked as a pre-release so GitHub's "latest" stays the newest Docked:
#   engine-<commit>.tar.xz              the whole engine, for any Docked
#   engine-<from>-<commit>.tar.xz       only what changed since an engine players may have (the one each recent Docked carries, and the last engine update)
#   engine.json, engine.json.sig        what Docked reads first: the engine's commit, date, fingerprint and files, signed. Uploaded last.
# MINAPP=1.8 sets the oldest Docked that may take it (default: the version in Info.plist). SUMMARY="..." sets the line players see.
set -eu
cd "$(dirname "$0")"; HERE=$PWD
PIN=$(awk '$1=="commit"{print $2}' ENGINE_PIN); DATE=$(awk '$1=="date"{print $2}' ENGINE_PIN)
MINAPP="${MINAPP:-$(plutil -extract CFBundleShortVersionString raw Info.plist)}"
E="$HOME/Docked/engine"; G=(git -c core.hooksPath=/dev/null -C "$E")
[ "$($G rev-parse HEAD)" = "$PIN" ] || { echo "~/Docked/engine is not at ${PIN:0:8}. Run bump-engine.sh first."; exit 1; }
KEY="${DOCKED_SIGNING_KEY:-$(security find-generic-password -s docked-signing-key -w 2>/dev/null || true)}"; [ -n "$KEY" ] || { echo "No signing key: set DOCKED_SIGNING_KEY or add it to the Keychain."; exit 1; }
PUB=$(sed -n 's/.*static let publicKey = "\(.*\)".*/\1/p' Sources/Update.swift)
[ "$(DOCKED_SIGNING_KEY="$KEY" swift Bundle/sign.swift --public)" = "$PUB" ] || { echo "That key is not the one whose public half is in Sources/Update.swift."; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
# An engine exactly as committed, as Bundle/make.sh carries it
lay() { mkdir -p "$2/engine"; $G archive "$1" | tar -xf - -C "$2/engine"; rm -rf "$2/engine/docs/images" "$2/engine/.github"; }
# Play with friends goes in as Bundle/make.sh puts it in. Older engines in players' hands may or may not have it, so a difference from one is offered only when
# its tree matches (Engine.swift falls back to the full engine otherwise)
layf() { lay "$1" "$2"; ./Friends/apply.sh "$2/engine"; }
pack() { (cd "$1" && COPYFILE_DISABLE=1 tar -cJf "$2" engine*) }   # no AppleDouble files: Docked checks every file
layf "$PIN" "$W/new"; read TREE FILES <<< "$(python3 -I Bundle/engine_tree.py tree "$W/new/engine")"
C=${PIN:0:12}; pack "$W/new" "$W/engine-$C.tar.xz"
# Which engines players may have: those recent Docked versions carried, and the one the last engine update gave them
froms=$(for c in $(git log --format=%H -n 30 -- ENGINE_PIN Sources/Core.swift); do git show "$c:ENGINE_PIN" 2>/dev/null | awk '$1=="commit"{print $2}'; git show "$c:Sources/Core.swift" 2>/dev/null | sed -n 's/^let pinnedEngine = "\(.*\)"/\1/p'; done)
gh release download engine -p engine.json -D "$W/old" 2>/dev/null && froms+=$'\n'$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$W/old/engine.json")
froms=$(print -r -- "$froms" | awk 'length($0)==40' | grep -vx "$PIN" | awk '!seen[$0]++' | head -6)
deltas="[]"
for F in ${(f)froms}; do
  $G fetch -q --depth 1 https://github.com/seedds/nxnative.git "$F" || { echo "skipping ${F:0:8}: not fetchable"; continue; }
  if ! $G diff --quiet "$F" "$PIN" -- .github/requirements/tools.txt; then echo "The engine wants other Python packages than ${F:0:8} has. Players need a full Docked release for it. Nothing was published."; exit 1; fi
  lay "$F" "$W/old-$F"; ./Friends/apply.sh "$W/old-$F/engine" >/dev/null 2>&1 || { rm -rf "$W/old-$F"; lay "$F" "$W/old-$F"; }   # with Play with friends, as Docked carries engines now
  read FT _ <<< "$(python3 -I Bundle/engine_tree.py tree "$W/old-$F/engine")"
  mkdir "$W/d-$F"; echo "from ${F:0:8}: $(python3 -I Bundle/engine_tree.py delta "$W/old-$F/engine" "$W/new/engine" "$W/d-$F")"
  N="engine-${F:0:12}-$C.tar.xz"; pack "$W/d-$F" "$W/$N"
  deltas=$(python3 -I -c 'import json,sys,hashlib,os; d=json.loads(sys.argv[1]); f=sys.argv[2]; d.append({"name":os.path.basename(f),"sha256":hashlib.sha256(open(f,"rb").read()).hexdigest(),"bytes":os.path.getsize(f),"from":sys.argv[3],"fromTree":sys.argv[4]}); print(json.dumps(d))' "$deltas" "$W/$N" "$F" "$FT")
done
# What players are told: given, or counted from the game profiles
if [ -z "${SUMMARY:-}" ] && [ -n "$froms" ]; then
  L=$(print -r -- "$froms" | head -1)
  SUMMARY="$($G diff --name-only --diff-filter=A "$L" "$PIN" -- dm/games | awk -F/ '$4=="game.tsv"' | wc -l | tr -d ' ') new game profiles and $($G diff --name-only "$L" "$PIN" -- dm/games | awk -F/ '{print $3}' | sort -u | wc -l | tr -d ' ') updated, with fixes."
fi
python3 -I - "$W" "$PIN" "$DATE" "$MINAPP" "$TREE" "${SUMMARY:-Fixes and game profiles.}" "$W/engine-$C.tar.xz" "$deltas" <<'PY'
import hashlib, json, os, sys
w, commit, date, minapp, tree, summary, full, deltas = sys.argv[1:]
m = {"format": 1, "commit": commit, "date": date, "minApp": minapp, "tree": tree, "summary": summary,
     "full": {"name": os.path.basename(full), "sha256": hashlib.sha256(open(full, "rb").read()).hexdigest(), "bytes": os.path.getsize(full)}, "deltas": json.loads(deltas)}
open(os.path.join(w, "engine.json"), "w").write(json.dumps(m, indent=1, sort_keys=True) + "\n")
PY
DOCKED_SIGNING_KEY="$KEY" swift Bundle/sign.swift "docked-engine-v1|" "$W/engine.json" > "$W/engine.json.sig"
DOCKED_PUBLIC_KEY="$PUB" swift Bundle/sign.swift --check "docked-engine-v1|" "$W/engine.json" "$W/engine.json.sig"
cat "$W/engine.json"; ls -la "$W"/*.tar.xz | awk '{print $5, $9}'
printf "Publish this engine to every Docked? [y/N] "; read -r ok; [ "$ok" = y ] || { echo "Nothing was published."; exit 1; }
gh release view engine >/dev/null 2>&1 || gh release create engine --prerelease --latest=false --title "Conversion engine" --notes "Engine updates for Docked. Docked downloads and checks these itself: there is nothing here to install by hand."
gh release upload engine "$W"/*.tar.xz --clobber
gh release upload engine "$W/engine.json" "$W/engine.json.sig" --clobber   # last: Docked never sees a version file before its files are there
keep=$(cd "$W" && ls *.tar.xz engine.json engine.json.sig)
for a in $(gh release view engine --json assets -q '.assets[].name'); do print -r -- "$keep" | grep -qxF "$a" || gh release delete-asset engine "$a" -y; done
echo "Published ${PIN:0:8}. Docked offers it at its next launch, or under Settings, Setup, Check Now."
