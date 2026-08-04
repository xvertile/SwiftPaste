import AppKit
import CryptoKit
import Foundation

/// Owns the history list plus its on-disk representation.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    let settings: Settings

    private let directory: URL
    private let imagesDirectory: URL
    private let indexURL: URL
    private var saveWorkItem: DispatchWorkItem?

    init(settings: Settings) {
        self.settings = settings

        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let base = support.appendingPathComponent("SwiftPaste", isDirectory: true)

        // Carry over history from the app's previous name.
        let legacy = support.appendingPathComponent("ClipboardHistory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.moveItem(at: legacy, to: base)
        }

        directory = base
        imagesDirectory = base.appendingPathComponent("images", isDirectory: true)
        indexURL = base.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Persistence

    func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([ClipboardItem].self, from: data) else { return }
        // Drop entries whose backing image vanished.
        items = decoded.filter { item in
            guard let file = item.imageFile else { return true }
            return FileManager.default.fileExists(atPath: imagesDirectory.appendingPathComponent(file).path)
        }
        sort()
        applyRetention()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Paths

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageFile.map { imagesDirectory.appendingPathComponent($0) }
    }

    func thumbURL(for item: ClipboardItem) -> URL? {
        item.thumbFile.map { imagesDirectory.appendingPathComponent($0) }
    }

    // MARK: - Mutation

    /// Inserts a capture, collapsing duplicates onto the existing entry.
    func insert(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.fingerprint == item.fingerprint }) {
            var existing = items[index]
            existing.createdAt = item.createdAt
            existing.sourceAppName = item.sourceAppName ?? existing.sourceAppName
            existing.sourceBundleID = item.sourceBundleID ?? existing.sourceBundleID
            items.remove(at: index)
            items.insert(existing, at: 0)
            deleteBackingFiles(of: item) // the fresh copy is redundant
        } else {
            items.insert(item, at: 0)
        }
        sort()
        applyRetention()
        scheduleSave()
    }

    func touch(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var moved = items[index]
        moved.createdAt = Date()
        items.remove(at: index)
        items.insert(moved, at: 0)
        sort()
        scheduleSave()
    }

    func delete(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        deleteBackingFiles(of: items[index])
        items.remove(at: index)
        scheduleSave()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        sort()
        scheduleSave()
    }

    /// Removes everything except pinned entries.
    func clearUnpinned() {
        for item in items where !item.pinned { deleteBackingFiles(of: item) }
        items.removeAll { !$0.pinned }
        saveNow()
    }

    func clearAll() {
        for item in items { deleteBackingFiles(of: item) }
        items.removeAll()
        saveNow()
    }

    /// Enforces both retention rules. Pinned entries are exempt from each of them.
    @discardableResult
    func applyRetention(now: Date = Date()) -> Int {
        let limit = settings.itemLimit
        let maxAge = settings.expiry.seconds

        var unpinnedSeen = 0
        var survivors: [ClipboardItem] = []
        var removed = 0

        for item in items {
            if item.pinned {
                survivors.append(item)
                continue
            }

            if let maxAge, now.timeIntervalSince(item.createdAt) > maxAge {
                deleteBackingFiles(of: item)
                removed += 1
                continue
            }

            unpinnedSeen += 1
            if let limit, unpinnedSeen > limit {
                deleteBackingFiles(of: item)
                removed += 1
                continue
            }

            survivors.append(item)
        }

        guard removed > 0 else { return 0 }
        items = survivors
        scheduleSave()
        return removed
    }

    /// Pinned first, then newest first.
    private func sort() {
        items.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func deleteBackingFiles(of item: ClipboardItem) {
        for name in [item.imageFile, item.thumbFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }

    // MARK: - Image storage

    /// Writes full-size PNG + thumbnail, returning their file names.
    func storeImage(pngData: Data, thumbData: Data?) -> (image: String, thumb: String?) {
        let stem = UUID().uuidString
        let imageName = "\(stem).png"
        try? pngData.write(to: imagesDirectory.appendingPathComponent(imageName), options: .atomic)
        var thumbName: String?
        if let thumbData {
            let name = "\(stem)-thumb.png"
            try? thumbData.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
            thumbName = name
        }
        return (imageName, thumbName)
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
