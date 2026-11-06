import AppKit
import GustaveCore
import SwiftUI

/// The window list shown while a Dock icon is hovered.
@MainActor
final class DockPanelController {
    private static let closeDelay: TimeInterval = 0.25

    private let panel = FloatingPanel()
    private let highlight = DockPanelHover()
    private var content = DockPanelContent()
    private var actions: DockPanelActions!
    private var hostingView: FirstMouseHostingView<DockPanelView>!
    private lazy var observer = DockHoverObserver { [weak self] hover in
        self?.hoverChanged(hover)
    }

    private var hover: DockHover?
    private var isPointerOnIcon = false
    private var isPointerOnPanel = false
    private var pendingClose: DispatchWorkItem?
    private var generation = 0

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
        content = DockPanelContent(
            appName: DisplayTitle.sanitise(app.localizedName ?? ""),
            icon: app.icon,
            windows: windows
        )
        highlight.window = nil
        place()
        panel.orderFrontRegardless()
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
        panel.orderOut(nil)
        hover = nil
        isPointerOnPanel = false
        content = DockPanelContent()
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
        content.windows.removeAll { $0.id == window.id }
        if content.windows.isEmpty {
            hide()
        } else {
            place()
        }
    }

    private func toggleMinimized(_ window: AppWindow) {
        AXQueues.windows.async { AppWindows.toggleMinimized(window) }
        if let index = content.windows.firstIndex(where: { $0.id == window.id }) {
            content.windows[index] = AppWindow(
                id: window.id,
                pid: window.pid,
                element: window.element,
                title: window.title,
                isMinimized: !window.isMinimized
            )
            place()
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
