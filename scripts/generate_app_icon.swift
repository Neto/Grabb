#!/usr/bin/env swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
// Made by Design/MakeIcon.swift (neon style shared with Spin).
let source = root.appendingPathComponent("Design/AppIconSource.png")
let outDir = root.appendingPathComponent("Grabb/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

guard let sourceImage = NSImage(contentsOf: source), sourceImage.isValid else {
    fputs("Failed to load \(source.path)\n", stderr)
    exit(1)
}

struct Slot {
    let size: Int
    let scale: Int
    let idiomSize: String
    var filename: String { "icon_\(idiomSize)@\(scale)x.png" }
}

let slots: [Slot] = [
    Slot(size: 16, scale: 1, idiomSize: "16"),
    Slot(size: 32, scale: 2, idiomSize: "16"),
    Slot(size: 32, scale: 1, idiomSize: "32"),
    Slot(size: 64, scale: 2, idiomSize: "32"),
    Slot(size: 128, scale: 1, idiomSize: "128"),
    Slot(size: 256, scale: 2, idiomSize: "128"),
    Slot(size: 256, scale: 1, idiomSize: "256"),
    Slot(size: 512, scale: 2, idiomSize: "256"),
    Slot(size: 512, scale: 1, idiomSize: "512"),
    Slot(size: 1024, scale: 2, idiomSize: "512"),
]

func savePNG(_ source: NSImage, pixelSize: Int, to url: URL) throws {
    let bit = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bit.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: bit) else {
        fputs("No graphics context\n", stderr)
        exit(1)
    }
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    source.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bit.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode PNG \(url.lastPathComponent)\n", stderr)
        exit(1)
    }
    try data.write(to: url)
}

var contents: [[String: String]] = []
for slot in slots {
    let url = outDir.appendingPathComponent(slot.filename)
    try savePNG(sourceImage, pixelSize: slot.size, to: url)
    contents.append([
        "filename": slot.filename,
        "idiom": "mac",
        "scale": "\(slot.scale)x",
        "size": "\(slot.idiomSize)x\(slot.idiomSize)",
    ])
}

let json: [String: Any] = [
    "images": contents,
    "info": ["author": "xcode", "version": 1],
]
let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
try jsonData.write(to: outDir.appendingPathComponent("Contents.json"))
print("App icon written to \(outDir.path)")
