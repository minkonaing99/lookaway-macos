import SwiftUI

struct FocusBlockWindowEditorView: View {
    @ObservedObject var scheduler: BreakScheduler
    let window: BreakScheduler.FocusBlockWindow

    private let weekdayColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Window name", text: Binding(
                    get: { window.name },
                    set: { newName in
                        let updated = BreakScheduler.FocusBlockWindow(
                            id: window.id,
                            name: newName,
                            startHour: window.startHour,
                            endHour: window.endHour,
                            weekdays: window.weekdays
                        )
                        scheduler.updateFocusBlockWindow(updated)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

                Spacer()

                Button(role: .destructive) {
                    scheduler.removeFocusBlockWindow(id: window.id)
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 16) {
                windowHourPicker(title: "Start", hour: window.startHour) { newHour in
                    let updated = BreakScheduler.FocusBlockWindow(
                        id: window.id, name: window.name,
                        startHour: newHour, endHour: window.endHour,
                        weekdays: window.weekdays
                    )
                    scheduler.updateFocusBlockWindow(updated)
                }
                windowHourPicker(title: "End", hour: window.endHour) { newHour in
                    let updated = BreakScheduler.FocusBlockWindow(
                        id: window.id, name: window.name,
                        startHour: window.startHour, endHour: newHour,
                        weekdays: window.weekdays
                    )
                    scheduler.updateFocusBlockWindow(updated)
                }
            }

            windowWeekdayRow(selected: window.weekdays)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func windowHourPicker(title: String, hour: Int, onChange: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: Binding(get: { hour }, set: onChange)) {
                ForEach(0..<24, id: \.self) { h in
                    Text(BreakScheduler.hourText(h)).tag(h)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func windowWeekdayRow(selected: Set<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active on")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: weekdayColumns, spacing: 8) {
                ForEach(BreakScheduler.Weekday.allCases) { day in
                    Button(day.shortTitle) {
                        var updated = window.weekdays
                        if updated.contains(day.rawValue) {
                            updated.remove(day.rawValue)
                        } else {
                            updated.insert(day.rawValue)
                        }
                        let updatedWindow = BreakScheduler.FocusBlockWindow(
                            id: window.id, name: window.name,
                            startHour: window.startHour, endHour: window.endHour,
                            weekdays: updated
                        )
                        scheduler.updateFocusBlockWindow(updatedWindow)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(selected.contains(day.rawValue) ? .accentColor : .gray.opacity(0.28))
                    .controlSize(.small)
                }
            }
        }
    }
}
