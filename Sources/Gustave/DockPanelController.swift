import AppKit
import GustaveCore
import SwiftUI

/// The window list shown while a Dock icon is hovered.
@MainActor
final class DockPanelController {
    private static let closeDelay: TimeInterval = 0.25
    /// Apps animate a close or minimize before reporting it.
    private static let refreshDelay: TimeInterval = 0.4
    /// Slack around the icon, so the pointer can cross to the panel without it closing.
    private static let iconSlack = 6.0

    private let panel = FloatingPanel()
    private let highlight = DockPanelHover()
    private var content = DockPanelContent()
    private var actions: DockPanelActions!
    private var hostingView: FirstMouseHostingView<DockPanelView>!
    private lazy var observer = DockHoverObserver { [weak self] hover in
        self?.hoverChanged(hover)
    }

    private var hover: DockHover?
    private var pendingClose: DispatchWorkItem?
    private var generation = 0
    /// Present only while the panel is visible, to close it the moment it is left behind.
    private var dismissMonitor: Any?
    private var spaceObserver: NSObjectProtocol?

    init() {
        actions = DockPanelActions(
            select: { [weak self] window in self?.select(window) },
            close: { [weak self] window in self?.close(window) },
            toggleMinimized: { [weak self] window in self?.toggleMinimized(window) },
            toggleFullScreen: { [weak self] window in self?.toggleFullScreen(window) },
            quit: { [weak self] in self?.quit() }
        )
        hostingView = FirstMouseHostingView(rootView: makeView())
        let material = FloatingPanel.materialView(around: hostingView)
        material.autoresizingMask = [.width, .height]
        let tracking = HoverTrackingView()
        tracking.addSubview(material)
        tracking.onHoverChange = { [weak self] inside in self?.pointerOnPanelChanged(inside) }
        tracking.onMove = { [weak self] distance in self?.pointerMovedOnPanel(distance) }
        panel.contentView = tracking
    }

    private func makeView() -> DockPanelView {
        DockPanelView(content: content, hover: highlight, actions: actions)
    }

    /// Off removes the Dock observer entirely.
    func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            observer.start()
        } else {
            observer.stop()
            hide()
        }
    }

    private func hoverChanged(_ newHover: DockHover?) {
        guard let newHover else {
            scheduleClose()
            return
        }
        cancelClose()
        let isSameApp = newHover.app.processIdentifier == hover?.app.processIdentifier
        hover = newHover
        if isSameApp && panel.isVisible {
            place()
        } else {
            loadWindows(for: newHover)
        }
    }

    private func loadWindows(for hover: DockHover) {
        generation += 1
        let token = generation
        let pid = hover.app.processIdentifier
        AXQueues.windows.async { [weak self] in
            let windows = AppWindows.list(pid: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation else { return }
                    if let windows, !windows.isEmpty {
                        self.show(windows, of: hover.app)
                    }
                }
            }
            // Windows on other Spaces arrive second: the slower search never delays the panel.
            guard let windows else { return }
            let others = AppWindows.otherSpaces(pid: pid, known: windows)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation else { return }
                    let all = windows + others
                    if all.isEmpty {
                        self.hide()
                    } else if !others.isEmpty || !self.panel.isVisible {
                        self.show(all, of: hover.app)
                    }
                }
            }
        }
    }

    private func show(_ windows: [AppWindow], of app: NSRunningApplication) {
        content = DockPanelContent(
            appName: DisplayTitle.sanitise(app.localizedName ?? ""),
            icon: app.icon,
            windows: windows
        )
        highlight.row = nil
        place()
        panel.orderFrontRegardless()
        installDismissal()
    }

    /// Renders the current content, measures it, and moves the panel next to the icon.
    private func place() {
        guard let hover else { return }
        hostingView.rootView = makeView()
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let frame = PanelPlacement.frame(
            width: size.width,
            height: size.height,
            anchor: hover.iconFrame,
            edge: hover.edge,
            bounds: hover.screenFrame
        )
        let rect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        panel.setFrame(rect, display: true)
        panel.contentView?.subviews.first?.frame = CGRect(origin: .zero, size: rect.size)
        panel.invalidateShadow()
    }

    private func hide() {
        generation += 1
        cancelClose()
        removeDismissal()
        panel.orderOut(nil)
        hover = nil
        highlight.row = nil
        content = DockPanelContent()
    }

    // MARK: Closing

    private func installDismissal() {
        guard dismissMonitor == nil else { return }
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                // Global monitors only see events for other apps: a click is never on the panel.
                if event.type == .mouseMoved {
                    self?.pointerMovedElsewhere()
                } else {
                    self?.hide()
                }
            }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeDismissal() {
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        dismissMonitor = nil
        spaceObserver = nil
    }

    private func isPointerInside() -> Bool {
        let pointer = NSEvent.mouseLocation
        if panel.frame.contains(pointer) {
            return true
        }
        guard let icon = hover?.iconFrame else { return false }
        let slack = Self.iconSlack
        return CGRect(x: icon.x, y: icon.y, width: icon.width, height: icon.height)
            .insetBy(dx: -slack, dy: -slack)
            .contains(pointer)
    }

    private func pointerMovedElsewhere() {
        if isPointerInside() {
            cancelClose()
        } else if pendingClose == nil {
            scheduleClose()
        }
    }

    private func pointerOnPanelChanged(_ inside: Bool) {
        if inside {
            cancelClose()
        } else {
            highlight.row = nil
            scheduleClose()
        }
    }

    private func pointerMovedOnPanel(_ distanceFromTop: Double) {
        let rows = min(content.windows.count, DockPanelView.maxRows)
        let row = DockPanelLayout.rowIndex(atDistanceFromTop: distanceFromTop, rowCount: rows)
        if highlight.row != row {
            highlight.row = row
        }
    }

    private func scheduleClose() {
        cancelClose()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingClose = nil
                if !self.isPointerInside() {
                    self.hide()
                }
            }
        }
        pendingClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDelay, execute: work)
    }

    private func cancelClose() {
        pendingClose?.cancel()
        pendingClose = nil
    }

    // MARK: Actions

    private func select(_ window: AppWindow) {
        hide()
        AXQueues.windows.async { AppWindows.raise(window) }
    }

    private func close(_ window: AppWindow) {
        perform({ AppWindows.close($0) }, on: window)
    }

    private func toggleMinimized(_ window: AppWindow) {
        perform({ AppWindows.toggleMinimized($0) }, on: window)
    }

    /// Runs the action, then shows what the app reports afterwards rather than a guess.
    private func perform(_ action: @escaping @Sendable (AppWindow) -> Void, on window: AppWindow) {
        AXQueues.windows.async { action(window) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let hover = self.hover, hover.app.processIdentifier == window.pid else { return }
                self.loadWindows(for: hover)
            }
        }
    }

    private func toggleFullScreen(_ window: AppWindow) {
        hide()
        AXQueues.windows.async { AppWindows.toggleFullScreen(window) }
    }

    private func quit() {
        let app = hover?.app
        hide()
        app?.terminate()
    }
}
