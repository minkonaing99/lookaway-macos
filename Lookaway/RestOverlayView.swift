import SwiftUI

struct RestOverlayView: View {
    let restDuration: Int
    let style: BreakScheduler.BreakStyle
    let dimAmount: Double
    let displayName: String?
    let customPrompts: [String]?
    let backgroundStyle: BreakScheduler.OverlayBackgroundStyle
    let theme: BreakScheduler.OverlayTheme
    let wallpaper: NSImage?
    let reduceMotion: Bool
    let onDismiss: () -> Void
    let onSkip: () -> Void

    private let palette: OverlayPalette

    @State private var secondsRemaining: Int
    @State private var appeared = false
    @State private var didAutoDismiss = false
    @State private var gradientShifted = false
    @State private var countdownTask: Task<Void, Never>?

    init(
        restDuration: Int,
        style: BreakScheduler.BreakStyle,
        dimAmount: Double,
        displayName: String?,
        customPrompts: [String]?,
        backgroundStyle: BreakScheduler.OverlayBackgroundStyle = .classic,
        theme: BreakScheduler.OverlayTheme = .ocean,
        wallpaper: NSImage? = nil,
        reduceMotion: Bool = false,
        onDismiss: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.restDuration = restDuration
        self.style = style
        self.dimAmount = dimAmount
        self.displayName = displayName
        self.customPrompts = customPrompts
        self.backgroundStyle = backgroundStyle
        self.theme = theme
        self.wallpaper = wallpaper
        self.reduceMotion = reduceMotion
        self.palette = theme.palette()
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

                    if style == .breathing {
                        BreathingGuideView()
                    } else if style == .eyeExercise {
                        EyeExerciseGuideView()
                    } else {
                        Text(rotatingPrompt)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: 520)
                    }
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
            // Decorative animation only on mains power; static frame on battery.
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                    gradientShifted = true
                }
            }
            countdownTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { break }
                    if secondsRemaining > 0 {
                        secondsRemaining -= 1
                    } else if !didAutoDismiss {
                        didAutoDismiss = true
                        onDismiss()
                        break
                    }
                }
            }
        }
        .onDisappear {
            countdownTask?.cancel()
            countdownTask = nil
        }
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch backgroundStyle {
        case .classic:
            classicBackground
        case .aurora:
            AuroraBackgroundView(palette: palette, reduceMotion: reduceMotion)
        case .wallpaper:
            if let wallpaper {
                wallpaperBackground(wallpaper)
            } else {
                // No readable image → calm blue aurora, regardless of theme.
                AuroraBackgroundView(palette: BreakScheduler.OverlayTheme.ocean.palette(), reduceMotion: reduceMotion)
            }
        }
    }

    private func wallpaperBackground(_ image: NSImage) -> some View {
        GeometryReader { geo in
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .blur(radius: 24, opaque: true)
                .overlay(Color.black.opacity(0.35))
                .clipped()
        }
        .ignoresSafeArea()
    }

    // Gradient drift + wandering glow; static when reduceMotion. Radial
    // falloff instead of blurred layers keeps frames cheap to composite.
    private var classicBackground: some View {
        ZStack {
            LinearGradient(
                colors: palette.gradient,
                startPoint: gradientShifted ? .topTrailing : .topLeading,
                endPoint: gradientShifted ? .bottomLeading : .bottomTrailing
            )

            RadialGradient(
                colors: [palette.glow.opacity(0.34), Color.clear],
                center: gradientShifted ? UnitPoint(x: 0.2, y: 0.15) : UnitPoint(x: 0.85, y: 0.85),
                startRadius: 60,
                endRadius: gradientShifted ? 820 : 620
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [Color.cyan.opacity(0.14), Color.clear],
                center: gradientShifted ? UnitPoint(x: 0.75, y: 0.8) : UnitPoint(x: 0.3, y: 0.3),
                startRadius: 40,
                endRadius: 700
            )
            .blendMode(.plusLighter)
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
        case .eyeExercise: return "eye.circle"
        }
    }

    private var styleTitle: String {
        switch style {
        case .eyes: return "Coffee Reset"
        case .breathing: return "Breathing Break"
        case .stretch: return "Stretch Break"
        case .blink: return "Blink Reset"
        case .hydration: return "Hydration Break"
        case .eyeExercise: return "Eye Exercise"
        }
    }

    private var rotatingPrompt: String {
        let prompts = promptOptions
        guard !prompts.isEmpty else { return "Relax for a moment." }
        let index = max(0, min(prompts.count - 1, (restDuration - max(secondsRemaining, 1)) / 4))
        return prompts[index]
    }

    private var promptOptions: [String] {
        if let custom = customPrompts, !custom.isEmpty {
            return custom
        }
        return style.defaultPrompts
    }
}
