import AppKit
import GustaveCore

/// The running app whose Dock icon is under the pointer.
struct DockHover {
    let app: NSRunningApplication
    /// AppKit coordinates.
    let iconFrame: Rect
    let edge: DockEdge
    let screenFrame: Rect
}

/// Watches the pointer and asks the Dock what is under it, only near the Dock edge and at
/// most about 30 times a second. Installed only while the feature is on.
@MainActor
final class DockHoverMonitor {
    private static let minimumProbeInterval: TimeInterval = 1.0 / 30

    private let onChange: (DockHover?) -> Void
    private var monitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var current: DockHover?

    private var dockPID: pid_t?
    private var dockOrientation: DockEdge = .bottom

    private var isProbing = false
    private var pendingPoint: Point?
    private var lastProbe = Date.distantPast
    private var generation = 0

    init(onChange: @escaping (DockHover?) -> Void) {
        self.onChange = onChange
    }

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        refreshDockFacts()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDockFacts() }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        monitor = nil
        screenObserver = nil
        generation += 1
        isProbing = false
        pendingPoint = nil
        current = nil
    }

    /// The Dock's pid and edge change only on relaunch or a settings change, both of which
    /// change the screen parameters.
    private func refreshDockFacts() {
        dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: DockProbe.dockBundleIdentifier).first?.processIdentifier
        let orientation = UserDefaults(suiteName: DockProbe.dockBundleIdentifier)?.string(forKey: "orientation")
        dockOrientation = DockGeometry.edge(orientation: orientation)
    }

    private func pointerMoved() {
        let location = NSEvent.mouseLocation
        let pointer = Point(x: location.x, y: location.y)
        guard nearDock(pointer) != nil else {
            report(nil)
            return
        }
        probe(pointer)
    }

    /// The pointer's screen and the Dock's edge on it, when the pointer is near the Dock.
    private func nearDock(_ pointer: Point) -> (screen: Rect, edge: DockEdge)? {
        let screens = NSScreen.screens.map { screen in
            (frame: Rect(screen.frame), visible: Rect(screen.visibleFrame))
        }
        let placements = screens.map { DockGeometry.placement(frame: $0.frame, visibleFrame: $0.visible) }
        let dockAutoHides = placements.allSatisfy { $0 == nil }

        for (screen, placement) in zip(screens, placements) where screen.frame.contains(pointer) {
            if let placement {
                let near = DockGeometry.isNearDock(
                    pointer: pointer, frame: screen.frame, edge: placement.edge, thickness: placement.thickness)
                return near ? (screen.frame, placement.edge) : nil
            }
            // With a fixed Dock, a screen without the inset has no Dock.
            guard dockAutoHides else { return nil }
            let near = DockGeometry.isNearDock(
                pointer: pointer, frame: screen.frame, edge: dockOrientation, thickness: nil)
            return near ? (screen.frame, dockOrientation) : nil
        }
        return nil
    }

    private func probe(_ pointer: Point) {
        let wait = Self.minimumProbeInterval - Date().timeIntervalSince(lastProbe)
        if isProbing || wait > 0 {
            let isFirstPending = pendingPoint == nil
            pendingPoint = pointer
            if !isProbing && isFirstPending {
                // A single trailing probe, so the last position is always checked.
                let token = generation
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                    MainActor.assumeIsolated { self?.runPending(token) }
                }
            }
            return
        }
        guard let dockPID, let primary = NSScreen.screens.first else { return }

        isProbing = true
        lastProbe = Date()
        let token = generation
        let primaryHeight = primary.frame.height
        let axPoint = ScreenCoordinates.flipped(pointer, primaryScreenHeight: primaryHeight)
        AXQueues.dock.async { [weak self] in
            let item = DockProbe.item(at: axPoint, dockPID: dockPID)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finishProbe(item, pointer: pointer, primaryHeight: primaryHeight, token: token)
                }
            }
        }
    }

    private func runPending(_ token: Int) {
        guard token == generation, !isProbing, let point = pendingPoint else { return }
        pendingPoint = nil
        probe(point)
    }

    private func finishProbe(_ item: DockItem?, pointer: Point, primaryHeight: Double, token: Int) {
        guard token == generation else { return }
        isProbing = false

        if let item, let near = nearDock(pointer), let app = runningApp(at: item.appURL) {
            report(DockHover(
                app: app,
                iconFrame: ScreenCoordinates.flipped(item.frame, primaryScreenHeight: primaryHeight),
                edge: near.edge,
                screenFrame: near.screen
            ))
        } else {
            report(nil)
        }

        if let point = pendingPoint {
            pendingPoint = nil
            probe(point)
        }
    }

    private func runningApp(at url: URL) -> NSRunningApplication? {
        let target = url.standardizedFileURL
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == target }
    }

    private func report(_ hover: DockHover?) {
        guard hover?.app.processIdentifier != current?.app.processIdentifier
            || hover?.iconFrame != current?.iconFrame
        else { return }
        current = hover
        onChange(hover)
    }
}

extension Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }
}
