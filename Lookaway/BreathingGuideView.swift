import SwiftUI

struct BreathingGuideView: View {
    private enum Phase {
        case inhale, hold, exhale

        var duration: Double {
            switch self {
            case .inhale: return 4
            case .hold: return 4
            case .exhale: return 6
            }
        }

        var label: String {
            switch self {
            case .inhale: return "Inhale"
            case .hold: return "Hold"
            case .exhale: return "Exhale"
            }
        }

        var targetScale: CGFloat {
            switch self {
            case .inhale, .hold: return 1.0
            case .exhale: return 0.38
            }
        }
    }

    @State private var phase: Phase = .exhale
    @State private var scale: CGFloat = 0.38
    @State private var cycleTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cyan.opacity(0.55),
                                Color.teal.opacity(0.22)
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 72
                        )
                    )
                    .frame(width: 148, height: 148)
                    .scaleEffect(scale)
                    .animation(.easeInOut(duration: phase.duration), value: scale)
                    .blur(radius: 3)

                Circle()
                    .strokeBorder(Color.white.opacity(0.32), lineWidth: 1.5)
                    .frame(width: 148, height: 148)
                    .scaleEffect(scale)
                    .animation(.easeInOut(duration: phase.duration), value: scale)
            }

            Text(phase.label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .animation(.easeInOut(duration: 0.25), value: phase.label)
        }
        .onAppear {
            cycleTask = Task { @MainActor in
                while !Task.isCancelled {
                    phase = .inhale
                    scale = Phase.inhale.targetScale
                    try? await Task.sleep(for: .seconds(Phase.inhale.duration))
                    guard !Task.isCancelled else { break }

                    phase = .hold
                    try? await Task.sleep(for: .seconds(Phase.hold.duration))
                    guard !Task.isCancelled else { break }

                    phase = .exhale
                    scale = Phase.exhale.targetScale
                    try? await Task.sleep(for: .seconds(Phase.exhale.duration))
                }
            }
        }
        .onDisappear {
            cycleTask?.cancel()
        }
    }
}
