import AppKit
import ApplicationServices
import GustaveCore
import os

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
    /// AppKit coordinates. Moves to where the icon rests while an auto-hiding Dock slides (D36).
    var iconFrame: Rect
    let edge: DockEdge
    /// Where the panel may go: the screen, below the menu bar.
    let screenFrame: Rect
}

/// Follows the Dock's own selection, which is the icon under the pointer. The Dock reports
/// every change through Accessibility, so there is no mouse monitor and no polling.
///
/// A subscription can go silent with no error, when the Dock replaces its list while keeping
/// its process (D33, D35). Nothing reports that, so the subscription is checked whenever
/// something else happens anyway (an app comes forward, the Space changes, the screens wake)
/// and made again when it is on a list the Dock no longer shows.
@MainActor
final class DockHoverObserver {
    nonisolated private static let log = Logger(subsystem: "io.github.0xrd.gustave", category: "dock")

    private let onChange: (DockHoverEvent) -> Void

    /// A new Dock answers Accessibility only after a moment, longer at login. The delay
    /// doubles on each try (0.5 s to 4 s, about 7.5 s in all), then nothing until the next
    /// change: a few events, never polling.
    private static let attachRetries = 5
    private static let attachRetryDelay: TimeInterval = 0.5
    /// After a wake or a display change the Dock may rebuild its list a moment later.
    private static let resubscribeDelay: TimeInterval = 1.0
    /// The Dock can also rebuild its list later than that, after the new subscription: one
    /// more check follows each wake and display change.
    private static let settledCheckDelay: TimeInterval = 10.0
    /// Events come in bursts, such as several apps coming forward at login.
    private static let minimumCheckInterval: TimeInterval = 2.0

