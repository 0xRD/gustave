import AppKit
import Combine
import SwiftUI

@MainActor
final class DockPanelModel: ObservableObject {
    @Published var appName = ""
    @Published var icon: NSImage?
    @Published var windows: [AppWindow] = []
    @Published var hoveredWindow: AppWindow.ID?
}

struct DockPanelActions {
    var select: (AppWindow) -> Void
    var close: (AppWindow) -> Void
    var toggleMinimized: (AppWindow) -> Void
    var toggleFullScreen: (AppWindow) -> Void
    var quit: () -> Void
}

struct DockPanelView: View {
    static let width = 320.0
    /// More rows would not fit above a Dock on a small screen.
    static let maxRows = 20

    @ObservedObject var model: DockPanelModel
    let actions: DockPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            ForEach(model.windows.prefix(Self.maxRows)) { window in
                WindowRowView(
                    icon: model.icon,
                    title: window.title,
                    isDimmed: window.isMinimized,
                    isHighlighted: model.hoveredWindow == window.id
                ) {
                    controls(for: window)
                }
                .onHover { model.hoveredWindow = $0 ? window.id : nil }
                .onTapGesture { actions.select(window) }
            }
            if model.windows.count > Self.maxRows {
                Text(verbatim: "\(model.windows.count - Self.maxRows) more windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }
        }
        .padding(6)
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(spacing: 8) {
            AppIconView(icon: model.icon)
            Text(verbatim: model.appName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button(action: actions.quit) {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func controls(for window: AppWindow) -> some View {
        HStack(spacing: 6) {
            Button { actions.close(window) } label: { Image(systemName: "xmark") }
                .help("Close")
            Button { actions.toggleMinimized(window) } label: { Image(systemName: "minus") }
                .help(window.isMinimized ? "Restore" : "Minimize")
            Button { actions.toggleFullScreen(window) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Full Screen")
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}
