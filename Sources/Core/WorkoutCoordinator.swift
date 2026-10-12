import Foundation
#if canImport(SwiftUI)
import Observation
#endif

public enum WorkoutLocation: String, CaseIterable, Sendable { case outdoor, indoor }
public enum WorkoutStatus: String, Sendable {
    case idle, recovering, authorizing, starting, running, paused, ending, saving, saveFailed, failed, saved
}
public enum WorkoutEvent: Sendable {
    case running, paused, ended(Date), failed(String)
}
public enum RecoveredWorkout: Sendable { case running, paused, ended(Date) }

/// The HealthKit adapter is the only platform-specific piece. Tests use a fake client.
@MainActor
public protocol WorkoutClient: AnyObject {
    var onEvent: ((WorkoutEvent) -> Void)? { get set }
    func authorize() async throws -> Bool
    func start(location: WorkoutLocation) async throws
    func recover() async throws -> RecoveredWorkout?
    func pause()
    func resume()
    func end()
    func finish(at date: Date) async throws
    func discard()
    func elapsed(at date: Date) -> TimeInterval
    func heartRate(at date: Date) -> Double?
}

// UI observation is Apple-platform instrumentation; the lifecycle also runs without UI on Linux.
#if canImport(SwiftUI)
@Observable
#endif
@MainActor
public final class WorkoutCoordinator {
    public private(set) var status: WorkoutStatus = .idle
    public private(set) var message: String?
    public private(set) var hasRecovered = false
    private let client: any WorkoutClient
    private var endDate: Date?
    private var pendingEnd: Date?
    private var pausedDuringStart = false

    public init(client: any WorkoutClient) {
        self.client = client
        client.onEvent = { [weak self] event in self?.receive(event) }
    }

    public var canStart: Bool { [.idle, .failed, .saved].contains(status) && hasRecovered }
    public var canEnd: Bool { status == .running || status == .paused }
    public func elapsed(at date: Date) -> TimeInterval { client.elapsed(at: date) }
    public func heartRate(at date: Date) -> Double? {
        status == .running ? client.heartRate(at: date) : nil
    }

    public func recover() async {
        guard !hasRecovered, status == .idle else { return }
        status = .recovering
        do {
            switch try await client.recover() {
            case .running: status = .running
            case .paused: status = .paused
            case .ended(let date): await save(at: date)
            case nil: status = .idle
            }
            hasRecovered = true
        } catch {
            // Do not start a second session when recovery could not be established.
            status = .failed
            hasRecovered = false
            message = "Workout recovery failed. \(error.localizedDescription)"
        }
    }

    public func retryRecovery() async {
        guard !hasRecovered, status == .failed else { return }
        status = .idle
        await recover()
    }

    public func start(location: WorkoutLocation) async {
        guard canStart else { return }
        status = .authorizing
        message = nil
        endDate = nil
        pendingEnd = nil
        pausedDuringStart = false
        do {
            guard try await client.authorize() else {
                status = .failed
                message = "Workout saving is not allowed. Enable Workouts in Health permissions to track exercise. Scoring still works."
                return
            }
            status = .starting
            try await client.start(location: location)
            if let pendingEnd {
                self.pendingEnd = nil
                await save(at: pendingEnd)
            } else {
                status = pausedDuringStart ? .paused : .running
            }
        } catch {
            client.discard()
            status = .failed
            message = error.localizedDescription
            pendingEnd = nil
        }
    }

    public func pauseOrResume() {
        if status == .running { client.pause() }
        else if status == .paused { client.resume() }
        // HealthKit's delegate confirms the transition.
    }

    public func end() {
        guard canEnd else { return }
        status = .ending
        client.end()
        // Save only after HealthKit confirms the session ended.
    }

    public func retrySave() async {
        guard status == .saveFailed, let endDate else { return }
        await save(at: endDate)
    }

    public func discardUnsavedWorkout() {
        guard status == .saveFailed else { return }
        client.discard()
        status = .idle
        message = "Workout discarded. Any samples already saved by HealthKit may remain."
    }

    private func receive(_ event: WorkoutEvent) {
        switch event {
        case .running:
            if status == .starting { pausedDuringStart = false }
            if status == .paused { status = .running }
        case .paused:
            if status == .starting { pausedDuringStart = true }
            if status == .running { status = .paused }
        case .failed(let reason):
            guard [.starting, .running, .paused, .ending].contains(status) else { return }
            message = reason
            // HKWorkoutSession delivers failure before its ended state; retain collected data.
        case .ended(let date):
            if status == .starting { pendingEnd = date; return }
            guard [.running, .paused, .ending].contains(status) else { return }
            status = .saving // Prevent duplicate ended callbacks from saving twice.
            Task { await self.save(at: date) }
        }
    }

    private func save(at date: Date) async {
        status = .saving
        endDate = date
        do {
            try await client.finish(at: date)
            status = .saved
            message = message.map { "\($0) Collected workout saved to Health." } ?? "Workout saved to Health."
        } catch {
            status = .saveFailed
            message = "Workout could not be saved. \(error.localizedDescription)"
        }
    }
}
