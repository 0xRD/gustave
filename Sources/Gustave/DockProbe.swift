import AppKit
import ApplicationServices
import GustaveCore

/// The app icon under the pointer in the Dock.
struct DockItem: Equatable, Sendable {
    let appURL: URL
    /// Accessibility coordinates.
    let frame: Rect
}

enum DockProbe {
    static let dockBundleIdentifier = "com.apple.dock"

    /// Runs on `AXQueues.dock`. `point` is in Accessibility coordinates.
    static func item(at point: Point, dockPID: pid_t) -> DockItem? {
        var hit: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            AXElement.application(dockPID).raw, Float(point.x), Float(point.y), &hit)
        guard error == .success, let hit else { return nil }
        let element = AXElement(hit)
        guard element.string(kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = element.value(kAXURLAttribute) as? URL,
              let origin = element.point(kAXPositionAttribute),
              let size = element.size(kAXSizeAttribute)
        else { return nil }
        let frame = Rect(x: origin.x, y: origin.y, width: size.width, height: size.height)
        return DockItem(appURL: url, frame: frame)
    }
}
