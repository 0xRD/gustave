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
    /// Room for the Dock's own name label, which appears next to the hovered icon. Set from
    /// screenshots on device: the label ends about 9 pt past the icon's frame.
    private static let tooltipClearance = 15.0
    /// How far the panel slides in from the Dock while opening.
    private static let openOffset = 6.0
    /// Slack around the icon, so the pointer can cross to the panel without it closing.
    private static let iconSlack = 6.0

    private let panel = FloatingPanel()
    private let highlight = DockPanelHover()
    private var content = DockPanelContent()
    private var actions: DockPanelActions!
    private var hostingView: FirstMouseHostingView<DockPanelView>!
    private lazy var observer = DockHoverObserver { [weak self] event in
        self?.dockPointerChanged(event)
    }

    private var hover: DockHover?
    /// True from the moment the panel opens until it starts closing, so a fade-out still on
    /// screen counts as closed.
    private var isPresented = false
    /// The frame last asked for. The window's own frame lags behind while animating.
    private var requestedFrame: CGRect?
    private var hoverDelay = Settings.defaultDockHoverDelay
    private var pendingShow: DispatchWorkItem?
    /// Present only while a show is pending: anything that means the user moved on cancels it.
    private var pendingShowMonitor: Any?
    private var pendingShowObservers: [NSObjectProtocol] = []
    private var pendingClose: DispatchWorkItem?
    private var generation = 0
    /// The generation, readable from the Accessibility queues, so work queued for an older
    /// hover is skipped instead of run.
    private let currentGeneration = GenerationToken()
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
        // Sized explicitly by `layOut`, never by autoresizing: autoresizing would add each
        // window resize on top of the size already set, leaving the content taller than the
        // panel with its top cut off.
        let tracking = HoverTrackingView()
        tracking.addSubview(hostingView)
        tracking.onHoverChange = { [weak self] inside in self?.pointerOnPanelChanged(inside) }
        tracking.onMove = { [weak self] distance in self?.pointerMovedOnPanel(distance) }
        panel.contentView = tracking
    }

    private func makeView() -> DockPanelView {
        DockPanelView(content: content, hover: highlight, actions: actions)
    }

    /// Off removes the Dock observer entirely.
    func setEnabled(_ isEnabled: Bool, hoverDelay: Double) {
        self.hoverDelay = hoverDelay
        if isEnabled {
            observer.start()
        } else {
            observer.stop()
            hide()
        }
    }

    private func dockPointerChanged(_ event: DockHoverEvent) {
        cancelShow()
        switch DockPanelRule.response(to: event.pointer) {
        case .closeAfterGrace:
            scheduleClose()
        case .closeNow:
            hide()
        case .show:
            if case .app(let hover) = event {
                hoverChanged(hover)
            }
        }
    }

    /// The first icon waits for the delay. Once the panel is open, moving along the Dock
    /// switches at once, as tooltips do.
    private func hoverChanged(_ newHover: DockHover) {
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
                self.cancelShow()
                self.loadWindows(for: hover)
            }
        }
        pendingShow = work
        watchPendingShow()
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay, execute: work)
    }

    /// A click (on the icon or anywhere), an app switch or a Space change during the delay
    /// means the user has moved on. Without this, clicking an icon before the delay ends
    /// would open the list after the app came forward and the Dock hid.
    private func watchPendingShow() {
        guard pendingShowMonitor == nil else { return }
        pendingShowMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelShow() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            pendingShowObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelShow() }
            })
        }
    }

    private func cancelShow() {
        pendingShow?.cancel()
        pendingShow = nil
        if let pendingShowMonitor {
            NSEvent.removeMonitor(pendingShowMonitor)
        }
        pendingShowMonitor = nil
        for token in pendingShowObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        pendingShowObservers = []
    }

    private func loadWindows(for hover: DockHover) {
        bumpGeneration()
        let token = generation
        let current = currentGeneration
        let pid = hover.app.processIdentifier
        let appIsHidden = hover.app.isHidden
        AXQueues.windows.async { [weak self] in
            guard current.matches(token) else { return }
            let windows = AppWindows.list(pid: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation else { return }
                    if let windows, !windows.isEmpty {
                        self.show(windows, of: hover.app)
                    } else if windows == nil {
                        // The app does not answer: no list, rather than the last app's rows.
                        self.hide()
                    } else if self.content.app?.processIdentifier != pid {
                        // Nothing here yet; other Spaces may still bring windows.
                        self.clearPanel()
                    }
                }
            }
            // Windows on other Spaces arrive second, on their own queue: the slower search
            // never delays the panel or a window action.
            guard let windows else { return }
            AXQueues.otherSpaces.async {
                guard current.matches(token) else { return }
                let others = AppWindows.otherSpaces(pid: pid, known: windows, appIsHidden: appIsHidden)
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
    }

    private func show(_ windows: [AppWindow], of app: NSRunningApplication) {
        content = DockPanelContent(
            app: app,
            appName: DisplayTitle.sanitise(app.localizedName ?? ""),
            icon: app.icon,
            windows: windows
        )
        if isPresented {
            place()
        } else {
            isPresented = true
            present()
        }
        updateHighlightFromPointer()
        installDismissal()
    }

    /// After the rows change under a still pointer, the row under it is highlighted again,
    /// so its controls stay usable.
    private func updateHighlightFromPointer() {
        guard let frame = requestedFrame, frame.contains(NSEvent.mouseLocation) else {
            highlight.row = nil
            return
        }
        pointerMovedOnPanel(frame.maxY - NSEvent.mouseLocation.y)
    }

    /// Closes what is on screen but keeps the hover and the loading in progress.
    private func clearPanel() {
        removeDismissal()
        fadeOut()
        highlight.row = nil
        content = DockPanelContent()
    }

    private func bumpGeneration() {
        generation += 1
        currentGeneration.set(generation)
    }

    /// Fades in while sliding a few points away from the Dock. The window, not the view,
    /// is animated, so the window server does the work and nothing is laid out per frame.
    private func present() {
        guard let hover, let final = targetFrame() else { return }
        var start = final
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            switch hover.edge {
            case .bottom: start.origin.y -= Self.openOffset
            case .left: start.origin.x -= Self.openOffset
            case .right: start.origin.x += Self.openOffset
            }
        }
        panel.alphaValue = 0
        setFrame(start, duration: 0)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.openDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        setFrame(final, duration: Self.openDuration)
    }

    /// Renders the current content and moves the open panel next to the icon: gliding
    /// when only the position changes, at once when the size changes.
    private func place() {
        guard let rect = targetFrame() else { return }
        let isSameSize = rect.size == requestedFrame?.size
        setFrame(rect, duration: isSameSize ? Self.moveDuration : 0)
    }

    /// The only way the panel's frame changes. Each call replaces any animation still
    /// running, so a glide that started before the content grew cannot shrink the panel
    /// back when it ends. Only same-size moves are ever animated.
    private func setFrame(_ rect: CGRect, duration: TimeInterval) {
        let isResize = rect.size != requestedFrame?.size
        requestedFrame = rect
        layOut(in: rect)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isResize ? 0 : duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(rect, display: true)
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
            bounds: hover.screenFrame,
            gap: Self.tooltipClearance
        )
        return CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    private func layOut(in rect: CGRect) {
        hostingView.frame = CGRect(origin: .zero, size: rect.size)
    }

    private func hide() {
        bumpGeneration()
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

    /// On the panel, on the icon, or in the gap between them, so a slow move from the icon
    /// to the panel does not close it on the way.
    private func isPointerInside() -> Bool {
        let pointer = NSEvent.mouseLocation
        let panelFrame = requestedFrame ?? panel.frame
        guard let icon = hover?.iconFrame else { return panelFrame.contains(pointer) }
        let slack = Self.iconSlack
        let iconFrame = CGRect(x: icon.x, y: icon.y, width: icon.width, height: icon.height)
            .insetBy(dx: -slack, dy: -slack)
        return panelFrame.union(iconFrame).contains(pointer)
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
        let app = content.app
        hide()
        app?.terminate()
    }
}
