import AppKit
import Combine
import DesktopControlCore
import SwiftUI

/// Everything one popup card needs. Built by the app model from a `PopupRequest`.
struct PopupSpec {
    var id: String?
    var title: String
    var imageURL: URL?
    var seconds: Double?          // nil = sticky
    var level: PopupRequest.Level
    var actions: [PopupRequest.Action]
    var openURL: URL?
    var openLabel: String
    var pausesMedia: Bool
}

@MainActor
final class PopupItem: ObservableObject, Identifiable {
    let uid = UUID()
    nonisolated var id: UUID { uid }
    let spec: PopupSpec
    @Published var image: NSImage?
    @Published var imageFailed = false
    @Published var remaining: Int?
    fileprivate var tasks: [Task<Void, Never>] = []

    init(spec: PopupSpec) {
        self.spec = spec
        remaining = spec.seconds.map { Int($0.rounded(.up)) }
    }
}

/// Floating window in the top-right corner holding up to three stacked popup cards. It never
/// takes focus and also shows over full-screen apps. A popup with the same `id` replaces the old one.
@MainActor
final class PopupController: ObservableObject {
    static let maxItems = 3

    @Published private(set) var items: [PopupItem] = []
    private var panel: NSPanel?
    private var watcher: AnyCancellable?

    var onDismiss: ((PopupItem) -> Void)?
    var onAction: ((PopupItem, String) -> Void)?
    var isVisible: Bool { panel?.isVisible ?? false }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func show(_ spec: PopupSpec) {
        if let id = spec.id, let index = items.firstIndex(where: { $0.spec.id == id }) {
            remove(items[index])
        }
        while items.count >= Self.maxItems { remove(items[0]) }

        let item = PopupItem(spec: spec)
        items.append(item)

        if item.remaining != nil {
            item.tasks.append(Task { [weak self, weak item] in
                while let item, !Task.isCancelled, let left = item.remaining, left > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    item.remaining = left - 1
                }
                if let self, let item, !Task.isCancelled { self.dismiss(item) }
            })
        }
        if let url = spec.imageURL {
            item.tasks.append(Task { [weak item] in
                while !Task.isCancelled {
                    let image = await Self.fetch(url)
                    guard let item, !Task.isCancelled else { return }
                    if let image {
                        item.image = image
                        item.imageFailed = false
                    } else if item.image == nil {
                        item.imageFailed = true
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            })
        }
        presentPanel()
    }

    func dismiss(_ item: PopupItem) {
        guard items.contains(where: { $0.uid == item.uid }) else { return }
        remove(item)
        onDismiss?(item)
    }

    func click(_ item: PopupItem, action: String) {
        onAction?(item, action)
        dismiss(item)
    }

    // MARK: - Internals

    private func remove(_ item: PopupItem) {
        item.tasks.forEach { $0.cancel() }
        item.tasks = []
        items.removeAll { $0.uid == item.uid }
        if items.isEmpty { panel?.orderOut(nil) } else { layout() }
    }

    /// One JPEG/PNG from Home Assistant; anything else (status, size, format) counts as a failure.
    private static func fetch(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 8_000_000 else { return nil }
        return NSImage(data: data)
    }

    private func presentPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        layout()
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: PopupStack(controller: self))
        return panel
    }

    /// Sizes the panel to its content and pins it to the top-right corner. SwiftUI needs a pass
    /// to update its size after the item list changed, hence the deferred measurement.
    private func layout() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, !self.items.isEmpty,
                  let host = panel.contentView as? NSHostingView<PopupStack> else { return }
            let size = host.fittingSize
            panel.setContentSize(size)
            guard let screen = NSScreen.main else { return }
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 16))
        }
    }
}

// MARK: - Views

private struct PopupStack: View {
    @ObservedObject var controller: PopupController

    var body: some View {
        VStack(spacing: 10) {
            ForEach(controller.items) { item in
                PopupCard(item: item, controller: controller)
            }
        }
        .padding(8)
        .frame(width: 396)
    }
}

private struct PopupCard: View {
    @ObservedObject var item: PopupItem
    let controller: PopupController

    private var tint: Color {
        switch item.spec.level {
        case .info: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var symbol: String {
        switch item.spec.level {
        case .info: return "bell.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(item.spec.title.isEmpty ? "Home Assistant" : item.spec.title).font(.headline).lineLimit(1)
                Spacer()
                if let remaining = item.remaining {
                    Text("\(remaining)").monospacedDigit().foregroundStyle(.secondary)
                }
                Button { controller.dismiss(item) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            if item.spec.imageURL != nil {
                // Fixed height, so the card does not jump while the image loads.
                Group {
                    if let image = item.image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    } else if item.imageFailed {
                        Image(systemName: "video.slash").font(.largeTitle).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
                .background(Color.black.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if !item.spec.actions.isEmpty || item.spec.openURL != nil {
                HStack {
                    if let url = item.spec.openURL {
                        Button(item.spec.openLabel) { NSWorkspace.shared.open(url) }
                    }
                    Spacer()
                    ForEach(item.spec.actions, id: \.id) { action in
                        Button(action.label) { controller.click(item, action: action.id) }
                            .buttonStyle(.borderedProminent).tint(tint)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.55), lineWidth: 1.5))
    }
}
