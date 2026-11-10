import AppKit
import ApplicationServices
import GustaveCore
import os

/// A Dock app icon.
struct DockItem: Equatable, Sendable {
    let appURL: URL
    /// Accessibility coordinates.
    let frame: Rect
}

/// Calls into the Dock process. Run on `AXQueues.dock` only.
enum DockProbe {
    static let dockBundleIdentifier = "com.apple.dock"

    private static let log = Logger(subsystem: "io.github.0xrd.gustave", category: "dock")

    struct Subscription: @unchecked Sendable {
        let observer: AXObserver
        let list: AXElement
    }

    /// Watched on the Dock's list. Selection changes follow the pointer; the list being
    /// destroyed means the Dock replaced it while keeping its process, and a subscription
    /// left on the old list would go silent without any error.
    static let notifications = [
        kAXSelectedChildrenChangedNotification as String,
        kAXUIElementDestroyedNotification as String,
    ]

    /// Asks the Dock to report changes of its selection, and the end of its list.
    static func subscribe(
        dockPID: pid_t,
        callback: AXObserverCallback,
        refcon: UnsafeMutableRawPointer
    ) -> Subscription? {
        guard case .found(let list) = currentList(dockPID: dockPID) else { return nil }

        var observer: AXObserver?
        guard AXObserverCreate(dockPID, callback, &observer) == .success, let observer,
              AXObserverAddNotification(
                observer, list.raw, kAXSelectedChildrenChangedNotification as CFString, refcon) == .success
        else { return nil }
        // Best effort: wake and display changes also resubscribe, should the Dock not post it.
        AXObserverAddNotification(observer, list.raw, kAXUIElementDestroyedNotification as CFString, refcon)
        return Subscription(observer: observer, list: list)
    }

    static func unsubscribe(_ subscription: Subscription) {
        for name in notifications {
            AXObserverRemoveNotification(subscription.observer, subscription.list.raw, name as CFString)
        }
    }

    private enum CurrentList {
        case found(AXElement)
        /// The Dock answered, and has no list.
        case missing
        case noAnswer
    }

    /// The list the Dock shows now.
    private static func currentList(dockPID: pid_t) -> CurrentList {
        guard let children = AXElement.application(dockPID).value(kAXChildrenAttribute) as? [AXUIElement]
        else { return .noAnswer }
        guard let list = children.map(AXElement.init).first(where: { $0.string(kAXRoleAttribute) == kAXListRole })
        else { return .missing }
        return .found(list)
    }

    /// Whether the subscription is on a list the Dock no longer shows (D35): the checks
    /// DockDoor makes every 5 s, made here only when the caller has an event to go on.
    static func isStale(_ list: AXElement, dockPID: pid_t) -> Bool {
        let subscribed: DockListAnswer
        switch list.copy(kAXRoleAttribute).0 {
        case .success: subscribed = .answered
        case .invalidUIElement: subscribed = .gone
        default: subscribed = .silent
        }
        var current = DockCurrentList.unknown
        if subscribed == .answered {
            switch currentList(dockPID: dockPID) {
            case .found(let shown): current = CFEqual(shown.raw, list.raw) ? .same : .different
            case .missing: current = .missing
            case .noAnswer: current = .unknown
            }
        }
        let isStale = DockSubscriptionHealth.isStale(subscribed: subscribed, current: current)
        log.debug("check: subscribed list \(String(describing: subscribed), privacy: .public), current \(String(describing: current), privacy: .public), stale \(isStale)")
        return isStale
    }

    enum Selection: Sendable {
        /// Nothing selected: the pointer is not on the Dock.
        case nothing
        /// An item that is not an app icon, such as a folder or the Trash.
        case otherItem
        case app(DockItem)
        /// The Dock says the list no longer exists: the subscription is on a dead element.
        case listGone
    }

    static func selection(in list: AXElement) -> Selection {
        let (error, value) = list.copy(kAXSelectedChildrenAttribute)
        if error == .invalidUIElement { return .listGone }
        if error != .success, error != .noValue {
            log.debug("selection read failed: \(error.rawValue)")
        }
        guard error == .success, let selected = value as? [AXUIElement], let first = selected.first
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
