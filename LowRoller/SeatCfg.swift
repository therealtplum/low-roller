// Model/SeatCfg.swift
import Foundation

struct SeatCfg: Identifiable, Equatable {
    let id = UUID()
    var isBot: Bool
    var botLevel: BotLevel = .amateur   // relies on your BotLevel enum
    var name: String
    var wagerCents: Int                 // cents ($5 = 500)
}
