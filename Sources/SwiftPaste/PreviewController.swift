import AppKit
import SwiftUI

/// Takes key focus only when clicked, so selecting and copying preview text works while the
/// list still owns the keyboard the rest of the time. Esc keeps working either way, because
/// the shortcut handler is an app-wide monitor rather than this window's responder chain.
final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PreviewModel: ObservableObject {
    @Published var item: ClipboardItem?
    let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }
}

/// Shows the highlighted entry in a panel beside the list.
@MainActor
final class PreviewController {
    private let store: ClipboardStore
    private let model: PreviewModel
    private var panel: PreviewPanel?

    private let size = NSSize(width: 520, height: 540)

    init(store: ClipboardStore) {
        self.store = store
        self.model = PreviewModel(store: store)
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var isKey: Bool { panel?.isKeyWindow ?? false }

    func owns(_ window: NSWindow?) -> Bool {
        window != nil && window === panel
    }

    func makeKey() {
        panel?.makeKey()
    }

    func toggle(_ item: ClipboardItem, attachedTo parent: NSWindow) {
        if isVisible {
            close()
        } else {
            show(item, attachedTo: parent)
        }
    }

    func show(_ item: ClipboardItem, attachedTo parent: NSWindow) {
        let panel = panel ?? makePanel()
        self.panel = panel

        model.item = item
        panel.setFrame(frame(besides: parent.frame), display: false)

        // As a child window it rides along with the list: it can't take key focus away,
        // and it is ordered out automatically whenever the list goes away.
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    /// Follows the selection while the preview stays open.
    func update(_ item: ClipboardItem) {
        guard isVisible else { return }
        model.item = item
    }

    func close() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        model.item = nil
    }

    private func makePanel() -> PreviewPanel {
        let panel = PreviewPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let host = NSHostingView(rootView: PreviewView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        return panel
    }

    /// Prefers the right of the list, flips left when there isn't room.
    private func frame(besides anchor: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 8

        var origin = NSPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        if origin.x + size.width > visible.maxX {
            origin.x = anchor.minX - size.width - gap
        }
        origin.x = min(max(origin.x, visible.minX + gap), visible.maxX - size.width - gap)
        origin.y = min(max(origin.y, visible.minY + gap), visible.maxY - size.height - gap)

        return NSRect(origin: origin, size: size)
    }
}

/// A real NSTextView: mouse selection, ⌘C, ⌘A and the standard context menu all work,
/// which SwiftUI's `Text(...).textSelection(.enabled)` does not reliably do inside a panel.
struct SelectableTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scroll(.zero)
    }
}

struct PreviewView: View {
    @ObservedObject var model: PreviewModel

    @State private var copied = false

    /// Rendering a megabyte of text in one Text view is painfully slow.
    private let textLimit = 20_000

    var body: some View {
        VStack(spacing: 0) {
            if let item = model.item {
                header(item)
                Divider().opacity(0.6)
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider().opacity(0.6)
                footer(item)
            }
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func header(_ item: ClipboardItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName(item))
                .foregroundStyle(.secondary)
            Text(title(item))
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func content(_ item: ClipboardItem) -> some View {
        switch item.kind {
        case .image:
            if let url = model.store.imageURL(for: item), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(12)
            } else {
                missing("Image file is gone")
            }

        case .text:
            SelectableTextView(text: clipped(item.text))

        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.fileURLs, id: \.path) { url in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            if !FileManager.default.fileExists(atPath: url.path) {
                                Text("missing")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func footer(_ item: ClipboardItem) -> some View {
        HStack(spacing: 10) {
            Text(item.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(copied ? "Copied" : "Copy") {
                Paster.writeToPasteboard(item, store: model.store)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10))
            .disabled(copied)
            hint("esc", "Close")
            hint("↩", "Paste")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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

    private func missing(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clipped(_ text: String) -> String {
        guard text.count > textLimit else { return text }
        return String(text.prefix(textLimit)) + "\n\n… \(text.count - textLimit) more characters"
    }

    private func title(_ item: ClipboardItem) -> String {
        switch item.kind {
        case .image:
            if let w = item.pixelWidth, let h = item.pixelHeight { return "Image · \(w) × \(h)" }
            return "Image"
        case .files:
            return item.fileURLs.count == 1
                ? (item.fileURLs.first?.lastPathComponent ?? "File")
                : "\(item.fileURLs.count) files"
        case .text:
            return item.preview
        }
    }

    private func symbolName(_ item: ClipboardItem) -> String {
        switch item.kind {
        case .image: return "photo"
        case .files: return "doc"
        case .text: return item.text.hasPrefix("http") ? "link" : "text.alignleft"
        }
    }
}
