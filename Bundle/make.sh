#!/bin/zsh
# Makes Docked's payload: the reviewed engine, Python with its packages, glslang and zstd, in one archive.
# Everything is copied from what is already installed and reviewed here; nothing is downloaded. Reads only.
set -eu
OUT="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"
PIN=$(awk '$1=="commit"{print $2}' "$HERE/../ENGINE_PIN")
[ "$(git -C "$HOME/Docked/engine" rev-parse HEAD)" = "$PIN" ] || { echo "engine is not the reviewed version"; exit 1; }
# The prebuilt tools are the ones reviewed with it
awk '$1=="tool"{print $2, $3}' "$HERE/../ENGINE_PIN" | while read -r f h; do [ "$(git -C "$HOME/Docked/engine" show "$PIN:$f" | shasum -a 256 | cut -c1-64)" = "$h" ] || { echo "fingerprint mismatch: $f"; exit 1; }; done
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; P="$W/tools"; mkdir -p "$P/bin" "$P/lib"
# The engine exactly as committed (not the working copy, which builds write into).
mkdir "$P/engine"; git -C "$HOME/Docked/engine" archive "$PIN" | tar -xf - -C "$P/engine"; rm -rf "$P/engine/docs/images" "$P/engine/.github"
# Play with friends (Friends/engine-patches): part of every game Docked converts, off until the player turns it on in that game's settings
"$HERE/../Friends/apply.sh" "$P/engine"
# The in-game Course Browser (CourseBrowser/engine-patches): dormant in a converted game until Docked launches it with a private browser folder
"$HERE/../CourseBrowser/apply.sh" "$P/engine"
# Python: a pinned, standalone build that runs on macOS 11 and later (see python-standalone/SOURCE.txt), with the packages already installed and reviewed here
PY="$HOME/Docked/python-standalone/cpython-3.14.10+20261124-aarch64-apple-darwin-install_only_stripped.tar.gz"
[ "$(shasum -a 256 "$PY" | cut -c1-64)" = 81fca81fcc8a715288fd12286b66bbdaaf4a0db6818bc91826ddbcffae2ac2cf ] || { echo "Python is not the reviewed file"; exit 1; }
mkdir -p "$W/py" "$P/python/bin" "$P/python/lib"; tar -xzf "$PY" -C "$W/py"
rsync -a --exclude test --exclude idlelib --exclude ensurepip --exclude tkinter --exclude turtledemo --exclude __pycache__ --exclude site-packages --exclude 'config-*' --exclude '_tkinter*' "$W/py/python/lib/python3.14" "$P/python/lib/"
rsync -a --exclude __pycache__ --exclude pip --exclude 'pip-*' --exclude tests "$HOME/Docked/venv/lib/python3.14/site-packages" "$P/python/lib/python3.14/"
cp "$W/py/python/bin/python3.14" "$P/python/bin/python3"; chmod 755 "$P/python/bin/python3"; codesign --force --sign - "$P/python/bin/python3" 2>/dev/null; cp "$W/py/python/lib/python3.14/LICENSE.txt" "$P/LICENSE-python.txt" 2>/dev/null || true
# glslang and zstd
for n in glslangValidator zstd; do o=$(readlink -f /opt/homebrew/bin/$n); cp "$o" "$P/bin/$n"; chmod 755 "$P/bin/$n"; python3 "$HERE/relocate.py" "$P/bin/$n" "$o" "$P/lib" @executable_path/../lib; done
ln -s ../python/bin/python3 "$P/bin/python3"
cp "$P/engine/LICENSE" "$P/LICENSE-nxnative.txt"; echo "$PIN" > "$P/.dockside-pin"
# The macOS these tools need, read from the files themselves. The OpenGL helper is left out of it: only OpenGL games use it.
find "$P" -type f \( -perm +111 -o -name '*.so' -o -name '*.dylib' \) ! -name 'glslangValidator' ! -name 'libglslang*' ! -name 'libSPIRV*' -print0 | xargs -0 -n1 otool -l 2>/dev/null | awk '/minos/{print $2}' | sort -t. -k1,1n -k2,2n | tail -1 > "$P/.tools-minimum"; [ -s "$P/.tools-minimum" ] || { echo "no minimum found"; exit 1; }
# Nothing may still point at this Mac.
bad=$(find "$P/python" "$P/bin" "$P/lib" -type f \( -perm +111 -o -name '*.so' -o -name '*.dylib' \) -exec sh -c 'file -b "$1" | grep -q Mach-O && otool -L "$1" | tail -n +2 | grep -E "/opt/homebrew|/Users/" && echo "^ $1"' _ {} \;)
[ -z "$bad" ] || { echo "$bad"; echo "still refers to this Mac"; exit 1; }
if grep -rlE '^(master_key|titlekek|bis_key)_[0-9a-f]{2} *=' "$P" --include='*.keys' --include='*.txt'; then echo "keys found"; exit 1; fi
# No owner names (they would carry this Mac's account name) and no macOS metadata or ._ files in the archive.
export COPYFILE_DISABLE=1; ANON=(--uid 0 --gid 0 --uname root --gname wheel --no-xattrs --no-mac-metadata)
du -sh "$P"; XZ_OPT="-6 -T4" tar "${ANON[@]}" -cJf "$OUT" --options 'xz:compression-level=6,xz:threads=4' -C "$W" tools 2>/dev/null || tar "${ANON[@]}" -cJf "$OUT" -C "$W" tools
ls -la "$OUT" | awk '{print $5" bytes"}'; shasum -a 256 "$OUT" | cut -c1-64
