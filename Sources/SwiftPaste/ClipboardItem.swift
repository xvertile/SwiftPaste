import AppKit
import Foundation

enum ClipboardKind: String, Codable {
    case text
    case image
    case files
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ClipboardKind
    /// Plain text payload, or newline-separated file paths for `.files`.
    var text: String
    /// File name inside the images directory (full-size PNG).
    var imageFile: String?
    /// File name inside the images directory (thumbnail PNG).
    var thumbFile: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteCount: Int
    var createdAt: Date
    var pinned: Bool
    /// Content fingerprint used for de-duplication.
    var fingerprint: String
    var sourceAppName: String?
    var sourceBundleID: String?

    init(
        id: UUID = UUID(),
        kind: ClipboardKind,
        text: String,
        imageFile: String? = nil,
        thumbFile: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        byteCount: Int,
        createdAt: Date = Date(),
        pinned: Bool = false,
        fingerprint: String,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.thumbFile = thumbFile
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.pinned = pinned
        self.fingerprint = fingerprint
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
    }

    var fileURLs: [URL] {
        guard kind == .files else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    /// Single-line preview used in the list.
    var preview: String {
        switch kind {
        case .text:
            let collapsed = text
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return collapsed.isEmpty ? "(whitespace)" : collapsed
        case .image:
            if let w = pixelWidth, let h = pixelHeight { return "Image \(w) × \(h)" }
            return "Image"
        case .files:
            let names = fileURLs.map(\.lastPathComponent)
            if names.count == 1 { return names[0] }
            return "\(names.count) items — " + names.prefix(3).joined(separator: ", ")
        }
    }

    var subtitle: String {
        var parts: [String] = []
        if let app = sourceAppName { parts.append(app) }
        parts.append(Self.relativeFormatter.localizedString(for: createdAt, relativeTo: Date()))
        switch kind {
        case .text:
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
            parts.append(lines > 1 ? "\(lines) lines" : "\(text.count) chars")
        case .image, .files:
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    /// Text matched by the search field.
    var searchHaystack: String {
        switch kind {
        case .text: return text
        case .files: return fileURLs.map(\.lastPathComponent).joined(separator: " ") + " " + text
        case .image: return "image picture screenshot " + (sourceAppName ?? "")
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
