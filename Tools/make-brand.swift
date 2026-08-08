#!/usr/bin/env swift
// Renders every brand asset from Resources/logo.svg.
//
//   swift Tools/make-brand.swift ["tagline for the OG card"]
//
// Everything lands in assets/brand/. The look is deliberately plain: a near-white
// plate, the black ⌘V mark, and system type. One mark, one colour, no decoration.

import AppKit
import Foundation

// MARK: - Design tokens

enum Brand {
    /// The macOS icon-grid corner radius, as a fraction of the plate's width.
    static let cornerRatio: CGFloat = 0.2246
    /// Margin around the mark inside its plate, as a fraction of the plate's width.
    static let markInset: CGFloat = 0.17

    static let plateTop = NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)
    static let plateBottom = NSColor(srgbRed: 0.90, green: 0.90, blue: 0.92, alpha: 1)

    static let ink = NSColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1)
    static let inkInverse = NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    static let muted = NSColor(srgbRed: 0.43, green: 0.43, blue: 0.47, alpha: 1)
    static let mutedInverse = NSColor(srgbRed: 0.63, green: 0.63, blue: 0.67, alpha: 1)

    static let pageLight = NSColor(srgbRed: 0.976, green: 0.976, blue: 0.980, alpha: 1)
    static let pageDark = NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)

    static let hairline = NSColor(white: 0, alpha: 0.10)
}

let outputDir = URL(fileURLWithPath: "assets/brand")
let logoURL = URL(fileURLWithPath: "Resources/logo.svg")
let tagline = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Clipboard history for macOS"

guard let logo = NSImage(contentsOf: logoURL) else {
    print("error: could not load \(logoURL.path)")
    exit(1)
}
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

// MARK: - Drawing helpers

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// The app icon: near-white plate, hairline edge, centred mark.
func drawPlate(in bounds: NSRect) {
    let plate = rounded(bounds, bounds.width * Brand.cornerRatio)
    NSGradient(colors: [Brand.plateTop, Brand.plateBottom])!.draw(in: plate, angle: -90)

    // Keeps the icon from dissolving into a white page.
    Brand.hairline.setStroke()
    plate.lineWidth = max(1, bounds.width * 0.006)
    plate.stroke()

    let inset = bounds.width * Brand.markInset
    logo.draw(in: bounds.insetBy(dx: inset, dy: inset),
              from: .zero, operation: .sourceOver, fraction: 1.0)
}

/// A soft drop shadow, applied to whatever the body draws.
func withShadow(blur: CGFloat, offsetY: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: -offsetY)
    shadow.shadowColor = NSColor(white: 0, alpha: alpha)
    shadow.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func attributes(size: CGFloat, weight: NSFont.Weight, color: NSColor, kern: CGFloat = 0) -> [NSAttributedString.Key: Any] {
    [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: kern
    ]
}

/// Draws `text` with its left edge at x and its visual centre at midY.
@discardableResult
func draw(_ text: String, at x: CGFloat, midY: CGFloat, _ attrs: [NSAttributedString.Key: Any]) -> CGFloat {
    let string = NSAttributedString(string: text, attributes: attrs)
    let size = string.size()
    string.draw(at: NSPoint(x: x, y: midY - size.height / 2))
    return size.width
}

/// Draws `text` centred horizontally on the canvas.
@discardableResult
func drawCentred(_ text: String, width: CGFloat, midY: CGFloat, _ attrs: [NSAttributedString.Key: Any]) -> CGFloat {
    let string = NSAttributedString(string: text, attributes: attrs)
    let size = string.size()
    string.draw(at: NSPoint(x: (width - size.width) / 2, y: midY - size.height / 2))
    return size.width
}

func render(width: Int, height: Int, _ body: () -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    body()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ name: String) {
    let url = outputDir.appendingPathComponent(name)
    try! data.write(to: url)
    let kb = Double(data.count) / 1024
    print(String(format: "  %-28s %6.1f KB", (name as NSString).utf8String!, kb))
}

// MARK: - Icon set

print("icon")
for size in [1024, 512, 256, 128, 64, 32] {
    let data = render(width: size, height: size) {
        drawPlate(in: NSRect(x: 0, y: 0, width: size, height: size))
    }
    write(data, "icon-\(size).png")
}

// MARK: - Favicons

print("favicon")
for (size, name) in [(16, "favicon-16.png"), (32, "favicon-32.png"),
                     (180, "apple-touch-icon.png"), (192, "icon-192.png"),
                     (512, "icon-512.png")] {
    let data = render(width: size, height: size) {
        drawPlate(in: NSRect(x: 0, y: 0, width: size, height: size))
    }
    write(data, name)
}

// MARK: - Wordmark

/// Plated mark followed by the name, sized off a single `height` value.
func drawWordmark(height: CGFloat, canvasWidth: CGFloat, dark: Bool) {
    let mark = NSRect(x: 0, y: 0, width: height, height: height)
    withShadow(blur: height * 0.09, offsetY: height * 0.03, alpha: 0.12) {
        drawPlate(in: mark)
    }
    draw("Swift Paste",
         at: height * 1.26,
         midY: height * 0.5,
         attributes(size: height * 0.54,
                    weight: .semibold,
                    color: dark ? Brand.inkInverse : Brand.ink,
                    kern: height * -0.008))
}

/// Measured so the canvas fits the mark plus the name exactly.
func wordmarkWidth(height: CGFloat) -> CGFloat {
    let string = NSAttributedString(string: "Swift Paste",
                                    attributes: attributes(size: height * 0.54,
                                                           weight: .semibold,
                                                           color: .black,
                                                           kern: height * -0.008))
    return height * 1.26 + string.size().width + height * 0.06
}

