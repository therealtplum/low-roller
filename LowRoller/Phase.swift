// Model/GameTypes (Phase).swift
import Foundation

enum Phase: String, Codable { case normal, suddenDeath, finished }
enum BotLevel: String, Codable { case amateur, pro }

// ✅ Codable replacement for the tuple
struct SuddenFaces: Codable {
    var p0: Int? = nil
    var p1: Int? = nil
}

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var display: String
    var isBot: Bool
    var botLevel: BotLevel?
    var wagerCents: Int
    var picks: [Int] = []
    var totalScore: Int { picks.reduce(0, +) }   // computed; not encoded
}

struct GameState: Codable {
    var players: [Player]
    var turnIdx: Int = 0
    var remainingDice: Int = 7
    var lastFaces: [Int] = []            // must pick ≥1 before next roll
    var potCents: Int
    var phase: Phase = .normal
    var turnsTaken: Int = 0              // one round == players.count

    // --- winner + sudden death ---
    var winnerIdx: Int? = nil
    var suddenRound: Int = 0
    var suddenFaces: SuddenFaces = SuddenFaces()
}
