import AppKit
import Carbon.HIToolbox
import Combine
import GustaveCore
import os
import SwiftUI

/// Windows-style Option+Tab. A quick press switches to the previous window without showing
/// anything; holding Option shows the list, Tab and Shift+Tab move, releasing Option
/// switches, Option+Escape cancels. Nothing is registered while the feature is off.
@MainActor
final class WindowSwitcher: ObservableObject {
    /// True when the feature is on but the system refused the shortcut.
    @Published private(set) var isUnavailable = false

    private static let log = Logger(subsystem: "io.github.0xrd.gustave", category: "switcher")

    /// Long enough that a quick press never flashes the list.
    private static let showDelay: TimeInterval = 0.12
    private static let fadeDuration: TimeInterval = 0.1

    private struct Session {
        var steps: Int
        var windows: [AppWindow]?
        var isCommitted = false
    }

    private let hotKeys = HotKeyCenter()
    private var shortcutIDs: [UInt32] = []
    private var escapeID: UInt32?
    private var flagMonitors: [Any] = []
    private var session: Session?
    private var generation = 0
    private var pendingShow: DispatchWorkItem?
    private var isEnabled = false

    private let panel = FloatingPanel()
    private var content = SwitcherContent()
    private var hostingView: FirstMouseHostingView<SwitcherView>!
    private var materialView: NSView!

    init() {
        hostingView = FirstMouseHostingView(rootView: makeView())
        materialView = FloatingPanel.materialView(around: hostingView)
        let container = NSView()
        container.addSubview(materialView)
        panel.contentView = container
    }

    func setEnabled(_ enabled: Bool, glass: PanelGlass) {
        GlassStyle.apply(glass, to: materialView)
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            register()
        } else {
            end()
            for id in shortcutIDs {
                hotKeys.unregister(id)
            }
            shortcutIDs = []
            isUnavailable = false
        }
    }

    private func register() {
        let forward = hotKeys.register(keyCode: kVK_Tab, modifiers: optionKey) { [weak self] event in
            self?.shortcut(event, step: 1)
        }
        let backward = hotKeys.register(keyCode: kVK_Tab, modifiers: optionKey | shiftKey) { [weak self] event in
            self?.shortcut(event, step: -1)
        }
        shortcutIDs = [forward, backward].compactMap { $0 }
        isUnavailable = forward == nil
        Self.log.debug("shortcuts registered: forward \(forward != nil), backward \(backward != nil)")
    }

    private func shortcut(_ event: HotKeyCenter.Event, step: Int) {
        switch event {
        case .pressed:
            if session == nil {
                begin(steps: step)
            } else {
                session?.steps += step
                render()
            }
        case .released:
            // Covers a press so quick that Option is already up when Tab comes up.
            commitIfOptionReleased()
        }
    }

    // MARK: Session

    private func begin(steps: Int) {
        generation += 1
        let token = generation
        session = Session(steps: steps)
        installSessionWatchers()

        let own = ProcessInfo.processInfo.processIdentifier
        let regular = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map(\.processIdentifier)
        AXQueues.windows.async { [weak self] in
            let windows = SwitcherWindows.collect(regularApps: regular, excluding: own)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation else { return }
                    self.windowsArrived(windows)
                }
            }
        }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, token == self.generation else { return }
                self.pendingShow = nil
                self.showPanel()
            }
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    private func windowsArrived(_ windows: [AppWindow]) {
        session?.windows = windows
        if session?.isCommitted == true {
            commit()
        } else {
            render()
        }
    }

    /// Option is the key that ends a session, so its release is watched while one is open,
    /// and only then. Global monitors see other apps' events, local ones Gustave's own.
    private func installSessionWatchers() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard !event.modifierFlags.contains(.option) else { return }
            MainActor.assumeIsolated { self?.commit() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) {
            flagMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            handler(event)
            return event
        }) {
            flagMonitors.append(local)
        }
        escapeID = hotKeys.register(keyCode: kVK_Escape, modifiers: optionKey) { [weak self] event in
            if event == .pressed {
                self?.end()
            }
        }
    }

    private func commitIfOptionReleased() {
        if session != nil, !NSEvent.modifierFlags.contains(.option) {
            commit()
        }
    }

    /// Switches to the selection, or waits for the list if it is still being built.
    private func commit() {
        guard let session else { return }
        guard let windows = session.windows else {
            self.session?.isCommitted = true
            return
        }
        let index = SwitcherSelection.index(steps: session.steps, count: windows.count)
        Self.log.debug("switch: \(windows.count) windows, steps \(session.steps), index \(index ?? -1)")
        end()
        if let index {
            activate(windows[index])
        }
    }

    private func select(_ index: Int) {
        guard let windows = session?.windows, windows.indices.contains(index) else { return }
        end()
        activate(windows[index])
    }

    private func activate(_ window: AppWindow) {
        AXQueues.windows.async { AppWindows.raise(window) }
    }

    private func end() {
        generation += 1
        session = nil
        pendingShow?.cancel()
        pendingShow = nil
        for monitor in flagMonitors {
            NSEvent.removeMonitor(monitor)
        }
        flagMonitors = []
        if let escapeID {
            hotKeys.unregister(escapeID)
        }
        escapeID = nil
        hidePanel()
    }

    // MARK: Panel

    private func makeView() -> SwitcherView {
        SwitcherView(content: content) { [weak self] index in self?.select(index) }
    }

    private func render() {
        guard let session, let windows = session.windows else { return }
        let icons = Dictionary(
            Set(windows.map(\.pid)).compactMap { pid in
                NSRunningApplication(processIdentifier: pid)?.icon.map { (pid, $0) }
            },
            uniquingKeysWith: { first, _ in first })
        content = SwitcherContent(
            windows: windows,
            icons: icons,
            selection: SwitcherSelection.index(steps: session.steps, count: windows.count)
        )
        if panel.isVisible {
            layOut()
        }
    }

    private func showPanel() {
        guard session?.windows?.isEmpty == false else { return }
        layOut()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            panel.animator().alphaValue = 1
        }
    }

    /// Centred on the screen with the pointer, like the system switcher.
    private func layOut() {
        hostingView.rootView = makeView()
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = CGRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        materialView.frame = CGRect(origin: .zero, size: frame.size)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        content = SwitcherContent()
    }
}
