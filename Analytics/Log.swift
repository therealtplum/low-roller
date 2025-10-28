//
//  Log.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/26/25.
//


// Analytics/Log.swift
import Foundation

enum Log {
    static func matchStarted(matchId: UUID, players: [Player], potCents: Int, youStart: Bool) {
        AnalyticsLogger.shared.log(.init(
            type: "match_started",
            payload: [
                "matchId": .string(matchId.uuidString),
                "playerCount": .int(players.count),
                "botCount": .int(players.filter(\.isBot).count),
                "potCents": .int(potCents),
                "youStart": .bool(youStart)
            ]
        ))
    }

    static func decisionMade(matchId: UUID, playerIdx: Int, decision: String, picked: [Int]) {
        AnalyticsLogger.shared.log(.init(
            type: "decision_made",
            payload: [
                "matchId": .string(matchId.uuidString),
                "playerIdx": .int(playerIdx),
                "decision": .string(decision),        // "roll", "pass", "cashout"
                "picked": .array(picked.map { .int($0) })
            ]
        ))
    }

    static func betPlaced(matchId: UUID, playerIdx: Int, wagerCents: Int) {
        AnalyticsLogger.shared.log(.init(
            type: "bet_placed",
            payload: [
                "matchId": .string(matchId.uuidString),
                "playerIdx": .int(playerIdx),
                "wagerCents": .int(wagerCents)
            ]
        ))
    }

    static func roll(matchId: UUID, rollerIdx: Int, faces: [Int]) {
        AnalyticsLogger.shared.log(.init(
            type: "dice_rolled",
            payload: [
                "matchId": .string(matchId.uuidString),
                "rollerIdx": .int(rollerIdx),
                "faces": .array(faces.map { .int($0) })
            ]
        ))
    }

    static func roundEnded(matchId: UUID, turnIdx: Int, bankChangeCents: [Int]) {
        AnalyticsLogger.shared.log(.init(
            type: "round_ended",
            payload: [
                "matchId": .string(matchId.uuidString),
                "turnIdx": .int(turnIdx),
                "bankChangeCents": .array(bankChangeCents.map { .int($0) })
            ]
        ))
    }

    static func matchEnded(matchId: UUID, winnerIdx: Int, potCents: Int, balancesCents: [Int]) {
        AnalyticsLogger.shared.log(.init(
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
        AnalyticsLogger.shared.log(.init(type: "error", payload: payload))
    }
}