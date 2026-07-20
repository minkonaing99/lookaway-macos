import SwiftUI

struct EyeExerciseGuideView: View {
    private enum Phase: CaseIterable {
        case left, right, up, down, far

        var duration: Double {
            self == .far ? 5 : 3
        }

        var label: String {
            switch self {
            case .left: return "Look left"
            case .right: return "Look right"
            case .up: return "Look up"
            case .down: return "Look down"
            case .far: return "Focus on something far away"
            }
        }

        var offset: CGSize {
            switch self {
            case .left: return CGSize(width: -120, height: 0)
            case .right: return CGSize(width: 120, height: 0)
            case .up: return CGSize(width: 0, height: -55)
            case .down: return CGSize(width: 0, height: 55)
            case .far: return .zero
            }
        }
    }

    @State private var phase: Phase = .far
    @State private var dotOffset: CGSize = .zero
    @State private var cycleTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cyan.opacity(0.85),
                                Color.teal.opacity(0.35)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 14
                        )
                    )
                    .frame(width: 26, height: 26)
                    .shadow(color: .cyan.opacity(0.6), radius: 10)
                    .offset(dotOffset)
                    .opacity(phase == .far ? 0.35 : 1)
                    .animation(.easeInOut(duration: 1.0), value: dotOffset)
                    .animation(.easeInOut(duration: 0.6), value: phase == .far)
            }
            .frame(width: 300, height: 140)

            Text(phase.label)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .animation(.easeInOut(duration: 0.25), value: phase.label)
        }
        .onAppear {
            cycleTask = Task { @MainActor in
                while !Task.isCancelled {
                    for nextPhase in Phase.allCases {
                        phase = nextPhase
                        dotOffset = nextPhase.offset
                        try? await Task.sleep(for: .seconds(nextPhase.duration))
                        guard !Task.isCancelled else { return }
                    }
                }
            }
        }
        .onDisappear {
            cycleTask?.cancel()
        }
    }
}
