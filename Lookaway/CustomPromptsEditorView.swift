import SwiftUI

struct CustomPromptsEditorView: View {
    @ObservedObject var scheduler: BreakScheduler
    @State private var selectedStyle: BreakScheduler.BreakStyle = .eyes

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Break style", selection: $selectedStyle) {
                ForEach(BreakScheduler.BreakStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let currentPrompts = scheduler.customPrompts[selectedStyle.rawValue] ?? []

            if currentPrompts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Using built-in prompts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(selectedStyle.defaultPrompts.indices, id: \.self) { i in
                        Text("• \(selectedStyle.defaultPrompts[i])")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(currentPrompts.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            TextField("Prompt text", text: Binding(
                                get: { currentPrompts[i] },
                                set: { newValue in
                                    var updated = scheduler.customPrompts[selectedStyle.rawValue] ?? []
                                    guard i < updated.count else { return }
                                    updated[i] = newValue
                                    scheduler.updatePrompts(for: selectedStyle, prompts: updated)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Button {
                                var updated = scheduler.customPrompts[selectedStyle.rawValue] ?? []
                                guard i < updated.count else { return }
                                updated.remove(at: i)
                                scheduler.updatePrompts(for: selectedStyle, prompts: updated)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Add Prompt") {
                    var updated = scheduler.customPrompts[selectedStyle.rawValue] ?? selectedStyle.defaultPrompts
                    updated.append("")
                    scheduler.updatePrompts(for: selectedStyle, prompts: updated)
                }
                .buttonStyle(.bordered)

                Button("Reset to Defaults") {
                    scheduler.resetPrompts(for: selectedStyle)
                }
                .buttonStyle(.bordered)
                .disabled((scheduler.customPrompts[selectedStyle.rawValue] ?? []).isEmpty)
            }
        }
    }
}
