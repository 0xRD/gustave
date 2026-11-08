import AppKit
import ApplicationServices
import GustaveCore

/// What is under the pointer in the Dock.
enum DockHoverEvent {
    case outside
    case otherItem
    case app(DockHover)

    var pointer: DockPointer {
        switch self {
        case .outside: .outside
        case .otherItem: .otherItem
        case .app(let hover): .app(pid: hover.app.processIdentifier)
        }
    }
}

/// The running app whose Dock icon is under the pointer.
struct DockHover {
    let app: NSRunningApplication
    /// AppKit coordinates.
    let iconFrame: Rect
    let edge: DockEdge
    /// Where the panel may go: the screen, below the menu bar.
    let screenFrame: Rect
}

/// Follows the Dock's own selection, which is the icon under the pointer. The Dock reports
/// every change through Accessibility, so there is no mouse monitor and no polling.
@MainActor
final class DockHoverObserver {
    private let onChange: (DockHoverEvent) -> Void

    /// A new Dock answers Accessibility only after a moment, longer at login. The delay
    /// doubles on each try (0.5 s to 4 s, about 7.5 s in all), then nothing until the next
    /// change: a few events, never polling.
    private static let attachRetries = 5
    private static let attachRetryDelay: TimeInterval = 0.5
    /// After a wake or a display change the Dock may rebuild its list a moment later.
    private static let resubscribeDelay: TimeInterval = 1.0

    private var isRunning = false
    private var observer: AXObserver?
    private var list: AXElement?
    private var attachedDockPID: pid_t?
    private var runningAppsObservation: NSKeyValueObservation?
    private var systemObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pendingResubscribe: DispatchWorkItem?
    private var current: DockHoverEvent = .outside
    private var generation = 0
    /// The generation, readable from the Dock queue, so selection reads already replaced by
    /// a newer one are skipped during a fast sweep along the Dock.
    private let currentGeneration = GenerationToken()

