import AppKit
import ApplicationServices
import GustaveCore

/// A Dock app icon.
struct DockItem: Equatable, Sendable {
    let appURL: URL
    /// Accessibility coordinates.
    let frame: Rect
}

/// Calls into the Dock process. Run on `AXQueues.dock` only.
enum DockProbe {
    static let dockBundleIdentifier = "com.apple.dock"

    struct Subscription: @unchecked Sendable {
        let observer: AXObserver
        let list: AXElement
    }

    /// Asks the Dock to report changes of its selection, which follows the pointer.
    static func subscribe(
        dockPID: pid_t,
        callback: AXObserverCallback,
        refcon: UnsafeMutableRawPointer
    ) -> Subscription? {
        let dock = AXElement.application(dockPID)
        guard let children = dock.value(kAXChildrenAttribute) as? [AXUIElement],
              let list = children.map(AXElement.init).first(where: { $0.string(kAXRoleAttribute) == kAXListRole })
        else { return nil }

        var observer: AXObserver?
        guard AXObserverCreate(dockPID, callback, &observer) == .success, let observer,
              AXObserverAddNotification(
                observer, list.raw, kAXSelectedChildrenChangedNotification as CFString, refcon) == .success
        else { return nil }
        return Subscription(observer: observer, list: list)
    }

    enum Selection: Sendable {
        /// Nothing selected: the pointer is not on the Dock.
        case nothing
        /// An item that is not an app icon, such as a folder or the Trash.
        case otherItem
        case app(DockItem)
    }

    static func selection(in list: AXElement) -> Selection {
        guard let selected = list.value(kAXSelectedChildrenAttribute) as? [AXUIElement],
              let first = selected.first
        else { return .nothing }
        let element = AXElement(first)
        guard element.string(kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = element.value(kAXURLAttribute) as? URL,
              let origin = element.point(kAXPositionAttribute),
              let size = element.size(kAXSizeAttribute)
        else { return .otherItem }
        return .app(DockItem(appURL: url, frame: Rect(x: origin.x, y: origin.y, width: size.width, height: size.height)))
    }
}
