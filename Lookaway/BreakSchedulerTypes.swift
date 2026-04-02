import Foundation

extension BreakScheduler {
    struct DailyCounters: Codable {
        var completed: Int = 0
        var skipped: Int = 0
        var snoozed: Int = 0
    }

    enum Keys {
        static let interval = "lookaway.interval"
        static let restDuration = "lookaway.restDuration"
        static let protocolPreset = "lookaway.protocolPreset"
        static let breakStyle = "lookaway.breakStyle"
        static let preAlertEnabled = "lookaway.preAlert"
        static let preAlertPresentation = "lookaway.preAlertPresentation"
        static let pointerCountdownEnabled = "lookaway.pointerCountdownEnabled"
        static let dimAmount = "lookaway.dimAmount"
        static let showDisplayLabel = "lookaway.displayLabel"
        static let launchAtLogin = "lookaway.launchAtLogin"
        static let scheduleEnabled = "lookaway.scheduleEnabled"
        static let scheduleStartHour = "lookaway.scheduleStartHour"
        static let scheduleEndHour = "lookaway.scheduleEndHour"
        static let activeWeekdays = "lookaway.activeWeekdays"
        static let focusBlocksEnabled = "lookaway.focusBlocksEnabled"
        // Legacy single-window keys (read-only for migration)
        static let focusStartHour = "lookaway.focusStartHour"
        static let focusEndHour = "lookaway.focusEndHour"
        static let focusWeekdays = "lookaway.focusWeekdays"
        // Multi-window focus blocks
        static let focusBlockWindows = "lookaway.focusBlockWindows"
        static let pauseOnSystemIdle = "lookaway.pauseOnSystemIdle"
        static let delayDuringMeetings = "lookaway.delayDuringMeetings"
        static let onlyAcceptedCalendarEvents = "lookaway.onlyAcceptedCalendarEvents"
        static let deviceAwareModeEnabled = "lookaway.deviceAwareModeEnabled"
        static let reduceIntensityOnBattery = "lookaway.reduceIntensityOnBattery"
        static let menuBarMode = "lookaway.menuBarMode"
        static let selectedSetupPreset = "lookaway.selectedSetupPreset"
        static let dayStats = "lookaway.dayStats"
        // Custom prompts
        static let customPrompts = "lookaway.customPrompts"
        // App-aware pausing
        static let appAwarePauseEnabled = "lookaway.appAwarePauseEnabled"
        static let pauseAppBundleIDs = "lookaway.pauseAppBundleIDs"
        // Webcam detection
        static let pauseWhenCameraActive = "lookaway.pauseWhenCameraActive"
        // Idle detection
        static let pauseWhenIdle = "lookaway.pauseWhenIdle"
    }

    enum IntervalOption: Int, CaseIterable, Identifiable {
        case min20 = 20
        case min25 = 25
        case min30 = 30

        var id: Int { rawValue }
        var title: String { "\(rawValue) min" }
        var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    }

    enum RestDurationOption: Int, CaseIterable, Identifiable {
        case sec10 = 10
        case sec20 = 20
        case sec30 = 30
        case min5 = 300

        var id: Int { rawValue }
        var title: String {
            rawValue >= 60 ? "\(rawValue / 60) min" : "\(rawValue) sec"
        }
    }

    enum BreakProtocolPreset: String, CaseIterable, Identifiable {
        case eyeCare202020
        case pomodoro
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .eyeCare202020: return "20-20-20"
            case .pomodoro: return "Pomodoro"
            case .custom: return "Custom"
            }
        }
    }

    enum SetupPreset: String, CaseIterable, Identifiable {
        case gentle
        case eyeCare202020
        case pomodoro
        case deepWork

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gentle: return "Gentle"
            case .eyeCare202020: return "20-20-20"
            case .pomodoro: return "Pomodoro"
            case .deepWork: return "Deep Work"
            }
        }

        var subtitle: String {
            switch self {
            case .gentle: return "30 min work, 20 sec reset"
            case .eyeCare202020: return "20 min work, 20 sec eye rest"
            case .pomodoro: return "25 min focus, 5 min reset"
            case .deepWork: return "30 min deep work, 30 sec stretch"
            }
        }
    }

    enum BreakStyle: String, CaseIterable, Identifiable {
        case eyes
        case breathing
        case stretch
        case blink
        case hydration

        var id: String { rawValue }

        var title: String {
            switch self {
            case .eyes: return "Coffee Reset"
            case .breathing: return "Breathing"
            case .stretch: return "Stretch"
            case .blink: return "Blink"
            case .hydration: return "Hydration"
            }
        }

        var defaultPrompts: [String] {
            switch self {
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

    enum Weekday: Int, CaseIterable, Identifiable {
        case sunday = 1
        case monday = 2
        case tuesday = 3
        case wednesday = 4
        case thursday = 5
        case friday = 6
        case saturday = 7

        var id: Int { rawValue }

        var shortTitle: String {
            switch self {
            case .sunday: return "Sun"
            case .monday: return "Mon"
            case .tuesday: return "Tue"
            case .wednesday: return "Wed"
            case .thursday: return "Thu"
            case .friday: return "Fri"
            case .saturday: return "Sat"
            }
        }
    }

    enum MenuBarMode: String, CaseIterable, Identifiable {
        case iconOnly
        case iconAndMinutes
        case iconAndStatus

        var id: String { rawValue }

        var title: String {
            switch self {
            case .iconOnly: return "Icon only"
            case .iconAndMinutes: return "Icon + minutes"
            case .iconAndStatus: return "Icon + status"
            }
        }
    }

    enum PreAlertPresentation: String, CaseIterable, Identifiable {
        case pointerCountdown
        case centerBanner
        case notification

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pointerCountdown: return "Countdown beside pointer"
            case .centerBanner: return "Center-screen banner"
            case .notification: return "System notification"
            }
        }
    }

    struct DayChartEntry: Identifiable {
        let id: String
        let weekdayLabel: String
        let completed: Int
        let skipped: Int
        let snoozed: Int

        var total: Int { completed + skipped + snoozed }
    }

    struct ExtendedStatsSnapshot {
        let currentStreak: Int
        let completionRate: Double
        let bestDayOfWeek: String?
        let weeklyChartData: [DayChartEntry]

        static let empty = ExtendedStatsSnapshot(
            currentStreak: 0,
            completionRate: 0,
            bestDayOfWeek: nil,
            weeklyChartData: []
        )
    }

    struct FocusBlockWindow: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var startHour: Int
        var endHour: Int
        var weekdays: Set<Int>

        init(id: UUID = UUID(), name: String, startHour: Int, endHour: Int, weekdays: Set<Int>) {
            self.id = id
            self.name = name
            self.startHour = startHour
            self.endHour = endHour
            self.weekdays = weekdays
        }
    }

    enum RuntimeBlocker {
        case none
        case paused
        case outsideSchedule(nextStart: Date?)
        case focus(until: Date?)
        case meeting(until: Date?, title: String?)
    }
}
