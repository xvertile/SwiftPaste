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

struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    /// Observed directly so deletes, pins and new captures redraw the list immediately.
    @ObservedObject var store: ClipboardStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().opacity(0.6)
            content
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 400, height: 480)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: model.presentationToken) { _ in searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onChange(of: model.query) { _ in model.ensureSelectionValid() }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    model.ensureSelectionValid()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        let items = model.filtered
        if items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text(model.query.isEmpty ? "Nothing copied yet" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HistoryRow(
                                item: item,
                                index: index,
                                store: model.store,
                                isSelected: item.id == model.selectedID
                            )
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedID = item.id
                                model.onPaste?(item)
                            }
                            .onHover { inside in
                                if inside { model.selectedID = item.id }
                            }
                            // Drag an entry straight into another app: text drops as text,
                            // images and copied files drop as files.
                            .onDrag { dragProvider(for: item) }
                            .contextMenu {
                                Button("Preview") {
                                    model.selectedID = item.id
                                    model.onPreview?(item)
                                }
                                Button(item.pinned ? "Unpin" : "Pin") { model.store.togglePin(item) }
                                Button("Copy") {
                                    Paster.writeToPasteboard(item, store: model.store)
                                }
                                Divider()
                                Button("Delete", role: .destructive) { model.store.delete(item) }
                            }
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
                .onChange(of: model.presentationToken) { _ in
                    guard let first = model.filtered.first?.id else { return }
                    proxy.scrollTo(first, anchor: .top)
                }
                .onChange(of: model.query) { _ in
                    guard let first = model.filtered.first?.id else { return }
                    proxy.scrollTo(first, anchor: .top)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            hint("↩", "Paste")
            hint("space", "Preview")
            hint("⌫", "Delete")
            hint("⌘P", "Pin")
            Spacer()
            Text("\(model.filtered.count) items")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// What the entry turns into when dropped on another app.
    private func dragProvider(for item: ClipboardItem) -> NSItemProvider {
        switch item.kind {
        case .text:
            return NSItemProvider(object: item.text as NSString)
        case .image:
            guard let url = model.store.imageURL(for: item),
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

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

struct HistoryRow: View {
    let item: ClipboardItem
    let index: Int
    let store: ClipboardStore
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(item.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.tertiaryLabel)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .image:
            if let image = ThumbnailCache.shared.image(for: item, store: store) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                symbol("photo")
            }
        case .files:
            if let first = item.fileURLs.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            } else {
                symbol("doc")
            }
        case .text:
            symbol(item.text.hasPrefix("http") ? "link" : "text.alignleft")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
    }
}

extension Color {
    static var tertiaryLabel: Color { Color(nsColor: .tertiaryLabelColor) }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
