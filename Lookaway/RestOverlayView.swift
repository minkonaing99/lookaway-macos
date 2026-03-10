import Combine
import SwiftUI

struct RestOverlayView: View {
    let restDuration: Int
    let style: BreakScheduler.BreakStyle
    let dimAmount: Double
    let displayName: String?
    let onDismiss: () -> Void
    let onSkip: () -> Void

    @State private var secondsRemaining: Int
    @State private var appeared = false
    @State private var didAutoDismiss = false
    @State private var gradientShifted = false
    @State private var glowExpanded = false

    init(
        restDuration: Int,
        style: BreakScheduler.BreakStyle,
        dimAmount: Double,
        displayName: String?,
        onDismiss: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.restDuration = restDuration
        self.style = style
        self.dimAmount = dimAmount
        self.displayName = displayName
        self.onDismiss = onDismiss
        self.onSkip = onSkip
        _secondsRemaining = State(initialValue: restDuration)
    }

    var body: some View {
        ZStack {
            backgroundLayer
            Color.black.opacity(max(0.12, dimAmount * 0.55)).ignoresSafeArea()

            VStack(spacing: 18) {
                if let displayName {
                    Text(displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.74))
                }

                Image(systemName: styleIcon)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.white.opacity(0.94))

                VStack(spacing: 8) {
                    Text(styleTitle)
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(rotatingPrompt)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: 520)
                }

                Text(secondsRemaining > 0 ? "\(secondsRemaining)s" : "Done")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.gray.opacity(0.36))
                .foregroundStyle(.white.opacity(0.78))
                .frame(minWidth: 210)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .scaleEffect(appeared ? 1 : 0.96)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.35), value: appeared)
        }
        .onAppear {
            appeared = true
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                gradientShifted = true
            }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                glowExpanded = true
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if secondsRemaining > 0 {
                secondsRemaining -= 1
            } else if !didAutoDismiss {
                didAutoDismiss = true
                onDismiss()
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.19, green: 0.29, blue: 0.53),
                    Color(red: 0.08, green: 0.51, blue: 0.56),
                    Color(red: 0.21, green: 0.39, blue: 0.64)
                ],
                startPoint: gradientShifted ? .topTrailing : .topLeading,
                endPoint: gradientShifted ? .bottomLeading : .bottomTrailing
            )

            RadialGradient(
                colors: [Color(red: 0.99, green: 0.83, blue: 0.57).opacity(0.38), Color.clear],
                center: gradientShifted ? .topLeading : .bottomTrailing,
                startRadius: glowExpanded ? 120 : 72,
                endRadius: glowExpanded ? 760 : 520
            )
            .blendMode(.screen)
            .blur(radius: 18)

            AngularGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.10),
                    Color.cyan.opacity(0.12),
                    Color.mint.opacity(0.11),
                    Color.orange.opacity(0.08),
                    Color.white.opacity(0.10)
                ]),
                center: .center,
                angle: .degrees(gradientShifted ? 360 : 0)
            )
            .blendMode(.plusLighter)
            .opacity(0.42)
            .blur(radius: 30)
        }
        .ignoresSafeArea()
    }

    private var styleIcon: String {
        switch style {
        case .eyes: return "cup.and.saucer.fill"
        case .breathing: return "wind"
        case .stretch: return "figure.cooldown"
        case .blink: return "eye"
        case .hydration: return "drop.fill"
        }
    }

    private var styleTitle: String {
        switch style {
        case .eyes: return "Coffee Reset"
        case .breathing: return "Breathing Break"
        case .stretch: return "Stretch Break"
        case .blink: return "Blink Reset"
        case .hydration: return "Hydration Break"
        }
    }

    private var rotatingPrompt: String {
        let prompts = promptOptions
        guard !prompts.isEmpty else { return "Relax for a moment." }
        let index = max(0, min(prompts.count - 1, (restDuration - max(secondsRemaining, 1)) / 4))
        return prompts[index]
    }

    private var promptOptions: [String] {
        switch style {
        case .eyes:
            return [
                "Take a sip of coffee and relax a bit.",
                "Unclench your jaw and drop your shoulders.",
                "Look across the room and let your eyes reset."
            ]
        case .breathing:
            return [
                "Inhale slowly through your nose.",
                "Hold for a beat, then exhale gently.",
                "Keep the pace easy and relaxed."
            ]
        case .stretch:
            return [
                "Roll your shoulders back.",
                "Stand tall and loosen your neck.",
                "Let your wrists and hands reset."
            ]
        case .blink:
            return [
                "Blink slowly and naturally.",
                "Soften your gaze.",
                "Look away from the screen for a few seconds."
            ]
        case .hydration:
            return [
                "Take a sip of water.",
                "Relax your shoulders.",
                "Reset before the next work block."
            ]
        }
    }
}
