import AppKit
import EventKit
import Foundation
import Testing
@testable import Lookaway

@Suite("recorded activity and interruptions", .serialized)
struct RecordedActivityTests {
    private func scheduler(media: MediaPlaybackController? = nil) -> BreakScheduler {
        let scheduler = BreakScheduler(mediaPlaybackController: media ?? MediaPlaybackController(snapshot: { nil }, send: { _ in false }))
        scheduler.stopTicker()
        scheduler.scheduleEnabled = false
        scheduler.focusBlocksEnabled = false
        scheduler.delayDuringMeetings = false
        scheduler.appAwarePauseEnabled = false
        scheduler.pauseWhenCameraActive = false
        scheduler.manualPauseEnabled = false
        scheduler.autoPauseReasons = []
        scheduler.pauseWhenIdle = true
        scheduler.idleSecondsProvider = { 0 }
        scheduler.checkIdleState()
        scheduler.adaptiveIntervalsEnabled = false
        scheduler.intervalOption = .min20
        scheduler.enablePreAlert = false
        scheduler.workSessionStartedAt = nil
        scheduler.dayStats = [:]
        return scheduler
    }

    @Test func legacyHistoryStillDecodes() throws {
        let data = Data(#"{"completed":3,"skipped":1,"snoozed":2}"#.utf8)
        let counters = try JSONDecoder().decode(BreakScheduler.DailyCounters.self, from: data)
        #expect(counters.completed == 3)
        #expect(counters.completedBreakSeconds == nil)
        #expect(counters.longestWorkSeconds == nil)
    }

    @Test func completedTimeUsesCapturedDurationAndExcludesPreviews() {
        let s = scheduler()
        let now = Date()
        s.activeBreakStartedAt = now.addingTimeInterval(-60)
        s.activeBreakDuration = 20
        s.restDurationOption = .min5
        s.recordCompletedBreak(at: now)
        #expect(s.computeExtendedStats().completedBreakSeconds == 20)
        s.isShowingTestBreak = true
        s.recordCompletedBreak(at: now)
        #expect(s.computeExtendedStats().completedBreakSeconds == 20)
    }

    @Test func workPeriodSurvivesSnoozeButEndsOnPause() {
        let s = scheduler()
        let start = Date().addingTimeInterval(-600)
        s.workSessionStartedAt = start
        s.snooze(minutes: 5)
        #expect(s.workSessionStartedAt == start)
        s.skipOnce()
        #expect(s.workSessionStartedAt == start)
        s.manualPauseEnabled = true
        #expect(s.workSessionStartedAt == nil)
        #expect(s.computeExtendedStats().longestWorkSeconds >= 600)
    }

    @Test func idleAndOverlappingPausesExcludeUnobservedTime() {
        let s = scheduler()
        let now = Date()
        s.workSessionStartedAt = now.addingTimeInterval(-900)
        s.idleSecondsProvider = { 600 }
        s.updateWorkSession(now: now)
        #expect(s.computeExtendedStats().longestWorkSeconds == 300)
        s.setAutoPause("webcam", active: true)
        s.setAutoPause("frontmostApp", active: true)
        s.setAutoPause("webcam", active: false)
        #expect(s.isPaused)
        #expect(s.pauseReasonText == "An excluded app is active")
        s.idleSecondsProvider = { 0 }
        s.setAutoPause("frontmostApp", active: false)
        #expect(!s.isPaused)
        #expect(s.workSessionStartedAt != nil)
    }

    @Test func completedBreakAcrossMidnightSplitsDays() {
        let s = scheduler()
        let midnight = Calendar.current.startOfDay(for: Date())
        s.activeBreakStartedAt = midnight.addingTimeInterval(-10)
        s.activeBreakDuration = 20
        s.recordCompletedBreak(at: midnight.addingTimeInterval(10))
        #expect(s.dayStats[BreakScheduler.dayKey(for: midnight.addingTimeInterval(-10))]?.completedBreakSeconds == 10)
        #expect(s.dayStats[BreakScheduler.dayKey(for: midnight)]?.completedBreakSeconds == 10)
    }

    @Test func liveWorkIncludesPreviousDayBeforeSessionEnds() {
        let s = scheduler()
        let midnight = Calendar.current.startOfDay(for: Date())
        s.workSessionStartedAt = midnight.addingTimeInterval(-1800)
        let snapshot = s.computeExtendedStats(now: midnight.addingTimeInterval(300))
        #expect(snapshot.longestWorkSeconds == 1800)
    }

    @Test func tickerRefreshesLiveWorkSnapshot() {
        let s = scheduler()
        let now = Date()
        s.workSessionStartedAt = now.addingTimeInterval(-600)
        s.extendedStats = .empty
        s.lastStatsRefresh = .distantPast
        s.nextBreakDate = now.addingTimeInterval(1200)
        s.tick(now: now)
        #expect(s.extendedStats.longestWorkSeconds == 600)
    }

    @Test func meetingCacheExpiresAtEventBoundaryAndIncludesUpcomingEvents() {
        let s = scheduler()
        let now = Date()
        let first = EKEvent(eventStore: s.eventStore)
        first.startDate = now.addingTimeInterval(-60)
        first.endDate = now.addingTimeInterval(10)
        let second = EKEvent(eventStore: s.eventStore)
        second.startDate = now.addingTimeInterval(20)
        second.endDate = now.addingTimeInterval(60)
        s.meetingEventsProvider = { _ in [first, second] }
        s.meetingCacheTimestamp = .distantPast
        #expect(s.currentBlockingMeeting(at: now) === first)
        #expect(s.currentBlockingMeeting(at: now.addingTimeInterval(10)) == nil)
        #expect(s.currentBlockingMeeting(at: now.addingTimeInterval(20)) === second)
        #expect(s.currentBlockingMeeting(at: now.addingTimeInterval(60)) == nil)
    }

    @Test func meetingNearDeadlineGetsOneGracePeriod() {
        let s = scheduler()
        let now = Date()
        let end = now.addingTimeInterval(10)
        s.nextBreakDate = now
        s.softlyRescheduleIfNeeded(for: .meeting(until: end, title: "Meeting"), now: now)
        #expect(s.nextBreakDate == end.addingTimeInterval(60))
        s.softlyRescheduleIfNeeded(for: .meeting(until: end, title: "Meeting"), now: now.addingTimeInterval(5))
        #expect(s.nextBreakDate == end.addingTimeInterval(60))
        s.nextBreakDate = now.addingTimeInterval(20)
        s.softlyRescheduleIfNeeded(for: .meeting(until: end, title: nil), now: now)
        #expect(s.nextBreakDate == now.addingTimeInterval(20))
    }

    @Test func displayChangePreservesBreakDeadlineAndIdentity() {
        let s = scheduler()
        defer { s.skipOnce(); s.stopTicker() }
        s.showBreak()
        let deadline = s.activeBreakDeadline
        let id = s.activeBreakID
        s.handleDisplayChange()
        #expect(s.activeBreakDeadline == deadline)
        #expect(s.activeBreakID == id)
        #expect(s.isShowingBreak)
        #expect(s.overlayController.visibleDisplayCount == NSScreen.screens.count)
    }

    @Test func sleepInterruptsWithoutCreditAndResumesMediaOnlyAfterUnlock() async {
        var playing = true
        var commands: [MediaPlaybackController.Command] = []
        let media = MediaPlaybackController(snapshot: { .init(id: "player|track", isPlaying: playing) }, send: {
            commands.append($0)
            playing = $0 == .play
            return true
        })
        let s = scheduler(media: media)
        defer { s.stopTicker() }
        s.showBreak()
        await media.waitForPendingWork()
        s.setSystemSuspension("sleep", active: true)
        s.setSystemSuspension("session", active: true)
        #expect(!s.isShowingBreak)
        #expect(s.activeBreakID == nil)
        #expect(!s.tickerActive)
        s.dismissBreakCompleted()
        #expect(s.computeExtendedStats().completedBreakSeconds == 0)
        #expect(s.dayStats.values.allSatisfy { $0.completed == 0 })
        s.setSystemSuspension("sleep", active: false)
        await media.waitForPendingWork()
        #expect(commands == [.pause])
        #expect(!s.tickerActive)
        s.setSystemSuspension("session", active: false)
        await media.waitForPendingWork()
        #expect(commands == [.pause, .play])
        #expect(s.tickerActive)
        #expect(s.nextBreakDate > Date())
    }

    @Test func menuShowsCalendarOnlyWhenEnabledAndNeedsAttention() {
        let s = scheduler()
        s.calendarStatusText = "Access denied"
        #expect(!s.showsCalendarAttention)
        s.meetingEventsProvider = { _ in [] }
        s.delayDuringMeetings = true
        s.calendarStatusText = "Access denied"
        #expect(s.showsCalendarAttention)
        s.calendarStatusText = "Connected"
        #expect(!s.showsCalendarAttention)
        s.manualPauseEnabled = true
        #expect(!s.showsNextBreakTime)
        #expect(s.currentBlockerText.contains("Paused manually"))
    }
}
