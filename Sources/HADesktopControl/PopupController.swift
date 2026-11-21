import AppKit
import DesktopControlCore
import SwiftUI

/// Observable content of the popup window.
@MainActor
final class PopupState: ObservableObject {
    @Published var title = ""
    @Published var image: NSImage?
    @Published var imageFailed = false
    @Published var hasImageSource = false
    @Published var remaining = 0
    var close: () -> Void = {}
}

/// A small floating window in the top-right corner. It never takes focus and also shows over
/// full-screen apps. A new request replaces the current one instead of stacking windows.
@MainActor
final class PopupController {
    let state = PopupState()
    private var panel: NSPanel?
    private var countdown: Task<Void, Never>?
    private var refresher: Task<Void, Never>?
    private var generation = 0

    var onDismiss: (() -> Void)?
    var isVisible: Bool { panel?.isVisible ?? false }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func show(title: String, imageURL: URL?, seconds: Double) {
        generation += 1
        let current = generation
        countdown?.cancel()
        refresher?.cancel()

        state.title = title
        state.image = nil
        state.imageFailed = false
        state.hasImageSource = imageURL != nil
        state.remaining = Int(seconds.rounded(.up))
        state.close = { [weak self] in self?.dismiss() }

        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()

        countdown = Task { [weak self] in
            while let self, !Task.isCancelled, self.generation == current, self.state.remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, self.generation == current else { return }
                self.state.remaining -= 1
            }
            if let self, !Task.isCancelled, self.generation == current { self.dismiss() }
        }

        if let imageURL {
            refresher = Task { [weak self] in
                while !Task.isCancelled {
                    let image = await Self.fetch(imageURL)
                    guard let self, !Task.isCancelled, self.generation == current else { return }
                    if let image {
                        self.state.image = image
                        self.state.imageFailed = false
                    } else if self.state.image == nil {
                        self.state.imageFailed = true
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    func dismiss() {
        guard panel?.isVisible == true else { return }
        generation += 1
        countdown?.cancel()
        refresher?.cancel()
        panel?.orderOut(nil)
        onDismiss?()
    }

    // MARK: - Internals

    /// One JPEG/PNG from Home Assistant; anything else (status, size, format) counts as a failure.
    private static func fetch(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 8_000_000 else { return nil }
        return NSImage(data: data)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let host = NSHostingView(rootView: PopupView(state: state))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        return panel
    }

    private func place(_ panel: NSPanel) {
        let size = (panel.contentView as? NSHostingView<PopupView>)?.fittingSize ?? NSSize(width: 380, height: 300)
        panel.setContentSize(size)
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 16))
    }
}

private struct PopupView: View {
    @ObservedObject var state: PopupState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bell.fill").foregroundStyle(.orange)
                Text(state.title.isEmpty ? "Home Assistant" : state.title).font(.headline).lineLimit(1)
                Spacer()
                Text("\(state.remaining)").monospacedDigit().foregroundStyle(.secondary)
                Button { state.close() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            if state.hasImageSource {
                Group {
                    if let image = state.image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    } else if state.imageFailed {
                        Image(systemName: "video.slash").font(.largeTitle).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .frame(width: 380)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12)))
    }
}
