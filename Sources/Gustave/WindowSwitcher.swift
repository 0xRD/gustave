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

    nonisolated private static let log = Logger(subsystem: "io.github.0xrd.gustave", category: "switcher")

    /// Long enough that a quick press never flashes the list.
    private static let showDelay: TimeInterval = 0.12
    private static let fadeDuration: TimeInterval = 0.1
    /// How often Option is checked while a session is open, in case its release goes unseen.
    /// Only while a session is open: nothing runs in steady state.
    private static let releaseCheckInterval: TimeInterval = 0.1

    private struct Session {
        var steps: Int
        /// The window that had focus when the session began, nil for none.
        var focused: WindowKey?
        /// Quick presses released before the list was built, each its own switch, in order.
        var earlierPresses: [Int] = []
        let cancellation = SwitcherWindows.Cancellation()
        var windows: [AppWindow]?
        var isCommitted = false
        /// The show delay has passed: show the list as soon as it is ready.
        var wantsPanel = false
    }

    private let hotKeys = HotKeyCenter()
    private let focus = FocusTracker()
    private var shortcutIDs: [UInt32] = []
    private var escapeIDs: [UInt32] = []
    private var releaseCheck: Timer?
    private var flagMonitors: [Any] = []
    private var session: Session?
    private var generation = 0
    private var pendingShow: DispatchWorkItem?
    private var isEnabled = false

    private let panel = FloatingPanel()
    private var content = SwitcherContent()
    private var hostingView: FirstMouseHostingView<SwitcherView>!

    init() {
        hostingView = FirstMouseHostingView(rootView: makeView())
        let container = NSView()
        container.addSubview(hostingView)
        panel.contentView = container
    }

    /// A refused shortcut leaves the feature off, with nothing registered or observed, and
    /// it is tried again on the next settings or permission change.
    func setEnabled(_ enabled: Bool) {
        if !enabled {
            isUnavailable = false
        }
        guard enabled != isEnabled else { return }
        if enabled {
            guard register() else { return }
            isEnabled = true
            let own = ProcessInfo.processInfo.processIdentifier
            focus.start(seed: SwitcherWindows.onScreenOrder(excluding: own))
        } else {
            isEnabled = false
            end()
            focus.stop()
            unregisterShortcuts()
        }
    }

    /// Both shortcuts or none.
    private func register() -> Bool {
        let forward = hotKeys.register(keyCode: kVK_Tab, modifiers: optionKey) { [weak self] event in
            self?.shortcut(event, step: 1)
        }
        let backward = hotKeys.register(keyCode: kVK_Tab, modifiers: optionKey | shiftKey) { [weak self] event in
            self?.shortcut(event, step: -1)
        }
        shortcutIDs = [forward, backward].compactMap { $0 }
        Self.log.debug("shortcuts registered: forward \(forward != nil), backward \(backward != nil)")
        guard forward != nil, backward != nil else {
            unregisterShortcuts()
            isUnavailable = true
            return false
        }
        isUnavailable = false
        return true
    }

    private func unregisterShortcuts() {
        for id in shortcutIDs {
            hotKeys.unregister(id)
        }
        shortcutIDs = []
    }

    private func shortcut(_ event: HotKeyCenter.Event, step: Int) {
        switch event {
        case .pressed:
            if session == nil {
                begin(steps: step)
            } else if session?.isCommitted == true {
                // The previous quick press is still waiting for the list: this is a new
                // press, not more steps of that one.
                if let earlier = session?.steps {
                    session?.earlierPresses.append(earlier)
                }
                session?.steps = step
                session?.isCommitted = false
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
        let session = Session(steps: steps, focused: focus.focusedWindow)
        self.session = session
        installSessionWatchers()

        let own = ProcessInfo.processInfo.processIdentifier
        let regularApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let regular = regularApps.map(\.processIdentifier)
        let hidden = Set(regularApps.filter(\.isHidden).map(\.processIdentifier))
        let recent = focus.recent.keys
        let cancellation = session.cancellation
        AXQueues.windows.async { [weak self] in
            // Queued behind an earlier session's work, and already over.
            guard !cancellation.isCancelled else { return }
            let started = Date()
            let server = WindowServerList.current()
            let current = SwitcherWindows.currentSpace(
                regularApps: regular, hiddenApps: hidden, excluding: own, recent: recent,
                server: server, cancellation: cancellation)
            let windows = current.ordered
            Self.log.debug("list: \(windows.count) windows (\(current.otherSpaces.count) on other Spaces, from memory) from \(regular.count) apps in \(Self.elapsed(since: started)) ms")
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, token == self.generation else { return }
                    self.windowsArrived(windows)
                }
            }

            // Other Spaces arrive second, on their own queue, so a quick press never waits
            // for them and raising the chosen window is not queued behind them.
            AXQueues.otherSpaces.async {
                // A quick press has usually committed and ended the session by now.
                guard !cancellation.isCancelled else { return }
                let full = SwitcherWindows.addingOtherSpaces(
                    to: current, regularApps: regular, hiddenApps: hidden, server: server,
                    cancellation: cancellation)
                Self.log.debug("other Spaces: \(full.windows.count - current.windows.count) windows in \(Self.elapsed(since: started)) ms")
                guard full.windows.count > current.windows.count else { return }
                let all = full.ordered
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, token == self.generation else { return }
                        self.moreWindowsArrived(all)
                    }
                }
            }
        }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, token == self.generation else { return }
                self.pendingShow = nil
                // Option's release can go unseen, for example while a password field has
                // secure input on: then switch now rather than leave the list up.
                guard NSEvent.modifierFlags.contains(.option) else {
                    self.commit()
                    return
                }
                self.session?.wantsPanel = true
                self.showPanel()
            }
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    nonisolated private static func elapsed(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    /// Windows from other Spaces joined the list. On screen, the list never reorders: they
    /// are added at the end and the selection stays where it is. A list that was empty, as
    /// on an empty Space, takes them as they come and shows once the delay has passed.
    private func moreWindowsArrived(_ windows: [AppWindow]) {
        guard let session, let old = session.windows else { return }
        guard !old.isEmpty else {
            windowsArrived(windows)
            return
        }
        if panel.isVisible {
            let known = Set(old.map(Self.key))
            self.session?.windows = old + windows.filter { !known.contains(Self.key($0)) }
        } else {
            if let selected = SwitcherSelection.index(steps: session.steps, count: old.count) {
                let key = Self.key(old[selected])
                self.session?.steps = SwitcherOrder.index(keeping: key, in: windows.map(Self.key)) ?? selected
            }
            self.session?.windows = windows
        }
        render()
    }

    private static func key(_ window: AppWindow) -> WindowKey {
        WindowKey(pid: window.pid, windowID: window.windowID ?? 0)
    }

    private func windowsArrived(_ windows: [AppWindow]) {
        guard var session else { return }
        var windows = windows
        if !session.earlierPresses.isEmpty {
            let replayed = SwitcherSelection.replay(
                session.earlierPresses, items: windows, focused: session.focused, key: Self.key)
            windows = replayed.items
            session.focused = replayed.focused
            session.earlierPresses = []
            for window in replayed.picked {
                if let windowID = window.windowID {
                    focus.touch(WindowKey(pid: window.pid, windowID: windowID))
                }
            }
            self.session = session
        }
        self.session?.windows = windows
        self.session?.steps = SwitcherSelection.steps(
            session.steps, focused: session.focused, first: windows.first.map(Self.key))
        if session.isCommitted || !NSEvent.modifierFlags.contains(.option) {
            commit()
            return
        }
        render()
        // The list took longer than the show delay: show it now.
        if session.wantsPanel, !panel.isVisible {
            showPanel()
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
        // Hot keys match modifiers exactly: Escape also cancels while Shift is held.
        escapeIDs = [optionKey, optionKey | shiftKey].compactMap { modifiers in
            hotKeys.register(keyCode: kVK_Escape, modifiers: modifiers) { [weak self] event in
                if event == .pressed {
                    self?.end()
                }
            }
        }
        // Option's release goes unseen while another app has secure input on. Checked on a
        // short timer for the life of the session only, so a missed release never leaves
        // the list up or switches later, when Option is next used for something else.
        let check = Timer(timeInterval: Self.releaseCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.commitIfOptionReleased() }
        }
        RunLoop.main.add(check, forMode: .common)
        releaseCheck = check
    }

    private func commitIfOptionReleased() {
        if let session, !session.isCommitted, !NSEvent.modifierFlags.contains(.option) {
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
        if let windowID = window.windowID {
            focus.touch(WindowKey(pid: window.pid, windowID: windowID))
        }
        AXQueues.windows.async { AppWindows.raise(window) }
    }

    private func end() {
        generation += 1
        session?.cancellation.cancel()
        session = nil
        pendingShow?.cancel()
        pendingShow = nil
        for monitor in flagMonitors {
            NSEvent.removeMonitor(monitor)
        }
        flagMonitors = []
        for id in escapeIDs {
            hotKeys.unregister(id)
        }
        escapeIDs = []
        releaseCheck?.invalidate()
        releaseCheck = nil
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

    /// Waits for the list: it shows once both the delay has passed and the list is built.
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
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        content = SwitcherContent()
    }
}
