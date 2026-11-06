import AppKit
import GustaveCore
import SwiftUI

/// The window list shown while a Dock icon is hovered.
@MainActor
final class DockPanelController {
    private static let closeDelay: TimeInterval = 0.25
    /// Apps animate a close or minimize before reporting it.
    private static let refreshDelay: TimeInterval = 0.4
    /// Short, so the panel feels like a system popover and costs a few frames of compositing.
    private static let openDuration: TimeInterval = 0.16
    private static let closeDuration: TimeInterval = 0.1
    private static let moveDuration: TimeInterval = 0.12
    /// How far the panel slides in from the Dock while opening.
    private static let openOffset = 6.0
    /// Slack around the icon, so the pointer can cross to the panel without it closing.
    private static let iconSlack = 6.0

    private let panel = FloatingPanel()
    private let highlight = DockPanelHover()
    private var content = DockPanelContent()
    private var actions: DockPanelActions!
    private var hostingView: FirstMouseHostingView<DockPanelView>!
    private var materialView: NSView!
    private lazy var observer = DockHoverObserver { [weak self] hover in
        self?.hoverChanged(hover)
    }

    private var hover: DockHover?
    /// True from the moment the panel opens until it starts closing, so a fade-out still on
    /// screen counts as closed.
    private var isPresented = false
    private var hoverDelay = Settings.defaultDockHoverDelay
    private var pendingShow: DispatchWorkItem?
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
        materialView = material
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
    func setEnabled(_ isEnabled: Bool, hoverDelay: Double, glass: PanelGlass) {
        self.hoverDelay = hoverDelay
        GlassStyle.apply(glass, to: materialView)
        if isEnabled {
            observer.start()
        } else {
            observer.stop()
            hide()
        }
    }

    /// The first icon waits for the delay. Once the panel is open, moving along the Dock
    /// switches at once, as tooltips do.
    private func hoverChanged(_ newHover: DockHover?) {
        cancelShow()
        guard let newHover else {
            scheduleClose()
            return
        }
        cancelClose()
        let isSameApp = newHover.app.processIdentifier == hover?.app.processIdentifier
        hover = newHover
        if isPresented {
            if isSameApp {
                place()
            } else {
                loadWindows(for: newHover)
            }
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let hover = self.hover, hover.app.processIdentifier == newHover.app.processIdentifier
                else { return }
                self.pendingShow = nil
                self.loadWindows(for: hover)
            }
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: work)
    }

    private func cancelShow() {
        pendingShow?.cancel()
        pendingShow = nil
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
                    } else if !others.isEmpty || !self.isPresented {
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
        if isPresented {
            place()
        } else {
            isPresented = true
            present()
        }
        installDismissal()
    }

    /// Fades in while sliding a few points away from the Dock. The window, not the view,
    /// is animated, so the window server does the work and nothing is laid out per frame.
    private func present() {
        guard let hover, let final = targetFrame() else { return }
        layOut(in: final)
        var start = final
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            switch hover.edge {
            case .bottom: start.origin.y -= Self.openOffset
            case .left: start.origin.x -= Self.openOffset
            case .right: start.origin.x += Self.openOffset
            }
        }
        panel.alphaValue = 0
        panel.setFrame(start, display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.openDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(final, display: false)
        }
    }

    /// Renders the current content and moves the open panel next to the icon: gliding
    /// when only the position changes, at once when the size changes.
    private func place() {
        guard let rect = targetFrame() else { return }
        if rect.size == panel.frame.size {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.moveDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(rect, display: false)
            }
        } else {
            layOut(in: rect)
            panel.setFrame(rect, display: true)
        }
        panel.invalidateShadow()
    }

    /// Renders the current content, measures it, and places it next to the icon.
    private func targetFrame() -> CGRect? {
        guard let hover else { return nil }
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
        return CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    private func layOut(in rect: CGRect) {
        panel.contentView?.subviews.first?.frame = CGRect(origin: .zero, size: rect.size)
    }

    private func hide() {
        generation += 1
        cancelShow()
        cancelClose()
        removeDismissal()
        fadeOut()
        hover = nil
        highlight.row = nil
        content = DockPanelContent()
    }

    // MARK: Closing

    private func fadeOut() {
        guard isPresented else { return }
        isPresented = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.closeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Reopened during the fade: leave it on screen.
                guard let self, !self.isPresented else { return }
                self.panel.orderOut(nil)
            }
        }
    }

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
