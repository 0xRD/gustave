import AppKit
import Combine
import SwiftUI

/// What the panel shows. Passed by value so the panel can be measured right after a change.
struct DockPanelContent {
    var appName = ""
    var icon: NSImage?
    var windows: [AppWindow] = []
}

/// Only the highlight changes without a new measurement.
@MainActor
final class DockPanelHover: ObservableObject {
    @Published var window: AppWindow.ID?
}

struct DockPanelActions {
    var select: (AppWindow) -> Void
    var close: (AppWindow) -> Void
    var toggleMinimized: (AppWindow) -> Void
    var toggleFullScreen: (AppWindow) -> Void
    var quit: () -> Void
}

struct DockPanelView: View {
    static let width = 300.0
    /// More rows would not fit above a Dock on a small screen.
    static let maxRows = 20

    let content: DockPanelContent
    @ObservedObject var hover: DockPanelHover
    let actions: DockPanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            Divider()
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
            ForEach(content.windows.prefix(Self.maxRows)) { window in
                WindowRowView(
                    icon: content.icon,
                    title: window.title,
                    isDimmed: window.isMinimized,
                    isHighlighted: hover.window == window.id
                ) {
                    controls(for: window)
                }
                .onHover { inside in
                    if inside {
                        hover.window = window.id
                    } else if hover.window == window.id {
                        hover.window = nil
                    }
                }
                .onTapGesture { actions.select(window) }
            }
            if content.windows.count > Self.maxRows {
                Text(verbatim: "\(content.windows.count - Self.maxRows) more windows")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.top, 2)
            }
        }
        .padding(5)
        .frame(width: Self.width)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(verbatim: content.appName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button(action: actions.quit) {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Quit")
        }
        .padding(.horizontal, 9)
        .padding(.top, 4)
    }

    private func controls(for window: AppWindow) -> some View {
        HStack(spacing: 8) {
            Button { actions.close(window) } label: { Image(systemName: "xmark") }
                .help("Close")
            Button { actions.toggleMinimized(window) } label: {
                Image(systemName: window.isMinimized ? "arrow.up.square" : "minus")
            }
            .help(window.isMinimized ? "Restore" : "Minimize")
            Button { actions.toggleFullScreen(window) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Full Screen")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .font(.system(size: 11, weight: .medium))
    }
}
