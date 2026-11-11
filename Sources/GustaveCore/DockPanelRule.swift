/// What the Dock reports under the pointer, reduced to what the window list needs.
public enum DockPointer: Equatable, Sendable {
    /// Nothing is selected: the pointer has left the Dock.
    case outside
    /// Another item: a folder, the Trash, or an app that is not running.
    case otherItem
    case app(pid: Int32)
}

public enum DockPanelResponse: Equatable, Sendable {
    case show(pid: Int32)
    /// The pointer may be on its way to the panel: close only if it does not arrive.
    case closeAfterGrace
    /// The Dock says something else is under the pointer, wherever the panel is.
    case closeNow
}

public enum DockPanelRule {
    public static func response(to pointer: DockPointer) -> DockPanelResponse {
        switch pointer {
        case .outside: .closeAfterGrace
        case .otherItem: .closeNow
        case .app(let pid): .show(pid: pid)
        }
    }
}

/// Whether a list of windows is worth a panel (D37).
public enum DockPanelContentRule {
    /// A single window needs no list: clicking the icon already brings it. An open panel for
    /// the same app keeps showing its list, so closing one of two windows from it does not
    /// pull the panel from under the pointer.
    public static func shows(windowCount: Int, alreadyShowingApp: Bool) -> Bool {
        alreadyShowingApp ? windowCount > 0 : windowCount > 1
    }
}
