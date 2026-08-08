#!/usr/bin/env swift
// Puts a raw window capture on a branded backdrop: light plate, generous margin,
// one soft shadow. Nothing else — the app is the subject.
//
//   frame-shot in.png out.png [--pad 0.09] [--bg light|dark|none] [--shadow 0.16]
//              [--max-width 2400] [--radius 0]
//
// `--radius` re-rounds the corners, for captures that came back square.

import AppKit
import Foundation

var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    print("""
    usage: frame-shot <in.png> <out.png> [--pad f] [--bg light|dark|none] [--shadow f] [--max-width n] [--radius n]
           frame-shot --compose <out.png> <in.png:x,y,w,h> ... [same options]
    """)
    exit(2)
}

/// Compose mode places several window captures at their real screen offsets on one
/// backdrop. Capturing the rectangle that encloses two panels would photograph the
/// desktop showing between them; this keeps only the windows themselves.
let composing = arguments.first == "--compose"

func option(_ name: String, _ fallback: Double) -> Double {
    guard let index = arguments.firstIndex(of: "--\(name)"), index + 1 < arguments.count else { return fallback }
    return Double(arguments[index + 1]) ?? fallback
}

func stringOption(_ name: String, _ fallback: String) -> String {
    guard let index = arguments.firstIndex(of: "--\(name)"), index + 1 < arguments.count else { return fallback }
    return arguments[index + 1]
}

/// Margin around the capture, as a fraction of its longest side.
let padFraction = option("pad", 0.09)
let shadowAlpha = option("shadow", 0.16)
let maxWidth = option("max-width", 0)
let cornerRadius = option("radius", 0)
let background = stringOption("bg", "light")

/// One window capture plus where it sat on screen.
struct Layer {
    let image: NSImage
    let pixelWidth: CGFloat
    let pixelHeight: CGFloat
    /// Screen frame in points, top-left origin. Absent in single-image mode.
    let frame: CGRect?
}

func loadLayer(_ spec: String) -> Layer {
    // "path.png:x,y,w,h" — the geometry is optional.
    var path = spec
    var frame: CGRect?
    if let separator = spec.lastIndex(of: ":") {
        let tail = String(spec[spec.index(after: separator)...])
        let parts = tail.split(separator: ",").compactMap { Double($0) }
        if parts.count == 4 {
            path = String(spec[..<separator])
            frame = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        }
    }
    guard let image = NSImage(contentsOfFile: path),
          let rep = NSImageRep(contentsOfFile: path) else {
        print("error: could not read \(path)")
        exit(1)
    }
    return Layer(image: image,
                 pixelWidth: CGFloat(rep.pixelsWide),
                 pixelHeight: CGFloat(rep.pixelsHigh),
                 frame: frame)
}

let outputPath: String
var layers: [Layer] = []

if composing {
    guard arguments.count >= 3 else { print("--compose needs an output and at least one input"); exit(2) }
    outputPath = arguments[1]
    // Inputs run until the first option flag. Skipping flags instead of stopping at
    // them would treat each flag's value as another input.
    for spec in arguments.dropFirst(2) {
        if spec.hasPrefix("--") { break }
        layers.append(loadLayer(spec))
    }
    guard !layers.isEmpty else { print("--compose needs at least one input"); exit(2) }
    guard layers.allSatisfy({ $0.frame != nil }) else {
        print("--compose inputs need :x,y,w,h geometry"); exit(2)
    }
} else {
    outputPath = arguments[1]
    layers = [loadLayer(arguments[0])]
}

// Backing scale, derived from the first capture: window geometry arrives in points
// and the bitmaps are in pixels.
let scaleFactor: CGFloat = {
    guard let frame = layers[0].frame, frame.width > 0 else { return 1 }
    return layers[0].pixelWidth / frame.width
}()

/// Union of every layer, in points.
let unionFrame: CGRect = layers.compactMap(\.frame).dropFirst().reduce(
    layers.compactMap(\.frame).first ?? .zero
) { $0.union($1) }

let shotWidth = composing ? (unionFrame.width * scaleFactor).rounded() : layers[0].pixelWidth
let shotHeight = composing ? (unionFrame.height * scaleFactor).rounded() : layers[0].pixelHeight
let source = layers[0].image
let pad = (max(shotWidth, shotHeight) * padFraction).rounded()

var canvasWidth = shotWidth + pad * 2
var canvasHeight = shotHeight + pad * 2

// Downscale at the end if a cap was asked for, so the shadow stays proportional.
var outputScale: CGFloat = 1
if maxWidth > 0, canvasWidth > CGFloat(maxWidth) {
    outputScale = CGFloat(maxWidth) / canvasWidth
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int((canvasWidth * outputScale).rounded()),
    pixelsHigh: Int((canvasHeight * outputScale).rounded()),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: canvasWidth * outputScale, height: canvasHeight * outputScale)

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.cgContext.scaleBy(x: outputScale, y: outputScale)

let canvas = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)

switch background {
case "dark":
    NSGradient(colors: [
        NSColor(srgbRed: 0.102, green: 0.102, blue: 0.118, alpha: 1),
        NSColor(srgbRed: 0.043, green: 0.043, blue: 0.051, alpha: 1)
    ])!.draw(in: canvas, angle: -90)
case "none":
    NSColor.clear.setFill()
    canvas.fill()
default:
    NSGradient(colors: [
        NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 1),
        NSColor(srgbRed: 0.937, green: 0.937, blue: 0.949, alpha: 1)
    ])!.draw(in: canvas, angle: -90)
}

let shotRect = NSRect(x: pad, y: pad, width: shotWidth, height: shotHeight)

/// Shared shadow, sized off the whole composition so every panel matches.
func applyShadow() {
    let shadow = NSShadow()
    shadow.shadowBlurRadius = max(shotWidth, shotHeight) * 0.05
    shadow.shadowOffset = NSSize(width: 0, height: -max(shotWidth, shotHeight) * 0.014)
    shadow.shadowColor = NSColor(white: 0, alpha: shadowAlpha)
    shadow.set()
}

if composing {
    for layer in layers {
        guard let frame = layer.frame else { continue }
        // Screen frames are top-left origin; the canvas is bottom-left.
        let offsetX = (frame.minX - unionFrame.minX) * scaleFactor
        let offsetFromTop = (frame.minY - unionFrame.minY) * scaleFactor
        let height = frame.height * scaleFactor
        let rect = NSRect(x: pad + offsetX,
                          y: pad + shotHeight - offsetFromTop - height,
                          width: frame.width * scaleFactor,
                          height: height)

        NSGraphicsContext.saveGraphicsState()
        applyShadow()
        layer.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
} else {
    NSGraphicsContext.saveGraphicsState()
    applyShadow()

    if cornerRadius > 0 {
        let clip = NSBezierPath(roundedRect: shotRect, xRadius: cornerRadius, yRadius: cornerRadius)
        // Fill first so the shadow follows the rounded silhouette, not the square bitmap.
        NSColor.white.setFill()
        clip.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        source.draw(in: shotRect, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        source.draw(in: shotRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    print("error: could not encode PNG")
    exit(1)
}
try data.write(to: URL(fileURLWithPath: outputPath))

print(String(format: "%@  %.0f×%.0f  %.0f KB",
             (outputPath as NSString).lastPathComponent,
             canvasWidth * outputScale, canvasHeight * outputScale,
             Double(data.count) / 1024))
