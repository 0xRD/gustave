import AppKit
import ApplicationServices
import GustaveCore

/// The running app whose Dock icon is under the pointer.
struct DockHover {
    let app: NSRunningApplication
    /// AppKit coordinates.
    let iconFrame: Rect
    let edge: DockEdge
    let screenFrame: Rect
}

/// Follows the Dock's own selection, which is the icon under the pointer. The Dock reports
/// every change through Accessibility, so there is no mouse monitor and no polling.
@MainActor
final class DockHoverObserver {
    private let onChange: (DockHover?) -> Void

    private var isRunning = false
    private var observer: AXObserver?
    private var list: AXElement?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var current: DockHover?
    private var generation = 0

    init(onChange: @escaping (DockHover?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        // The Dock restarts when its settings change or it crashes.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == DockProbe.dockBundleIdentifier else { return }
                MainActor.assumeIsolated { self?.attach() }
            })
        }
        attach()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers = []
        detach()
        current = nil
    }

    private func attach() {
        detach()
        guard let dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: DockProbe.dockBundleIdentifier).first?.processIdentifier
        else { return }

        let token = generation
        // The observer lives as long as the app, so an unretained pointer is safe.
        let address = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        AXQueues.dock.async { [weak self] in
            guard let refcon = UnsafeMutableRawPointer(bitPattern: address) else { return }
            let subscription = DockProbe.subscribe(dockPID: dockPID, callback: dockSelectionChanged, refcon: refcon)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let subscription, token == self.generation, self.isRunning else { return }
                    self.observer = subscription.observer
                    self.list = subscription.list
                    CFRunLoopAddSource(
                        CFRunLoopGetMain(), AXObserverGetRunLoopSource(subscription.observer), .commonModes)
                }
            }
        }
    }

    private func detach() {
        generation += 1
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            if let list {
                AXObserverRemoveNotification(observer, list.raw, kAXSelectedChildrenChangedNotification as CFString)
            }
        }
        observer = nil
        list = nil
    }

    fileprivate func selectionChanged() {
        guard let list, let primary = NSScreen.screens.first else { return }
        generation += 1
        let token = generation
        let primaryHeight = primary.frame.height
        AXQueues.dock.async { [weak self] in
            let item = DockProbe.selectedItem(in: list)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation else { return }
                    self.report(item.flatMap { self.hover(for: $0, primaryHeight: primaryHeight) })
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
        guard let screen = NSScreen.screens.first(where: { Rect($0.frame).contains(centre) }) else { return nil }

        let frame = Rect(screen.frame)
        let edge = DockGeometry.placement(frame: frame, visibleFrame: Rect(screen.visibleFrame))?.edge
            ?? DockGeometry.edge(orientation: UserDefaults(suiteName: DockProbe.dockBundleIdentifier)?
                .string(forKey: "orientation"))
        return DockHover(app: app, iconFrame: iconFrame, edge: edge, screenFrame: frame)
    }

    private func report(_ hover: DockHover?) {
        guard hover?.app.processIdentifier != current?.app.processIdentifier
            || hover?.iconFrame != current?.iconFrame
        else { return }
        current = hover
        onChange(hover)
    }
}

private func dockSelectionChanged(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    // The run loop source is on the main run loop.
    let hoverObserver = Unmanaged<DockHoverObserver>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { hoverObserver.selectionChanged() }
}

extension Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }
}
