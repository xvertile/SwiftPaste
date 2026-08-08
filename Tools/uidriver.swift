#!/usr/bin/env swift
// Drives Swift Paste with synthetic input so screenshots and screen recordings
// can be produced the same way twice.
//
//   swift Tools/uidriver.swift mouse 900 500      move the pointer (top-left origin)
//   swift Tools/uidriver.swift open               tap ⌥ twice to open the history
//   swift Tools/uidriver.swift type "invoice"     type a string
//   swift Tools/uidriver.swift key down           press a named key
//   swift Tools/uidriver.swift chord cmd p        press a modified key
//   swift Tools/uidriver.swift windows            list on-screen Swift Paste windows
//   swift Tools/uidriver.swift sleep 0.4          wait
//
// Whichever process runs this needs Accessibility access, because posting events
// into other applications is exactly what that permission gates.

import AppKit
import CoreGraphics
import Foundation

let source = CGEventSource(stateID: .hidSystemState)

// MARK: - Keys

let keyCodes: [String: CGKeyCode] = [
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "esc": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34,
    "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12,
    "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    "0": 29, "comma": 43, "period": 47, "slash": 44
]

let modifierFlags: [String: CGEventFlags] = [
    "cmd": .maskCommand, "command": .maskCommand,
    "opt": .maskAlternate, "option": .maskAlternate, "alt": .maskAlternate,
    "ctrl": .maskControl, "control": .maskControl,
    "shift": .maskShift
]

/// Virtual key codes for the modifiers themselves, needed for the double-tap.
let modifierKeyCodes: [String: (CGKeyCode, CGEventFlags)] = [
    "option": (58, .maskAlternate),
    "command": (55, .maskCommand),
    "control": (59, .maskControl),
    "shift": (56, .maskShift)
]

func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
}

func wait(_ seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
}

func pressKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    down?.flags = flags
    post(down)
    wait(0.02)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    up?.flags = flags
    post(up)
}

/// A modifier press on its own, which the app sees as a flagsChanged event.
func tapModifier(_ name: String) {
    guard let (code, flag) = modifierKeyCodes[name] else { return }
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    down?.flags = flag
    post(down)
    wait(0.05)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    up?.flags = []
    post(up)
}

/// Types arbitrary text as unicode, so punctuation needs no keycode table.
func typeString(_ text: String, perCharacter: Double = 0.055) {
    for character in text {
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        var utf16 = Array(String(character).utf16)
        event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        post(event)

        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        post(up)
        wait(perCharacter)
    }
}

func moveMouse(x: Double, y: Double) {
    post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                 mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left))
}

func click(x: Double, y: Double) {
    let point = CGPoint(x: x, y: y)
    moveMouse(x: x, y: y)
    wait(0.08)
    post(CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                 mouseCursorPosition: point, mouseButton: .left))
    wait(0.04)
    post(CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                 mouseCursorPosition: point, mouseButton: .left))
}

// MARK: - Window discovery

struct PanelWindow {
    let id: CGWindowID
    let bounds: CGRect
    let layer: Int
}

/// Every on-screen window belonging to the app, largest first.
/// `minSide` filters out the status item, which is a window like any other.
func swiftPasteWindows(minSide: CGFloat = 40, owners: [String] = ["Swift Paste", "SwiftPaste"]) -> [PanelWindow] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return list.compactMap { entry -> PanelWindow? in
        guard let owner = entry[kCGWindowOwnerName as String] as? String,
              owners.contains(owner),
              let id = entry[kCGWindowNumber as String] as? CGWindowID,
              let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
              bounds.width >= minSide, bounds.height >= minSide
        else { return nil }
        let layer = entry[kCGWindowLayer as String] as? Int ?? 0
        return PanelWindow(id: id, bounds: bounds, layer: layer)
    }
    .sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
}

/// The menu bar button. A status item is drawn by the system rather than by the
/// app, so it never shows up in the window list — the accessibility tree is the
/// only place it can be found.
func statusItemRect() -> CGRect? {
    guard let app = NSRunningApplication
        .runningApplications(withBundleIdentifier: "io.bytezero.SwiftPaste").first else { return nil }
    let root = AXUIElementCreateApplication(app.processIdentifier)

    var extras: CFTypeRef?
    guard AXUIElementCopyAttributeValue(root, "AXExtrasMenuBar" as CFString, &extras) == .success,
          let menuBar = extras else { return nil }

    var childrenValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString,
                                        &childrenValue) == .success,
          let items = childrenValue as? [AXUIElement], let item = items.first else { return nil }

    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue) == .success
    else { return nil }

    var origin = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    return CGRect(origin: origin, size: size)
}

