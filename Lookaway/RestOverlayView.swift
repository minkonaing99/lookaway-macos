import SwiftUI

struct RestOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let restDuration: Int
    let deadline: Date
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
        deadline: Date,
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
        self.deadline = deadline
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
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                backgroundLayer
                    .id(motionReduced)
                    .frame(width: geometry.size.width + 256, height: geometry.size.height + 256)
                    .drawingGroup(opaque: false, colorMode: .extendedLinear)
                    .blur(radius: reduceTransparency ? 0 : 32)
                    .offset(x: -128, y: -128)
            }
            .clipped()
            .ignoresSafeArea()
            Color.black.opacity(max(0.12, dimAmount * 0.55)).ignoresSafeArea()

            VStack(spacing: 24) {
                if let displayName {
                    Text(displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.74))
                }

                Image(systemName: styleIcon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.white.opacity(0.94))
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(styleTitle)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)

                    if style == .breathing {
                        BreathingGuideView(reduceMotion: motionReduced)
                    } else if style == .eyeExercise {
                        EyeExerciseGuideView(reduceMotion: motionReduced)
                    } else {
                        Text(promptOptions.first ?? "Relax for a moment.")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: 520)
                    }
                }

                Text(secondsRemaining > 0 ? "\(secondsRemaining)s" : "Done")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .accessibilityLabel("\(secondsRemaining) seconds remaining")

                Button("Skip") {
                    onSkip()
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("End this break early")
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.vertical, 36)
            .opacity(appeared ? 1 : 0)
            .animation(motionReduced ? nil : .easeOut(duration: 0.35), value: appeared)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            appeared = true
            // Decorative animation only on mains power; static frame on battery.
            if !motionReduced {
                withAnimation(.easeInOut(duration: 30).repeatForever(autoreverses: true)) {
                    gradientShifted = true
                }
            }
            countdownTask = Task { @MainActor in
                while !Task.isCancelled {
                    secondsRemaining = Self.remainingSeconds(until: deadline, now: .now)
                    if secondsRemaining == 0 && !didAutoDismiss {
                        didAutoDismiss = true
                        onDismiss()
                        break
                    }
                    let delay = min(1, max(0, deadline.timeIntervalSinceNow))
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
        .onDisappear {
            countdownTask?.cancel()
            countdownTask = nil
        }
        .onChange(of: motionReduced) { _, reduced in
            if reduced {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { gradientShifted = false }
            }
        }
    }

    private var motionReduced: Bool { reduceMotion || systemReduceMotion }

    static func remainingSeconds(until deadline: Date, now: Date) -> Int {
        max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch backgroundStyle {
        case .classic:
            classicBackground
        case .aurora:
            AuroraBackgroundView(palette: palette, reduceMotion: motionReduced)
                .saturation(0.75)
        case .wallpaper:
            if let wallpaper {
                wallpaperBackground(wallpaper)
            } else {
                // No readable image → calm blue aurora, regardless of theme.
                AuroraBackgroundView(palette: BreakScheduler.OverlayTheme.ocean.palette(), reduceMotion: motionReduced)
            }
        }
    }

    private func wallpaperBackground(_ image: NSImage) -> some View {
        GeometryReader { geo in
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
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
        case .eyes: return "eye"
        case .breathing: return "wind"
        case .stretch: return "figure.cooldown"
        case .blink: return "eye"
        case .hydration: return "drop.fill"
        case .eyeExercise: return "eye.circle"
        }
    }

    private var styleTitle: String {
        switch style {
        case .eyes: return "Rest your eyes"
        case .breathing: return "Breathing Break"
        case .stretch: return "Stretch Break"
        case .blink: return "Blink Reset"
        case .hydration: return "Hydration Break"
        case .eyeExercise: return "Eye Exercise"
        }
    }

    private var promptOptions: [String] {
        if let custom = customPrompts, !custom.isEmpty {
            return custom
        }
        return style.defaultPrompts
    }
}
