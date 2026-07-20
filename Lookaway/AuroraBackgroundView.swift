import SwiftUI

// Layered animated aurora: breathing base gradient, five drifting/pulsing
// color blobs, a soft light streak, and a top glow. All layers are plain
// gradient fills — no Gaussian blur, so frames stay cheap to composite.
// reduceMotion (battery / low power) renders the same scene as one static frame.
struct AuroraBackgroundView: View {
    let palette: OverlayPalette
    var reduceMotion: Bool = false

    @State private var animate = false

    private struct Blob {
        let colorIndex: Int
        let sizeFraction: CGFloat
        let from: UnitPoint
        let to: UnitPoint
        let duration: Double
        let pulseScale: CGFloat
    }

    private static let blobs: [Blob] = [
        Blob(colorIndex: 0, sizeFraction: 0.90, from: UnitPoint(x: 0.16, y: 0.24), to: UnitPoint(x: 0.34, y: 0.42), duration: 14, pulseScale: 1.14),
        Blob(colorIndex: 1, sizeFraction: 0.78, from: UnitPoint(x: 0.84, y: 0.28), to: UnitPoint(x: 0.66, y: 0.14), duration: 18, pulseScale: 1.10),
        Blob(colorIndex: 2, sizeFraction: 0.95, from: UnitPoint(x: 0.32, y: 0.84), to: UnitPoint(x: 0.54, y: 0.68), duration: 22, pulseScale: 1.16),
        Blob(colorIndex: 3, sizeFraction: 0.72, from: UnitPoint(x: 0.82, y: 0.78), to: UnitPoint(x: 0.92, y: 0.56), duration: 26, pulseScale: 1.08),
        Blob(colorIndex: 1, sizeFraction: 0.60, from: UnitPoint(x: 0.50, y: 0.10), to: UnitPoint(x: 0.44, y: 0.30), duration: 30, pulseScale: 1.12)
    ]

    var body: some View {
        GeometryReader { geo in
            let base = min(geo.size.width, geo.size.height)

            ZStack {
                // Breathing base gradient
                LinearGradient(
                    colors: palette.gradient,
                    startPoint: animate ? .topTrailing : .topLeading,
                    endPoint: animate ? .bottomLeading : .bottomTrailing
                )
                .animation(drift(duration: 20), value: animate)
                .saturation(1.1)
                .brightness(-0.18)

                // Drifting, pulsing color blobs (radial falloff, no blur)
                ForEach(Array(Self.blobs.enumerated()), id: \.offset) { _, blob in
                    let point = animate ? blob.to : blob.from
                    let color = palette.blobs[blob.colorIndex % palette.blobs.count]
                    let diameter = base * blob.sizeFraction * 1.3

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [color.opacity(0.55), color.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: diameter / 2
                            )
                        )
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(animate ? blob.pulseScale : 0.92)
                        .position(x: geo.size.width * point.x, y: geo.size.height * point.y)
                        .animation(drift(duration: blob.duration), value: animate)
                }

                // Soft diagonal light streak sweeping slowly across
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [palette.glow.opacity(0.16), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: base * 0.7
                        )
                    )
                    .frame(width: geo.size.width * 1.5, height: base * 0.42)
                    .rotationEffect(.degrees(-14))
                    .position(
                        x: geo.size.width * (animate ? 0.7 : 0.3),
                        y: geo.size.height * (animate ? 0.32 : 0.46)
                    )
                    .blendMode(.screen)
                    .animation(drift(duration: 24), value: animate)

                // Top glow
                RadialGradient(
                    colors: [palette.glow.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.5, y: 0.15),
                    startRadius: base * 0.05,
                    endRadius: base * 0.75
                )
                .blendMode(.screen)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if !reduceMotion { animate = true }
        }
    }

    private func drift(duration: Double) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }
}
