import AppKit
import SwiftUI

/// Gustave's palette: Hector's warm canvas and calm verdict colours (Hector, docs/DESIGN.md),
/// plus the colours of Gustave's own mark. Each colour has a light and a dark variant.
extension Color {
    static let gustaveOK = dynamic(light: (0.24, 0.44, 0.33), dark: (0.55, 0.78, 0.62))
    static let gustaveWarning = dynamic(light: (0.53, 0.37, 0.05), dark: (0.92, 0.77, 0.46))
    static let gustaveOKWash = dynamic(light: (0.87, 0.92, 0.86), dark: (0.19, 0.25, 0.21))
    static let gustaveWarningWash = dynamic(light: (0.98, 0.92, 0.79), dark: (0.28, 0.23, 0.14))

    static let surfaceCanvas = dynamic(light: (0.973, 0.957, 0.933), dark: (0.133, 0.122, 0.114))
    static let surfaceCard = dynamic(light: (1.0, 0.992, 0.980), dark: (0.176, 0.165, 0.153))
    static let surfaceStroke = dynamic(light: (0.24, 0.20, 0.15), dark: (1.0, 0.95, 0.88), lightAlpha: 0.10, darkAlpha: 0.09)

    /// The mark's own colours, the same in light and dark, as an app icon is.
    static let markInk = Color(red: 0.17, green: 0.15, blue: 0.24)
    static let markCap = Color(red: 0.25, green: 0.56, blue: 0.53)
    static let markBrim = Color(red: 0.19, green: 0.45, blue: 0.43)
    static let markFace = Color(red: 0.96, green: 0.89, blue: 0.82)
    static let markCheek = Color(red: 0.95, green: 0.76, blue: 0.70)
    static let markMoustache = Color(red: 0.42, green: 0.29, blue: 0.22)
    static let markWall = Color(red: 0.88, green: 0.82, blue: 0.70)
    static let markMortar = Color(red: 0.79, green: 0.71, blue: 0.56)
    static let markSun = Color(red: 0.95, green: 0.83, blue: 0.53)
    static let markSky = Color(red: 0.86, green: 0.93, blue: 0.90)

    private static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double),
        lightAlpha: Double = 1,
        darkAlpha: Double = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}
