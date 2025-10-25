// Model/GameTypes (Phase).swift
import Foundation

// MARK: - Phase
enum Phase: String, Codable { case normal, suddenDeath, finished }

// ✅ Codable replacement for the tuple
struct SuddenFaces: Codable {
    var p0: Int? = nil
    var p1: Int? = nil
}

// MARK: - Player
struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var display: String
    var isBot: Bool
    var botLevel: BotLevel?
    var wagerCents: Int
    var picks: [Int] = []
    var totalScore: Int { picks.reduce(0, +) }   // computed; not encoded

    /// NEW: persistent bankroll with $100 default
    /// Stored as cents; positive/negative allowed.
    var bankrollCents: Int = 10_000
}

// MARK: Codable migration for Player (default bankroll)
extension Player {
    private enum CodingKeys: String, CodingKey {
        case id, display, isBot, botLevel, wagerCents, picks, bankrollCents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        display = try c.decode(String.self, forKey: .display)
        isBot = try c.decode(Bool.self, forKey: .isBot)
        botLevel = try c.decodeIfPresent(BotLevel.self, forKey: .botLevel)
        wagerCents = try c.decode(Int.self, forKey: .wagerCents)
        picks = try c.decodeIfPresent([Int].self, forKey: .picks) ?? []
        // If older saves don’t have bankrollCents, default to $100
        bankrollCents = try c.decodeIfPresent(Int.self, forKey: .bankrollCents) ?? 10_000
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(display, forKey: .display)
        try c.encode(isBot, forKey: .isBot)
        try c.encodeIfPresent(botLevel, forKey: .botLevel)
        try c.encode(wagerCents, forKey: .wagerCents)
        try c.encode(picks, forKey: .picks)
        try c.encode(bankrollCents, forKey: .bankrollCents)
    }
}

// MARK: - GameState
struct GameState: Codable {
    var players: [Player]
    var turnIdx: Int = 0
    var remainingDice: Int = 7
    var lastFaces: [Int] = []            // must pick ≥1 before next roll
    var potCents: Int
    var potDebited: Bool = false 
    var phase: Phase = .normal
    var turnsTaken: Int = 0              // one round == players.count

    // --- winner + sudden death ---
    var winnerIdx: Int? = nil
    var suddenRound: Int = 0
    var suddenFaces: SuddenFaces = SuddenFaces()
}
