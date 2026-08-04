import AppKit
import Foundation

/// Fires when a modifier key is pressed and released twice in quick succession,
/// with no other key or modifier involved — e.g. tapping ⌥ twice.
@MainActor
final class DoubleTapHotKey {
    /// Maximum gap between the two taps.
    var doubleTapInterval: TimeInterval = 0.45
    /// A tap longer than this is treated as "held", not tapped.
    var maxHoldDuration: TimeInterval = 0.6

    private let flag: NSEvent.ModifierFlags
    private let otherFlags: NSEvent.ModifierFlags
    private let onTrigger: () -> Void

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    private var isDown = false
    private var downAt: Date?
    private var contaminated = false
    private var lastTapAt: Date?

    init(flag: NSEvent.ModifierFlags = .option, onTrigger: @escaping () -> Void) {
        self.flag = flag
        let modifiers: NSEvent.ModifierFlags = [.command, .control, .shift, .option, .function]
        self.otherFlags = modifiers.subtracting(flag)
        self.onTrigger = onTrigger
    }

    var isRunning: Bool { globalFlagsMonitor != nil }

    func start() {
        guard !isRunning else { return }
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.contaminate() }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.contaminate()
            return event
        }
    }

    func stop() {
        for monitor in [globalFlagsMonitor, localFlagsMonitor, globalKeyMonitor, localKeyMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        globalKeyMonitor = nil
        localKeyMonitor = nil
        reset()
    }

    /// Any other input during the tap disqualifies it (so ⌥C never triggers).
    private func contaminate() {
        if isDown { contaminated = true }
        lastTapAt = nil
    }

    private func reset() {
        isDown = false
        downAt = nil
        contaminated = false
        lastTapAt = nil
    }

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags
        let nowDown = flags.contains(flag)
        let othersHeld = !flags.intersection(otherFlags).isEmpty

        if nowDown, !isDown {
            isDown = true
            downAt = Date()
            contaminated = othersHeld
            return
        }

        guard !nowDown, isDown else {
            if othersHeld { contaminated = true }
            return
        }

        isDown = false
        let heldFor = downAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let wasClean = !contaminated && !othersHeld && heldFor <= maxHoldDuration
        downAt = nil
        contaminated = false

        guard wasClean else {
            lastTapAt = nil
            return
        }

        let now = Date()
        if let last = lastTapAt, now.timeIntervalSince(last) <= doubleTapInterval {
            lastTapAt = nil
            onTrigger()
        } else {
            lastTapAt = now
        }
    }
}
