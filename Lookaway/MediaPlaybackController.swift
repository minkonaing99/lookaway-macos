import Foundation

@MainActor
final class MediaPlaybackController {
    struct Snapshot: Equatable {
        let id: String
        let isPlaying: Bool
    }

    enum Command: Int {
        case play = 0
        case pause = 1
    }

    private let snapshot: () async -> Snapshot?
    private let send: (Command) async -> Bool
    private var pendingWork: Task<Void, Never>?
    private var pausedSnapshot: Snapshot?
    private var breakActive = false

    init(
        snapshot: @escaping () async -> Snapshot? = { await MediaRemoteBridge.shared.snapshot() },
        send: @escaping (Command) async -> Bool = { await MediaRemoteBridge.shared.send($0) }
    ) {
        self.snapshot = snapshot
        self.send = send
    }

    func beginBreak() {
        guard !breakActive else { return }
        breakActive = true
        let previous = pendingWork
        pendingWork = Task {
            await previous?.value
            guard breakActive, let current = await snapshot(), current.isPlaying else { return }
            guard breakActive, await send(.pause) else { return }
            pausedSnapshot = current
        }
    }

    func endBreak() {
        guard breakActive else { return }
        breakActive = false
        let previous = pendingWork
        pendingWork = Task {
            await previous?.value
            guard !breakActive else { return }
            guard let pausedSnapshot else { return }
            let current = await snapshot()
            guard !breakActive else { return }
            let playerID = pausedSnapshot.id.split(separator: "|", maxSplits: 1).first.map { "\($0)|" }
            guard let current, !current.isPlaying,
                  (current.id == pausedSnapshot.id || current.id == playerID) else {
                self.pausedSnapshot = nil
                return
            }
            self.pausedSnapshot = nil
            guard await send(.play) else { return }
            if breakActive, await send(.pause) {
                self.pausedSnapshot = await snapshot() ?? pausedSnapshot
            }
        }
    }

    func waitForPendingWork() async {
        await pendingWork?.value
    }
}

private struct MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    func snapshot() async -> MediaPlaybackController.Snapshot? {
        guard let result = await run("snapshot"),
              let id = result["id"] as? String,
              let playing = result["playing"] as? Bool else { return nil }
        return .init(id: id, isPlaying: playing)
    }

    func send(_ command: MediaPlaybackController.Command) async -> Bool {
        await run(command == .pause ? "pause" : "play")?["sent"] as? Bool ?? false
    }

    private func run(_ action: String) async -> [String: Any]? {
        guard let helper = Bundle.main.privateFrameworksURL?.appendingPathComponent("lookaway-media-helper.dylib") else {
            return nil
        }
        return await Task.detached {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = ["-e", "use DynaLoader; DynaLoader::dl_load_file($ARGV[0], 0x01)", helper.path]
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["LOOKAWAY_MEDIA_COMMAND": action], uniquingKeysWith: { _, new in new }
            )
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            } catch {
                return nil
            }
        }.value
    }
}
