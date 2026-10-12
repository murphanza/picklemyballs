import Foundation

public enum GameFileError: Error, LocalizedError {
    case invalidState
    public var errorDescription: String? { "The saved game could not be read. Its file has been preserved." }
}

public struct GameFile {
    public let url: URL
    public init(url: URL) { self.url = url }

    private struct Archive: Codable {
        let version: Int
        let game: Game
    }

    public func load() throws -> Game? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
        guard archive.version == 1, archive.game.isValid else { throw GameFileError.invalidState }
        return archive.game
    }

    public func save(_ game: Game) throws {
        guard game.isValid else { throw GameFileError.invalidState }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Archive(version: 1, game: game))
        try data.write(to: url, options: .atomic)
    }
}
