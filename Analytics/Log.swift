//
//  Log.swift
//  LowRoller
//
//  Centralized analytics facade. Keeps all event shapes consistent,
//  requires matchId for auditable events, and offers rich helpers
//  for fully replayable multi-player rounds.
//

import Foundation

enum Log {

    // MARK: - Core plumbing

    /// Generic logger if you want full control.
    static func write(type: String, payload: [String: Any] = [:], bypassGate: Bool = false) {
        let line = AnalyticsEvent.base(type: type, payload: payload, bypassGate: bypassGate)
        AnalyticsLogger.shared.write(line, bypassGate: bypassGate)
    }

    /// Merge helper to enforce a matchId on all auditable events.
    @inline(__always)
    private static func withMatchId(_ payload: [String: Any], matchId: UUID) -> [String: Any] {
        var p = payload
        p["matchId"] = matchId.uuidString
        return p
    }

    /// Backcompat shim: warn if callers forget a matchId.
    @inline(__always)
    private static func warnMissingMatchId(_ event: String) {
        #if DEBUG
        NSLog("⚠️ Log.\(event) called without matchId — add one to keep events auditable.")
        #endif
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

    // MARK: - Match / table snapshots (for replayability)

    /// Canonical snapshot at the start of a match/round.
    /// `players` is an array of dictionaries like:
    /// ["playerId":"p0","name":"You","seat":0,"isBot":false,"wagerCents":500]
    static func matchStarted(matchId: UUID,
                             players: [[String: Any]],
                             tableMode: String = "standard",
                             houseRules: [String: Any] = [:],
                             advertisedStakesCents: Int? = nil,
                             youStartSeat: Int? = nil) {
        var payload: [String: Any] = [
            "players": players,
            "tableMode": tableMode,
            "houseRules": houseRules
        ]
        if let s = advertisedStakesCents { payload["stakesCents"] = s }
        if let ys = youStartSeat { payload["youStartSeat"] = ys }
        write(type: "match_started", payload: withMatchId(payload, matchId: matchId))
    }

    /// End-of-match snapshot.
    static func matchEnded(matchId: UUID,
                           winnerPlayerId: String,
                           potCents: Int,
                           doubleCount: Int,
                           finalBalances: [String: Int]? = nil) {
        var payload: [String: Any] = [
            "winnerPlayerId": winnerPlayerId,
            "potCents": potCents,
            "doubleCount": doubleCount
        ]
        if let fb = finalBalances { payload["finalBalances"] = fb }
        write(type: "match_ended", payload: withMatchId(payload, matchId: matchId))
    }

    // MARK: - Turn-level telemetry

    static func turnStarted(matchId: UUID, turnNumber: Int, playerId: String, diceInCup: Int) {
        write(type: "turn_started",
              payload: withMatchId([
                "turn": turnNumber,
                "playerId": playerId,
                "diceInCup": diceInCup
              ], matchId: matchId))
    }

    static func diceRolled(matchId: UUID,
                           turnNumber: Int,
                           rollerPlayerId: String,
                           faces: [Int],
                           diceBefore: Int,
                           diceAfter: Int) {
        write(type: "dice_rolled",
              payload: withMatchId([
                "turn": turnNumber,
                "rollerPlayerId": rollerPlayerId,
                "faces": faces,
                "diceBefore": diceBefore,
                "diceAfter": diceAfter
              ], matchId: matchId))
    }

    /// Rich decision payload so a replay script can reconstruct state exactly.
    static func decisionMade(matchId: UUID,
                             turnNumber: Int,
                             playerId: String,
                             pickedFaces: [Int],
                             keptIndices: [Int],
                             keptTallies: [String: Int],
                             diceRemaining: Int) {
        write(type: "decision_made",
              payload: withMatchId([
                "turn": turnNumber,
                "playerId": playerId,
                "picked": pickedFaces,
                "keptIndices": keptIndices,
                "keptTallies": keptTallies,
                "diceRemaining": diceRemaining
              ], matchId: matchId))
    }

    static func turnEnded(matchId: UUID,
                          turnNumber: Int,
                          playerId: String,
                          turnScore: Int,
                          bust: Bool = false) {
        write(type: "turn_ended",
              payload: withMatchId([
                "turn": turnNumber,
                "playerId": playerId,
                "turnScore": turnScore,
                "bust": bust
              ], matchId: matchId))
    }

    // MARK: - Sudden death

    static func suddenDeathStarted(matchId: UUID,
                                   reason: String,
                                   playerIds: [String],
                                   round: Int) {
        write(type: "sudden_death_started",
              payload: withMatchId([
                "reason": reason,
                "players": playerIds,
                "round": round
              ], matchId: matchId))
    }

    static func suddenDeathRolled(matchId: UUID,
                                  round: Int,
                                  playerId: String,
                                  face: Int) {
        write(type: "sudden_death_rolled",
              payload: withMatchId([
                "round": round,
                "playerId": playerId,
                "face": face
              ], matchId: matchId))
    }

    static func suddenDeathEnded(matchId: UUID,
                                 winnerPlayerId: String,
                                 round: Int) {
        write(type: "sudden_death_ended",
              payload: withMatchId([
                "winnerPlayerId": winnerPlayerId,
                "round": round
              ], matchId: matchId))
    }

    // MARK: - Double or Nothing

    static func doubleOrNothingStarted(matchId: UUID,
                                       challengerId: String,
                                       opponentId: String,
                                       stakeCentsPerPlayer: Int) {
        write(type: "double_or_nothing_started",
              payload: withMatchId([
                "challengerId": challengerId,
                "opponentId": opponentId,
                "stakeCents": stakeCentsPerPlayer
              ], matchId: matchId))
    }

    // MARK: - Economy ledger (players & house) — matchId REQUIRED

    /// Positive inflow to a player's personal bank.
    static func bankCredited(player: String, amountCents: Int, reason: String, matchId: UUID) {
        write(type: "bank_credited",
              payload: withMatchId([
                "player": player,
                "amountCents": amountCents,
                "reason": reason
              ], matchId: matchId))
    }

    /// Outflow from a player's personal bank.
    static func bankDebited(player: String, amountCents: Int, reason: String, matchId: UUID) {
        write(type: "bank_debited",
              payload: withMatchId([
                "player": player,
                "amountCents": amountCents,
                "reason": reason
              ], matchId: matchId))
    }

    /// Positive inflow to the House balance.
    static func houseCredited(amountCents: Int, reason: String, matchId: UUID) {
        write(type: "house_credited",
              payload: withMatchId([
                "amountCents": amountCents,
                "reason": reason
              ], matchId: matchId))
    }

    /// Outflow from the House balance.
    static func houseDebited(amountCents: Int, reason: String, matchId: UUID) {
        write(type: "house_debited",
              payload: withMatchId([
                "amountCents": amountCents,
                "reason": reason
              ], matchId: matchId))
    }

    // MARK: - Backcompat shims (deprecated) — keep temporarily

    @available(*, deprecated, message: "Pass a matchId")
    static func bankCredited(player: String, amountCents: Int, reason: String, matchId: UUID? = nil) {
        guard let mid = matchId else { warnMissingMatchId("bankCredited"); return }
        bankCredited(player: player, amountCents: amountCents, reason: reason, matchId: mid)
    }

    @available(*, deprecated, message: "Pass a matchId")
    static func bankDebited(player: String, amountCents: Int, reason: String, matchId: UUID? = nil) {
        guard let mid = matchId else { warnMissingMatchId("bankDebited"); return }
        bankDebited(player: player, amountCents: amountCents, reason: reason, matchId: mid)
    }

    @available(*, deprecated, message: "Pass a matchId")
    static func houseCredited(amountCents: Int, reason: String, matchId: UUID? = nil) {
        guard let mid = matchId else { warnMissingMatchId("houseCredited"); return }
        houseCredited(amountCents: amountCents, reason: reason, matchId: mid)
    }

    @available(*, deprecated, message: "Pass a matchId")
    static func houseDebited(amountCents: Int, reason: String, matchId: UUID? = nil) {
        guard let mid = matchId else { warnMissingMatchId("houseDebited"); return }
        houseDebited(amountCents: amountCents, reason: reason, matchId: mid)
    }

    // MARK: - Utilities

    static func flush() { AnalyticsLogger.shared.flush() }
    static func shutdown() { AnalyticsLogger.shared.shutdown() }
}
