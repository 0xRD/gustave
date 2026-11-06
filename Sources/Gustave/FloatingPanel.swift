import AppKit
import SwiftUI

/// A borderless panel that floats over every Space and never takes focus.
final class FloatingPanel: NSPanel {
    static let cornerRadius = 14.0

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

    /// Puts `content` on the system material: Liquid Glass from macOS 26, the menu blur
    /// before it. Both are rounded like a system menu.
    static func materialView(around content: NSView) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        #endif
        let blur = NSVisualEffectView()
        blur.material = .menu
        blur.blendingMode = .behindWindow
        // Gustave is rarely the active app, and the inactive look is flat grey.
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        blur.addSubview(content)
        return blur
    }
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
