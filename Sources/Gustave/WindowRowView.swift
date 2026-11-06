import AppKit
import SwiftUI

/// One window: app icon and title, as in the Dock list and the switcher. The title is
/// already sanitised and is drawn verbatim, never as markdown or a format.
struct WindowRowView<Controls: View>: View {
    let icon: NSImage?
    let title: String
    let isDimmed: Bool
    let isHighlighted: Bool
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(icon: icon)
            Text(verbatim: title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            controls()
        }
        .opacity(isDimmed ? 0.5 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

struct AppIconView: View {
    let icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable()
            }
        }
        .frame(width: 16, height: 16)
    }
}
