#!/usr/bin/env swift
// Fills the history with a curated set of entries so screenshots and video look
// like a machine someone actually works on.
//
//   swift Tools/seed-demo.swift          seed (backs up real history first)
//   swift Tools/seed-demo.swift restore  put the real history back
//
// Swift Paste must not be running: it keeps the list in memory and would write
// over whatever this puts on disk. Tools/demo.sh handles the quit/seed/relaunch.

import AppKit
import CryptoKit
import Foundation

let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
let storeDir = support.appendingPathComponent("SwiftPaste", isDirectory: true)
let imagesDir = storeDir.appendingPathComponent("images", isDirectory: true)
let indexURL = storeDir.appendingPathComponent("history.json")
let backupDir = support.appendingPathComponent("SwiftPaste.real-history", isDirectory: true)

let fm = FileManager.default

// MARK: - Restore

if CommandLine.arguments.dropFirst().first == "restore" {
    guard fm.fileExists(atPath: backupDir.path) else {
        print("no backup at \(backupDir.path) — nothing to restore")
        exit(0)
    }
    try? fm.removeItem(at: storeDir)
    try fm.moveItem(at: backupDir, to: storeDir)
    print("restored your real history from \(backupDir.lastPathComponent)")
    exit(0)
}

// MARK: - Back up whatever is there now

// Only ever taken once. A second seed must not bury the real history under a
// backup of the previous demo.
if fm.fileExists(atPath: storeDir.path) && !fm.fileExists(atPath: backupDir.path) {
    try fm.copyItem(at: storeDir, to: backupDir)
    print("backed up your real history -> \(backupDir.path)")
} else if fm.fileExists(atPath: backupDir.path) {
    print("real history already backed up at \(backupDir.lastPathComponent) — leaving it alone")
}

try? fm.removeItem(at: storeDir)
try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

// MARK: - Demo images

func render(width: Int, height: Int, _ body: (CGFloat, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    body(CGFloat(width), CGFloat(height))
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func label(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color
    ]).draw(at: point)
}

// The artwork below is deliberately saturated. Each of these is 34×34 in the list,
// where a tasteful grey composition is indistinguishable from an empty row — colour
// is the only thing that reads at that size.

func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

func roundedFill(_ rect: NSRect, radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func gradientFill(_ rect: NSRect, radius: CGFloat, _ colors: [NSColor], angle: CGFloat = -60) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: colors)!.draw(in: rect, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
}

/// A palette card — the sort of thing that ends up on the clipboard mid-design-review.
let paletteRep = render(width: 1280, height: 800) { w, h in
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()

    let swatches: [(String, NSColor)] = [
        ("Cobalt", rgb(34, 102, 245)),
        ("Violet", rgb(122, 71, 240)),
        ("Rose", rgb(245, 71, 120)),
        ("Amber", rgb(250, 168, 33)),
        ("Teal", rgb(23, 184, 168))
    ]

    label("Brand palette", at: NSPoint(x: 100, y: h - 128), size: 42, weight: .semibold,
          color: NSColor(white: 0.06, alpha: 1))

    let cardW: CGFloat = 200, gap: CGFloat = 20
    for (index, swatch) in swatches.enumerated() {
        let x = 100 + CGFloat(index) * (cardW + gap)
        roundedFill(NSRect(x: x, y: 190, width: cardW, height: 380), radius: 24, swatch.1)
        label(swatch.0, at: NSPoint(x: x, y: 138), size: 23, weight: .medium,
              color: NSColor(white: 0.12, alpha: 1))
    }
}

/// A dashboard chart, in colour so the thumbnail is not a grey smudge.
let chartRep = render(width: 1200, height: 760) { w, h in
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()

    label("Weekly builds", at: NSPoint(x: 72, y: h - 118), size: 38, weight: .semibold,
          color: NSColor(white: 0.06, alpha: 1))
    label("Last 7 days", at: NSPoint(x: 72, y: h - 162), size: 22, weight: .regular,
          color: NSColor(white: 0.5, alpha: 1))

    let values: [CGFloat] = [0.42, 0.61, 0.38, 0.78, 0.55, 0.91, 0.66]
    let days = ["M", "T", "W", "T", "F", "S", "S"]
    let barW: CGFloat = 84, gap: CGFloat = 40
    let baseY: CGFloat = 130, maxH: CGFloat = 380

    NSColor(white: 0.92, alpha: 1).setStroke()
    for step in 0...4 {
        let y = baseY + maxH * CGFloat(step) / 4
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 72, y: y))
        line.line(to: NSPoint(x: w - 72, y: y))
        line.lineWidth = 1
        line.stroke()
    }

    for (index, value) in values.enumerated() {
        let x = 92 + CGFloat(index) * (barW + gap)
        let rect = NSRect(x: x, y: baseY, width: barW, height: maxH * value)
        gradientFill(rect, radius: 12, [rgb(96, 132, 255), rgb(34, 102, 245)], angle: 90)
        label(days[index], at: NSPoint(x: x + barW / 2 - 8, y: 80), size: 22, weight: .medium,
              color: NSColor(white: 0.45, alpha: 1))
    }
}

