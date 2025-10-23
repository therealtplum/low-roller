// Models/SeatCfg.swift
import Foundation

struct SeatCfg: Identifiable, Equatable {
    let id = UUID()
    var isBot: Bool
    var botLevel: BotLevel = .amateur   // uses BotLevel from Phase.swift
    var name: String
    /// Wager in cents (e.g. $5 = 500)
    var wagerCents: Int
}
