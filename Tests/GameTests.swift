import Foundation
import Testing
@testable import PickleScoreCore

@Suite("Traditional side-out scoring")
struct GameTests {
    @Test func openingDoublesService() {
        var game = Game()
        #expect(game.scoreCall == "0–0–2")
        #expect(game.state.serverPlayer == 0)
        #expect(game.serviceCourt == .right)
        game.recordRally(wonBy: .b)
        #expect(game.state.serving == .b)
        #expect(game.state.serverNumber == 1)
        #expect(game.state.scoreA == 0 && game.state.scoreB == 0)
        #expect(game.scoreCall == "0–0–1")
        #expect(game.serviceCourt == .right)
    }

    @Test func bothServersAndPlayerPositions() {
        var game = Game()
        game.recordRally(wonBy: .b) // B's first server, player 1 on right.
        game.recordRally(wonBy: .b) // B earns a point, player 1 switches to left.
        #expect(game.scoreCall == "1–0–1")
        #expect(game.serviceCourt == .left)
        #expect(game.state.serverPlayer == 0)
        game.recordRally(wonBy: .a) // Second server, player 2, now on right.
        #expect(game.state.serving == .b)
        #expect(game.state.serverPlayer == 1)
        #expect(game.state.serverNumber == 2)
        #expect(game.serviceCourt == .right)
        game.recordRally(wonBy: .a) // Side-out, A's first server.
        #expect(game.scoreCall == "0–1–1")
        #expect(game.state.serving == .a)
        #expect(game.serviceCourt == .right)
    }

    @Test func sideOutKeepsTeamPositions() {
        var game = Game()
        game.recordRally(wonBy: .a)
        #expect(game.serviceCourt == .left)
        #expect(game.state.rightPlayerA == 1)
        game.recordRally(wonBy: .b)
        game.recordRally(wonBy: .a)
        game.recordRally(wonBy: .a)
        #expect(game.state.serving == .a)
        #expect(game.state.serverPlayer == 1)
        #expect(game.serverName == "Player A2")
        #expect(game.serviceCourt == .right)
        #expect(game.state.serverNumber == 1)
    }

    @Test func secondServerAlsoSwitchesCourtsAfterPoint() {
        var game = Game()
        for side in [Side.b, .a] { game.recordRally(wonBy: side) }
        #expect(game.serviceCourt == .left) // Player 2 starts from the left at 0 points.
        game.recordRally(wonBy: .b)
        #expect(game.state.serving == .b)
        #expect(game.state.serverNumber == 2)
        #expect(game.state.serverPlayer == 1)
        #expect(game.state.scoreB == 1)
        #expect(game.serviceCourt == .right)
    }

    @Test func singlesServiceAndParity() {
        var game = Game(mode: .singles)
        game.recordRally(wonBy: .a)
        #expect(game.scoreCall == "1–0")
        #expect(game.serviceCourt == .left)
        game.recordRally(wonBy: .b)
        #expect(game.scoreCall == "0–1")
        #expect(game.serviceCourt == .right)
        game.recordRally(wonBy: .b)
        game.recordRally(wonBy: .a)
        #expect(game.state.serving == .a)
        #expect(game.serviceCourt == .left)
        #expect(game.state.serverNumber == 1)
        #expect(game.state.scoreA == 1 && game.state.scoreB == 1)
    }

    @Test(arguments: GameMode.allCases) func winAtElevenAndUndo(mode: GameMode) {
        var game = Game(mode: mode)
        for _ in 0..<11 { game.recordRally(wonBy: .a) }
        #expect(game.winner == .a)
        let completed = game
        #expect(game.recordRally(wonBy: .b) == false)
        #expect(game == completed)
        #expect(game.undo() == true)
        #expect(game.state.scoreA == 10)
        #expect(game.winner == nil)
        game.recordRally(wonBy: .a)
        #expect(game == completed)
    }

    @Test func winByTwoWithNoCap() {
        var game = Game(mode: .singles)
        for _ in 0..<10 { game.recordRally(wonBy: .a) }
        game.recordRally(wonBy: .b)
        for _ in 0..<10 { game.recordRally(wonBy: .b) }
        for _ in 0..<5 {
            game.recordRally(wonBy: .a) // Side-out
            game.recordRally(wonBy: .a) // Point
            #expect(game.winner == nil)
            game.recordRally(wonBy: .b)
            game.recordRally(wonBy: .b)
            #expect(game.winner == nil)
        }
        #expect(game.state.scoreA == 15 && game.state.scoreB == 15)
        game.recordRally(wonBy: .a)
        game.recordRally(wonBy: .a)
        #expect(game.winner == nil)
        game.recordRally(wonBy: .a)
        #expect(game.winner == .a)
        #expect(game.state.scoreA == 17)
    }

