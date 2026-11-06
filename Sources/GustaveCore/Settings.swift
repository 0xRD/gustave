import Foundation

/// User preferences. Every feature is off until the user turns it on, so nothing is
/// monitored on a first launch.
public struct Settings: Equatable, Sendable {
    public var dockListEnabled = false
    public var switcherEnabled = false
    public var invertMouseScroll = false
    public var invertTrackpadScroll = false
    /// Seconds the pointer rests on a Dock icon before its window list opens.
    public var dockHoverDelay = Settings.defaultDockHoverDelay {
        didSet { dockHoverDelay = Settings.clampedDelay(dockHoverDelay) }
    }

    public static let defaultDockHoverDelay = 0.5
    public static let dockHoverDelayRange = 0.0...2.0

    public init() {}

    static func clampedDelay(_ value: Double) -> Double {
        guard value.isFinite else { return defaultDockHoverDelay }
        return min(max(value, dockHoverDelayRange.lowerBound), dockHoverDelayRange.upperBound)
    }
}

extension Settings: Codable {
    private enum CodingKeys: String, CodingKey {
        case dockListEnabled, switcherEnabled, invertMouseScroll, invertTrackpadScroll, dockHoverDelay
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }

        // A wrong type for one key must not cost the user the other settings.
        func flag(_ key: CodingKeys, default fallback: Bool) -> Bool {
            (try? container.decodeIfPresent(Bool.self, forKey: key)) ?? fallback
        }
        dockListEnabled = flag(.dockListEnabled, default: dockListEnabled)
        switcherEnabled = flag(.switcherEnabled, default: switcherEnabled)
        invertMouseScroll = flag(.invertMouseScroll, default: invertMouseScroll)
        invertTrackpadScroll = flag(.invertTrackpadScroll, default: invertTrackpadScroll)
        // Observers do not run inside the type's own initialiser, so clamp here too.
        if let delay = try? container.decodeIfPresent(Double.self, forKey: .dockHoverDelay) {
            dockHoverDelay = Settings.clampedDelay(delay)
        }
    }

    /// Never fails: anything unreadable decodes to the defaults.
    public static func decoded(from data: Data) -> Settings {
        (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)) ?? Data()
    }
}
