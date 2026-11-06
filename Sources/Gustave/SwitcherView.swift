import AppKit
import SwiftUI

struct SwitcherContent {
    var windows: [AppWindow] = []
    var icons: [pid_t: NSImage] = [:]
    var selection: Int?
}

/// The window list of the Option+Tab switcher, in the row design of the Dock list.
struct SwitcherView: View {
    static let width = 440.0
    static let rowHeight = 28.0
    /// Rows shown at once; the visible slice follows the selection.
    static let maxRows = 12

    let content: SwitcherContent
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(visibleIndices, id: \.self) { index in
                let window = content.windows[index]
                WindowRowView(
                    icon: content.icons[window.pid],
                    title: window.title,
                    isDimmed: window.isMinimized,
                    isHighlighted: content.selection == index
                ) {
                    EmptyView()
                }
                .frame(height: Self.rowHeight)
                .onTapGesture { select(index) }
            }
        }
        .padding(6)
        .frame(width: Self.width)
    }

    private var visibleIndices: [Int] {
        let count = content.windows.count
        guard count > Self.maxRows else { return Array(0..<count) }
        let selection = content.selection ?? 0
        let start = min(max(selection - Self.maxRows / 2, 0), count - Self.maxRows)
        return Array(start..<(start + Self.maxRows))
    }
}
