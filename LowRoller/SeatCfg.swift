import Foundation

struct SeatCfg: Identifiable, Equatable {
    let id: UUID = UUID()
    var isBot: Bool
    var botLevel: AIBotLevel = .amateur
    var name: String
    var botId: UUID? = nil
    var showPicker: Bool = false
    var wagerCents: Int

    static func == (lhs: SeatCfg, rhs: SeatCfg) -> Bool {
        lhs.id == rhs.id &&
        lhs.isBot == rhs.isBot &&
        lhs.botLevel == rhs.botLevel &&
        lhs.name == rhs.name &&
        lhs.botId == rhs.botId &&
        lhs.showPicker == rhs.showPicker &&
        lhs.wagerCents == rhs.wagerCents
    }
}
