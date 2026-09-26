import SwiftUI

struct OnboardingView: View {
    @ObservedObject var scheduler: BreakScheduler
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Find your break rhythm")
                    .font(.largeTitle.weight(.semibold))
                Text("LookAway lives in your menu bar. Set a rhythm, try a short preview, and adjust anything later.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Choose a rhythm").font(.headline)
                ForEach(BreakScheduler.SetupPreset.allCases) { preset in
                    Button {
                        scheduler.applySetupPreset(preset)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(preset.title).font(.body.weight(.medium))
                                Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if scheduler.selectedSetupPreset == preset {
                                Image(systemName: "checkmark.circle.fill")
                                    .accessibilityLabel("Selected")
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityAddTraits(scheduler.selectedSetupPreset == preset ? .isSelected : [])
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("2. Try a break").font(.headline)
                    Text("10-second preview. Skip whenever you like.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Preview break") { scheduler.previewBreakNow() }
                    .disabled(scheduler.isShowingBreak)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("3. Make it fit your day").font(.headline)
                Toggle("Launch at login", isOn: $scheduler.launchAtLogin)
                Toggle("Pause during calendar events", isOn: $scheduler.delayDuringMeetings)
                Text("Calendar permission is requested only when you enable calendar pausing.")
                    .font(.caption).foregroundStyle(.secondary)
                if scheduler.delayDuringMeetings {
                    Text(scheduler.calendarDetailText)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = scheduler.settingsError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            HStack {
                Text("Changes save automatically.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Start using LookAway") {
                    scheduler.completeOnboarding()
                    dismissWindow(id: "welcome")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 500)
    }
}
