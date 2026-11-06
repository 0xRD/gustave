public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Rect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// Inclusive on all sides: a pointer pinned to a screen edge must count as inside.
    public func contains(_ point: Point) -> Bool {
        point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
    }
}

public enum DockEdge: Equatable, Sendable {
    case bottom, left, right
}

public struct DockPlacement: Equatable, Sendable {
    public var edge: DockEdge
    public var thickness: Double

    public init(edge: DockEdge, thickness: Double) {
        self.edge = edge
        self.thickness = thickness
    }
}

public enum DockGeometry {
    /// Infers the Dock from the space it reserves, in AppKit coordinates. Nil when it
    /// reserves none: it auto-hides, or it is on another screen. The menu bar reserves the
    /// top, which is why that gap is ignored.
    public static func placement(frame: Rect, visibleFrame: Rect) -> DockPlacement? {
        let gaps: [DockPlacement] = [
            DockPlacement(edge: .bottom, thickness: visibleFrame.y - frame.y),
            DockPlacement(edge: .left, thickness: visibleFrame.x - frame.x),
            DockPlacement(edge: .right, thickness: frame.maxX - visibleFrame.maxX),
        ]
        guard let largest = gaps.max(by: { $0.thickness < $1.thickness }),
              largest.thickness > 0
        else { return nil }
        return largest
    }

    /// Maps the Dock's `orientation` preference. The Dock omits it when at the bottom.
    public static func edge(orientation: String?) -> DockEdge {
        switch orientation {
        case "left": .left
        case "right": .right
        default: .bottom
        }
    }
}

/// AppKit has its origin at the bottom left of the primary screen, Accessibility at the top
/// left of it. Only y differs, and each conversion is its own inverse. Other displays can
/// have negative coordinates in either system.
public enum ScreenCoordinates {
    public static func flipped(_ point: Point, primaryScreenHeight: Double) -> Point {
        Point(x: point.x, y: primaryScreenHeight - point.y)
    }

    public static func flipped(_ rect: Rect, primaryScreenHeight: Double) -> Rect {
        Rect(
            x: rect.x,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
