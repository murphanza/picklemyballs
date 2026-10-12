import Foundation
import HealthKit
import WatchKit

@MainActor
final class HealthKitWorkoutClient: NSObject, WorkoutClient {
    var onEvent: ((WorkoutEvent) -> Void)?
    private let healthStore = HKHealthStore()
    private let heartRateType = HKQuantityType(.heartRate)
    private let energyType = HKQuantityType(.activeEnergyBurned)
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var collectionEnded = false
    private var sessionError: Error?
    private var latestHeartRate: Double?
    private var heartRateDate: Date?
    private var completedDuration: TimeInterval = 0
    private var recoveryEnd: CheckedContinuation<Date, Never>?

    func authorize() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutError("HealthKit is unavailable on this device. Scoring still works.")
        }
        // No routes, location access, distance, steps, or unrelated health data.
        let write: Set<HKSampleType> = [HKObjectType.workoutType(), energyType]
        let read: Set<HKObjectType> = [heartRateType, energyType]
        try await healthStore.requestAuthorization(toShare: write, read: read)
        // A successful request means the permission sheet completed, not that access was granted.
        // HealthKit intentionally does not expose read-permission status.
        return healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func start(location: WorkoutLocation) async throws {
        guard WKExtension.shared().applicationState == .active else {
            throw WorkoutError("Open the app on your Watch before starting a workout.")
        }
        guard session == nil else { throw WorkoutError("A workout is already attached to this app.") }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .pickleball
        configuration.locationType = location == .outdoor ? .outdoor : .indoor
        let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        attach(newSession)
        guard let builder else { throw WorkoutError("Workout collection could not be created.") }
        let date = Date()
        newSession.startActivity(with: date)
        try await builder.beginCollection(at: date)
        if let sessionError { throw sessionError }
    }

    func recover() async throws -> RecoveredWorkout? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        // This API only recovers this app's session, never Apple's Workout app's session.
        let recovered: HKWorkoutSession? = try await withCheckedThrowingContinuation { continuation in
            healthStore.recoverActiveWorkoutSession { session, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: session) }
            }
        }
        guard let recovered else { return nil }
        attach(recovered)
        switch recovered.state {
        case .running: return .running
        case .paused: return .paused
        case .stopped:
            // Stopped sessions still hold session mode; end before finishing their builder.
            let date: Date = await withCheckedContinuation { continuation in
                recoveryEnd = continuation
                recovered.end()
            }
            return .ended(date)
        case .ended: return .ended(recovered.endDate ?? Date())
        default:
            discard()
            throw WorkoutError("The recovered workout had not started. Start a new workout when ready.")
        }
    }

    private func attach(_ session: HKWorkoutSession) {
        self.session = session
        session.delegate = self
        let builder = session.associatedWorkoutBuilder()
        self.builder = builder
        builder.delegate = self
        if builder.dataSource == nil {
            let source = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: session.workoutConfiguration)
            // Restrict the default activity data source to the two metrics this app uses.
            for type in source.typesToCollect where type != heartRateType && type != energyType {
                source.disableCollection(for: type)
            }
            builder.dataSource = source
        }
        collectionEnded = builder.endDate != nil
        completedDuration = 0
        latestHeartRate = nil
        heartRateDate = nil
        sessionError = nil
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }
    func end() { session?.end() }

    func finish(at date: Date) async throws {
        guard let builder else { throw WorkoutError("The workout builder is no longer available.") }
        if !collectionEnded {
            try await builder.endCollection(at: date)
            collectionEnded = true
        }
        // Retain the builder on failure so the user can retry saving.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.finishWorkout { _, error in
                if let error { continuation.resume(throwing: error) }
                else {
                    // nil workout + nil error is a documented successful save on a locked device.
                    continuation.resume(returning: ())
                }
            }
        }
        completedDuration = builder.elapsedTime(at: date)
        releaseSession()
    }

    func discard() {
        session?.delegate = nil
        session?.end()
        builder?.discardWorkout()
        completedDuration = 0
        releaseSession()
    }

    private func releaseSession() {
        session?.delegate = nil
        builder?.delegate = nil
        session = nil
        builder = nil
        latestHeartRate = nil
        heartRateDate = nil
    }

    func elapsed(at date: Date) -> TimeInterval {
        guard let builder else { return completedDuration }
        return max(0, builder.elapsedTime(at: builder.endDate ?? date))
    }

    func heartRate(at date: Date) -> Double? {
        guard let heartRateDate, date.timeIntervalSince(heartRateDate) <= 60 else { return nil }
        return latestHeartRate
    }

    private func readableError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == HKErrorDomain && nsError.code == HKError.Code.errorAnotherWorkoutSessionStarted.rawValue {
            return "Another workout is active. End it in its app before starting here. Scoring still works."
        }
        return "Workout interrupted: \(error.localizedDescription) Scoring still works."
    }
}

extension HealthKitWorkoutClient: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                   from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            switch toState {
            case .running: self.onEvent?(.running)
            case .paused: self.onEvent?(.paused)
            case .ended:
                let waiting = self.recoveryEnd
                self.recoveryEnd = nil
                waiting?.resume(returning: date)
                self.onEvent?(.ended(date))
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession else { return }
            let message = self.readableError(error)
            self.sessionError = WorkoutError(message)
            self.onEvent?(.failed(message))
        }
    }
}

extension HealthKitWorkoutClient: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            guard self.builder === workoutBuilder, collectedTypes.contains(self.heartRateType),
                  let statistics = workoutBuilder.statistics(for: self.heartRateType),
                  let quantity = statistics.mostRecentQuantity() else { return }
            self.latestHeartRate = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            self.heartRateDate = statistics.mostRecentQuantityDateInterval()?.end ?? Date()
        }
    }
}

private struct WorkoutError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
