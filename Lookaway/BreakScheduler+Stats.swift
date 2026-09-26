import Foundation

extension BreakScheduler {
    func recordStat(_ keyPath: WritableKeyPath<DailyCounters, Int>) {
        let key = Self.dayKey(for: .now)
        var counters = dayStats[key] ?? DailyCounters()
        counters[keyPath: keyPath] += 1
        dayStats = dayStats.merging([key: counters]) { _, new in new }
        saveStats()
    }

    func recordCompletedBreak(at now: Date) {
        guard let start = activeBreakStartedAt, !isShowingTestBreak else { return }
        let end = min(now, start.addingTimeInterval(activeBreakDuration))
        addRecordedTime(from: start, to: end, completedBreak: true)
    }

    func updateWorkSession(now: Date) {
        let idle = currentIdleSeconds()
        guard !isShowingBreak, !isRunningBreakTest, !isShowingTestBreak,
              systemSuspensions.isEmpty, idle < 300,
              case .none = runtimeBlocker(for: now) else {
            endWorkSession(at: idle >= 300 ? now.addingTimeInterval(-idle) : now)
            return
        }
        if workSessionStartedAt == nil { workSessionStartedAt = now }
    }

    func endWorkSession(at now: Date) {
        guard let start = workSessionStartedAt else { return }
        workSessionStartedAt = nil
        addRecordedTime(from: start, to: now, completedBreak: false)
    }

    private func addRecordedTime(from start: Date, to end: Date, completedBreak: Bool) {
        guard end > start else { return }
        let calendar = Calendar.current
        var cursor = start
        var updated = dayStats
        while cursor < end {
            guard let boundary = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)) else { break }
            let segmentEnd = min(end, boundary)
            let seconds = segmentEnd.timeIntervalSince(cursor)
            let key = Self.dayKey(for: cursor)
            var counters = updated[key] ?? DailyCounters()
            if completedBreak {
                counters.completedBreakSeconds = (counters.completedBreakSeconds ?? 0) + seconds
            } else {
                counters.longestWorkSeconds = max(counters.longestWorkSeconds ?? 0, seconds)
            }
            updated = updated.merging([key: counters]) { _, new in new }
            cursor = segmentEnd
        }
        dayStats = updated
        saveStats()
        refreshStats()
    }

    func refreshStats(now: Date = .now) {
        extendedStats = computeExtendedStats(now: now)
        lastStatsRefresh = now
    }

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(for date: Date) -> String {
        dayKeyFormatter.string(from: date)
    }

    static func loadStats() -> [String: DailyCounters] {
        guard let data = UserDefaults.standard.data(forKey: Keys.dayStats) else { return [:] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([String: DailyCounters].self, from: data)) ?? [:]
    }

    func saveStats() {
        // Day keys sort chronologically (yyyy-MM-dd); keep the newest 400
        // days so the stats dictionary cannot grow unbounded over years.
        if dayStats.count > 400 {
            dayStats = Dictionary(
                uniqueKeysWithValues: dayStats.sorted { $0.key > $1.key }.prefix(400).map { ($0.key, $0.value) }
            )
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(dayStats) else { return }
        UserDefaults.standard.set(data, forKey: Keys.dayStats)
    }
}
