#!/usr/bin/env swift
// Renders the Swift Paste app icon and writes an .iconset next to Resources/.
// Every shape is drawn from scratch, so nothing here is licensed artwork.
//
//   swift Tools/make-icon.swift
//   iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

import AppKit
import Foundation

let canvas: CGFloat = 1024

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// One icon at full 1024 resolution; callers scale the whole context instead of
/// re-laying anything out, so every size stays identical in proportion.
func drawIcon() {
    // Background: rounded square with the macOS icon-grid corner radius.
    let plate = rounded(NSRect(x: 0, y: 0, width: canvas, height: canvas), canvas * 0.2246)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.36, blue: 0.98, alpha: 1),   // indigo
        NSColor(srgbRed: 0.66, green: 0.33, blue: 0.93, alpha: 1)    // violet
    ])!
    gradient.draw(in: plate, angle: -90)

    // Soft highlight across the top third.
    NSGraphicsContext.saveGraphicsState()
    plate.setClip()
    let sheen = NSGradient(colors: [
        NSColor(white: 1, alpha: 0.22),
        NSColor(white: 1, alpha: 0.0)
    ])!
    sheen.draw(in: NSRect(x: 0, y: canvas * 0.55, width: canvas, height: canvas * 0.45), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Clipboard body.
    let body = NSRect(x: 286, y: 168, width: 452, height: 600)
    NSColor(white: 0.06, alpha: 0.16).setFill()
    rounded(body.offsetBy(dx: 0, dy: -14), 74).fill()
    NSColor.white.setFill()
    rounded(body, 74).fill()

    // The clip at the top, drawn over the body so they read as one piece.
    let clipOuter = NSRect(x: 402, y: 706, width: 220, height: 132)
    NSColor.white.setFill()
    rounded(clipOuter, 46).fill()

    let clipInner = NSRect(x: 452, y: 744, width: 120, height: 66)
    NSColor(srgbRed: 0.47, green: 0.35, blue: 0.96, alpha: 1).setFill()
    rounded(clipInner, 33).fill()

    // Lightning bolt cut into the clipboard face — the "swift" half of the name.
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: 580, y: 656))
    bolt.line(to: NSPoint(x: 372, y: 440))
    bolt.line(to: NSPoint(x: 492, y: 440))
    bolt.line(to: NSPoint(x: 444, y: 262))
    bolt.line(to: NSPoint(x: 652, y: 478))
    bolt.line(to: NSPoint(x: 532, y: 478))
    bolt.close()

    let boltGradient = NSGradient(colors: [
        NSColor(srgbRed: 0.40, green: 0.33, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.71, green: 0.35, blue: 0.94, alpha: 1)
    ])!
    boltGradient.draw(in: bolt, angle: -90)
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let scale = CGFloat(size) / canvas
    context.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

let outputDirectory = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// (point size, scale) pairs required by iconutil.
let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                              (256, 1), (256, 2), (512, 1), (512, 2)]

for (points, scale) in variants {
    let pixels = points * scale
    let suffix = scale == 1 ? "" : "@2x"
    let name = "icon_\(points)x\(points)\(suffix).png"
    try render(size: pixels).write(to: outputDirectory.appendingPathComponent(name))
    print("wrote \(name) (\(pixels)px)")
}
