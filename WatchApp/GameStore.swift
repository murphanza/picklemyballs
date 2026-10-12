import Foundation
import Observation
import WatchKit

@MainActor @Observable
final class GameStore {
    private(set) var game = Game()
    private(set) var persistenceError: String?
    private(set) var needsStorageRecovery = false
    @ObservationIgnored private let file: GameFile

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = GameFile(url: directory.appendingPathComponent("PickleScore/game.json"))
        do { game = try file.load() ?? Game() }
        catch {
            needsStorageRecovery = true
            persistenceError = "Saved game could not be loaded. It is preserved. Use New game to archive it and continue."
        }
    }

    func rally(_ side: Side) {
        guard !needsStorageRecovery, game.recordRally(wonBy: side) else { return }
        save()
        WKInterfaceDevice.current().play(game.winner == nil ? .click : .success)
    }

    func undo() {
        guard !needsStorageRecovery, game.undo() else { return }
        save()
        WKInterfaceDevice.current().play(.click)
    }

    func rename(_ side: Side, team: Team) {
        guard !needsStorageRecovery else { return }
        game.rename(side, team: team)
        save()
    }

    func reset(mode: GameMode, openingSide: Side) {
        if needsStorageRecovery {
            do {
                let archive = file.url.deletingLastPathComponent().appendingPathComponent("unreadable-game-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: file.url, to: archive)
                needsStorageRecovery = false
            } catch {
                persistenceError = "Could not preserve the unreadable game: \(error.localizedDescription)"
                return
            }
        }
        game.reset(mode: mode, openingSide: openingSide)
        save()
        WKInterfaceDevice.current().play(.click)
    }

    func save() {
        guard !needsStorageRecovery else { return }
        do {
            try file.save(game)
            persistenceError = nil
        } catch {
            persistenceError = "Game is in memory but could not be saved: \(error.localizedDescription)"
        }
    }
}