/// A poster export — the loudest thumbnail in the list, on purpose.
let posterRep = render(width: 1200, height: 900) { w, h in
    gradientFill(NSRect(x: 0, y: 0, width: w, height: h), radius: 0,
                 [rgb(255, 108, 92), rgb(158, 61, 240), rgb(34, 102, 245)], angle: -55)

    // A couple of soft blooms, so it does not read as a flat gradient.
    for (cx, cy, r, alpha) in [(280.0, 660.0, 300.0, 0.22), (900.0, 250.0, 360.0, 0.16)] {
        NSColor(white: 1, alpha: alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).fill()
    }

    label("Launch", at: NSPoint(x: 90, y: 430), size: 130, weight: .bold, color: .white)
    label("Spring release", at: NSPoint(x: 96, y: 360), size: 40, weight: .medium,
          color: NSColor(white: 1, alpha: 0.85))
}

/// An interface mock, the way a screenshot of a design tool would look.
let mockRep = render(width: 1240, height: 860) { w, h in
    rgb(244, 245, 248).setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()

    // Window plate.
    roundedFill(NSRect(x: 70, y: 70, width: w - 140, height: h - 140), radius: 26, .white)

    // Sidebar.
    gradientFill(NSRect(x: 70, y: 70, width: 250, height: h - 140), radius: 26,
                 [rgb(46, 54, 82), rgb(28, 33, 54)], angle: -90)
    for index in 0..<5 {
        let y = h - 210 - CGFloat(index) * 66
        roundedFill(NSRect(x: 106, y: y, width: 178, height: 30), radius: 8,
                    NSColor(white: 1, alpha: index == 1 ? 0.85 : 0.22))
    }

    // Content cards.
    let accents = [rgb(34, 102, 245), rgb(245, 71, 120), rgb(23, 184, 168), rgb(250, 168, 33)]
    for index in 0..<4 {
        let column = index % 2, row = index / 2
        let x = 370 + CGFloat(column) * 400
        let y = h - 330 - CGFloat(row) * 250
        roundedFill(NSRect(x: x, y: y, width: 350, height: 200), radius: 18, rgb(247, 248, 251))
        roundedFill(NSRect(x: x + 24, y: y + 132, width: 56, height: 44), radius: 12, accents[index])
        roundedFill(NSRect(x: x + 24, y: y + 96, width: 220, height: 18), radius: 6, rgb(214, 218, 228))
        roundedFill(NSRect(x: x + 24, y: y + 66, width: 150, height: 18), radius: 6, rgb(228, 231, 239))
    }
}

/// Writes a full-size PNG plus the 220px thumbnail the list draws.
func storeImage(_ rep: NSBitmapImageRep, stem: String) -> (image: String, thumb: String, bytes: Int, w: Int, h: Int) {
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: imagesDir.appendingPathComponent("\(stem).png"))

    let scale = min(1, 220 / CGFloat(max(rep.pixelsWide, rep.pixelsHigh)))
    let tw = Int((CGFloat(rep.pixelsWide) * scale).rounded())
    let th = Int((CGFloat(rep.pixelsHigh) * scale).rounded())
    let thumbRep = render(width: tw, height: th) { w, h in
        rep.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    }
    let thumb = thumbRep.representation(using: .png, properties: [:])!
    try! thumb.write(to: imagesDir.appendingPathComponent("\(stem)-thumb.png"))

    return ("\(stem).png", "\(stem)-thumb.png", png.count, rep.pixelsWide, rep.pixelsHigh)
}

let palette = storeImage(paletteRep, stem: "demo-palette")
let chart = storeImage(chartRep, stem: "demo-chart")
let poster = storeImage(posterRep, stem: "demo-poster")
let mock = storeImage(mockRep, stem: "demo-mock")

// MARK: - Entries

func sha(_ string: String) -> String {
    SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
}

let now = Date()
func ago(_ minutes: Double) -> String {
    let formatter = ISO8601DateFormatter()
    return formatter.string(from: now.addingTimeInterval(-minutes * 60))
}

/// Real paths, so the row shows the true Finder icon rather than a generic one.
let repo = fm.currentDirectoryPath
let filePaths = [
    "\(repo)/assets/brand/icon-512.png",
    "\(repo)/assets/brand/og.png",
    "\(repo)/README.md"
].filter { fm.fileExists(atPath: $0) }

func fileBytes(_ paths: [String]) -> Int {
    paths.reduce(0) { total, path in
        let attributes = try? fm.attributesOfItem(atPath: path)
        return total + ((attributes?[.size] as? Int) ?? 0)
    }
}

struct Entry {
    var kind: String
    var text: String
    var minutesAgo: Double
    var app: String
    var bundle: String
    var pinned: Bool = false
    var image: (image: String, thumb: String, bytes: Int, w: Int, h: Int)? = nil
    var files: [String]? = nil
}

