#!/bin/zsh
# bump-engine.sh [commit or branch, default main]: moves Docked to a newer nxnative, after showing what changed. For Docked's maker, not for players.
# It fetches the commit into ~/Docked/engine, lists the new and changed game profiles, stops if a prebuilt tool changed (look at it, then run again with
# ACCEPT_TOOLS=1), updates the Python packages if the engine asks for others, writes ENGINE_PIN and the copy in Sources/Core.swift, and runs ./test.sh.
# Then convert one or two of your own games with a Docked built here (./build.sh), and publish it to players with ./engine-release.sh.
set -eu
cd "$(dirname "$0")"
WANT="${1:-main}"; E="$HOME/Docked/engine"; G=(git -c core.hooksPath=/dev/null -C "$E")
[ -d "$E/.git" ] || { echo "No engine checkout at $E. Run setup.sh once first."; exit 1; }
OLD=$(awk '$1=="commit"{print $2}' ENGINE_PIN)
$G fetch -q --depth 1 https://github.com/seedds/nxnative.git "$OLD"
$G fetch -q --depth 1 https://github.com/seedds/nxnative.git "$WANT"; NEW=$($G rev-parse FETCH_HEAD)
[ "$NEW" != "$OLD" ] || { echo "Docked already uses $OLD."; exit 0; }
DATE=$(TZ=UTC0 $G show -s --date=format-local:%Y-%m-%dT%H:%M:%SZ --format=%cd "$NEW")
[[ "$DATE" > "$(awk '$1=="date"{print $2}' ENGINE_PIN)" ]] || { echo "$NEW is not newer than the engine Docked uses."; exit 1; }
echo "nxnative ${OLD:0:8} -> ${NEW:0:8} ($DATE): $($G log --oneline "$OLD..$NEW" 2>/dev/null | wc -l | tr -d ' ') commits (fewer shown if the history is shallow)"
# Game profiles: which games now have one, and which changed
name() { $G show "$NEW:dm/games/$1/game.tsv" 2>/dev/null | sed -n '1s/^# *//p' | cut -c1-90; }
added=$($G diff --name-only --diff-filter=A "$OLD" "$NEW" -- dm/games | awk -F/ '$4=="game.tsv"{print $3}' | sort -u)
changed=$($G diff --name-only "$OLD" "$NEW" -- dm/games | awk -F/ '{print $3}' | sort -u | grep -vxF -f <(print -r -- "$added") || true)
echo "\nNew game profiles: $(print -r -- "$added" | grep -c . || true)"; for t in ${(f)added}; do echo "  $t  $(name $t)"; done
echo "Changed game profiles: $(print -r -- "$changed" | grep -c . || true)"; for t in ${(f)changed}; do echo "  $t  $(name $t)"; done
# What changed for apps like Docked (nxnative docs/frontends.md, "Following main"): the authors' Front-ends: lines, and the files that make the interface
$G fetch -q --shallow-since="$(awk '$1=="date"{print $2}' ENGINE_PIN)" https://github.com/seedds/nxnative.git "$NEW" 2>/dev/null || true
fe=$($G log --format=%B "$OLD..$NEW" 2>/dev/null | grep '^Front-ends:' || true)
echo "\nNotes for front ends: $(print -r -- "$fe" | grep -c . || true)"; [ -n "$fe" ] && print -r -- "$fe" | sed 's/^Front-ends: */  /'
for f in docs/frontends.md docs/launcher.schema.json dm/games/settings.tsv docs/env_switches.tsv; do $G diff --quiet "$OLD" "$NEW" -- "$f" 2>/dev/null || echo "  changed: $f (git -C $E diff ${OLD:0:8} ${NEW:0:8} -- $f)"; done
opts=$($G diff "$OLD" "$NEW" -- scripts/build_ipa_from_nsp.py | grep -E '^[-+].*add_argument' || true); [ -n "$opts" ] && { echo "  build script options:"; print -r -- "$opts" | sed 's/^/    /'; }
if print -r -- "$fe" | grep -qi '^Front-ends: *break'; then
  [ "${ACCEPT_BREAK:-}" = 1 ] || { echo "Upstream says something apps rely on stopped working (break: above). Check Docked against it, then run again with ACCEPT_BREAK=1."; exit 1; }
fi
# Prebuilt tools: their fingerprints were recorded at review, and a new one is code nobody here has built
tools=$(awk '$1=="tool"{print $2}' ENGINE_PIN); lines=""; moved=""
for f in ${(f)tools}; do h=$($G show "$NEW:$f" | shasum -a 256 | cut -c1-64); lines+="tool $f $h\n"; [ "$h" = "$(awk -v f="$f" '$1=="tool" && $2==f {print $3}' ENGINE_PIN)" ] || moved+="  $f\n"; done
others=$($G diff --name-only --diff-filter=AM "$OLD" "$NEW" | grep -E '_bin/' | grep -vxF -f <(print -r -- "$tools") || true)
if [ -n "$moved$others" ]; then
  echo "\nPrebuilt tools that changed:"; printf "$moved"; [ -n "$others" ] && echo "$others" | sed 's/^/  (new) /'
  [ "${ACCEPT_TOOLS:-}" = 1 ] || { echo "Look at upstream's notes for them, then run again with ACCEPT_TOOLS=1."; exit 1; }
  for f in ${(f)others}; do lines+="tool $f $($G show "$NEW:$f" | shasum -a 256 | cut -c1-64)\n"; done   # recorded from now on, like the others
fi
# Play with friends must come along: stop before anything changes when its patches no longer fit
./Friends/apply.sh --check "$E" "$NEW" || { echo "Nothing was changed. Refresh Friends/engine-patches for ${NEW:0:8} first (Friends/README.md)."; exit 1; }
# The engine in ~/Docked/engine, and its Python packages if they changed
$G checkout -q --detach "$NEW"
if ! $G diff --quiet "$OLD" "$NEW" -- .github/requirements/tools.txt; then
  echo "\nThe engine wants other Python packages. Installing them in ~/Docked/venv. Players need a full Docked release (Bundle/make.sh) for this engine; engine-release.sh will refuse it."
  "$HOME/Docked/venv/bin/python3" -m pip install --disable-pip-version-check --only-binary :all: -r "$E/.github/requirements/tools.txt"
fi
# ENGINE_PIN and the app's copy
{ sed -n '/^#/p' ENGINE_PIN; echo "commit $NEW"; echo "date $DATE"; printf "$lines"; } > ENGINE_PIN.new && mv ENGINE_PIN.new ENGINE_PIN
sed -i '' -e "s/^let pinnedEngine = \".*\"/let pinnedEngine = \"$NEW\"/" -e "s/^let pinnedEngineDate = \".*\"/let pinnedEngineDate = \"$DATE\"/" Sources/Core.swift
echo "\nENGINE_PIN and Sources/Core.swift now name ${NEW:0:8}. Running the tests…"
./test.sh
echo "\nNext: build Docked here (./build.sh), convert one or two of your own games, then publish it with ./engine-release.sh and commit."
