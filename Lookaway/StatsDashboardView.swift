import Charts
import SwiftUI

struct StatsDashboardView: View {
    let extendedStats: BreakScheduler.ExtendedStatsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Recorded activity")
                .font(.title2.weight(.semibold))
            Text("Break minutes count completed timers, not confirmed time looking away. Work periods exclude breaks, pauses, meetings, focus blocks, and detected idle time. Durations start with this version; earlier history has counts only. Work periods are split at midnight.")
                .font(.caption)
                .foregroundStyle(.secondary)
            metricsRow
            weeklyChartCard
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricCard(
                title: "Streak",
                value: "\(extendedStats.currentStreak)",
                unit: extendedStats.currentStreak == 1 ? "day" : "days"
            )
            metricCard(
                title: "Completed breaks",
                value: String(format: "%.1f", extendedStats.completedBreakSeconds / 60),
                unit: "minutes in last 7 days"
            )
            metricCard(
                title: "Longest work period",
                value: String(format: "%.1f", extendedStats.longestWorkSeconds / 60),
                unit: "minutes in last 7 days"
            )
        }
    }

    private func metricCard(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 30, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last 7 days")
                    .font(.title3.weight(.semibold))
                Text("Completed, skipped, and snoozed breaks per day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if extendedStats.weeklyChartData.allSatisfy({ $0.total == 0 }) {
                Text("No break data recorded yet. Complete your first break to see stats here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 36)
            } else {
                Chart {
                    ForEach(extendedStats.weeklyChartData) { entry in
                        BarMark(
                            x: .value("Day", entry.weekdayLabel),
                            y: .value("Count", entry.completed)
                        )
                        .foregroundStyle(by: .value("Type", "Completed"))

                        BarMark(
                            x: .value("Day", entry.weekdayLabel),
                            y: .value("Count", entry.skipped)
                        )
                        .foregroundStyle(by: .value("Type", "Skipped"))

                        BarMark(
                            x: .value("Day", entry.weekdayLabel),
                            y: .value("Count", entry.snoozed)
                        )
                        .foregroundStyle(by: .value("Type", "Snoozed"))
                    }
                }
                .chartXScale(domain: extendedStats.weeklyChartData.map(\.weekdayLabel))
                .chartForegroundStyleScale([
                    "Completed": Color.accentColor,
                    "Skipped": Color.orange.opacity(0.75),
                    "Snoozed": Color.gray.opacity(0.5)
                ])
                .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
                .frame(height: 160)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
