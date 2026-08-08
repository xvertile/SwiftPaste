import AppKit
import SwiftUI

/// Small in-memory cache so scrolling doesn't hit the disk repeatedly.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [UUID: NSImage] = [:]
    private var order: [UUID] = []
    private let limit = 120

    func image(for item: ClipboardItem, store: ClipboardStore) -> NSImage? {
        if let hit = cache[item.id] { return hit }
        guard let url = store.thumbURL(for: item) ?? store.imageURL(for: item),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[item.id] = image
        order.append(item.id)
        if order.count > limit {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        return image
    }
}

// MARK: - Shared style

enum Style {
    static let panelWidth: CGFloat = 420
    static let panelHeight: CGFloat = 524
    static let corner: CGFloat = 12
    static let rowCorner: CGFloat = 7

    static let title = Font.system(size: 13)
    static let subtitle = Font.system(size: 10.5)
    static let sectionHeader = Font.system(size: 10, weight: .semibold)
    static let brand = Font.system(size: 11.5, weight: .semibold)
    static let hintKey = Font.system(size: 9, weight: .semibold)
    static let hintLabel = Font.system(size: 10)
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    /// Observed directly so deletes, pins and new captures redraw the list immediately.
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: Settings
    @FocusState private var searchFocused: Bool
    /// Purely cosmetic — the keyboard owns `model.selectedID`.
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().opacity(0.5)
            searchBar
            filterBar
            Divider().opacity(0.5)
            content
            Divider().opacity(0.5)
            footer
        }
        .frame(width: Style.panelWidth, height: Style.panelHeight)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: Style.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Style.corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: model.presentationToken) { _ in searchFocused = true }
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(spacing: 7) {
            if let logo = AppAssets.logo {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.primary)
            }
            Text("Swift Paste")
                .font(Style.brand)
                .foregroundStyle(.primary)

            Text(settings.shortcutDescription)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.07), in: Capsule())

            Spacer()

            Button {
                model.onOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 8)
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onChange(of: model.query) { _ in model.ensureSelectionValid() }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    model.ensureSelectionValid()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var filterBar: some View {
        Picker("", selection: $model.filter) {
            ForEach(HistoryFilter.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.bottom, 9)
        .onChange(of: model.filter) { _ in model.ensureSelectionValid() }
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        let items = model.filtered
        if items.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: []) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if let header = sectionHeader(at: index, in: items) {
                                Text(header)
                                    .font(Style.sectionHeader)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 10)
                                    .padding(.top, index == 0 ? 2 : 10)
                                    .padding(.bottom, 2)
                            }
                            row(item, index: index)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.selectedID) { id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
                }
                // The scroll view is reused between openings, so it would otherwise keep the
                // offset from last time while the highlight sits on the first row.
                .onChange(of: model.presentationToken) { _ in scrollToTop(proxy) }
                .onChange(of: model.query) { _ in scrollToTop(proxy) }
                .onChange(of: model.filter) { _ in scrollToTop(proxy) }
            }
        }
    }

    private func row(_ item: ClipboardItem, index: Int) -> some View {
        HistoryRow(
            item: item,
            index: index,
            store: store,
            showSourceApp: settings.showSourceApp,
            isSelected: item.id == model.selectedID,
            isHovered: item.id == hoveredID
        )
        .id(item.id)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectedID = item.id
            model.onPaste?(item)
        }
        // Hovering only highlights. Moving the pointer must never move the selection,
        // or scrolling and arrowing fight the mouse.
        .onHover { inside in
            if inside {
                hoveredID = item.id
            } else if hoveredID == item.id {
                hoveredID = nil
            }
        }
        .onDrag { dragProvider(for: item) }
        .contextMenu {
            Button("Preview") {
                model.selectedID = item.id
                model.onPreview?(item)
            }
            Button("Copy") { Paster.writeToPasteboard(item, store: store) }
            Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(item) }
        }
    }

    /// "Pinned" / "Recent" headings, only while nothing is filtered out.
    private func sectionHeader(at index: Int, in items: [ClipboardItem]) -> String? {
        guard model.isUnfiltered, items.contains(where: \.pinned) else { return nil }
        if index == 0 { return items[0].pinned ? "Pinned" : "Recent" }
        if items[index - 1].pinned && !items[index].pinned { return "Recent" }
        return nil
    }

    private func scrollToTop(_ proxy: ScrollViewProxy) {
        guard let first = model.filtered.first?.id else { return }
        proxy.scrollTo(first, anchor: .top)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if let logo = AppAssets.logo {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.quaternary)
            }
            Text(emptyTitle)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(emptyHint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
    }

    private var emptyTitle: String {
        if !model.query.isEmpty { return "No matches" }
        if model.filter != .all { return "No \(model.filter.label.lowercased()) yet" }
        return "Nothing copied yet"
    }

    private var emptyHint: String {
        if !model.query.isEmpty { return "Try a different search, or switch the filter." }
        return "Copy something and it shows up here."
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 9) {
            hint("↩", "Paste")
            hint("←→", "Filter")
            hint("space", "Preview")
            hint("⌫", "Delete")
            Spacer(minLength: 6)
            Text(countLabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var countLabel: String {
        let shown = model.filtered.count
        let total = store.items.count
        return shown == total ? "\(total) items" : "\(shown) of \(total)"
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(Style.hintKey)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(Style.hintLabel)
                .foregroundStyle(.secondary)
        }
    }

    /// What the entry turns into when dropped on another app.
    private func dragProvider(for item: ClipboardItem) -> NSItemProvider {
        switch item.kind {
        case .text:
            return NSItemProvider(object: item.text as NSString)
        case .image:
            guard let url = store.imageURL(for: item),
                  let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
            provider.suggestedName = "Clipboard image.png"
            return provider
        case .files:
            guard let url = item.fileURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let provider = NSItemProvider(contentsOf: url) else {
                return NSItemProvider(object: item.text as NSString)
            }
            return provider
        }
    }
}

// MARK: - Row

struct HistoryRow: View {
    let item: ClipboardItem
    let index: Int
    let store: ClipboardStore
    let showSourceApp: Bool
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.preview)
                    .font(Style.title)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                Text(item.subtitle)
                    .font(Style.subtitle)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 4)

            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.tertiary))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Style.rowCorner)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor)
                      : isHovered ? AnyShapeStyle(Color.primary.opacity(0.07))
                      : AnyShapeStyle(Color.clear))
        )
    }

    /// Content icon, with the source app tucked into the corner.
    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch item.kind {
                case .image:
                    if let image = ThumbnailCache.shared.image(for: item, store: store) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        symbol("photo")
                    }
                case .files:
                    if let first = item.fileURLs.first {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                            .resizable().aspectRatio(contentMode: .fit).padding(3)
                    } else {
                        symbol("doc")
                    }
                case .text:
                    symbol(item.text.hasPrefix("http") ? "link" : "text.alignleft")
                }
            }
            .frame(width: 34, height: 34)
            .background(Color.primary.opacity(isSelected ? 0.12 : 0.06),
                        in: RoundedRectangle(cornerRadius: 6))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if showSourceApp, let icon = AppAssets.sourceIcon(bundleID: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 15, height: 15))
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 34, height: 34)
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
