import SwiftUI

struct OverlayPalette: Equatable {
    let gradient: [Color]
    let glow: Color
    let blobs: [Color]
}

extension BreakScheduler.OverlayTheme {
    func palette(hour: Int = Calendar.current.component(.hour, from: .now)) -> OverlayPalette {
        Self.resolvedTheme(for: self, hour: hour).concretePalette
    }

    private var concretePalette: OverlayPalette {
        switch self {
        case .auto, .ocean:
            return OverlayPalette(
                gradient: [
                    Color(red: 0.19, green: 0.29, blue: 0.53),
                    Color(red: 0.08, green: 0.51, blue: 0.56),
                    Color(red: 0.21, green: 0.39, blue: 0.64)
                ],
                glow: Color(red: 0.99, green: 0.83, blue: 0.57),
                blobs: [
                    Color(red: 0.20, green: 0.60, blue: 0.86),
                    Color(red: 0.10, green: 0.68, blue: 0.66),
                    Color(red: 0.36, green: 0.42, blue: 0.85),
                    Color(red: 0.55, green: 0.78, blue: 0.90)
                ]
            )
        case .sunset:
            return OverlayPalette(
                gradient: [
                    Color(red: 0.34, green: 0.14, blue: 0.32),
                    Color(red: 0.72, green: 0.32, blue: 0.20),
                    Color(red: 0.52, green: 0.22, blue: 0.36)
                ],
                glow: Color(red: 1.0, green: 0.72, blue: 0.42),
                blobs: [
                    Color(red: 0.94, green: 0.48, blue: 0.28),
                    Color(red: 0.86, green: 0.32, blue: 0.44),
                    Color(red: 0.62, green: 0.26, blue: 0.56),
                    Color(red: 1.0, green: 0.68, blue: 0.38)
                ]
            )
        case .forest:
            return OverlayPalette(
                gradient: [
                    Color(red: 0.09, green: 0.28, blue: 0.23),
                    Color(red: 0.18, green: 0.42, blue: 0.26),
                    Color(red: 0.10, green: 0.36, blue: 0.35)
                ],
                glow: Color(red: 0.85, green: 0.92, blue: 0.55),
                blobs: [
                    Color(red: 0.24, green: 0.62, blue: 0.38),
                    Color(red: 0.14, green: 0.55, blue: 0.50),
                    Color(red: 0.46, green: 0.68, blue: 0.32),
                    Color(red: 0.30, green: 0.74, blue: 0.58)
                ]
            )
        case .midnight:
            return OverlayPalette(
                gradient: [
                    Color(red: 0.06, green: 0.08, blue: 0.20),
                    Color(red: 0.14, green: 0.12, blue: 0.32),
                    Color(red: 0.20, green: 0.11, blue: 0.36)
                ],
                glow: Color(red: 0.70, green: 0.78, blue: 0.98),
                blobs: [
                    Color(red: 0.26, green: 0.24, blue: 0.62),
                    Color(red: 0.40, green: 0.20, blue: 0.58),
                    Color(red: 0.14, green: 0.34, blue: 0.60),
                    Color(red: 0.52, green: 0.36, blue: 0.78)
                ]
            )
        case .lavender:
            return OverlayPalette(
                gradient: [
                    Color(red: 0.30, green: 0.26, blue: 0.48),
                    Color(red: 0.52, green: 0.42, blue: 0.68),
                    Color(red: 0.38, green: 0.30, blue: 0.58)
                ],
                glow: Color(red: 0.96, green: 0.80, blue: 0.90),
                blobs: [
                    Color(red: 0.66, green: 0.52, blue: 0.86),
                    Color(red: 0.80, green: 0.58, blue: 0.82),
                    Color(red: 0.50, green: 0.48, blue: 0.88),
                    Color(red: 0.88, green: 0.70, blue: 0.92)
                ]
            )
        }
    }
}
