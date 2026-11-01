public enum ScrollDevice: Equatable, Sendable {
    case mouse
    case trackpad

    /// Wheel mice send stepped events. Magic Mouse sends continuous ones, so it counts as
    /// a trackpad (see SPEC, F3).
    public init(isContinuous: Bool) {
        self = isContinuous ? .trackpad : .mouse
    }
}

public enum ScrollRule {
    /// The event tap exists only while this is true.
    public static func needsEventTap(_ settings: Settings) -> Bool {
        settings.invertMouseScroll || settings.invertTrackpadScroll
    }

    public static func shouldInvert(_ device: ScrollDevice, settings: Settings) -> Bool {
        switch device {
        case .mouse: settings.invertMouseScroll
        case .trackpad: settings.invertTrackpadScroll
        }
    }

    /// Delta for an inverted event. Event fields are arbitrary 64-bit values, and plain
    /// negation of the smallest one would trap inside the event tap.
    public static func inverted(_ delta: Int64) -> Int64 {
        delta == .min ? .max : -delta
    }
}
