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
