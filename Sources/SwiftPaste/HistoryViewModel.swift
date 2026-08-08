import AppKit
import Combine
import Foundation

/// The type filter above the list.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, text, images, files

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .images: return "Images"
        case .files: return "Files"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.kind == .text
        case .images: return item.kind == .image
        case .files: return item.kind == .files
        }
    }
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var filter: HistoryFilter = .all
    @Published var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue, let item = selectedItem else { return }
            onSelectionChanged?(item)
        }
    }
    /// Changes every time the popup is shown; the view uses it to re-focus the search field.
    @Published var presentationToken = UUID()

    let store: ClipboardStore
    private var cancellables: Set<AnyCancellable> = []

    /// Invoked when the user commits a selection.
    var onPaste: ((ClipboardItem) -> Void)?
    var onClose: (() -> Void)?
    var onPreview: ((ClipboardItem) -> Void)?
    var onOpenSettings: (() -> Void)?
    /// Called when the highlight moves, so an open Quick Look panel can follow along.
    var onSelectionChanged: ((ClipboardItem) -> Void)?

    init(store: ClipboardStore) {
        self.store = store
        store.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.objectWillChange.send() }
            }
            .store(in: &cancellables)
    }

    var filtered: [ClipboardItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.items.filter { item in
            guard filter.matches(item) else { return false }
            guard !needle.isEmpty else { return true }
            return item.searchHaystack.range(
                of: needle, options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }

    /// True while the list is showing everything, which is when grouping pinned entries
    /// under their own heading makes sense.
    var isUnfiltered: Bool {
        filter == .all && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func prepareForDisplay() {
        query = ""
        filter = .all
        selectedID = filtered.first?.id
        presentationToken = UUID()
    }

    func cycleFilter(by offset: Int) {
        let all = HistoryFilter.allCases
        let current = all.firstIndex(of: filter) ?? 0
        let next = (current + offset + all.count) % all.count
        filter = all[next]
        ensureSelectionValid()
    }

    func ensureSelectionValid() {
        let list = filtered
        if let id = selectedID, list.contains(where: { $0.id == id }) { return }
        selectedID = list.first?.id
    }

    func moveSelection(by offset: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + offset, 0), list.count - 1)
        selectedID = list[next].id
    }

    func selectEdge(first: Bool) {
        let list = filtered
        selectedID = first ? list.first?.id : list.last?.id
    }

    var selectedItem: ClipboardItem? {
        filtered.first { $0.id == selectedID }
    }

    func pasteSelected() {
        guard let item = selectedItem else { return }
        onPaste?(item)
    }

    func previewSelected() {
        guard let item = selectedItem else { return }
        onPreview?(item)
    }

    func paste(at index: Int) {
        let list = filtered
        guard list.indices.contains(index) else { return }
        onPaste?(list[index])
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        let list = filtered
        let position = list.firstIndex { $0.id == item.id } ?? 0
        store.delete(item)
        let updated = filtered
        selectedID = updated.indices.contains(position) ? updated[position].id : updated.last?.id
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        store.togglePin(item)
    }
}
