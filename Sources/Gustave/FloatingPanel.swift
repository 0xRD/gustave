import AppKit
import SwiftUI

/// A borderless panel that floats over every Space and never takes focus.
final class FloatingPanel: NSPanel {
    /// The radius of a system menu on macOS 26.
    static let cornerRadius = 12.0

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Materials draw a flat, inactive look in windows that are not key. The panel never
    /// takes keyboard focus (`canBecomeKey` is false); this only makes it draw as active.
    override var isKeyWindow: Bool { true }
}

/// Gustave is usually not the active app, so the first click must act, not activate.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Reports the pointer entering, moving over and leaving the panel, also while Gustave is
/// inactive, which SwiftUI's own hover tracking does not.
final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    /// Distance of the pointer from the top edge, in points.
    var onMove: ((Double) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
        mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onMove?(bounds.height - location.y)
    }
}

extension View {
    /// The panels' background: Liquid Glass from macOS 26, a rounded material before. The
    /// regular glass keeps white text readable over light and dark content alike.
    @ViewBuilder
    func panelBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: FloatingPanel.cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
        #else
        background(.regularMaterial, in: shape)
        #endif
    }
}
