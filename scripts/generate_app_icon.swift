#!/usr/bin/env swift
//
// generate_app_icon.swift
//
// Renders the SmartClose app icon (a minimal white "close" monogram on a blue→violet
// gradient squircle) at every macOS app-icon size and writes the asset catalog
// `AppIcon.appiconset` (PNGs + Contents.json) plus the parent `Assets.xcassets/Contents.json`.
//
// Headless and reproducible — uses CoreGraphics + ImageIO only (no AppKit / no NSApplication),
// so it runs from the command line or CI.
//
// Usage:
//   swift scripts/generate_app_icon.swift [path/to/Assets.xcassets]
// Defaults to SmartCloseApp/Resources/Assets.xcassets relative to the repo root.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Drawing

private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

private func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

private func renderIcon(pixelSize: Int) -> CGImage? {
    let size = CGFloat(pixelSize)
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Rounded "squircle" inset from the canvas, following Apple's icon grid (~10% margin).
    let margin = size * 0.092
    let rect = CGRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let radius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Background gradient + a soft top sheen, both clipped to the squircle.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    let base = CGGradient(
        colorsSpace: sRGB,
        colors: [color(0.20, 0.40, 0.95), color(0.49, 0.23, 0.93)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        base,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    let sheen = CGGradient(
        colorsSpace: sRGB,
        colors: [color(1, 1, 1, 0.18), color(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        sheen,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.45),
        options: []
    )
    ctx.restoreGState()

    // White "×" close monogram, centered.
    let glyph = rect.insetBy(dx: rect.width * 0.30, dy: rect.height * 0.30)
    ctx.setStrokeColor(color(1, 1, 1))
    ctx.setLineWidth(rect.width * 0.115)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: glyph.minX, y: glyph.minY))
    ctx.addLine(to: CGPoint(x: glyph.maxX, y: glyph.maxY))
    ctx.move(to: CGPoint(x: glyph.minX, y: glyph.maxY))
    ctx.addLine(to: CGPoint(x: glyph.maxX, y: glyph.minY))
    ctx.strokePath()

    return ctx.makeImage()
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "generate_app_icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination at \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "generate_app_icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG at \(url.path)"])
    }
}

// MARK: - Asset catalog layout

private struct IconEntry {
    let fileName: String
    let pixelSize: Int
    let size: String
    let scale: String
}

private let entries: [IconEntry] = [
    IconEntry(fileName: "icon_16x16.png", pixelSize: 16, size: "16x16", scale: "1x"),
    IconEntry(fileName: "icon_16x16@2x.png", pixelSize: 32, size: "16x16", scale: "2x"),
    IconEntry(fileName: "icon_32x32.png", pixelSize: 32, size: "32x32", scale: "1x"),
    IconEntry(fileName: "icon_32x32@2x.png", pixelSize: 64, size: "32x32", scale: "2x"),
    IconEntry(fileName: "icon_128x128.png", pixelSize: 128, size: "128x128", scale: "1x"),
    IconEntry(fileName: "icon_128x128@2x.png", pixelSize: 256, size: "128x128", scale: "2x"),
    IconEntry(fileName: "icon_256x256.png", pixelSize: 256, size: "256x256", scale: "1x"),
    IconEntry(fileName: "icon_256x256@2x.png", pixelSize: 512, size: "256x256", scale: "2x"),
    IconEntry(fileName: "icon_512x512.png", pixelSize: 512, size: "512x512", scale: "1x"),
    IconEntry(fileName: "icon_512x512@2x.png", pixelSize: 1024, size: "512x512", scale: "2x"),
]

private func appIconContentsJSON() -> String {
    let images = entries.map { entry in
        """
            {
              "filename" : "\(entry.fileName)",
              "idiom" : "mac",
              "scale" : "\(entry.scale)",
              "size" : "\(entry.size)"
            }
        """
    }.joined(separator: ",\n")

    return """
    {
      "images" : [
    \(images)
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
}

private let topLevelContentsJSON = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""

// MARK: - Main

let fm = FileManager.default

let assetsPath: String
if CommandLine.arguments.count > 1 {
    assetsPath = CommandLine.arguments[1]
} else {
    let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    assetsPath = scriptURL
        .deletingLastPathComponent() // repo root (scripts/ -> root)
        .appendingPathComponent("SmartCloseApp/Resources/Assets.xcassets")
        .path
}

let assetsURL = URL(fileURLWithPath: assetsPath)
let appIconURL = assetsURL.appendingPathComponent("AppIcon.appiconset")

do {
    try fm.createDirectory(at: appIconURL, withIntermediateDirectories: true)

    for entry in entries {
        guard let image = renderIcon(pixelSize: entry.pixelSize) else {
            FileHandle.standardError.write(Data("Failed to render \(entry.fileName)\n".utf8))
            exit(1)
        }
        try writePNG(image, to: appIconURL.appendingPathComponent(entry.fileName))
    }

    try appIconContentsJSON().write(to: appIconURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    try topLevelContentsJSON.write(to: assetsURL.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    print("Wrote \(entries.count) icon images to \(appIconURL.path)")
} catch {
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
