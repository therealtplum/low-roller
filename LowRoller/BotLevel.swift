import Foundation

// Use a unique name to avoid collisions with anything else in your app/frameworks.
enum AIBotLevel: String, Codable, CaseIterable {
    case amateur, pro
}

typealias BotLevel = AIBotLevel

struct BotIdentity: Hashable, Codable, Identifiable {
    let id: UUID
    let name: String
    let level: AIBotLevel
    let slot: Int // 1...7 if you want flavor
}

enum BotRoster {
    static let amateurs: [BotIdentity] = [
        .init(id: UUID(), name: "Dicey McRollface", level: .amateur, slot: 1),
        .init(id: UUID(), name: "Bet Midler", level: .amateur, slot: 2),
        .init(id: UUID(), name: "Snake Eyes Sally", level: .amateur, slot: 3),
        .init(id: UUID(), name: "Sir Lose-A-Lot", level: .amateur, slot: 4),
        .init(id: UUID(), name: "Bluffalo Bill", level: .amateur, slot: 5),
        .init(id: UUID(), name: "Risky Biscuit", level: .amateur, slot: 6),
        .init(id: UUID(), name: "Rollin’ Stones", level: .amateur, slot: 7),
    ]

    static let pros: [BotIdentity] = [
        .init(id: UUID(), name: "High Roller Hank", level: .pro, slot: 1),
        .init(id: UUID(), name: "Bot Damon", level: .pro, slot: 2),
        .init(id: UUID(), name: "The Count of Monte Crisco", level: .pro, slot: 3),
        .init(id: UUID(), name: "Win Diesel", level: .pro, slot: 4),
        .init(id: UUID(), name: "Lady Luckless", level: .pro, slot: 5),
        .init(id: UUID(), name: "Pair O’Dice Hilton", level: .pro, slot: 6),
        .init(id: UUID(), name: "Claude Monetball", level: .pro, slot: 7),
    ]

    static func all(for level: AIBotLevel) -> [BotIdentity] {
        level == .pro ? pros : amateurs
    }

    static func random(level: AIBotLevel, avoiding used: Set<UUID>) -> BotIdentity {
        let pool = all(for: level)
        let unused = pool.filter { !used.contains($0.id) }
        return (unused.isEmpty ? pool : unused).randomElement()!
    }
}
