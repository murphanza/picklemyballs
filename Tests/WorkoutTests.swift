import Foundation
import Testing
@testable import PickleScoreCore

@MainActor
private final class FakeWorkoutClient: WorkoutClient {
    var onEvent: ((WorkoutEvent) -> Void)?
    var calls: [String] = []
    var permission = true
    var recovered: RecoveredWorkout?
    var recoveryError = false
    var startError = false
    var saveError = false
    var startHook: (() -> Void)?
    var elapsedTime: TimeInterval = 125
    var rate: Double? = 118

    func authorize() async throws -> Bool { calls.append("authorize"); return permission }
    func start(location: WorkoutLocation) async throws {
        calls.append("start:\(location.rawValue)")
        startHook?()
        if startError { throw FakeError.failed }
    }
    func recover() async throws -> RecoveredWorkout? {
        calls.append("recover")
        if recoveryError { throw FakeError.failed }
        return recovered
    }
    func pause() { calls.append("pause"); onEvent?(.paused) }
    func resume() { calls.append("resume"); onEvent?(.running) }
    func end() { calls.append("end") }
    func finish(at date: Date) async throws {
        calls.append("finish")
        if saveError { throw FakeError.failed }
    }
    func discard() { calls.append("discard") }
    func elapsed(at date: Date) -> TimeInterval { elapsedTime }
    func heartRate(at date: Date) -> Double? { rate }
}

private enum FakeError: Error { case failed }

@Suite("Workout lifecycle independent of games") @MainActor
struct WorkoutTests {
    @Test func authorizationDeniedStillAllowsScoring() async {
        let client = FakeWorkoutClient()
        client.permission = false
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.start(location: .indoor)
        #expect(workout.status == .failed)
        #expect(!client.calls.contains("start:indoor"))
        var game = Game()
        #expect(game.recordRally(wonBy: .a) == true)
        #expect(game.state.scoreA == 1)
    }

    @Test func startPauseResumeAndResetIndependence() async {
        let client = FakeWorkoutClient()
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.start(location: .outdoor)
        #expect(workout.status == .running)
        #expect(workout.elapsed(at: Date()) == 125)
        #expect(workout.heartRate(at: Date()) == 118)
        var game = Game()
        for _ in 0..<11 { game.recordRally(wonBy: .a) }
        #expect(game.winner == .a)
        game.reset(mode: .singles)
        #expect(workout.status == .running)
        #expect(!client.calls.contains("end"))
        workout.pauseOrResume()
        #expect(workout.status == .paused)
        #expect(workout.heartRate(at: Date()) == nil)
        workout.pauseOrResume()
        #expect(workout.status == .running)
        await workout.start(location: .indoor)
        #expect(client.calls.filter { $0.hasPrefix("start:") }.count == 1)
    }

    @Test func endWaitsForSessionThenSavesOnce() async {
        let client = FakeWorkoutClient()
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.start(location: .outdoor)
        workout.end()
        workout.end()
        #expect(workout.status == .ending)
        #expect(client.calls.filter { $0 == "end" }.count == 1)
        #expect(!client.calls.contains("finish"))
        client.onEvent?(.ended(Date()))
        client.onEvent?(.ended(Date()))
        await settle(workout)
        #expect(workout.status == .saved)
        #expect(client.calls.filter { $0 == "finish" }.count == 1)
        #expect(workout.canStart)
    }

    @Test func failedSaveCanBeRetriedWithoutEndingAgain() async {
        let client = FakeWorkoutClient()
        client.saveError = true
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.start(location: .outdoor)
        workout.end()
        client.onEvent?(.ended(Date()))
        await settle(workout)
        #expect(workout.status == .saveFailed)
        #expect(!workout.canStart)
        client.saveError = false
        await workout.retrySave()
        #expect(workout.status == .saved)
        #expect(client.calls.filter { $0 == "end" }.count == 1)
        #expect(client.calls.filter { $0 == "finish" }.count == 2)
    }

    @Test func discardRequiresAFailedSave() async {
        let client = FakeWorkoutClient()
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.start(location: .outdoor)
        workout.discardUnsavedWorkout()
        #expect(workout.status == .running)
        #expect(!client.calls.contains("discard"))
        client.saveError = true
        workout.end()
        client.onEvent?(.ended(Date()))
        await settle(workout)
        workout.discardUnsavedWorkout()
        #expect(workout.status == .idle)
        #expect(client.calls.contains("discard"))
    }

    @Test func recoverOwnedSessionWithoutStartingAnother() async {
        let client = FakeWorkoutClient()
        client.recovered = .paused
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.recover()
        #expect(workout.status == .paused)
        #expect(!workout.canStart)
        #expect(client.calls == ["recover"])
        workout.pauseOrResume()
        #expect(workout.status == .running)
    }

    @Test func recoveryErrorBlocksNewSessionUntilRetried() async {
        let client = FakeWorkoutClient()
        client.recoveryError = true
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        #expect(workout.status == .failed)
        #expect(!workout.hasRecovered)
        #expect(!workout.canStart)
        await workout.start(location: .indoor)
        #expect(!client.calls.contains("authorize"))
        client.recoveryError = false
        await workout.retryRecovery()
        #expect(workout.canStart)
    }

    @Test func recoveryCanFinishStoppedWorkout() async {
        let client = FakeWorkoutClient()
        client.recovered = .ended(Date())
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        #expect(workout.status == .saved)
        #expect(client.calls == ["recover", "finish"])
    }

    @Test func startFailureCleansUpAndCanRetry() async {
        let client = FakeWorkoutClient()
        client.startError = true
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.start(location: .outdoor)
        #expect(workout.status == .failed)
        #expect(client.calls.contains("discard"))
        #expect(workout.canStart)
        client.startError = false
        await workout.start(location: .indoor)
        #expect(workout.status == .running)
    }

    @Test func interruptedWorkoutSavesCollectedData() async {
        let client = FakeWorkoutClient()
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.start(location: .outdoor)
        client.onEvent?(.failed("Another workout started."))
        client.onEvent?(.ended(Date()))
        await settle(workout)
        #expect(workout.status == .saved)
        #expect(workout.message?.contains("Another workout started.") == true)
        #expect(workout.message?.contains("saved") == true)
    }

    @Test func endedDuringStartupDoesNotReturnToRunning() async {
        let client = FakeWorkoutClient()
        client.startHook = { client.onEvent?(.ended(Date())) }
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.start(location: .outdoor)
        #expect(workout.status == .saved)
        #expect(client.calls.filter { $0 == "finish" }.count == 1)
    }

    @Test func missingHeartRateIsNotInvented() async {
        let client = FakeWorkoutClient()
        client.rate = nil
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.start(location: .outdoor)
        #expect(workout.heartRate(at: Date()) == nil)
    }

    @Test func pauseDuringStartupIsPreserved() async {
        let client = FakeWorkoutClient()
        client.startHook = { client.onEvent?(.paused) }
        let workout = WorkoutCoordinator(client: client)
        await workout.recover()
        await workout.start(location: .outdoor)
        #expect(workout.status == .paused)
    }

    private func settle(_ workout: WorkoutCoordinator) async {
        for _ in 0..<100 where workout.status == .saving { await Task.yield() }
    }
}
