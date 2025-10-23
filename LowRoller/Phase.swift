// Model/GameTypes.swift
import Foundation

enum Phase: String, Codable { case normal, finished }
enum BotLevel: String, Codable { case amateur, pro }

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var display: String
    var isBot: Bool
    var botLevel: BotLevel?
    var wagerCents: Int
    var picks: [Int] = []
    var totalScore: Int { picks.reduce(0, +) }
}

struct GameState: Codable {
    var players: [Player]
    var turnIdx: Int = 0
    var remainingDice: Int = 7
    var lastFaces: [Int] = []            // must pick ≥1 before next roll
    var potCents: Int
    var phase: Phase = .normal
    var turnsTaken: Int = 0              // one round == players.count
}
