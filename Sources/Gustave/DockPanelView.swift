import AppKit
import Combine
import GustaveCore
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
    @Published var row: Int?
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
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: DockPanelLayout.headerHeight)
            Divider()
                .padding(.horizontal, 9)
                .frame(height: DockPanelLayout.separatorHeight)
            ForEach(Array(content.windows.prefix(Self.maxRows).enumerated()), id: \.element.id) { index, window in
                WindowRowView(
                    icon: content.icon,
                    title: window.title,
                    isDimmed: window.isMinimized,
                    isHighlighted: hover.row == index
                ) {
                    controls(for: window, isHighlighted: hover.row == index)
                }
                .frame(height: DockPanelLayout.rowHeight)
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
        .padding(DockPanelLayout.padding)
        .frame(width: Self.width)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text(verbatim: content.appName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button(action: actions.quit) {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Quit")
        }
        .padding(.horizontal, 9)
    }

    /// Hidden until the row is highlighted, like a menu item's extra controls.
    private func controls(for window: AppWindow, isHighlighted: Bool) -> some View {
        HStack(spacing: 6) {
            TrafficLightButton(kind: .close, showsGlyph: isHighlighted) { actions.close(window) }
                .help("Close")
            TrafficLightButton(kind: .minimize, showsGlyph: isHighlighted) { actions.toggleMinimized(window) }
                .help(window.isMinimized ? "Restore" : "Minimize")
            TrafficLightButton(kind: .zoom, showsGlyph: isHighlighted) { actions.toggleFullScreen(window) }
                .help("Full Screen")
        }
        .opacity(isHighlighted ? 1 : 0)
    }
}
