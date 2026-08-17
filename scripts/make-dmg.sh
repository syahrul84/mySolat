#!/bin/bash
# Builds a compressed drag-to-install DMG from an .app bundle.
#
#   scripts/make-dmg.sh build/mySolat.app dist/mySolat-1.0.0.dmg mySolat
set -euo pipefail

APP="${1:?usage: make-dmg.sh <app> <output.dmg> [volume name]}"
OUT="${2:?usage: make-dmg.sh <app> <output.dmg> [volume name]}"
VOLNAME="${3:-$(basename "$APP" .app)}"

[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"; hdiutil detach "/Volumes/$VOLNAME" >/dev/null 2>&1 || true' EXIT

mkdir -p "$STAGE/src"
cp -R "$APP" "$STAGE/src/"
ln -s /Applications "$STAGE/src/Applications"

# A short README inside the image explains the unsigned-app first-launch step.
cat > "$STAGE/src/README.txt" <<'TXT'
mySolat — Malaysian prayer times in your menu bar

To install:
  1. Drag mySolat into the Applications folder alias here.
  2. Open Applications, right-click mySolat and choose "Open".
     (macOS asks for this once because the app isn't notarized by Apple.
      Every later launch, and every auto-update, works normally.)

Look for the crescent-moon icon in your menu bar — mySolat has no Dock icon.

Source and issues: https://github.com/syahrul/mySolat
TXT

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"

RW="$STAGE/rw.dmg"
# Size the image from the payload plus headroom for the filesystem.
SIZE_KB=$(du -sk "$STAGE/src" | cut -f1)
SIZE_MB=$(( SIZE_KB / 1024 + 24 ))

hdiutil create -srcfolder "$STAGE/src" -volname "$VOLNAME" \
  -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$RW" >/dev/null

# Set a sensible icon layout so the window looks intentional when opened.
DEV="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | grep -E '^/dev/' | head -1 | awk '{print $1}')"
sleep 1
osascript >/dev/null 2>&1 <<APPLESCRIPT || true
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 150, 760, 480}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set position of item "$(basename "$APP")" of container window to {140, 150}
    set position of item "Applications" of container window to {410, 150}
    set position of item "README.txt" of container window to {410, 290}
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

echo "✓ $OUT"
