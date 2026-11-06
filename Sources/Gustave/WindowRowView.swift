import AppKit
import SwiftUI

/// One window, styled like a system menu item: app icon and title, highlighted under the
/// pointer. The title is already sanitised and is drawn verbatim, never as markdown.
struct WindowRowView<Controls: View>: View {
    let icon: NSImage?
    let title: String
    let isDimmed: Bool
    let isHighlighted: Bool
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        HStack(spacing: 7) {
            AppIconView(icon: icon)
            Text(verbatim: title)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(isDimmed ? 0.55 : 1)
            Spacer(minLength: 6)
            controls()
                .opacity(isHighlighted ? 1 : 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .padding(.horizontal, 9)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHighlighted ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
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
