import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var scheduler: BreakScheduler

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHero

            if scheduler.isInPreAlert {
                Label(
                    preAlertLabel,
                    systemImage: "bell.badge"
                )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Button("Start Break") {
                    scheduler.triggerBreakNow()
                }

                SettingsLink {
                    Text("Preferences…")
                }
            }

            HStack(spacing: 8) {
                Button("Snooze 5m") { scheduler.snooze(minutes: 5) }
                Button("Snooze 10m") { scheduler.snooze(minutes: 10) }
                Button("Skip Once") { scheduler.skipOnce() }
            }

            Toggle("Pause reminders", isOn: $scheduler.manualPauseEnabled)

            if let settingsError = scheduler.settingsError {
                Text(settingsError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(scheduler.calendarStatusText)
                    .font(.caption.weight(.semibold))
                Text(scheduler.calendarDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Quit LookAway") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    private var preAlertLabel: String {
        switch scheduler.preAlertPresentation {
        case .pointerCountdown: return "Break soon near pointer"
        case .centerBanner: return "Break soon on screen"
        case .notification: return "Break soon — notification sent"
        }
    }

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(scheduler.currentStateTitle)
                    .font(.headline)
                Spacer()
                Text(scheduler.nextBreakClockText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(heroText)
                .font(.title3.weight(.semibold))

            Text(scheduler.currentStateExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var heroText: String {
        switch scheduler.currentStateTitle {
        case "Working", "Break soon":
            return "Next break in \(scheduler.timeRemainingText)"
        default:
            return scheduler.currentBlockerText
        }
    }
}

private enum PreferencesSection: String, CaseIterable, Identifiable {
    case schedule
    case breaks
    case focus
    case stats
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "Schedule"
        case .breaks: return "Breaks"
        case .focus: return "Focus"
        case .stats: return "Stats"
        case .advanced: return "Advanced"
        }
    }

    var eyebrow: String {
        switch self {
        case .schedule: return "Work rhythm"
        case .breaks: return "Reset design"
        case .focus: return "Interruptions"
        case .stats: return "Your data"
        case .advanced: return "Diagnostics"
        }
    }

    var description: String {
        switch self {
        case .schedule: return "Define when LookAway should be active and pick a default rhythm."
        case .breaks: return "Tune the countdown, overlay feel, and the break experience itself."
        case .focus: return "Control how meetings, focus blocks, and specific apps delay interruptions."
        case .stats: return "Review your break history, streaks, and completion rate."
        case .advanced: return "Adjust menu bar behavior, system adaptation, testing, and local data."
        }
    }

    var icon: String {
        switch self {
        case .schedule: return "calendar"
        case .breaks: return "cup.and.saucer.fill"
        case .focus: return "moon.stars"
        case .stats: return "chart.bar.fill"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

struct PreferencesContentView: View {
    @ObservedObject var scheduler: BreakScheduler
    @State private var selection: PreferencesSection? = .schedule

    private let weekdayColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    private let cardColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailContent(for: selection ?? .schedule)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(PreferencesWindowChromeConfigurator().frame(width: 0, height: 0))
    }

    private var sidebar: some View {
        List(PreferencesSection.allCases, selection: $selection) { section in
            Label(section.title, systemImage: section.icon)
                .tag(section)
        }
        .listStyle(.sidebar)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private func detailContent(for section: PreferencesSection) -> some View {
        settingsScroll(section: section) {
            switch section {
            case .schedule:
                schedulePage
            case .breaks:
                breaksPage
            case .focus:
                focusPage
            case .stats:
                statsPage
            case .advanced:
                advancedPage
            }
        }
    }

    private func settingsScroll<Content: View>(section: PreferencesSection, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryCard
                pageHeader(section)
                content()
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Coffee break rhythm", systemImage: "cup.and.saucer.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(scheduler.preferencesSummaryTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(scheduler.preferencesSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 12) {
                summaryMetric("State", value: scheduler.currentStateTitle)
                summaryMetric("Next", value: scheduler.nextBreakClockText)
                summaryMetric("Blocker", value: scheduler.currentBlockerText)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Color.orange.opacity(0.08), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
    }

    private var schedulePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "Quick Setup", subtitle: "Start with a named rhythm, then adjust only if needed.") {
                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 12) {
                    ForEach(BreakScheduler.SetupPreset.allCases) { preset in
                        presetCard(preset)
                    }
                }
            }

            settingsCard(title: "Working Hours", subtitle: "Restrict reminders to the part of the week that matters.") {
                Toggle("Only remind during work schedule", isOn: $scheduler.scheduleEnabled)
                    .toggleStyle(.switch)

                HStack(spacing: 16) {
                    hourPicker(title: "Start", selection: $scheduler.scheduleStartHour)
                    hourPicker(title: "End", selection: $scheduler.scheduleEndHour)
                }

                weekdayChipRow(
                    title: "Active weekdays",
                    selected: scheduler.activeWeekdays,
                    toggle: { scheduler.toggleWeekday($0) }
                )
            }
        }
    }

    private var breaksPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "Protocol", subtitle: "Choose a break cadence or keep things fully custom.") {
                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 12) {
                    protocolCard(.eyeCare202020, subtitle: "20 min work, 20 sec eye rest")
                    protocolCard(.pomodoro, subtitle: "25 min focus, 5 min reset")
                    protocolCard(.custom, subtitle: "Tune timing yourself")
                }
            }

            settingsCard(title: "Break Timing", subtitle: "Set the length and tone of each break.") {
                HStack(spacing: 16) {
                    pickerColumn(title: "Interval") {
                        Picker("Interval", selection: $scheduler.intervalOption) {
                            ForEach(BreakScheduler.IntervalOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.large)
                    }

                    pickerColumn(title: "Break duration") {
                        Picker("Rest Duration", selection: $scheduler.restDurationOption) {
                            ForEach(BreakScheduler.RestDurationOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.large)
                    }
                }

                pickerColumn(title: "Break style") {
                    Picker("Break Style", selection: $scheduler.breakStyle) {
                        ForEach(BreakScheduler.BreakStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.large)
                }
            }

            settingsCard(title: "Custom Break Prompts", subtitle: "Override the default overlay text per break style. Leave empty to use built-in prompts.") {
                CustomPromptsEditorView(scheduler: scheduler)
            }
        }
    }

    private var focusPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "Calendar Integration", subtitle: "Delay breaks when your schedule says you are busy.") {
                Toggle("Pause during calendar events", isOn: $scheduler.delayDuringMeetings)
                Toggle("Only block accepted events", isOn: $scheduler.onlyAcceptedCalendarEvents)

                statusStrip(title: scheduler.calendarStatusText, detail: scheduler.calendarDetailText)

                HStack(spacing: 10) {
                    Button("Request Calendar Access") {
                        scheduler.requestCalendarAccessManually()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Check Calendar Access") {
                        scheduler.refreshCalendarAccessStatus()
                    }
                    .buttonStyle(.bordered)
                }
            }

            settingsCard(title: "Focus Blocks", subtitle: "Protect deep work windows. All listed windows suppress breaks when active.") {
                Toggle("Enable focus blocks", isOn: $scheduler.focusBlocksEnabled)

                if !scheduler.focusBlockWindows.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(scheduler.focusBlockWindows) { window in
                            FocusBlockWindowEditorView(scheduler: scheduler, window: window)
                        }
                    }
                }

                Button {
                    scheduler.addFocusBlockWindow()
                } label: {
                    Label("Add Focus Block", systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .disabled(scheduler.focusBlockWindows.count >= 10)
            }

            settingsCard(title: "App-Aware Pausing", subtitle: "Automatically pause breaks when specific apps are in focus.") {
                Toggle("Pause when a listed app is active", isOn: $scheduler.appAwarePauseEnabled)
                AppAwarePauseView(scheduler: scheduler)
                    .disabled(!scheduler.appAwarePauseEnabled)
            }

            settingsCard(title: "Camera Detection", subtitle: "Pause breaks when your camera is actively in use by another app.") {
                Toggle("Pause during active camera use", isOn: $scheduler.pauseWhenCameraActive)
                statusStrip(
                    title: "Privacy note",
                    detail: "LookAway only checks whether your camera is in use. It does not record or access your camera footage."
                )
            }

            settingsCard(title: "Recovery Logic", subtitle: "How LookAway behaves after blockers clear.") {
                statusStrip(
                    title: "Soft rescheduling is active",
                    detail: "Short blockers postpone the break to just after the blocker ends. Long blockers restart a fresh cycle after the blocker finishes."
                )
            }
        }
    }

    private var statsPage: some View {
        StatsDashboardView(extendedStats: scheduler.extendedStats)
    }

    private var advancedPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard(title: "Menu Bar", subtitle: "Choose how much information stays visible all day.") {
                Picker("Menu Bar Mode", selection: $scheduler.menuBarMode) {
                    ForEach(BreakScheduler.MenuBarMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            settingsCard(title: "App Behavior", subtitle: "Startup and system-level handling.") {
                Toggle("Launch at login", isOn: $scheduler.launchAtLogin)
                Toggle("Pause on lock/sleep", isOn: $scheduler.pauseOnSystemIdle)
                Toggle("Pause when idle (5 min)", isOn: $scheduler.pauseWhenIdle)
            }

            settingsCard(title: "Overlay Feel", subtitle: "Keep the break visible without making it heavy.") {
                Toggle("Enable 30s pre-alert", isOn: $scheduler.enablePreAlert)
                Picker("Pre-break cue", selection: $scheduler.preAlertPresentation) {
                    ForEach(BreakScheduler.PreAlertPresentation.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!scheduler.enablePreAlert)
                Toggle("Show display name on overlay", isOn: $scheduler.showPerDisplayLabel)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Overlay dim")
                        Spacer()
                        Text(dimLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $scheduler.restOverlayDimAmount, in: 0.35...0.9)
                }
            }

            settingsCard(title: "Device Awareness", subtitle: "Adapt reminders to power and display context.") {
                Toggle("Adapt reminder timing by display context", isOn: $scheduler.deviceAwareModeEnabled)
                Toggle("Lower intensity on battery / low power mode", isOn: $scheduler.reduceIntensityOnBattery)
                statusStrip(title: "Display", detail: scheduler.deviceContextText)
                statusStrip(title: "Power", detail: scheduler.powerContextText)
            }

            settingsCard(title: "Testing", subtitle: "Preview the pointer countdown and overlay without waiting.") {
                Button(scheduler.preAlertPresentation == .centerBanner ? "Test Banner + Break" : "Test Countdown + Break") {
                    scheduler.runBreakTest()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            settingsCard(title: "Diagnostics", subtitle: "Quick answers when behavior looks wrong.") {
                diagnosticRow("Current state", value: scheduler.currentStateTitle)
                diagnosticRow("Next scheduled break", value: scheduler.nextBreakClockText)
                diagnosticRow("Current blocker", value: scheduler.currentBlockerText)
                diagnosticRow("Calendar", value: scheduler.calendarStatusText)
                diagnosticRow("Meeting", value: scheduler.currentMeetingText)
                diagnosticRow("Last break event", value: scheduler.lastBreakReasonText)
            }

            settingsCard(title: "Privacy", subtitle: "Everything stays local unless macOS permission is required.") {
                HStack(spacing: 10) {
                    Button("Clear Local Stats", role: .destructive) {
                        scheduler.clearStatsHistory()
                    }

                    Button("Reset All Local Data", role: .destructive) {
                        scheduler.resetAllLocalData()
                    }
                }
            }

            if let settingsError = scheduler.settingsError {
                settingsCard(title: "Error", subtitle: nil) {
                    Text(settingsError)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func pageHeader(_ section: PreferencesSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Text(section.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(section.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func diagnosticRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
        .padding(.vertical, 3)
    }

    private func hourPicker(title: String, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(BreakScheduler.hourText(hour)).tag(hour)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pickerColumn<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func weekdayChipRow(title: String, selected: Set<Int>, toggle: @escaping (BreakScheduler.Weekday) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: weekdayColumns, spacing: 8) {
                ForEach(BreakScheduler.Weekday.allCases) { day in
                    Button(day.shortTitle) {
                        toggle(day)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selected.contains(day.rawValue) ? .accentColor : .gray.opacity(0.28))
                    .controlSize(.small)
                }
            }
        }
    }

    private func protocolCard(_ preset: BreakScheduler.BreakProtocolPreset, subtitle: String) -> some View {
        let selected = scheduler.protocolPreset == preset

        return Button {
            scheduler.protocolPreset = preset
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(preset.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(14)
            .background(selected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.06), lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func presetCard(_ preset: BreakScheduler.SetupPreset) -> some View {
        let selected = scheduler.selectedSetupPreset == preset

        return Button {
            scheduler.applySetupPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(preset.title)
                    .font(.headline)
                Text(preset.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 98, alignment: .leading)
            .padding(14)
            .background(selected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.06), lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusStrip(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingsCard<Content: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }

    private var dimLabel: String {
        let percent = Int((scheduler.restOverlayDimAmount * 100).rounded())
        return "\(percent)%"
    }
}
