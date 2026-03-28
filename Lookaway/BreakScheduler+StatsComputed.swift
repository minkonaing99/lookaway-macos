import Foundation

extension BreakScheduler {
    func computeExtendedStats() -> ExtendedStatsSnapshot {
        let calendar = Calendar.current
        let today = Date.now

        // Last 7 days chart data (oldest first for chronological display)
        var chartData: [DayChartEntry] = []
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "EEE"

        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = Self.dayKey(for: day)
            let counters = dayStats[key] ?? DailyCounters()
            chartData.append(DayChartEntry(
                id: key,
                weekdayLabel: dayFormatter.string(from: day),
                completed: counters.completed,
                skipped: counters.skipped,
                snoozed: counters.snoozed
            ))
        }

        // Current streak: consecutive days ending today with >= 1 completed
        var streak = 0
        for offset in 0... {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
            let key = Self.dayKey(for: day)
            let counters = dayStats[key] ?? DailyCounters()
            if counters.completed >= 1 {
                streak += 1
            } else {
                break
            }
            if streak > 365 { break }
        }

        // Weekly completion rate
        let weeklyTotal = chartData.reduce(0) { $0 + $1.total }
        let weeklyCompleted = chartData.reduce(0) { $0 + $1.completed }
        let completionRate: Double = weeklyTotal > 0 ? Double(weeklyCompleted) / Double(weeklyTotal) : 0

        // Best day of week by average completions across all history
        var weekdaySums: [Int: Int] = [:]
        var weekdayCounts: [Int: Int] = [:]

        for (key, counters) in dayStats where counters.completed > 0 {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: key) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            weekdaySums[weekday, default: 0] += counters.completed
            weekdayCounts[weekday, default: 0] += 1
        }

        var bestWeekday: String? = nil
        var bestAverage: Double = 0
        let shortWeekdays = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        for (weekday, sum) in weekdaySums {
            let count = weekdayCounts[weekday] ?? 1
            let avg = Double(sum) / Double(count)
            if avg > bestAverage {
                bestAverage = avg
                bestWeekday = weekday < shortWeekdays.count ? shortWeekdays[weekday] : nil
            }
        }

        return ExtendedStatsSnapshot(
            currentStreak: streak,
            completionRate: completionRate,
            bestDayOfWeek: bestWeekday,
            weeklyChartData: chartData
        )
    }
}
