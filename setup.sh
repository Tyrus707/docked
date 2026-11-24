#!/bin/zsh
# One-time setup for Dockside. Safe to run again. Never uses sudo.
# Third-party: Homebrew python@3.14, glslang and zstd; nxnative at one reviewed commit; its pinned Python packages.
set -eu
ROOT="${DOCKSIDE_ROOT:-$HOME/Dockside}"
PIN=01439b0fe923929d275e2fd4337cbdf08b54fcfd
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
# The two prebuilt tools whose fingerprints were recorded at review, and the extractor.
check() { [ "$(shasum -a 256 "$ROOT/engine/$1" | cut -c1-64)" = "$2" ] || { echo "Fingerprint mismatch: $1"; exit 1; }; }
check dm/tools/nx_extract_bin/nx_extract 0a89455e0aa41df451bd9a6f05bb32fda7a92cddf93cafdaa9b8090bd3355f65
check dm/gfx/tools/dmsh_xlate_bin/dmsh_xlate 5c3099a7c611c2de0fa031b718d23f0cde91ff85b00a4dda47155185dabebfd6
check dm/gfx/tools/spirv_cross_bin/spirv-cross 76fd1e68297459488b2929bf5d656e40767a0840daa438368cb87fcaf3070a9e
[ -x "$ROOT/venv/bin/python3" ] || /opt/homebrew/opt/python@3.14/bin/python3.14 -m venv "$ROOT/venv"
"$ROOT/venv/bin/python3" -m pip install --disable-pip-version-check --only-binary :all: -r "$ROOT/engine/.github/requirements/tools.txt"
echo "Setup finished. Go back to Dockside and press Check Again."
