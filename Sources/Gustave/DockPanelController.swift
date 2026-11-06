import AppKit
import GustaveCore
import SwiftUI

/// The window list shown while a Dock icon is hovered.
@MainActor
final class DockPanelController {
    private static let closeDelay: TimeInterval = 0.25

    private let panel = FloatingPanel()
    private let model = DockPanelModel()
    private var hostingView: NSView?
    private lazy var monitor = DockHoverMonitor { [weak self] hover in
        self?.hoverChanged(hover)
    }

    private var hover: DockHover?
    private var isPointerOnIcon = false
    private var isPointerOnPanel = false
    private var pendingClose: DispatchWorkItem?
    private var generation = 0

    init() {
        let actions = DockPanelActions(
            select: { [weak self] window in self?.select(window) },
            close: { [weak self] window in self?.close(window) },
            toggleMinimized: { [weak self] window in self?.toggleMinimized(window) },
            toggleFullScreen: { [weak self] window in self?.toggleFullScreen(window) },
            quit: { [weak self] in self?.quit() }
        )
        let hosting = FirstMouseHostingView(rootView: DockPanelView(model: model, actions: actions))
        let tracking = HoverTrackingView()
        tracking.addSubview(hosting)
        tracking.onHoverChange = { [weak self] inside in self?.pointerOnPanelChanged(inside) }
        panel.contentView = tracking
        hostingView = hosting
    }

    /// Off removes the mouse monitor entirely.
    func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            monitor.start()
        } else {
            monitor.stop()
            hide()
        }
    }

    private func hoverChanged(_ newHover: DockHover?) {
        guard let newHover else {
            isPointerOnIcon = false
            scheduleClose()
            return
        }
        isPointerOnIcon = true
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
                    } else {
                        self.hide()
                    }
                }
            }
        }
    }

    private func show(_ windows: [AppWindow], of app: NSRunningApplication) {
        model.appName = DisplayTitle.sanitise(app.localizedName ?? "")
        model.icon = app.icon
        model.windows = windows
        place()
        panel.orderFrontRegardless()
    }

    private func place() {
        guard let hover, let hostingView else { return }
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
        hostingView.frame = CGRect(origin: .zero, size: rect.size)
    }

    private func hide() {
        generation += 1
        cancelClose()
        panel.orderOut(nil)
        hover = nil
        isPointerOnPanel = false
        model.windows = []
    }

    private func pointerOnPanelChanged(_ inside: Bool) {
        isPointerOnPanel = inside
        if inside {
            cancelClose()
        } else {
            scheduleClose()
        }
    }

    private func scheduleClose() {
        cancelClose()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isPointerOnIcon, !self.isPointerOnPanel else { return }
                self.hide()
            }
        }
        pendingClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDelay, execute: work)
    }

    private func cancelClose() {
        pendingClose?.cancel()
        pendingClose = nil
    }

    private func select(_ window: AppWindow) {
        hide()
        AXQueues.windows.async { AppWindows.raise(window) }
    }

    private func close(_ window: AppWindow) {
        AXQueues.windows.async { AppWindows.close(window) }
        model.windows.removeAll { $0.id == window.id }
        if model.windows.isEmpty {
            hide()
        } else {
            place()
        }
    }

    private func toggleMinimized(_ window: AppWindow) {
        AXQueues.windows.async { AppWindows.toggleMinimized(window) }
        if let index = model.windows.firstIndex(where: { $0.id == window.id }) {
            model.windows[index] = AppWindow(
                id: window.id,
                pid: window.pid,
                element: window.element,
                title: window.title,
                isMinimized: !window.isMinimized
            )
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
