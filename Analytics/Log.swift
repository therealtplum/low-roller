// Log.swift
import Foundation

enum Log {
    static func matchStarted(matchId: UUID, players: [LowRoller.Player], potCents: Int, youStart: Bool) {
        AnalyticsLogger.shared.logIfEnabled(.init(
            type: "match_started",
            payload: [
                "matchId": .string(matchId.uuidString),
                "playerCount": .int(players.count),
                "botCount": .int(players.filter { $0.isBot }.count),
                "potCents": .int(potCents),
                "youStart": .bool(youStart)
            ]
        ))
    }
    
    static func decisionMade(matchId: UUID, playerIdx: Int, decision: String, picked: [Int]) {
        AnalyticsLogger.shared.logIfEnabled(.init(
            type: "decision_made",
            payload: [
                "matchId": .string(matchId.uuidString),
                "playerIdx": .int(playerIdx),
                "decision": .string(decision), // "roll", "pass", "cashout"
                "picked": .array(picked.map { .int($0) })
            ]
        ))
    }
    
    static func betPlaced(matchId: UUID, playerIdx: Int, wagerCents: Int) {
        AnalyticsLogger.shared.logIfEnabled(.init(
            type: "bet_placed",
            payload: [
                "matchId": .string(matchId.uuidString),
                "playerIdx": .int(playerIdx),
                "wagerCents": .int(wagerCents)
            ]
        ))
    }
    
    static func roll(matchId: UUID, rollerIdx: Int, faces: [Int]) {
        AnalyticsLogger.shared.logIfEnabled(.init(
            type: "dice_rolled",
            payload: [
                "matchId": .string(matchId.uuidString),
                "rollerIdx": .int(rollerIdx),
                "faces": .array(faces.map { .int($0) })
            ]
        ))
    }
    
    static func roundEnded(matchId: UUID, turnIdx: Int, bankChangeCents: [Int]) {
        AnalyticsLogger.shared.logIfEnabled(.init(
            type: "round_ended",
            payload: [
                "matchId": .string(matchId.uuidString),
                "turnIdx": .int(turnIdx),
                "bankChangeCents": .array(bankChangeCents.map { .int($0) })
            ]
        ))
    }
    
    static func matchEnded(matchId: UUID, winnerIdx: Int, potCents: Int, balancesCents: [Int]) {
        AnalyticsLogger.shared.logIfEnabled(.init(
            type: "match_ended",
            payload: [
                "matchId": .string(matchId.uuidString),
                "winnerIdx": .int(winnerIdx),
                "potCents": .int(potCents),
                "balancesCents": .array(balancesCents.map { .int($0) })
            ]
        ))
    }
    
    static func error(_ message: String, context: [String: CodableValue] = [:]) {
        var payload = context
        payload["message"] = .string(message)
        AnalyticsLogger.shared.logIfEnabled(.init(
            type: "error",
            payload: payload
        ))
    }
    
    // Additional useful analytics events
    static func appLaunched() {
        AnalyticsLogger.shared.logIfEnabled(.init(
            type: "app_launched",
            payload: [:]
        ))
    }
    
    static func appBackgrounded() {
        AnalyticsLogger.shared.logIfEnabled(.init(
            type: "app_backgrounded",
            payload: [:]
        ))
    }
    
    static func analyticsToggled(enabled: Bool) {
        AnalyticsLogger.shared.log(.init(
            type: "analytics_toggled",
            payload: ["enabled": .bool(enabled)]
        ))
    }
}