    @Test func undoEveryTransitionAndNameEdits() {
        var game = Game()
        #expect(game.undo() == false)
        let opening = game.state
        game.recordRally(wonBy: .a)
        let point = game.state
        game.recordRally(wonBy: .b)
        let sideOut = game.state
        game.recordRally(wonBy: .a)
        game.rename(.a, team: Team(name: "Dink", player1: "Alex", player2: "Sam"))
        #expect(game.undo() == true)
        #expect(game.state == sideOut)
        #expect(game.undo() == true)
        #expect(game.state == point)
        #expect(game.undo() == true)
        #expect(game.state == opening)
        #expect(game.teamA.name == "Dink")
        #expect(!game.canUndo)
    }

    @Test func resetAndChooseOpeningSide() {
        var game = Game()
        game.rename(.b, team: Team(name: "B team", player1: "Blair", player2: "Jo"))
        game.recordRally(wonBy: .a)
        game.reset(mode: .singles, openingSide: .b)
        #expect(game.state.serving == .b)
        #expect(game.state.scoreA == 0 && game.state.scoreB == 0)
        #expect(game.mode == .singles)
        #expect(game.history.isEmpty)
        #expect(game.sideName(.b) == "Blair")
        game.reset(mode: .doubles)
        #expect(game.scoreCall == "0–0–2")
        #expect(game.state.serving == .b)
        #expect(game.serverName == "Blair")
    }

    @Test(arguments: GameMode.allCases) func otherOpeningSideCanWin(mode: GameMode) {
        var game = Game(mode: mode, openingSide: .b)
        for _ in 0..<11 { game.recordRally(wonBy: .b) }
        #expect(game.winner == .b)
        #expect(game.state.scoreA == 0 && game.state.scoreB == 11)
        #expect(game.isValid)
    }

    @Test(arguments: GameMode.allCases) func longRallySequenceIsReversible(mode: GameMode) throws {
        var game = Game(mode: mode, openingSide: .b)
        var random: UInt64 = 42
        for _ in 0..<500 {
            if game.winner != nil { game.reset() }
            let prior = game
            random = random &* 6364136223846793005 &+ 1
            let side: Side = random >> 61 & 1 == 0 ? .a : .b
            game.recordRally(wonBy: side)
            #expect(game.isValid)
            let after = game
            #expect(game.undo() == true)
            #expect(game == prior)
            game = after
            #expect(try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game)) == game)
        }
    }
}

@Suite("Atomic local game persistence")
struct PersistenceTests {
    private func temporaryFile() -> GameFile {
        GameFile(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("game.json"))
    }

    @Test func saveLoadUndoAndReplace() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        #expect(try file.load() == nil)
        var game = Game()
        game.rename(.a, team: Team(name: "Kitchen", player1: "Alex", player2: "Sam"))
        for side in [Side.a, .b, .b, .a] { game.recordRally(wonBy: side) }
        try file.save(game)
        let loaded = try file.load()
        var restored = try #require(loaded)
        #expect(restored == game)
        #expect(restored.undo() == true)
        #expect(game.undo() == true)
        #expect(restored == game)
        restored.reset(mode: .singles, openingSide: .b)
        try file.save(restored)
        #expect(try file.load() == restored)
        #expect(restored.teamA.name == "Kitchen")
    }

    @Test func corruptFileIsRejectedAndPreserved() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        try file.save(Game())
        let corrupt = Data("invalid JSON".utf8)
        try corrupt.write(to: file.url)
        #expect(throws: (any Error).self) { try file.load() }
        #expect(try Data(contentsOf: file.url) == corrupt)
    }

    @Test func impossibleStateAndUnknownVersionAreRejected() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        try file.save(Game())
        let data = try Data(contentsOf: file.url)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = 2
        try JSONSerialization.data(withJSONObject: object).write(to: file.url)
        #expect(throws: (any Error).self) { try file.load() }
        object["version"] = 1
        var game = try #require(object["game"] as? [String: Any])
        var state = try #require(game["state"] as? [String: Any])
        state["serverPlayer"] = 9
        game["state"] = state
        object["game"] = game
        try JSONSerialization.data(withJSONObject: object).write(to: file.url)
        #expect(throws: GameFileError.invalidState) { try file.load() }
    }

    @Test func writeFailurePropagates() throws {
        let blocked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: blocked) }
        try Data("not a directory".utf8).write(to: blocked)
        let file = GameFile(url: blocked.appendingPathComponent("game.json"))
        #expect(throws: (any Error).self) { try file.save(Game()) }
    }
}
