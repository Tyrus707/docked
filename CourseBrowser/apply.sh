#!/bin/zsh
# Puts the in-game Course Browser into an engine tree: the patches in engine-patches/, in order, on top of the reviewed engine.
#   CourseBrowser/apply.sh <engine dir>          apply them (the tree must be the plain engine)
#   CourseBrowser/apply.sh --check <git checkout> [commit]   only test that they still apply to that commit (bump-engine.sh)
# A patch that no longer applies stops the build: an engine update must never quietly drop the in-game browser.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; P=("$HERE"/engine-patches/*.patch(N)); [ ${#P} -gt 0 ] || { echo "No course browser patches in $HERE/engine-patches."; exit 1; }
if [ "${1:-}" = --check ]; then
  E="$2"; G=(git -c core.hooksPath=/dev/null -C "$E"); W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
  $G archive "${3:-HEAD}" | tar -xf - -C "$W"; "$0" "$W"; exit
fi
E="$1"; [ -d "$E/dm/host" ] || { echo "$E is not an engine tree."; exit 1; }
for p in $P; do
  (cd "$E" && git apply --whitespace=nowarn "$p") || { echo "The course browser patch $(basename "$p") no longer applies to this engine. Refresh CourseBrowser/engine-patches before using it."; exit 1; }
done
