#!/usr/bin/env swift
// Renders the app icon and the menu bar glyph from Resources/logo.svg.
//
//   swift Tools/make-icon.swift
//   iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

import AppKit
import Foundation

let canvas: CGFloat = 1024
let logoURL = URL(fileURLWithPath: "Resources/logo.svg")

guard let logo = NSImage(contentsOf: logoURL) else {
    print("error: could not load \(logoURL.path)")
    exit(1)
}

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Full icon at 1024; callers scale the context rather than re-laying anything out.
func drawIcon() {
    let bounds = NSRect(x: 0, y: 0, width: canvas, height: canvas)
    let plate = rounded(bounds, canvas * 0.2246)   // the macOS icon-grid corner radius

    // Near-white plate, so the black logo reads exactly as drawn.
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.90, green: 0.90, blue: 0.92, alpha: 1)
    ])!
    gradient.draw(in: plate, angle: -90)

    // A hairline keeps the icon from dissolving into white backgrounds.
    NSColor(white: 0, alpha: 0.10).setStroke()
    plate.lineWidth = canvas * 0.006
    plate.stroke()

    // Logo centred, leaving the usual macOS margin.
    let inset = canvas * 0.17
    logo.draw(in: bounds.insetBy(dx: inset, dy: inset),
              from: .zero,
              operation: .sourceOver,
              fraction: 1.0)
}

/// Just the glyph in black on transparency, for use as a menu bar template image.
func drawGlyph(side: CGFloat) {
    let bounds = NSRect(x: 0, y: 0, width: side, height: side)
    logo.draw(in: bounds.insetBy(dx: side * 0.02, dy: side * 0.02),
              from: .zero,
              operation: .sourceOver,
              fraction: 1.0)
}

func render(size: Int, _ body: (CGFloat) -> Void) -> Data {
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
    body(CGFloat(size))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

// MARK: - App icon

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                              (256, 1), (256, 2), (512, 1), (512, 2)]

for (points, scale) in variants {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)\(scale == 1 ? "" : "@2x").png"
    let data = render(size: pixels) { side in
        NSGraphicsContext.current?.cgContext.scaleBy(x: side / canvas, y: side / canvas)
        drawIcon()
    }
    try data.write(to: iconset.appendingPathComponent(name))
    print("wrote \(name) (\(pixels)px)")
}

// MARK: - Menu bar template

let menuBar = URL(fileURLWithPath: "Resources/MenuBarIcon.png")
try render(size: 36) { drawGlyph(side: $0) }.write(to: menuBar)
print("wrote \(menuBar.lastPathComponent) (36px, 18pt @2x)")