    private var isRunning = false
    private var observer: AXObserver?
    private var list: AXElement?
    private var attachedDockPID: pid_t?
    private var runningAppsObservation: NSKeyValueObservation?
    private var systemObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var pendingResubscribe: DispatchWorkItem?
    private var pendingCheck: DispatchWorkItem?
    /// Moves on with each subscription, so work started for an older one is dropped.
    private var subscriptionID = 0
    /// True from the first try until the Dock accepts or the tries run out.
    private var isAttaching = false
    private var isChecking = false
    /// In system uptime.
    private var lastCheck: TimeInterval = 0
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
        // running apps is observed instead: an event, not a poll. An app starting or
        // quitting is the Dock itself, or one more moment to check.
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.checkSubscription() }
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
        // Nothing reports a subscription that went silent, so it is checked on events that
        // happen in normal use, and only then: no timer (hard rule 7).
        let workspace = NSWorkspace.shared.notificationCenter
        let checks = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        let checkObservers: [(NotificationCenter, NSObjectProtocol)] = checks.map { name in
            (workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkSubscription() }
            })
        }
        systemObservers += checkObservers
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
        pendingCheck?.cancel()
        pendingCheck = nil
        detach()
        attachedDockPID = nil
    }

    /// The Dock's process. The lookup by bundle identifier comes back empty for a moment
    /// each time any app starts or quits, which are the very moments this is asked (D38).
    /// So the Dock already subscribed to is asked first, by pid, and the list of running
    /// apps, which does not have that gap, finds a new one.
    private func dockPID() -> pid_t? {
        if let attachedDockPID, let attached = NSRunningApplication(processIdentifier: attachedDockPID),
           Self.isRunningDock(attached) {
            return attachedDockPID
        }
        return NSWorkspace.shared.runningApplications.first(where: Self.isRunningDock)?.processIdentifier
    }

    private static func isRunningDock(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == DockProbe.dockBundleIdentifier && !app.isTerminated
    }

    /// Makes the subscription again when the Dock is another process, when no subscription
    /// exists and none is being tried, or when the Dock says the list it is on is not the
    /// one it shows. A Dock that does not answer is left alone until the next event.
    private func checkSubscription() {
        guard isRunning else { return }
        let dockPID = dockPID()
        guard dockPID == attachedDockPID else {
            Self.log.notice("Dock process changed, subscribing")
            attach(retriesLeft: Self.attachRetries)
            return
        }
        guard let dockPID else { return }
        guard let list else {
            if !isAttaching {
                Self.log.notice("no Dock subscription, subscribing")
                attach(retriesLeft: Self.attachRetries)
            }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard !isChecking, now - lastCheck >= Self.minimumCheckInterval else { return }
        isChecking = true
        lastCheck = now
        let token = subscriptionID
        AXQueues.dock.async { [weak self] in
            let isStale = DockProbe.isStale(list, dockPID: dockPID)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isChecking = false
                    guard isStale, self.isRunning, token == self.subscriptionID else { return }
                    Self.log.notice("Dock replaced its list, subscribing again")
                    self.resubscribe()
                }
            }
        }
    }

    /// The selection on the old list means nothing now.
    private func resubscribe() {
        onChange(.outside)
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
                self.scheduleSettledCheck()
            }
        }
        pendingResubscribe = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resubscribeDelay, execute: work)
    }

    /// One check, once the Dock has had time to settle after a wake or a display change.
    private func scheduleSettledCheck() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.pendingCheck = nil
                self.checkSubscription()
            }
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settledCheckDelay, execute: work)
    }

    /// The list is gone: subscribe to the one that replaces it. The Dock also posts this for
    /// each icon that leaves the list, as when an app quits; the list itself is still there
    /// then, and the subscription with it (D38).
    fileprivate func elementDestroyed(_ element: AXUIElement) {
        guard isRunning, let list else { return }
        guard CFEqual(element, list.raw) else {
            Self.log.debug("a Dock item was destroyed, the list stays")
            return
        }
        Self.log.notice("Dock list destroyed, subscribing again")
        resubscribe()
    }

    private func attach(retriesLeft: Int) {
        detach()
        isAttaching = true
        let token = subscriptionID
        guard let dockPID = dockPID() else {
            // Between two Docks. The new one also shows in the list of running apps.
            attachedDockPID = nil
            retryAttach(retriesLeft: retriesLeft - 1, token: token)
            return
        }
        attachedDockPID = dockPID

        // The observer lives as long as the app, so an unretained pointer is safe.
        let address = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        AXQueues.dock.async { [weak self] in
            guard let refcon = UnsafeMutableRawPointer(bitPattern: address) else { return }
            let subscription = DockProbe.subscribe(dockPID: dockPID, callback: dockNotification, refcon: refcon)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.subscriptionID, self.isRunning else {
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
                    self.isAttaching = false
                    self.observer = subscription.observer
                    self.list = subscription.list
                    Self.log.notice("subscribed to Dock pid \(dockPID)")
                    CFRunLoopAddSource(
                        CFRunLoopGetMain(), AXObserverGetRunLoopSource(subscription.observer), .commonModes)
                }
            }
        }
    }

    /// A few spaced tries after a Dock start, then nothing until the next event that checks
    /// the subscription: no polling.
    private func retryAttach(retriesLeft: Int, token: Int) {
        guard retriesLeft > 0 else {
            isAttaching = false
            Self.log.notice("the Dock did not take the subscription, waiting for the next event")
            return
        }
        let attempt = Self.attachRetries - 1 - retriesLeft
        let delay = Self.attachRetryDelay * Double(1 << max(attempt, 0))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, token == self.subscriptionID else { return }
                self.attach(retriesLeft: retriesLeft)
            }
        }
    }

    private func detach() {
        subscriptionID += 1
        isAttaching = false
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
                        self.onChange(.outside)
                    case .otherItem:
                        self.onChange(.otherItem)
                    case .app(let item):
                        // An app that is not running is just another item.
                        self.onChange(self.hover(for: item, primaryHeight: primaryHeight).map(DockHoverEvent.app) ?? .otherItem)
                    case .listGone:
                        Self.log.notice("Dock list gone at a selection read, subscribing again")
                        self.resubscribe()
                    }
                }
            }
        }
    }

    /// Reads the icon under the pointer again, without reporting it: an auto-hiding Dock
    /// reports an icon while still sliding in, so its frame then is not where it rests (D36).
    /// Nil when nothing usable is selected or no subscription exists.
    func readHover(_ completion: @escaping @MainActor (DockHover?) -> Void) {
        guard let list, let primary = NSScreen.screens.first else {
            completion(nil)
            return
        }
        let primaryHeight = primary.frame.height
        AXQueues.dock.async { [weak self] in
            let selection = DockProbe.selection(in: list)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, case .app(let item) = selection else {
                        completion(nil)
                        return
                    }
                    completion(self.hover(for: item, primaryHeight: primaryHeight))
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
            hoverObserver.elementDestroyed(element)
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