    init(onChange: @escaping (DockHoverEvent) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // The Dock restarts when its settings change or it crashes. It is a UI element app,
        // for which launch and quit notifications are not reliably posted, so the list of
        // running apps is observed instead: an event, not a poll.
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.dockMayHaveChanged() }
            }
        }
        // The Dock can replace its list while keeping its process, around sleep and display
        // changes, which leaves the subscription silent. Both are events, not polls.
        let observations: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
        ]
        systemObservers = observations.map { center, name in
            (center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleResubscribe() }
            })
        }
        attach(retriesLeft: Self.attachRetries)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        runningAppsObservation?.invalidate()
        runningAppsObservation = nil
        for (center, token) in systemObservers {
            center.removeObserver(token)
        }
        systemObservers = []
        pendingResubscribe?.cancel()
        pendingResubscribe = nil
        detach()
        attachedDockPID = nil
        current = .outside
    }

    private static func dockPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: DockProbe.dockBundleIdentifier)
            .first { !$0.isTerminated }?.processIdentifier
    }

    private func dockMayHaveChanged() {
        guard isRunning, Self.dockPID() != attachedDockPID else { return }
        attach(retriesLeft: Self.attachRetries)
    }

    /// One resubscription for a burst of wake and display notifications.
    private func scheduleResubscribe() {
        pendingResubscribe?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.pendingResubscribe = nil
                self.attach(retriesLeft: Self.attachRetries)
            }
        }
        pendingResubscribe = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resubscribeDelay, execute: work)
    }

    /// The list is gone: subscribe to the one that replaces it.
    fileprivate func listDestroyed() {
        guard isRunning else { return }
        report(.outside)
        attach(retriesLeft: Self.attachRetries)
    }

    private func attach(retriesLeft: Int) {
        detach()
        guard let dockPID = Self.dockPID() else {
            attachedDockPID = nil
            return
        }
        attachedDockPID = dockPID

        let token = generation
        // The observer lives as long as the app, so an unretained pointer is safe.
        let address = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        AXQueues.dock.async { [weak self] in
            guard let refcon = UnsafeMutableRawPointer(bitPattern: address) else { return }
            let subscription = DockProbe.subscribe(dockPID: dockPID, callback: dockNotification, refcon: refcon)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation, self.isRunning else {
                        // Replaced or stopped meanwhile: leave nothing registered in the Dock.
                        if let subscription {
                            AXQueues.dock.async { DockProbe.unsubscribe(subscription) }
                        }
                        return
                    }
                    guard let subscription else {
                        self.retryAttach(retriesLeft: retriesLeft - 1, token: token)
                        return
                    }
                    self.observer = subscription.observer
                    self.list = subscription.list
                    CFRunLoopAddSource(
                        CFRunLoopGetMain(), AXObserverGetRunLoopSource(subscription.observer), .commonModes)
                }
            }
        }
    }

    /// A few spaced tries after a Dock start, then nothing until the next change: no polling.
    private func retryAttach(retriesLeft: Int, token: Int) {
        guard retriesLeft > 0 else { return }
        let attempt = Self.attachRetries - 1 - retriesLeft
        let delay = Self.attachRetryDelay * Double(1 << max(attempt, 0))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, token == self.generation else { return }
                self.attach(retriesLeft: retriesLeft)
            }
        }
    }

    private func detach() {
        bumpGeneration()
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            // Unsubscribing is a call into the Dock: off the main thread, like every other.
            if let list {
                let subscription = DockProbe.Subscription(observer: observer, list: list)
                AXQueues.dock.async { DockProbe.unsubscribe(subscription) }
            }
        }
        observer = nil
        list = nil
    }

    fileprivate func selectionChanged() {
        guard let list, let primary = NSScreen.screens.first else { return }
        bumpGeneration()
        let token = generation
        let current = currentGeneration
        let primaryHeight = primary.frame.height
        AXQueues.dock.async { [weak self] in
            guard current.matches(token) else { return }
            let selection = DockProbe.selection(in: list)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation else { return }
                    switch selection {
                    case .nothing:
                        self.report(.outside)
                    case .otherItem:
                        self.report(.otherItem)
                    case .app(let item):
                        // An app that is not running is just another item.
                        self.report(self.hover(for: item, primaryHeight: primaryHeight).map(DockHoverEvent.app) ?? .otherItem)
                    }
                }
            }
        }
    }

    private func hover(for item: DockItem, primaryHeight: Double) -> DockHover? {
        let target = item.appURL.standardizedFileURL
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL == target
        }) else { return nil }

        let iconFrame = ScreenCoordinates.flipped(item.frame, primaryScreenHeight: primaryHeight)
        let centre = Point(x: iconFrame.midX, y: iconFrame.midY)
        // An icon still sliding in with an auto-hiding Dock can have its centre off every
        // screen for a moment: the pointer's screen is the Dock's then.
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { Rect($0.frame).contains(centre) })
            ?? NSScreen.screens.first(where: { $0.frame.contains(pointer) })
        else { return nil }

        let frame = Rect(screen.frame)
        let visible = Rect(screen.visibleFrame)
        let edge = DockGeometry.placement(frame: frame, visibleFrame: visible)?.edge
            ?? DockGeometry.edge(orientation: UserDefaults(suiteName: DockProbe.dockBundleIdentifier)?
                .string(forKey: "orientation"))
        // The full screen at the bottom and sides (an auto-hiding Dock reserves nothing), but
        // never over the menu bar.
        let bounds = Rect(x: frame.x, y: frame.y, width: frame.width, height: visible.maxY - frame.y)
        return DockHover(app: app, iconFrame: iconFrame, edge: edge, screenFrame: bounds)
    }

    private func bumpGeneration() {
        generation += 1
        currentGeneration.set(generation)
    }

    private func report(_ event: DockHoverEvent) {
        if case .app(let new) = event, case .app(let old) = current {
            guard new.app.processIdentifier != old.app.processIdentifier || new.iconFrame != old.iconFrame
            else { return }
        } else if event.pointer == current.pointer {
            return
        }
        current = event
        onChange(event)
    }
}

private func dockNotification(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    // The run loop source is on the main run loop.
    let hoverObserver = Unmanaged<DockHoverObserver>.fromOpaque(refcon).takeUnretainedValue()
    let isDestroyed = (notification as String) == kAXUIElementDestroyedNotification
    MainActor.assumeIsolated {
        if isDestroyed {
            hoverObserver.listDestroyed()
        } else {
            hoverObserver.selectionChanged()
        }
    }
}

extension Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }
}
