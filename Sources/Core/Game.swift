import Foundation

public enum Side: String, Codable, CaseIterable, Sendable {
    case a, b
    public var other: Side { self == .a ? .b : .a }
}

public enum GameMode: String, Codable, CaseIterable, Sendable {
    case singles, doubles
}

public enum ServiceCourt: String, Sendable {
    case right, left
}

public struct Team: Codable, Equatable, Sendable {
    public var name: String
    public var player1: String
    public var player2: String

    public init(name: String, player1: String, player2: String) {
        self.name = name
        self.player1 = player1
        self.player2 = player2
    }

    public func player(_ index: Int) -> String { index == 0 ? player1 : player2 }
}

/// Only rally state is undone. Name edits remain intact.
public struct RallyState: Codable, Equatable, Sendable {
    public internal(set) var scoreA = 0
    public internal(set) var scoreB = 0
    public internal(set) var serving: Side
    public internal(set) var serverNumber: Int
    public internal(set) var serverPlayer = 0
    public internal(set) var rightPlayerA = 0
    public internal(set) var rightPlayerB = 0

    public func score(_ side: Side) -> Int { side == .a ? scoreA : scoreB }
    public func rightPlayer(_ side: Side) -> Int { side == .a ? rightPlayerA : rightPlayerB }

    public var winner: Side? {
        guard max(scoreA, scoreB) >= 11, abs(scoreA - scoreB) >= 2 else { return nil }
        return scoreA > scoreB ? .a : .b
    }
}

public struct Game: Codable, Equatable, Sendable {
    public private(set) var mode: GameMode
    public private(set) var teamA: Team
    public private(set) var teamB: Team
    public private(set) var openingSide: Side
    public private(set) var state: RallyState
    public private(set) var history: [RallyState] = []

    public init(mode: GameMode = .doubles, openingSide: Side = .a,
                teamA: Team = Team(name: "Team A", player1: "Player A1", player2: "Player A2"),
                teamB: Team = Team(name: "Team B", player1: "Player B1", player2: "Player B2")) {
        self.mode = mode
        self.openingSide = openingSide
        self.teamA = teamA
        self.teamB = teamB
        state = RallyState(serving: openingSide, serverNumber: mode == .doubles ? 2 : 1)
    }

    public var canUndo: Bool { !history.isEmpty }
    public var winner: Side? { state.winner }
    public var serviceCourt: ServiceCourt {
        if mode == .singles { return state.score(state.serving).isMultiple(of: 2) ? .right : .left }
        return state.serverPlayer == state.rightPlayer(state.serving) ? .right : .left
    }

    /// Scores are always called in serving–receiving–server order.
    public var scoreCall: String {
        let scores = "\(state.score(state.serving))–\(state.score(state.serving.other))"
        return mode == .doubles ? "\(scores)–\(state.serverNumber)" : scores
    }

    public func team(_ side: Side) -> Team { side == .a ? teamA : teamB }
    public func sideName(_ side: Side) -> String {
        mode == .singles ? team(side).player1 : team(side).name
    }
    public var serverName: String { team(state.serving).player(state.serverPlayer) }

    public mutating func rename(_ side: Side, team: Team) {
        if side == .a { teamA = team } else { teamB = team }
    }

    @discardableResult
    public mutating func recordRally(wonBy side: Side) -> Bool {
        guard winner == nil else { return false }
        history.append(state)
        state = Self.afterRally(state, mode: mode, wonBy: side)
        return true
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        state = previous
        return true
    }

    public mutating func reset(mode: GameMode? = nil, openingSide: Side? = nil) {
        self = Game(mode: mode ?? self.mode, openingSide: openingSide ?? self.openingSide,
                    teamA: teamA, teamB: teamB)
    }

    private static func afterRally(_ previous: RallyState, mode: GameMode, wonBy side: Side) -> RallyState {
        var next = previous
        if side == previous.serving {
            if side == .a { next.scoreA += 1 } else { next.scoreB += 1 }
            // Only the serving teammates switch courts after earning a point.
            if mode == .doubles {
                if side == .a { next.rightPlayerA = 1 - next.rightPlayerA }
                else { next.rightPlayerB = 1 - next.rightPlayerB }
            }
        } else if mode == .doubles && previous.serverNumber == 1 {
            next.serverNumber = 2
            next.serverPlayer = 1 - previous.serverPlayer
        } else {
            next.serving = previous.serving.other
            next.serverNumber = 1
            next.serverPlayer = mode == .doubles ? previous.rightPlayer(next.serving) : 0
        }
        return next
    }

    /// Validate decoded state by replaying each possible rally, rather than trusting JSON fields.
    public var isValid: Bool {
        let initial = RallyState(serving: openingSide, serverNumber: mode == .doubles ? 2 : 1)
        guard let first = history.first else { return state == initial }
        guard first == initial else { return false }
        var expected = initial
        for next in history.dropFirst() + [state] {
            guard expected.winner == nil,
                  next == Self.afterRally(expected, mode: mode, wonBy: .a)
                    || next == Self.afterRally(expected, mode: mode, wonBy: .b) else { return false }
            expected = next
        }
        return true
    }
}
