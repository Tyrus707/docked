#!/bin/zsh
# Bundle/dmg.sh Docked.app [Docked.dmg]: the download people open and drag to Applications.
# A window with Docked on the left, Applications on the right and an arrow between them. Needs a Mac (hdiutil, Finder).
# Docked.zip and Docked-Update.zip are made as before; this only adds the disk image beside them.
#   SIGN="Developer ID Application: …"  signs the app inside and the image (optional)
#   NOTARY=profile                       sends it to Apple and staples the ticket (optional; see `xcrun notarytool store-credentials`)
set -eu
APP="$1"; OUT="${2:-Docked.dmg}"
case "$APP" in /*) ;; *) APP="$PWD/$APP";; esac; case "$OUT" in /*) ;; *) OUT="$PWD/$OUT";; esac
HERE="$(cd "$(dirname "$0")/.." && pwd)"; VOL=Docked; MNT="/Volumes/$VOL"
[ -d "$APP/Contents" ] || { echo "no app at $APP"; exit 1; }
[ -e "$MNT" ] && { echo "$MNT is already open; eject it first"; exit 1; }
W=$(mktemp -d); trap 'hdiutil detach "$MNT" -quiet 2>/dev/null || true; rm -rf "$W"' EXIT

# What the window holds: the app, a link to Applications, and the picture behind them (both sizes in one file, for Retina)
S="$W/stage"; mkdir -p "$S/.background"
ditto "$APP" "$S/Docked.app"
ln -s /Applications "$S/Applications"
tiffutil -cathidpicheck "$HERE/Art/dmg/background.png" "$HERE/Art/dmg/background@2x.png" -out "$S/.background/background.tiff" >/dev/null
if [ -n "${SIGN:-}" ]; then codesign --force --options runtime --timestamp --sign "$SIGN" "$S/Docked.app"; fi
codesign --verify --strict "$S/Docked.app"

# A writable image first, so Finder can be told how the window looks; then it is compressed and made read-only
MB=$(( $(du -sm "$S" | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder "$S" -volname "$VOL" -fs HFS+ -format UDRW -size ${MB}m "$W/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$W/rw.dmg"
# Icon centres match Art/dmg/draw.py. Finder may ask once whether this Terminal can control it.
osascript <<OSA || echo "warning: Finder could not lay out the window (allow Terminal under Privacy & Security › Automation); the image still works"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 840, 548}
    set o to icon view options of container window
    set arrangement of o to not arranged
    set icon size of o to 128
    set text size of o to 13
    set background picture of o to file ".background:background.tiff"
    set position of item "Docked.app" of container window to {170, 190}
    set position of item "Applications" of container window to {470, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
# The disk's own icon, added once Finder is done with the window (it was lost when set before)
cp "$S/Docked.app/Contents/Resources/AppIcon.icns" "$MNT/.VolumeIcon.icns"
SetFile -a C "$MNT" 2>/dev/null || xattr -wx com.apple.FinderInfo "0000000000000000040000000000000000000000000000000000000000000000" "$MNT" 2>/dev/null || true
rm -rf "$MNT/.fseventsd" "$MNT/.Trashes" 2>/dev/null || true
chmod -Rf go-w "$MNT" 2>/dev/null || true; sync
for i in 1 2 3 4 5; do hdiutil detach "$MNT" -quiet && break || sleep 2; done
rm -f "$OUT"; hdiutil convert -quiet "$W/rw.dmg" -format ULFO -o "$OUT"
if [ -n "${SIGN:-}" ]; then codesign --force --timestamp --sign "$SIGN" "$OUT"; fi
if [ -n "${NOTARY:-}" ]; then xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY" --wait && xcrun stapler staple "$OUT"; fi
hdiutil verify -quiet "$OUT"
ls -la "$OUT" | awk '{print $5" bytes"}'; shasum -a 256 "$OUT" | cut -c1-64