print("wordmark")
for (suffix, dark) in [("light", false), ("dark", true)] {
    let height: CGFloat = 128
    let width = Int(ceil(wordmarkWidth(height: height)))
    let data = render(width: width, height: Int(height * 1.14)) {
        NSGraphicsContext.current?.cgContext.translateBy(x: 0, y: height * 0.07)
        drawWordmark(height: height, canvasWidth: CGFloat(width), dark: dark)
    }
    write(data, "wordmark-\(suffix).png")
}

// MARK: - Social card

/// 1200×630 Open Graph card: mark, name, tagline. Nothing else.
func drawSocialCard(width: CGFloat, height: CGFloat, dark: Bool) {
    (dark ? Brand.pageDark : Brand.pageLight).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let markSize: CGFloat = 168
    let markRect = NSRect(x: (width - markSize) / 2, y: height * 0.545, width: markSize, height: markSize)
    withShadow(blur: 34, offsetY: 12, alpha: dark ? 0.55 : 0.14) {
        drawPlate(in: markRect)
    }

    drawCentred("Swift Paste", width: width, midY: height * 0.415,
                attributes(size: 82, weight: .semibold,
                           color: dark ? Brand.inkInverse : Brand.ink, kern: -1.4))

    drawCentred(tagline, width: width, midY: height * 0.295,
                attributes(size: 34, weight: .regular,
                           color: dark ? Brand.mutedInverse : Brand.muted))

    drawCentred("swiftpaste.app", width: width, midY: height * 0.135,
                attributes(size: 24, weight: .medium,
                           color: dark ? Brand.mutedInverse.withAlphaComponent(0.75)
                                       : Brand.muted.withAlphaComponent(0.75), kern: 0.6))
}

print("social")
for (suffix, dark) in [("og", false), ("og-dark", true)] {
    let data = render(width: 1200, height: 630) {
        drawSocialCard(width: 1200, height: 630, dark: dark)
    }
    write(data, "\(suffix).png")
}

// MARK: - Download button

/// A real button image, because a markdown link cannot look like one. Drawn at 3×
/// and displayed at a third of the size, so it stays sharp on a retina screen.
func drawDownloadButton(scale: CGFloat, dark: Bool) -> (Int, Int, () -> Void) {
    let text = "Download for macOS"
    let fontSize = 15 * scale
    let attrs = attributes(size: fontSize, weight: .semibold,
                           color: dark ? Brand.ink : Brand.inkInverse, kern: 0.1 * scale)
    let textWidth = NSAttributedString(string: text, attributes: attrs).size().width

    let arrowBox = 16 * scale
    let gap = 9 * scale
    let padX = 22 * scale
    let height = 44 * scale
    let width = padX * 2 + arrowBox + gap + textWidth

    return (Int(width.rounded()), Int(height.rounded()), {
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let pill = NSBezierPath(roundedRect: bounds, xRadius: height / 2, yRadius: height / 2)
        (dark ? Brand.inkInverse : Brand.ink).setFill()
        pill.fill()

        // A downward arrow into a tray — the same idea as the system download glyph.
        let ink = dark ? Brand.ink : Brand.inkInverse
        ink.setStroke()
        let stroke = 1.9 * scale
        let cx = padX + arrowBox / 2
        let cy = height / 2

        let shaft = NSBezierPath()
        shaft.move(to: NSPoint(x: cx, y: cy + arrowBox * 0.42))
        shaft.line(to: NSPoint(x: cx, y: cy - arrowBox * 0.18))
        shaft.lineWidth = stroke
        shaft.lineCapStyle = .round
        shaft.stroke()

        let head = NSBezierPath()
        head.move(to: NSPoint(x: cx - arrowBox * 0.26, y: cy + arrowBox * 0.04))
        head.line(to: NSPoint(x: cx, y: cy - arrowBox * 0.22))
        head.line(to: NSPoint(x: cx + arrowBox * 0.26, y: cy + arrowBox * 0.04))
        head.lineWidth = stroke
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.stroke()

        let tray = NSBezierPath()
        tray.move(to: NSPoint(x: cx - arrowBox * 0.40, y: cy - arrowBox * 0.42))
        tray.line(to: NSPoint(x: cx + arrowBox * 0.40, y: cy - arrowBox * 0.42))
        tray.lineWidth = stroke
        tray.lineCapStyle = .round
        tray.stroke()

        draw(text, at: padX + arrowBox + gap, midY: cy + 0.5 * scale, attrs)
    })
}

print("button")
for (suffix, dark) in [("download-button", false), ("download-button-dark", true)] {
    let (width, height, body) = drawDownloadButton(scale: 3, dark: dark)
    write(render(width: width, height: height) { body() }, "\(suffix).png")
}

// MARK: - README header

/// A wide, quiet header strip: mark, name, tagline, centred.
print("header")
do {
    let w = 2400, h = 720
    let data = render(width: w, height: h) {
        Brand.pageLight.setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()

        let markSize: CGFloat = 208
        let markRect = NSRect(x: (CGFloat(w) - markSize) / 2, y: CGFloat(h) * 0.50,
                              width: markSize, height: markSize)
        withShadow(blur: 40, offsetY: 14, alpha: 0.13) { drawPlate(in: markRect) }

        drawCentred("Swift Paste", width: CGFloat(w), midY: CGFloat(h) * 0.355,
                    attributes(size: 104, weight: .semibold, color: Brand.ink, kern: -1.8))
        drawCentred(tagline, width: CGFloat(w), midY: CGFloat(h) * 0.215,
                    attributes(size: 42, weight: .regular, color: Brand.muted))
    }
    write(data, "header.png")
}

print("\ndone — assets/brand/")
