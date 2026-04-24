#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

OUTPUT_ICNS="${1:-Resources/mach.icns}"
OUTPUT_DIR="$(dirname "${OUTPUT_ICNS}")"

TMP_DIR="$(mktemp -d)"
ICONSET_DIR="${TMP_DIR}/mach.iconset"
BASE_PNG="${TMP_DIR}/base-1024.png"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${ICONSET_DIR}"
mkdir -p "${OUTPUT_DIR}"

swift - "${BASE_PNG}" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let canvasSize: CGFloat = 1024
let canvasRect = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)

let image = NSImage(size: canvasRect.size)
image.lockFocus()

NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.14, alpha: 1.0).setFill()
NSBezierPath(roundedRect: canvasRect, xRadius: 220, yRadius: 220).fill()

let glowCenter = NSPoint(x: canvasSize * 0.5, y: canvasSize * 0.8)
let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.33, green: 0.74, blue: 0.93, alpha: 0.45),
    NSColor(calibratedRed: 0.33, green: 0.74, blue: 0.93, alpha: 0.0)
])
glow?.draw(fromCenter: glowCenter, radius: 460, toCenter: glowCenter, radius: 0, options: [])

let frameRect = NSRect(x: 144, y: 220, width: 736, height: 500)
NSColor(calibratedWhite: 0.95, alpha: 1.0).setStroke()
let framePath = NSBezierPath(roundedRect: frameRect, xRadius: 64, yRadius: 64)
framePath.lineWidth = 28
framePath.stroke()

let rows = 4
let cols = 7
let keyWidth: CGFloat = 72
let keyHeight: CGFloat = 72
let keyGapX: CGFloat = 22
let keyGapY: CGFloat = 24
let startX = frameRect.minX + 54
let startY = frameRect.minY + 70

for row in 0..<rows {
    for col in 0..<cols {
        let x = startX + CGFloat(col) * (keyWidth + keyGapX)
        let y = startY + CGFloat(row) * (keyHeight + keyGapY)
        let keyRect = NSRect(x: x, y: y, width: keyWidth, height: keyHeight)

        let keyPath = NSBezierPath(roundedRect: keyRect, xRadius: 16, yRadius: 16)

        if row == rows - 1 && col == cols - 2 {
            NSColor(calibratedRed: 0.33, green: 0.74, blue: 0.93, alpha: 1.0).setFill()
        } else {
            NSColor(calibratedWhite: 0.93, alpha: 1.0).setFill()
        }
        keyPath.fill()
    }
}

let spaceRect = NSRect(x: startX + 2 * (keyWidth + keyGapX), y: startY - 88, width: 3 * keyWidth + 2 * keyGapX, height: 54)
NSColor(calibratedWhite: 0.93, alpha: 1.0).setFill()
NSBezierPath(roundedRect: spaceRect, xRadius: 14, yRadius: 14).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let pngData = rep.representation(using: .png, properties: [:])
else {
    fputs("Failed to generate base icon PNG\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fputs("Failed to write icon PNG: \(error)\n", stderr)
    exit(1)
}
SWIFT

resize_png() {
    local size="$1"
    local outputName="$2"
    sips -z "${size}" "${size}" "${BASE_PNG}" --out "${ICONSET_DIR}/${outputName}" >/dev/null
}

resize_png 16   icon_16x16.png
resize_png 32   icon_16x16@2x.png
resize_png 32   icon_32x32.png
resize_png 64   icon_32x32@2x.png
resize_png 128  icon_128x128.png
resize_png 256  icon_128x128@2x.png
resize_png 256  icon_256x256.png
resize_png 512  icon_256x256@2x.png
resize_png 512  icon_512x512.png
resize_png 1024 icon_512x512@2x.png

iconutil --convert icns "${ICONSET_DIR}" --output "${OUTPUT_ICNS}"

echo "Generated icon: ${OUTPUT_ICNS}"
