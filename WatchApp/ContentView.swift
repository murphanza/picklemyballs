import SwiftUI

private let sideAColor = Color(red: 0.76, green: 0.98, blue: 0.34)
private let sideBColor = Color(red: 0.35, green: 0.87, blue: 1)

struct ContentView: View {
    let store: GameStore
    let workout: WorkoutCoordinator

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 6) {
                    HStack {
                        Text(store.game.scoreCall)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .accessibilityLabel("Score call \(store.game.scoreCall)")
                        Spacer(minLength: 2)
                        NavigationLink {
                            MatchSettingsView(store: store)
                        } label: {
                            Image(systemName: "gearshape.fill").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Game settings")
                    }

                    if let winner = store.game.winner {
                        Label("\(store.game.sideName(winner)) wins!", systemImage: "trophy.fill")
                            .font(.headline)
                            .foregroundStyle(.yellow)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                    } else {
                        VStack(spacing: 1) {
                            Text("\(store.game.sideName(store.game.state.serving)) serves")
                                .font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                            Text(serverDetail)
                                .font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                        }
                    }

                    HStack(spacing: 8) {
                        rallyButton(.a, color: sideAColor)
                        rallyButton(.b, color: sideBColor)
                    }

                    HStack(spacing: 8) {
                        Button { store.undo() } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                        .disabled(!store.game.canUndo || store.needsStorageRecovery)
                        .accessibilityLabel("Undo last rally")

                        NavigationLink {
                            WorkoutView(workout: workout)
                        } label: {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                VStack(spacing: 1) {
                                    Text(workout.canEnd ? clock(workout.elapsed(at: context.date)) : "Workout")
                                        .monospacedDigit().font(.caption.bold())
                                    if workout.status == .running {
                                        heartRate(workout.heartRate(at: context.date))
                                    } else {
                                        Text(workout.status == .paused ? "Paused" : "Manage")
                                            .font(.system(size: 10))
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }
                        .buttonStyle(.plain)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Manage workout")
                    }

                    if let error = store.persistenceError {
                        Text(error).font(.caption2).foregroundStyle(.yellow)
                        if !store.needsStorageRecovery {
                            Button("Retry game save") { store.save() }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            .background(.black)
            .foregroundStyle(.white)
        }
    }

    private var serverDetail: String {
        let court = store.game.serviceCourt == .right ? "Right court" : "Left court"
        if store.game.mode == .singles { return court }
        return "\(store.game.serverName) · \(court) · Server \(store.game.state.serverNumber)"
    }

    private func rallyButton(_ side: Side, color: Color) -> some View {
        Button { store.rally(side) } label: {
            VStack(spacing: 1) {
                Text(store.game.sideName(side))
                    .font(.caption.bold()).lineLimit(2).minimumScaleFactor(0.7)
                Text("\(store.game.state.score(side))")
                    .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                Text("Won rally").font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .padding(.horizontal, 3)
            .foregroundStyle(.black)
            .background(color, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(store.game.winner != nil || store.needsStorageRecovery)
        .accessibilityLabel("\(store.game.sideName(side)), \(store.game.state.score(side)) points. Record rally won.")
    }
}

struct MatchSettingsView: View {
    let store: GameStore
    var body: some View {
        List {
            NavigationLink("Edit names") { NamesView(store: store) }
                .disabled(store.needsStorageRecovery)
            NavigationLink("New game / Reset") { NewGameView(store: store) }
            Text("First to 11, win by 2. Only the serving side earns points.")
                .font(.caption)
            Text("Game changes never stop your workout.").font(.caption)
        }
        .navigationTitle("Game")
    }
}

struct NamesView: View {
    let store: GameStore
    @State private var teamA: Team
    @State private var teamB: Team
    @Environment(\.dismiss) private var dismiss

    init(store: GameStore) {
        self.store = store
        _teamA = State(initialValue: store.game.teamA)
        _teamB = State(initialValue: store.game.teamB)
    }

    var body: some View {
        Form {
            Section("Side A") {
                if store.game.mode == .doubles { TextField("Team name", text: $teamA.name) }
                TextField("Player 1", text: $teamA.player1)
                if store.game.mode == .doubles { TextField("Player 2", text: $teamA.player2) }
            }
            Section("Side B") {
                if store.game.mode == .doubles { TextField("Team name", text: $teamB.name) }
                TextField("Player 1", text: $teamB.player1)
                if store.game.mode == .doubles { TextField("Player 2", text: $teamB.player2) }
            }
            Text("Player 1 starts on the right; Player 2 on the left.").font(.caption)
            Button("Save names") {
                store.rename(.a, team: normalized(teamA, fallback: store.game.teamA))
                store.rename(.b, team: normalized(teamB, fallback: store.game.teamB))
                dismiss()
            }
        }
        .navigationTitle("Names")
    }

    private func normalized(_ team: Team, fallback: Team) -> Team {
        func name(_ value: String, _ fallback: String) -> String {
            let trimmed = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
            return trimmed.isEmpty ? fallback : trimmed
        }
        return Team(name: name(team.name, fallback.name), player1: name(team.player1, fallback.player1),
                    player2: name(team.player2, fallback.player2))
    }
}

struct NewGameView: View {
    let store: GameStore
    @State private var mode: GameMode
    @State private var openingSide: Side
    @State private var confirmReset = false
    @Environment(\.dismiss) private var dismiss

    init(store: GameStore) {
        self.store = store
        _mode = State(initialValue: store.game.mode)
        _openingSide = State(initialValue: store.game.openingSide)
    }

    var body: some View {
        Form {
            Picker("Mode", selection: $mode) {
                Text("Singles").tag(GameMode.singles)
                Text("Doubles").tag(GameMode.doubles)
            }
            Picker("First serve", selection: $openingSide) {
                Text(mode == .singles ? store.game.teamA.player1 : store.game.teamA.name).tag(Side.a)
                Text(mode == .singles ? store.game.teamB.player1 : store.game.teamB.name).tag(Side.b)
            }
            Text("Doubles starts at 0–0–2: the opening side gets one server.").font(.caption)
            Button("Start new game", role: .destructive) { confirmReset = true }
        }
        .navigationTitle("New game")
        .alert("Reset this game?", isPresented: $confirmReset) {
            Button("Reset game", role: .destructive) {
                store.reset(mode: mode, openingSide: openingSide)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Score and undo history will be cleared. Names stay. Your workout keeps running.")
        }
    }
}

struct WorkoutView: View {
    let workout: WorkoutCoordinator
    @State private var location: WorkoutLocation = .outdoor
    @State private var confirmEnd = false
    @State private var confirmDiscard = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(statusLabel).font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 4) {
                        Text(clock(workout.elapsed(at: context.date)))
                            .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                            .accessibilityLabel("Workout duration")
                            .accessibilityValue(clock(workout.elapsed(at: context.date)))
                        heartRate(workout.heartRate(at: context.date))
                    }
                }

                if workout.canStart {
                    Picker("Court", selection: $location) {
                        Text("Outdoor").tag(WorkoutLocation.outdoor)
                        Text("Indoor").tag(WorkoutLocation.indoor)
                    }
                    Button("Start pickleball") { Task { await workout.start(location: location) } }
                        .tint(sideAColor).foregroundStyle(.black)
                    Text("End any other Watch workout first. This app runs its own workout and cannot control Apple’s Workout app.")
                        .font(.caption2)
                }
                if workout.canEnd {
                    Button(workout.status == .paused ? "Resume workout" : "Pause workout") {
                        workout.pauseOrResume()
                    }
                    Button("End & save workout", role: .destructive) { confirmEnd = true }
                    Text("Keep scoring across games. A new game does not end this workout.").font(.caption2)
                }
                if workout.status == .saveFailed {
                    Button("Retry save") { Task { await workout.retrySave() } }
                    Button("Discard workout", role: .destructive) { confirmDiscard = true }
                }
                if workout.status == .failed && !workout.hasRecovered {
                    Button("Retry recovery") { Task { await workout.retryRecovery() } }
                }
                if [.recovering, .authorizing, .starting, .ending, .saving].contains(workout.status) {
                    ProgressView()
                }
                if let message = workout.message { Text(message).font(.caption2) }
                Text("Heart rate may be unavailable. Health and Activity credit depend on permissions and Apple’s measurements.")
                    .font(.caption2)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 4)
        }
        .navigationTitle("Workout")
        .alert("End this workout?", isPresented: $confirmEnd) {
            Button("End & save", role: .destructive) { workout.end() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the workout to Apple Health. Your game stays available for scoring.")
        }
        .alert("Discard unsaved workout?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { workout.discardUnsavedWorkout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The unsaved workout will be lost. Health samples already written may remain.")
        }
    }

    private var statusLabel: String {
        switch workout.status {
        case .idle: "Pickleball workout"
        case .recovering: "Recovering workout…"
        case .authorizing: "Health permissions…"
        case .starting: "Starting…"
        case .running: "Workout running"
        case .paused: "Workout paused"
        case .ending: "Ending…"
        case .saving: "Saving to Health…"
        case .saveFailed: "Save needs attention"
        case .failed: "Scoring is available"
        case .saved: "Saved to Health"
        }
    }
}

private func clock(_ duration: TimeInterval) -> String {
    let seconds = Int(max(0, duration))
    if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

@MainActor
private func heartRate(_ value: Double?) -> some View {
    Label(value.map { "\(Int($0.rounded())) bpm" } ?? "— bpm", systemImage: "heart.fill")
        .font(.caption2).foregroundStyle(.white)
        .accessibilityLabel(value.map { "Heart rate \(Int($0.rounded())) beats per minute" } ?? "Heart rate unavailable")
}