// MARK: - Waiting on state

/// The history panel, identified by its fixed size (Style.panelWidth × panelHeight).
/// Distinguishing it by size keeps the preview panel and the settings window from
/// being mistaken for it.
func popupPanel() -> PanelWindow? {
    swiftPasteWindows().first {
        abs($0.bounds.width - 420) < 6 && abs($0.bounds.height - 524) < 6
    }
}

@discardableResult
func waitUntil(timeout: Double, _ test: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if test() { return true }
        wait(0.07)
    }
    return test()
}

/// Opens the history and confirms it actually appeared. The double tap is easy to
/// miss — a stray key during the gap disqualifies it, and toggling an already-open
/// panel closes it — so this checks first and retries rather than assuming.
func ensurePopupOpen(modifier: String, attempts: Int = 5) -> Bool {
    for attempt in 1...attempts {
        if popupPanel() != nil { return true }
        tapModifier(modifier)
        wait(0.12)
        tapModifier(modifier)
        if waitUntil(timeout: 1.3, { popupPanel() != nil }) { return true }
        // Back off a little further each time; the app debounces taps.
        wait(0.3 * Double(attempt))
    }
    return popupPanel() != nil
}

/// Closes the history and confirms it went away.
func ensurePopupClosed(attempts: Int = 6) -> Bool {
    for _ in 1...attempts {
        if swiftPasteWindows().isEmpty { return true }
        guard let escape = keyCodes["escape"] else { return false }
        pressKey(escape)
        if waitUntil(timeout: 0.6, { swiftPasteWindows().isEmpty }) { return true }
    }
    return swiftPasteWindows().isEmpty
}

// MARK: - Accessibility

/// Presses a control by its label. Clicking tabs by guessed coordinates breaks the
/// moment a font or layout shifts; asking the accessibility tree for the control
/// named "History" does not.
func pressElement(titled wanted: String) -> Bool {
    guard let app = NSRunningApplication
        .runningApplications(withBundleIdentifier: "io.bytezero.SwiftPaste").first else { return false }

    let root = AXUIElementCreateApplication(app.processIdentifier)

    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    func search(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > 18 { return nil }
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            if let title = attribute(element, key) as? String, title == wanted {
                return element
            }
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children {
            if let hit = search(child, depth: depth + 1) { return hit }
        }
        return nil
    }

    guard let target = search(root, depth: 0) else { return false }
    return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
}

// MARK: - Commands

var arguments = Array(CommandLine.arguments.dropFirst())

guard !arguments.isEmpty else {
    print("usage: uidriver <command> [args]   (mouse|open|type|key|chord|click|windows|sleep)")
    exit(2)
}

// Posting into other apps is refused silently without this, which looks like the
// script simply not working — so say so up front.
if !AXIsProcessTrusted(), ["open", "type", "key", "chord", "click"].contains(arguments[0]) {
    FileHandle.standardError.write(Data("""
    uidriver: the process running this does not have Accessibility access.
    Grant it in System Settings › Privacy & Security › Accessibility, then retry.

    """.utf8))
    exit(3)
}

