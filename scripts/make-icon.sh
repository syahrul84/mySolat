#!/bin/bash
# Builds AppIcon.icns from Resources/logo.png.
#
# The source logo is not square and has a full-bleed green background, so it gets
# composited onto a 1024×1024 canvas and clipped to the macOS rounded-rect ("app
# icon") silhouette before the .icns ladder is generated. No Xcode asset catalog
# and no image tooling beyond what ships with macOS.
set -euo pipefail

OUT="${1:-build/AppIcon.icns}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGO="$ROOT/Resources/logo.png"

[ -f "$LOGO" ] || { echo "error: $LOGO not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

cat > "$WORK/draw.swift" <<'SWIFT'
import AppKit

// argv: <logo.png> <output.png>
let logoPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

let side: CGFloat = 1024
// macOS app icons sit inside a rounded rect that occupies ~82% of the tile, with
// a corner radius near 22.4% of the icon's own width.
let margin: CGFloat = side * 0.09
let tile = CGRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
let radius = tile.width * 0.2237

guard let source = NSImage(contentsOfFile: logoPath),
      let sourceRep = NSBitmapImageRep(data: source.tiffRepresentation ?? Data())
else {
    FileHandle.standardError.write("error: could not read logo\n".data(using: .utf8)!)
    exit(1)
}

/// Background colour, sampled from a corner pixel so the padding matches the art.
let background: CGColor = {
    if let c = sourceRep.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB) {
        return CGColor(red: c.redComponent, green: c.greenComponent,
                       blue: c.blueComponent, alpha: 1)
    }
    return CGColor(red: 0.16, green: 0.44, blue: 0.27, alpha: 1)
}()

let output = NSImage(size: NSSize(width: side, height: side))
output.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

ctx.interpolationQuality = .high
ctx.saveGState()

// Clip everything to the rounded tile, then fill and draw the art inside it.
ctx.addPath(CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()

ctx.setFillColor(background)
ctx.fill(tile)

// Aspect-fit the logo inside the tile so no part of the dome is cropped.
let logoSize = CGSize(width: CGFloat(sourceRep.pixelsWide), height: CGFloat(sourceRep.pixelsHigh))
let scale = min(tile.width / logoSize.width, tile.height / logoSize.height)
let drawSize = CGSize(width: logoSize.width * scale, height: logoSize.height * scale)
let drawRect = CGRect(
    x: tile.midX - drawSize.width / 2,
    y: tile.midY - drawSize.height / 2,
    width: drawSize.width,
    height: drawSize.height
)
sourceRep.draw(in: drawRect)

ctx.restoreGState()

// A hairline inner edge keeps the icon from vanishing into a dark Dock.
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 0.5, dy: 0.5),
                   cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.18))
ctx.setLineWidth(1.5)
ctx.strokePath()

output.unlockFocus()

guard let tiff = output.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else { exit(1) }

try png.write(to: URL(fileURLWithPath: outPath))
SWIFT

MASTER="$WORK/icon_1024.png"
swiftc -O -o "$WORK/draw" "$WORK/draw.swift"
"$WORK/draw" "$LOGO" "$MASTER"

# Standard .icns resolution ladder.
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$MASTER" --out "$ICONSET/icon_$2.png" >/dev/null
done

mkdir -p "$(dirname "$OUT")"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "✓ $OUT"
