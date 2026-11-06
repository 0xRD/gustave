/// Fixed metrics of the window list. The row under the pointer is computed from them,
/// because SwiftUI hover tracking does not run while Gustave is not the active app.
public enum DockPanelLayout {
    public static let padding = 5.0
    public static let headerHeight = 28.0
    public static let separatorHeight = 9.0
    public static let rowHeight = 26.0

    /// The row at `distanceFromTop` points below the panel's top edge, if any.
    public static func rowIndex(atDistanceFromTop distanceFromTop: Double, rowCount: Int) -> Int? {
        let offset = distanceFromTop - padding - headerHeight - separatorHeight
        guard offset >= 0, rowCount > 0 else { return nil }
        let index = Int(offset / rowHeight)
        return index < rowCount ? index : nil
    }
}
