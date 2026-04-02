import Foundation

extension BreakScheduler {
    func recordStat(_ keyPath: WritableKeyPath<DailyCounters, Int>) {
        let key = Self.dayKey(for: .now)
        var counters = dayStats[key] ?? DailyCounters()
        counters[keyPath: keyPath] += 1
        dayStats[key] = counters
        saveStats()
    }

    func refreshStats() {
        extendedStats = computeExtendedStats()
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
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(dayStats) else { return }
        UserDefaults.standard.set(data, forKey: Keys.dayStats)
    }
}
