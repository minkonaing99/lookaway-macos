import AppKit
import SwiftUI

struct AppAwarePauseView: View {
    @ObservedObject var scheduler: BreakScheduler
    @State private var runningApps: [NSRunningApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if scheduler.pauseAppBundleIDs.isEmpty {
                Text("No apps configured. Add apps using the menu below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(scheduler.pauseAppBundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 10) {
                            Text(displayName(for: bundleID))
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                            Text(bundleID)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Button {
                                scheduler.removePauseApp(bundleID: bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            Menu {
                ForEach(sortedRunningApps, id: \.bundleIdentifier) { app in
                    let id = app.bundleIdentifier ?? ""
                    Button(app.localizedName ?? id) {
                        if !id.isEmpty {
                            scheduler.addPauseApp(bundleID: id)
                        }
                    }
                    .disabled(scheduler.pauseAppBundleIDs.contains(id))
                }
                if sortedRunningApps.isEmpty {
                    Text("No running apps found")
                }
            } label: {
                Label("Add from Running Apps", systemImage: "plus.circle")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.bordered)
            .onAppear { refreshRunningApps() }
        }
    }

    private var sortedRunningApps: [NSRunningApplication] {
        runningApps
            .filter { !($0.bundleIdentifier ?? "").isEmpty && $0.localizedName != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }
    }

    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String
            return name ?? url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }
}
