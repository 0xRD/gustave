/// How the list the Dock subscription is on answered a read.
public enum DockListAnswer: Equatable, Sendable {
    case answered
    /// The Dock says the element no longer exists.
    case gone
    /// A timeout or another failure: the Dock may only be busy.
    case silent
}

/// The list the Dock shows now, compared with the one the subscription is on.
public enum DockCurrentList: Equatable, Sendable {
    case same
    case different
    /// The Dock answered, and has no list.
    case missing
    /// The Dock did not answer, or was not asked.
    case unknown
}

/// The Dock can replace its list of icons while keeping its process. A subscription left on
/// the old list reports nothing and fails nothing, so it has to be checked (D35).
public enum DockSubscriptionHealth {
    /// True only on proof. A Dock that does not answer keeps its subscription: making it
    /// again would fail the same way, and the next check decides.
    public static func isStale(subscribed: DockListAnswer, current: DockCurrentList) -> Bool {
        switch subscribed {
        case .gone: true
        case .silent: false
        case .answered: current == .different || current == .missing
        }
    }
}
