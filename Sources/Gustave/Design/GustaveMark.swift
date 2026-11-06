import SwiftUI

/// Gustave, drawn in code on a 24 by 24 grid like Hector's helmet: a flat-capped, moustached
/// neighbour peeking over the same wall, with the same sun. Taken from the app icon.
struct GustaveMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.scaleBy(x: scale, y: scale)
            let ink = GraphicsContext.Shading.color(.markInk)
            let line = StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round)

            let tile = Path(roundedRect: CGRect(x: 0, y: 0, width: 24, height: 24), cornerRadius: 5.4, style: .continuous)
            context.fill(tile, with: .color(.markSky))
            context.fill(Path(ellipseIn: CGRect(x: 14.6, y: 3.9, width: 5.6, height: 5.6)), with: .color(.markSun))

            // The face, partly hidden by the wall drawn after it.
            let face = Path(ellipseIn: CGRect(x: 7.3, y: 9.6, width: 9.4, height: 10.8))
            context.fill(face, with: .color(.markFace))
            context.stroke(face, with: ink, style: line)
            for x in [8.2, 14.2] {
                context.fill(Path(ellipseIn: CGRect(x: x, y: 13.6, width: 1.6, height: 1.6)), with: .color(.markCheek))
            }
            for x in [9.8, 13.0] {
                context.fill(Path(ellipseIn: CGRect(x: x, y: 12.6, width: 1.2, height: 1.2)), with: .color(.markInk))
            }
            var moustache = Path()
            moustache.move(to: CGPoint(x: 9.0, y: 15.4))
            moustache.addQuadCurve(to: CGPoint(x: 12.0, y: 14.5), control: CGPoint(x: 10.6, y: 13.7))
            moustache.addQuadCurve(to: CGPoint(x: 15.0, y: 15.4), control: CGPoint(x: 13.4, y: 13.7))
            moustache.addQuadCurve(to: CGPoint(x: 12.0, y: 15.6), control: CGPoint(x: 13.6, y: 15.0))
            moustache.addQuadCurve(to: CGPoint(x: 9.0, y: 15.4), control: CGPoint(x: 10.4, y: 15.0))
            moustache.closeSubpath()
            context.fill(moustache, with: .color(.markMoustache))
            context.stroke(moustache, with: ink, style: StrokeStyle(lineWidth: 0.5, lineJoin: .round))

            // The flat cap: dome, brim, button.
            var dome = Path()
            dome.move(to: CGPoint(x: 6.9, y: 10.6))
            dome.addCurve(to: CGPoint(x: 17.1, y: 10.6), control1: CGPoint(x: 6.9, y: 5.2), control2: CGPoint(x: 17.1, y: 5.2))
            dome.closeSubpath()
            context.fill(dome, with: .color(.markCap))
            context.stroke(dome, with: ink, style: line)
            let brim = Path(roundedRect: CGRect(x: 6.1, y: 10.0, width: 11.8, height: 1.8), cornerRadius: 0.9, style: .continuous)
            context.fill(brim, with: .color(.markBrim))
            context.stroke(brim, with: ink, style: line)
            let button = Path(ellipseIn: CGRect(x: 11.4, y: 5.9, width: 1.2, height: 1.2))
            context.fill(button, with: .color(.markCap))
            context.stroke(button, with: ink, style: StrokeStyle(lineWidth: 0.5))

            // The wall he peeks over, bricks offset row by row.
            let wall = tile.intersection(Path(CGRect(x: 0, y: 17.6, width: 24, height: 6.4)))
            context.fill(wall, with: .color(.markWall))
            var mortar = Path()
            for y in [19.7, 21.8] {
                mortar.move(to: CGPoint(x: 0, y: y))
                mortar.addLine(to: CGPoint(x: 24, y: y))
            }
            for (row, offset) in [(17.6, 2.0), (19.7, 5.0), (21.8, 2.0)] {
                var x = offset
                while x < 24 {
                    mortar.move(to: CGPoint(x: x, y: row))
                    mortar.addLine(to: CGPoint(x: x, y: row + 2.1))
                    x += 6
                }
            }
            context.clip(to: wall)
            context.stroke(mortar, with: .color(.markMortar), style: StrokeStyle(lineWidth: 0.35))
            var top = Path()
            top.move(to: CGPoint(x: 0, y: 17.6))
            top.addLine(to: CGPoint(x: 24, y: 17.6))
            context.stroke(top, with: ink, style: StrokeStyle(lineWidth: 0.6))
        }
        .accessibilityLabel("Gustave")
    }
}
