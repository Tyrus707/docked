#!/bin/zsh
# One-time setup for Dockside. Safe to run again. Never uses sudo.
# Third-party: Homebrew python@3.14, glslang and zstd; nxnative at one reviewed commit; its pinned Python packages.
set -eu
ROOT="${DOCKSIDE_ROOT:-$HOME/Dockside}"
HERE="$(cd "$(dirname "$0")" && pwd)"; PINS="$HERE/ENGINE_PIN"
[ -f "$PINS" ] || { echo "ENGINE_PIN is missing beside setup.sh."; exit 1; }
PIN=$(awk '$1=="commit"{print $2}' "$PINS"); [ ${#PIN} = 40 ] || { echo "ENGINE_PIN names no commit."; exit 1; }
case "$ROOT" in *" "*) echo "The folder must not contain spaces: $ROOT"; exit 1;; esac
[ "$(uname -m)" = arm64 ] || { echo "Dockside needs an Apple silicon Mac (M1 or newer)."; exit 1; }
export PATH="/opt/homebrew/bin:$PATH"
command -v brew >/dev/null || { echo "Homebrew is missing. Install it from https://brew.sh, then run this again."; exit 1; }
export HOMEBREW_NO_AUTO_UPDATE=1
for f in python@3.14 glslang zstd; do brew list --versions "$f" >/dev/null 2>&1 || brew install "$f"; done
mkdir -p "$ROOT/Games" "$ROOT/Inputs"
if [ ! -d "$ROOT/engine/.git" ]; then git init -q "$ROOT/engine"; fi
G=(git -c core.hooksPath=/dev/null -C "$ROOT/engine")
if [ "$($G rev-parse -q --verify HEAD 2>/dev/null || true)" != "$PIN" ]; then
  $G fetch --depth 1 https://github.com/seedds/nxnative.git "$PIN"
  $G checkout -q --detach "$PIN"
fi
[ "$($G rev-parse HEAD)" = "$PIN" ] || { echo "The engine is not the reviewed version."; exit 1; }
# The prebuilt tools whose fingerprints were recorded at review (ENGINE_PIN).
awk '$1=="tool"{print $2, $3}' "$PINS" | while read -r f h; do
  [ "$(shasum -a 256 "$ROOT/engine/$f" | cut -c1-64)" = "$h" ] || { echo "Fingerprint mismatch: $f"; exit 1; }
done
[ -x "$ROOT/venv/bin/python3" ] || /opt/homebrew/opt/python@3.14/bin/python3.14 -m venv "$ROOT/venv"
"$ROOT/venv/bin/python3" -m pip install --disable-pip-version-check --only-binary :all: -r "$ROOT/engine/.github/requirements/tools.txt"
echo "Setup finished. Go back to Dockside and press Check Again."
