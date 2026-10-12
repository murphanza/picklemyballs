import SwiftUI
import WatchKit

@MainActor
enum AppServices {
    static let workout = WorkoutCoordinator(client: HealthKitWorkoutClient())
}

final class ApplicationDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await AppServices.workout.recover() }
    }
}

@main
struct PickleScoreApp: App {
    @WKApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @State private var game = GameStore()
    @State private var workout = AppServices.workout
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(store: game, workout: workout)
                .task { await workout.recover() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { game.save() }
                }
        }
    }
}
