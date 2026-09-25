import Testing
@testable import Lookaway

@Suite("break media playback")
struct MediaPlaybackControllerTests {
    @Test func resumesOnlyMediaPausedForBreak() async {
        var current = MediaPlaybackController.Snapshot(id: "browser|video", isPlaying: true)
        var commands: [MediaPlaybackController.Command] = []
        let controller = MediaPlaybackController(
            snapshot: { current },
            send: { command in
                commands.append(command)
                current = .init(id: current.id, isPlaying: command == .play)
                return true
            }
        )

        controller.beginBreak()
        await controller.waitForPendingWork()
        #expect(commands == [.pause])

        controller.endBreak()
        await controller.waitForPendingWork()
        #expect(commands == [.pause, .play])
    }

    @Test func leavesPreviouslyPausedOrChangedMediaAlone() async {
        var current = MediaPlaybackController.Snapshot(id: "browser|video", isPlaying: false)
        var commands: [MediaPlaybackController.Command] = []
        let controller = MediaPlaybackController(
            snapshot: { current },
            send: { command in commands.append(command); return true }
        )

        controller.beginBreak()
        await controller.waitForPendingWork()
        controller.endBreak()
        await controller.waitForPendingWork()
        #expect(commands.isEmpty)

        current = .init(id: "browser|video", isPlaying: true)
        controller.beginBreak()
        await controller.waitForPendingWork()
        current = .init(id: "browser|another video", isPlaying: false)
        controller.endBreak()
        await controller.waitForPendingWork()
        #expect(commands == [.pause])
    }

    @Test func quickSkipDoesNotLeaveMediaPaused() async {
        var current = MediaPlaybackController.Snapshot(id: "browser|video", isPlaying: true)
        var commands: [MediaPlaybackController.Command] = []
        let controller = MediaPlaybackController(
            snapshot: { current },
            send: { command in
                commands.append(command)
                current = .init(id: current.id, isPlaying: command == .play)
                return true
            }
        )

        controller.beginBreak()
        controller.endBreak()
        await controller.waitForPendingWork()
        #expect(commands.isEmpty)
    }

    @Test func newBreakKeepsOwnershipUntilFinalEnd() async {
        var current = MediaPlaybackController.Snapshot(id: "browser|video", isPlaying: true)
        var commands: [MediaPlaybackController.Command] = []
        let controller = MediaPlaybackController(
            snapshot: { current },
            send: { command in
                commands.append(command)
                current = .init(id: current.id, isPlaying: command == .play)
                return true
            }
        )

        controller.beginBreak()
        await controller.waitForPendingWork()
        controller.endBreak()
        controller.beginBreak()
        await controller.waitForPendingWork()
        #expect(commands == [.pause])

        controller.endBreak()
        await controller.waitForPendingWork()
        #expect(commands == [.pause, .play])
    }

    @Test func newBreakDuringResumePausesMediaAgain() async {
        var current = MediaPlaybackController.Snapshot(id: "browser|video", isPlaying: true)
        var commands: [MediaPlaybackController.Command] = []
        var startNextOnPlay = true
        var controller: MediaPlaybackController!
        controller = MediaPlaybackController(
            snapshot: { current },
            send: { command in
                commands.append(command)
                current = .init(id: current.id, isPlaying: command == .play)
                if command == .play && startNextOnPlay {
                    startNextOnPlay = false
                    controller.beginBreak()
                }
                return true
            }
        )

        controller.beginBreak()
        await controller.waitForPendingWork()
        controller.endBreak()
        await controller.waitForPendingWork()
        await controller.waitForPendingWork()
        #expect(commands == [.pause, .play, .pause])

        controller.endBreak()
        await controller.waitForPendingWork()
        #expect(commands == [.pause, .play, .pause, .play])
    }
}
