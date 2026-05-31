import SwiftUI

/// Rule-of-thirds grid + center crosshair for horizon/composition alignment.
/// Rendered in screen space so it stays fixed while the image is panned/zoomed.
struct GuidingGridOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            let thirds = GraphicsContext.Shading.color(.white.opacity(0.35))
            let cross  = GraphicsContext.Shading.color(.white.opacity(0.6))

            // Rule-of-thirds verticals and horizontals
            for i in [1, 2] {
                var vp = Path()
                let x = size.width * CGFloat(i) / 3
                vp.move(to: CGPoint(x: x, y: 0))
                vp.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(vp, with: thirds, lineWidth: 1)

                var hp = Path()
                let y = size.height * CGFloat(i) / 3
                hp.move(to: CGPoint(x: 0, y: y))
                hp.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(hp, with: thirds, lineWidth: 1)
            }

            // Center horizontal — the horizon reference line
            var hc = Path()
            hc.move(to: CGPoint(x: 0, y: size.height / 2))
            hc.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(hc, with: cross, lineWidth: 0.5)

            // Center vertical
            var vc = Path()
            vc.move(to: CGPoint(x: size.width / 2, y: 0))
            vc.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            ctx.stroke(vc, with: cross, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}