switch arguments[0] {
case "mouse":
    guard arguments.count >= 3, let x = Double(arguments[1]), let y = Double(arguments[2]) else {
        print("usage: mouse <x> <y>"); exit(2)
    }
    moveMouse(x: x, y: y)

case "click":
    guard arguments.count >= 3, let x = Double(arguments[1]), let y = Double(arguments[2]) else {
        print("usage: click <x> <y>"); exit(2)
    }
    click(x: x, y: y)

case "open":
    // Two clean taps inside the app's 0.45s window.
    let modifier = arguments.count > 1 ? arguments[1] : "option"
    tapModifier(modifier)
    wait(0.12)
    tapModifier(modifier)

case "type":
    guard arguments.count >= 2 else { print("usage: type <text>"); exit(2) }
    let speed = arguments.count >= 3 ? (Double(arguments[2]) ?? 0.055) : 0.055
    typeString(arguments[1], perCharacter: speed)

case "key":
    guard arguments.count >= 2, let code = keyCodes[arguments[1].lowercased()] else {
        print("usage: key <name>   known: \(keyCodes.keys.sorted().joined(separator: " "))"); exit(2)
    }
    let repeats = arguments.count >= 3 ? (Int(arguments[2]) ?? 1) : 1
    for index in 0..<max(1, repeats) {
        pressKey(code)
        if index < repeats - 1 { wait(0.09) }
    }

case "chord":
    guard arguments.count >= 3 else { print("usage: chord <mod[+mod]> <key>"); exit(2) }
    var flags: CGEventFlags = []
    for name in arguments[1].lowercased().split(separator: "+") {
        guard let flag = modifierFlags[String(name)] else {
            print("unknown modifier: \(name)"); exit(2)
        }
        flags.insert(flag)
    }
    guard let code = keyCodes[arguments[2].lowercased()] else {
        print("unknown key: \(arguments[2])"); exit(2)
    }
    pressKey(code, flags: flags)

case "windows":
    let windows = swiftPasteWindows(minSide: arguments.contains("--all") ? 8 : 40)
    if windows.isEmpty {
        print("none")
        exit(1)
    }
    for window in windows {
        // x y w h are what screencapture -R wants, in points.
        print("\(window.id) \(Int(window.bounds.origin.x)) \(Int(window.bounds.origin.y)) "
              + "\(Int(window.bounds.width)) \(Int(window.bounds.height)) layer=\(window.layer)")
    }

/// The rectangle enclosing every visible panel, for shots where the preview sits
/// alongside the list and both need to be in frame.
case "union":
    let windows = swiftPasteWindows()
    guard var union = windows.first?.bounds else { print("none"); exit(1) }
    for window in windows.dropFirst() { union = union.union(window.bounds) }
    print("\(Int(union.origin.x)) \(Int(union.origin.y)) \(Int(union.width)) \(Int(union.height))")

case "statusitem":
    guard let rect = statusItemRect() else { print("none"); exit(1) }
    print("\(Int(rect.origin.x)) \(Int(rect.origin.y)) \(Int(rect.width)) \(Int(rect.height))")

case "press":
    guard arguments.count >= 2 else { print("usage: press <control label>"); exit(2) }
    guard pressElement(titled: arguments[1]) else {
        FileHandle.standardError.write(Data("uidriver: no control labelled \"\(arguments[1])\"\n".utf8))
        exit(1)
    }

/// Exits 0 only once the history panel is genuinely on screen.
case "ensure-open":
    let modifier = arguments.count > 1 ? arguments[1] : "option"
    guard ensurePopupOpen(modifier: modifier) else {
        FileHandle.standardError.write(Data("uidriver: the history did not open\n".utf8))
        exit(1)
    }

case "ensure-closed":
    guard ensurePopupClosed() else {
        FileHandle.standardError.write(Data("uidriver: the history did not close\n".utf8))
        exit(1)
    }

case "popup-visible":
    exit(popupPanel() == nil ? 1 : 0)

/// Waits for any app window of roughly the given size — used for the settings window.
case "wait-window":
    guard arguments.count >= 3,
          let width = Double(arguments[1]), let height = Double(arguments[2]) else {
        print("usage: wait-window <width> <height> [timeout]"); exit(2)
    }
    let timeout = arguments.count >= 4 ? (Double(arguments[3]) ?? 4) : 4
    let found = waitUntil(timeout: timeout) {
        swiftPasteWindows().contains {
            abs($0.bounds.width - width) < 12 && abs($0.bounds.height - height) < 40
        }
    }
    exit(found ? 0 : 1)

/// Right-clicks the menu bar icon, which is what opens the app's menu.
case "menubar":
    guard let rect = statusItemRect() else {
        FileHandle.standardError.write(Data("uidriver: no menu bar item found\n".utf8))
        exit(1)
    }
    let point = CGPoint(x: rect.midX, y: rect.midY)
    moveMouse(x: point.x, y: point.y)
    wait(0.12)
    post(CGEvent(mouseEventSource: source, mouseType: .rightMouseDown,
                 mouseCursorPosition: point, mouseButton: .right))
    wait(0.05)
    post(CGEvent(mouseEventSource: source, mouseType: .rightMouseUp,
                 mouseCursorPosition: point, mouseButton: .right))

case "sleep":
    wait(arguments.count >= 2 ? (Double(arguments[1]) ?? 0.5) : 0.5)

default:
    print("unknown command: \(arguments[0])")
    exit(2)
}
