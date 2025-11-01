//
//  Log.swift
//  LowRoller
//

import Foundation

/// Centralized analytics facade. Keeps all event shapes consistent.
enum Log {

    // MARK: - Core plumbing

    /// Generic logger if you want full control.
    static func write(type: String, payload: [String: Any] = [:], bypassGate: Bool = false) {
        let line = AnalyticsEvent.base(type: type, payload: payload, bypassGate: bypassGate)
        AnalyticsLogger.shared.write(line, bypassGate: bypassGate)
    }

    // MARK: - App lifecycle / settings

    static func appForegrounded() {
        write(type: "app_foregrounded")
    }

    static func appBackgrounded() {
        write(type: "app_backgrounded")
    }

    /// Always logs (even if analytics are OFF) so you can verify toggling.
    static func analyticsToggled(enabled: Bool) {
        write(type: "analytics_toggled", payload: ["enabled": enabled], bypassGate: true)
    }

    // MARK: - Game: session & flow

    static func matchStarted(matchId: UUID,
                             playerCount: Int,
                             botCount: Int,
                             potCents: Int,
                             youStart: Bool) {
        write(type: "match_started", payload: [
            "matchId": matchId.uuidString,
            "playerCount": playerCount,
            "botCount": botCount,
            "potCents": potCents,
            "youStart": youStart
        ])
    }

    static func betPlaced(matchId: UUID, playerIdx: Int, wagerCents: Int) {
        write(type: "bet_placed", payload: [
            "matchId": matchId.uuidString,
            "playerIdx": playerIdx,
            "wagerCents": wagerCents
        ])
    }

    static func diceRolled(matchId: UUID, rollerIdx: Int, faces: [Int]) {
        write(type: "dice_rolled", payload: [
            "matchId": matchId.uuidString,
            "rollerIdx": rollerIdx,
            "faces": faces
        ])
    }

    static func decisionMade(matchId: UUID, playerIdx: Int, decision: String, picked: [Int]) {
        write(type: "decision_made", payload: [
            "matchId": matchId.uuidString,
            "playerIdx": playerIdx,
            "decision": decision,
            "picked": picked
        ])
    }

    static func roundEnded(matchId: UUID, turnIdx: Int, bankChangeCents: [Int]) {
        write(type: "round_ended", payload: [
            "matchId": matchId.uuidString,
            "turnIdx": turnIdx,
            "bankChangeCents": bankChangeCents
        ])
    }

    static func matchEnded(matchId: UUID, winnerIdx: Int, balancesCents: [Int], potCents: Int) {
        write(type: "match_ended", payload: [
            "matchId": matchId.uuidString,
            "winnerIdx": winnerIdx,
            "balancesCents": balancesCents,
            "potCents": potCents
        ])
    }

    // MARK: - Economy ledger (players & house)

    /// Positive inflow to a player's personal bank.
    static func bankCredited(player: String, amountCents: Int, reason: String, matchId: UUID? = nil) {
        var payload: [String: Any] = [
            "player": player,
            "amountCents": amountCents,
            "reason": reason
        ]
        if let mid = matchId { payload["matchId"] = mid.uuidString }
        write(type: "bank_credited", payload: payload)
    }

    /// Outflow from a player's personal bank.
    static func bankDebited(player: String, amountCents: Int, reason: String, matchId: UUID? = nil) {
        var payload: [String: Any] = [
            "player": player,
            "amountCents": amountCents,
            "reason": reason
        ]
        if let mid = matchId { payload["matchId"] = mid.uuidString }
        write(type: "bank_debited", payload: payload)
    }

    /// Positive inflow to the House balance.
    static func houseCredited(amountCents: Int, reason: String, matchId: UUID? = nil) {
        var payload: [String: Any] = [
            "amountCents": amountCents,
            "reason": reason
        ]
        if let mid = matchId { payload["matchId"] = mid.uuidString }
        write(type: "house_credited", payload: payload)
    }

    /// Outflow from the House balance.
    static func houseDebited(amountCents: Int, reason: String, matchId: UUID? = nil) {
        var payload: [String: Any] = [
            "amountCents": amountCents,
            "reason": reason
        ]
        if let mid = matchId { payload["matchId"] = mid.uuidString }
        write(type: "house_debited", payload: payload)
    }

    // MARK: - Utilities

    static func flush() {
        AnalyticsLogger.shared.flush()
    }

    static func shutdown() {
        AnalyticsLogger.shared.shutdown()
    }
}
