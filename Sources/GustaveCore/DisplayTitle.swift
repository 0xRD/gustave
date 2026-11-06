/// Turns text from another app into something safe to show as a single plain line.
public enum DisplayTitle {
    public static let placeholder = "Untitled"
    public static let maxCharacters = 120

    /// Scalars read from the input. Keeps the cost constant on hostile titles.
    static let inputLimit = 2048
    /// Stops a single character from stacking marks past the height of its row.
    static let maxConsecutiveMarks = 2

    public static func sanitise(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.prefix(inputLimit)
        let wasClipped = scalars.endIndex != raw.unicodeScalars.endIndex

        var clean = String.UnicodeScalarView()
        var pendingSpace = false
        var consecutiveMarks = 0

        for scalar in scalars {
            let properties = scalar.properties
            if properties.isWhitespace {
                pendingSpace = !clean.isEmpty
                consecutiveMarks = 0
                continue
            }
            if isInvisible(scalar) {
                continue
            }
            if isMark(properties.generalCategory) {
                consecutiveMarks += 1
                if consecutiveMarks > maxConsecutiveMarks { continue }
            } else {
                consecutiveMarks = 0
            }
            if pendingSpace {
                clean.append(" ")
                pendingSpace = false
            }
            clean.append(scalar)
        }

        let title = String(clean)
        if title.isEmpty {
            return placeholder
        }
        // A clipped input also ends with an ellipsis, so it may keep one character less.
        let limit = wasClipped ? maxCharacters - 1 : maxCharacters
        if title.count > limit {
            return withEllipsis(String(title.prefix(maxCharacters - 1)))
        }
        return wasClipped ? withEllipsis(title) : title
    }

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isDefaultIgnorableCodePoint {
            return true
        }
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned:
            return true
        default:
            return false
        }
    }

    private static func isMark(_ category: Unicode.GeneralCategory) -> Bool {
        switch category {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return false
        }
    }

    private static func withEllipsis(_ text: String) -> String {
        var text = Substring(text)
        while text.last == " " {
            text.removeLast()
        }
        return text + "…"
    }
}
