import CoreGraphics
import Foundation
import GustaveCore

/// Builds the switcher's list when it opens. Run on `AXQueues.windows`. Apps are asked in
/// parallel, so the list costs about as much as the slowest app, not the sum of all of them.
enum SwitcherWindows {
    /// The windows found so far, by key, with what is needed to order them.
    struct Snapshot: @unchecked Sendable {
        var recent: [WindowKey] = []
        var windows: [WindowKey: AppWindow] = [:]
        var frontToBack: [WindowKey] = []
        var otherSpaces: [WindowKey] = []
        var minimized: [WindowKey] = []

        /// Most recently used first, numbered from zero.
        var ordered: [AppWindow] {
            let order = SwitcherOrder.order(
                recent: recent, frontToBack: frontToBack, otherSpaces: otherSpaces, minimized: minimized)
            return order.enumerated().compactMap { index, key in
                windows[key].map { window in
                    AppWindow(
                        id: index,
                        pid: window.pid,
                        element: window.element,
                        title: window.title,
                        isMinimized: window.isMinimized,
                        windowID: window.windowID
                    )
                }
            }
        }
    }

    /// Every switchable window on the current Space, then the minimized windows of
    /// `regularApps`. The on-screen order comes from the window server, which lists windows
    /// front to back. Only ids and layers are read, never names. Windows on other Spaces
    /// that Gustave has seen before are included too (D27): a quick press commits on this
    /// list, and the window focused before the current one may be on another Space.
    static func currentSpace(
        regularApps: [pid_t], hiddenApps: Set<pid_t>, excluding ownPID: pid_t, recent: [WindowKey]
    ) -> Snapshot {
        let frontToBack = onScreenOrder(excluding: ownPID)
        var pids: [pid_t] = []
        for pid in frontToBack.map(\.pid) + regularApps where pid != ownPID && !pids.contains(pid) {
            pids.append(pid)
        }

        let lists = inParallel(pids) { pid -> (here: [AppWindow], elsewhere: [AppWindow]) in
            guard let here = AppWindows.list(pid: pid) else { return ([], []) }
            return (here, AppWindows.remembered(pid: pid, known: here, appIsHidden: hiddenApps.contains(pid)))
        }
        var snapshot = Snapshot()
        snapshot.recent = recent
        _ = add(lists.flatMap(\.here), to: &snapshot)
        snapshot.frontToBack = frontToBack.filter { snapshot.windows[$0] != nil }
        let elsewhere = add(lists.flatMap(\.elsewhere), to: &snapshot)
        if !elsewhere.isEmpty {
            snapshot.otherSpaces = inGlobalOrder(elsewhere, allWindowsOrder())
        }
        return snapshot
    }

    /// Adds the windows of `regularApps` on other Spaces (docs/DECISIONS.md, D17), in the
    /// window server's order, which runs front to back across Spaces.
    static func addingOtherSpaces(to snapshot: Snapshot, regularApps: [pid_t], hiddenApps: Set<pid_t>) -> Snapshot {
        let known = Dictionary(grouping: snapshot.windows.values, by: \.pid)
        let found = inParallel(regularApps) { pid in
            AppWindows.otherSpaces(pid: pid, known: known[pid] ?? [], appIsHidden: hiddenApps.contains(pid))
        }

        var result = snapshot
        let added = add(Array(found.joined()), to: &result)
        let everyWindow = allWindowsOrder()
        result.otherSpaces = inGlobalOrder(snapshot.otherSpaces + added, everyWindow)
        // The one place every app's windows are listed at once: windows closed since they
        // were seen, including those of apps that quit, leave the memory here.
        if !everyWindow.isEmpty {
            SeenWindowElements.forget(except: Set(everyWindow))
        }
        return result
    }

    /// Adds windows not listed yet, and returns the keys of those that are not minimized.
    private static func add(_ windows: [AppWindow], to snapshot: inout Snapshot) -> [WindowKey] {
        var added: [WindowKey] = []
        for window in windows {
            guard let id = window.windowID else { continue }
            let key = WindowKey(pid: window.pid, windowID: id)
            guard snapshot.windows[key] == nil else { continue }
            snapshot.windows[key] = window
            if window.isMinimized {
                snapshot.minimized.append(key)
            } else {
                added.append(key)
            }
        }
        return added
    }

    private static func inGlobalOrder(_ keys: [WindowKey], _ everyWindow: [WindowKey]) -> [WindowKey] {
        let position = Dictionary(everyWindow.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return keys.sorted { (position[$0] ?? .max) < (position[$1] ?? .max) }
    }

    static func onScreenOrder(excluding ownPID: pid_t) -> [WindowKey] {
        windowKeys(options: [.optionOnScreenOnly, .excludeDesktopElements]).filter { $0.pid != ownPID }
    }

    private static func allWindowsOrder() -> [WindowKey] {
        windowKeys(options: [.optionAll, .excludeDesktopElements])
    }

    private static func windowKeys(options: CGWindowListOption) -> [WindowKey] {
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID
            else { return nil }
            return WindowKey(pid: pid, windowID: id)
        }
    }

    /// Runs `work` for each pid at once and returns the results in the same order. Each
    /// call is bounded by the Accessibility timeout, so a frozen app costs one timeout.
    private static func inParallel<T>(_ pids: [pid_t], _ work: (pid_t) -> T) -> [T] {
        let results = ParallelResults<T>(count: pids.count)
        DispatchQueue.concurrentPerform(iterations: pids.count) { index in
            results.set(work(pids[index]), at: index)
        }
        return results.values
    }
}

/// Slots written from `concurrentPerform`, each by exactly one iteration.
private final class ParallelResults<T>: @unchecked Sendable {
    private var slots: [T?]
    private let lock = NSLock()

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    func set(_ value: T, at index: Int) {
        lock.lock()
        slots[index] = value
        lock.unlock()
    }

    var values: [T] {
        lock.lock()
        defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}
