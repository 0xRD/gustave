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
        }
        .font(.system(size: 13))
        .foregroundStyle(isHighlighted ? Color.white : Color.primary)
        .padding(.horizontal, 9)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
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

/// A window title bar button, in its system colours. The glyph shows while the row is
/// highlighted, as it does when hovering a title bar.
struct TrafficLightButton: View {
    enum Kind {
        case close, minimize, zoom

        var color: Color {
            switch self {
            case .close: Color(red: 1.0, green: 0.373, blue: 0.341)
            case .minimize: Color(red: 0.996, green: 0.737, blue: 0.180)
            case .zoom: Color(red: 0.157, green: 0.784, blue: 0.251)
            }
        }

        var symbol: String {
            switch self {
            case .close: "xmark"
            case .minimize: "minus"
            case .zoom: "arrow.up.left.and.arrow.down.right"
            }
        }
    }

    let kind: Kind
    let showsGlyph: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(kind.color)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                Image(systemName: kind.symbol)
                    .font(.system(size: 6.5, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .opacity(showsGlyph ? 1 : 0)
            }
            .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
    }
}
