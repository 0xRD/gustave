/// The glass styles offered for the window list, picked by the user from live samples on
/// macOS 26. The raw values are the private glass variants (docs/DECISIONS.md, D19). Only
/// these constants ever reach the glass view: out-of-range values stop the process.
public enum PanelGlass: Int, CaseIterable, Codable, Sendable {
    case variant2 = 2
    case variant6 = 6
    case variant11 = 11

    public static let `default` = PanelGlass.variant6

    public var label: String {
        switch self {
        case .variant2: "V2"
        case .variant6: "V6"
        case .variant11: "V11"
        }
    }
}