let entries: [Entry] = [
    // Pinned — the things you keep reaching for.
    Entry(kind: "text", text: "git rebase --autosquash -i HEAD~5",
          minutesAgo: 640, app: "Terminal", bundle: "com.apple.Terminal", pinned: true),
    Entry(kind: "text", text: "swift build -c release && ./build.sh --install",
          minutesAgo: 1500, app: "Warp", bundle: "dev.warp.Warp-Stable", pinned: true),

    // Recent. The images sit high on purpose: the top of the list is what a
    // screenshot shows, and colour there is what makes it read as full.
    Entry(kind: "text", text: "https://developer.apple.com/documentation/appkit/nspasteboard",
          minutesAgo: 2, app: "Safari", bundle: "com.apple.Safari"),
    Entry(kind: "image", text: "", minutesAgo: 5, app: "Figma", bundle: "com.figma.Desktop",
          image: poster),
    Entry(kind: "image", text: "", minutesAgo: 9, app: "Figma", bundle: "com.figma.Desktop",
          image: palette),
    Entry(kind: "text", text: """
    func paste(_ item: ClipboardItem, plainText: Bool?) {
        monitor.acknowledgeOwnWrite()
        Paster.writeToPasteboard(item, store: store,
                                 plainTextOnly: plainText ?? settings.pastePlainText)
        store.touch(item)
    }
    """, minutesAgo: 13, app: "Code", bundle: "com.microsoft.VSCode"),
    Entry(kind: "image", text: "", minutesAgo: 18, app: "Figma", bundle: "com.figma.Desktop",
          image: mock),
    Entry(kind: "files", text: "", minutesAgo: 22, app: "Finder", bundle: "com.apple.finder",
          files: filePaths),
    Entry(kind: "text", text: "Can you send over the latest build when you get a sec?",
          minutesAgo: 28, app: "Slack", bundle: "com.tinyspeck.slackmacgap"),
    Entry(kind: "text", text: "SP-124  Popup should open on the same screen as the cursor",
          minutesAgo: 38, app: "Linear", bundle: "com.linear"),
    Entry(kind: "image", text: "", minutesAgo: 52, app: "Safari", bundle: "com.apple.Safari",
          image: chart),
    Entry(kind: "text", text: "~/Library/Application Support/SwiftPaste/",
          minutesAgo: 66, app: "Terminal", bundle: "com.apple.Terminal"),
    Entry(kind: "text", text: """
    ## Release checklist

    - [ ] Bump CFBundleShortVersionString
    - [ ] Tag and push
    - [ ] Check the Actions run went green
    """, minutesAgo: 95, app: "Obsidian", bundle: "md.obsidian"),
    Entry(kind: "text", text: "https://github.com/xvertile/SwiftPaste/releases/latest",
          minutesAgo: 140, app: "Chrome", bundle: "com.google.Chrome"),
    Entry(kind: "text", text: "Thanks for the quick turnaround on this — merged and shipping today.",
          minutesAgo: 190, app: "Mail", bundle: "com.apple.mail"),
    Entry(kind: "text", text: "NSPasteboard.general.changeCount",
          minutesAgo: 250, app: "Xcode", bundle: "com.apple.dt.Xcode"),
    Entry(kind: "text", text: "Standup moved to 09:45 for the rest of the week",
          minutesAgo: 320, app: "Notes", bundle: "com.apple.Notes"),
    Entry(kind: "files", text: "", minutesAgo: 400, app: "Finder", bundle: "com.apple.finder",
          files: Array(filePaths.prefix(1))),
    Entry(kind: "text", text: "codesign --force --sign - --identifier io.bytezero.SwiftPaste",
          minutesAgo: 520, app: "Terminal", bundle: "com.apple.Terminal")
]

// MARK: - Encode

var json: [[String: Any]] = []

for entry in entries {
    var object: [String: Any] = [
        "id": UUID().uuidString,
        "kind": entry.kind,
        "createdAt": ago(entry.minutesAgo),
        "pinned": entry.pinned,
        "sourceAppName": entry.app,
        "sourceBundleID": entry.bundle
    ]

    switch entry.kind {
    case "text":
        object["text"] = entry.text
        object["byteCount"] = entry.text.utf8.count
        object["fingerprint"] = sha("text:" + entry.text)

    case "image":
        guard let image = entry.image else { continue }
        object["text"] = ""
        object["imageFile"] = image.image
        object["thumbFile"] = image.thumb
        object["pixelWidth"] = image.w
        object["pixelHeight"] = image.h
        object["byteCount"] = image.bytes
        object["fingerprint"] = sha("image:" + image.image)

    case "files":
        guard let files = entry.files, !files.isEmpty else { continue }
        let joined = files.joined(separator: "\n")
        object["text"] = joined
        object["byteCount"] = fileBytes(files)
        object["fingerprint"] = sha("files:" + joined)

    default:
        continue
    }

    json.append(object)
}

// Pinned first, then newest — the same order the app sorts into.
let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .withoutEscapingSlashes])
try data.write(to: indexURL, options: .atomic)

print("seeded \(json.count) entries -> \(indexURL.path)")
print("  \(entries.filter(\.pinned).count) pinned, "
      + "\(entries.filter { $0.kind == "image" }.count) images, "
      + "\(entries.filter { $0.kind == "files" }.count) file entries")
