//
//  GameEngine.swift
//  LowRoller
//

import Foundation
import Combine

// MARK: - Notifications used by the UI
extension Notification.Name {
    /// Posted when a match ends. `object` is a Bool: true if a human (non-bot) won.
    static let humanWonMatch = Notification.Name("humanWonMatch")
}

// MARK: - Telemetry payloads local to GameEngine

private struct TurnStartedPayload: Codable {
    let turn: Int
    let playerId: String
    let diceInCup: Int
}

private struct TurnEndedPayload: Codable {
    let turn: Int
    let playerId: String
    let turnScore: Int
    let bust: Bool
}

private struct SuddenDeathStartedPayload: Codable {
    let reason: String
    let players: [String]
}

private struct SuddenDeathRolledPayload: Codable {
    let round: Int
    let playerId: String
    let face: Int
}

private struct SuddenDeathEndedPayload: Codable {
    let winnerPlayerId: String
}

private struct DoubleOrNothingStartedPayload: Codable {
    let challengerId: String
    let opponentId: String
    let stakeCents: Int
}

private struct MatchEndedPayload: Codable {
    let winnerPlayerId: String
    let potCents: Int
    let doubleCount: Int
}

final class GameEngine: ObservableObject {
    @Published private(set) var state: GameState
    private var rng = SystemRandomNumberGenerator()

    // MARK: - Telemetry
    private let bus = EventBus.shared
    private let matchUUID = UUID()                // <- concrete UUID to satisfy Log.* deprecation
    private var matchId: String { matchUUID.uuidString }

    // MARK: - Init

    init(players: [Player], youStart: Bool, leaders: LeaderboardStore) {
        var hydrated = players
        for i in hydrated.indices {
            let name = hydrated[i].display.trimmingCharacters(in: .whitespacesAndNewlines)
            if let entry = leaders.entries.first(where: {
                $0.name.caseInsensitiveCompare(name.isEmpty ? "You" : name) == .orderedSame
            }) {
                hydrated[i].bankrollCents = entry.bankrollCents
            }
        }

        var s = GameState(players: hydrated, potCents: 0)
        s.turnIdx = youStart ? 0 : Int.random(in: 0..<hydrated.count, using: &rng)
        self.state = s

        if hydrated.count == 2 && hydrated[0].wagerCents == hydrated[1].wagerCents {
            self.state.baseWagerCentsPerPlayer = hydrated[0].wagerCents
        } else if let first = hydrated.first {
            self.state.baseWagerCentsPerPlayer = first.wagerCents
        }

        // match_started
        let seats: [PlayerSeat] = hydrated.enumerated().map { (i, _) in
            PlayerSeat(playerId: "p\(i)", name: displayName(i), seat: i)
        }
        bus.emit(.match_started,
                 matchId: matchId,
                 body: MatchStartedPayload(players: seats,
                                           stakesCents: nil,
                                           tableMode: "standard",
                                           houseRules: ["rerollOnTie": true, "maxRollsPerTurn": true]))

        // Debit wagers and build pot
        assemblePotFromPlayerWagers()

        // First turn
        emitTurnStarted()
    }

    convenience init(players: [Player], youStart: Bool) {
        let tmp = LeaderboardStore()
        self.init(players: players, youStart: youStart, leaders: tmp)
    }

    // MARK: - Helpers

    private func score(_ face: Int) -> Int { face == 3 ? 0 : face }
    private func totalPoints(for p: Player) -> Int { p.picks.reduce(0, +) }
    private var isFinished: Bool { state.phase == .finished }

    private func targetScoreToBeat() -> Int? {
        guard state.turnsTaken > 0 else { return nil }
        let completedTotals = state.players.prefix(state.turnsTaken).map(totalPoints(for:))
        return completedTotals.min()
    }

    private func expectedScoreFromDice(count: Int) -> Double {
        guard count > 0 else { return 0 }
        return Double(count) * 3.0
    }

    private func displayName(_ i: Int) -> String {
        guard i >= 0 && i < state.players.count else { return "Player\(i)" }
        let d = state.players[i].display.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.isEmpty ? "You" : d
    }

    private func playerId(_ idx: Int) -> String { "p\(idx)" }

    private func emitTurnStarted() {
        bus.emit(.turn_started,
                 matchId: matchId,
                 body: TurnStartedPayload(
                    turn: state.turnsTaken + 1,
                    playerId: playerId(state.turnIdx),
                    diceInCup: state.remainingDice
                 ))
    }

    private func tally(_ picks: [Int]) -> [String:Int] {
        var t: [String:Int] = ["1":0,"2":0,"3":0,"4":0,"5":0,"6":0]
        for v in picks { t["\(v)", default: 0] += 1 }
        return t
    }

    // MARK: - Public actions

    func roll() {
        guard !isFinished, state.remainingDice > 0, state.lastFaces.isEmpty else { return }
        let before = state.remainingDice
        let faces = (0..<state.remainingDice).map { _ in Int.random(in: 1...6, using: &rng) }
        state.lastFaces = faces

        bus.emit(.dice_rolled,
                 matchId: matchId,
                 body: DiceRolledPayload(
                    turn: state.turnsTaken + 1,
                    rollerPlayerId: playerId(state.turnIdx),
                    faces: faces,
                    diceBefore: before,
                    diceAfter: before
                 ))
    }

    func pick(indices: [Int]) {
        guard !isFinished, !state.lastFaces.isEmpty else { return }

        let uniq = Array(Set(indices)).sorted()
        guard !uniq.isEmpty, uniq.allSatisfy({ $0 >= 0 && $0 < state.lastFaces.count }) else { return }

        let pickedValues = uniq.map { state.lastFaces[$0] }
        let scored = pickedValues.map { score($0) }
        state.players[state.turnIdx].picks.append(contentsOf: scored)
        state.remainingDice -= uniq.count
        state.lastFaces = []

        let turn = state.turnsTaken + 1
        let currentTurnPicks = state.players[state.turnIdx].picks
        bus.emit(.decision_made,
                 matchId: matchId,
                 body: DecisionMadePayload(
                    turn: turn,
                    playerId: playerId(state.turnIdx),
                    picked: pickedValues,
                    keptIndices: uniq,
                    keptTallies: tally(currentTurnPicks),
                    diceRemaining: state.remainingDice
                 ))

        _ = endTurnIfDone()
    }

    @discardableResult
    func endTurnIfDone() -> Bool {
        guard state.remainingDice == 0 else { return false }

        let endedIdx = state.turnIdx
        let turn = state.turnsTaken + 1
        let turnScore = totalPoints(for: state.players[endedIdx])
        bus.emit(.turn_ended,
                 matchId: matchId,
                 body: TurnEndedPayload(
                    turn: turn,
                    playerId: playerId(endedIdx),
                    turnScore: turnScore,
                    bust: false
                 ))

        state.turnsTaken &+= 1

        if state.turnsTaken >= state.players.count {
            if let wIdx = computeWinnerIndex() {
                state.winnerIdx = wIdx
                if shouldOfferDoubleNow() {
                    state.phase = .awaitDouble
                } else {
                    finalizeAndNotify()
                }
            } else {
                let totals = state.players.map { totalPoints(for: $0) }
                let minTotal = totals.min()!
                let tied = state.players.indices.filter { totals[$0] == minTotal }
                startSuddenDeath(with: tied)
            }
        } else {
            state.turnIdx = (state.turnIdx + 1) % state.players.count
            state.remainingDice = 7
            state.lastFaces = []
            emitTurnStarted()
        }
        return true
    }

    // MARK: - Sudden Death

    func rollSuddenDeath() -> Int? {
        guard state.phase == .suddenDeath, var contenders = state.suddenContenders else { return nil }

        var rolls: [Int: Int] = [:]
        for idx in contenders {
            let face = Int.random(in: 1...6, using: &rng)
            rolls[idx] = face
            bus.emit(.sudden_death_rolled,
                     matchId: matchId,
                     body: SuddenDeathRolledPayload(
                        round: state.suddenRound,
                        playerId: playerId(idx),
                        face: face
                     ))
        }
        state.suddenRolls = rolls

        let minAdj = rolls.values.map(score).min()
        let lowest = rolls.filter { score($0.value) == minAdj }.map(\.key)

        if lowest.count == 1 {
            state.winnerIdx = lowest[0]
            bus.emit(.sudden_death_ended,
                     matchId: matchId,
                     body: SuddenDeathEndedPayload(winnerPlayerId: playerId(lowest[0])))
            finalizeAndNotify()
            return state.winnerIdx
        } else {
            contenders = lowest
            state.suddenContenders = contenders
            state.suddenRound &+= 1
            return nil
        }
    }

    // MARK: - Double or Nothing

    private func shouldOfferDoubleNow() -> Bool {
        guard state.doubleCount == 0, state.players.count == 2, let w = state.winnerIdx else { return false }
        let p0Human = !state.players[0].isBot
        let p1Human = !state.players[1].isBot
        guard p0Human != p1Human else { return false }
        let humanIdx = p0Human ? 0 : 1
        let loserIdx = (w == 0) ? 1 : 0
        return loserIdx == humanIdx
    }

    func acceptDoubleOrNothing() {
        guard state.phase == .awaitDouble,
              let winner = state.winnerIdx,
              state.players.count == 2 else { return }

        state.doubleCount += 1

        let challengerIdx = (winner == 0) ? 1 : 0
        let stake = state.players[0].wagerCents
        bus.emit(.double_or_nothing_started,
                 matchId: matchId,
                 body: DoubleOrNothingStartedPayload(
                    challengerId: playerId(challengerIdx),
                    opponentId: playerId(winner),
                    stakeCents: stake
                 ))

        // Each player posts original wager again
        for i in state.players.indices {
            let originalWager = state.players[i].wagerCents
            let oldBankroll = state.players[i].bankrollCents
            state.players[i].bankrollCents -= originalWager

            // Legacy line with concrete matchId (kills deprecation warning)
            Log.bankDebited(player: displayName(i),
                            amountCents: originalWager,
                            reason: "double_or_nothing",
                            matchId: matchUUID)

            if oldBankroll >= 0 && state.players[i].bankrollCents < 0 {
                let borrowedAmount = abs(state.players[i].bankrollCents)
                let penalty = Int(Double(borrowedAmount) * 0.20)
                EconomyStore.shared.recordBorrowPenalty(playerName: displayName(i),
                                                        cents: penalty,
                                                        matchId: matchUUID,
                                                        matchIdString: matchId)
                state.players[i].bankrollCents -= penalty
            }
            state.potCents += originalWager
        }

        resetForNewRound()
        state.turnIdx = (winner + 1) % state.players.count
        emitTurnStarted()
    }

    func declineDoubleOrNothing() {
        guard state.phase == .awaitDouble else { return }
        finalizeAndNotify()
    }

    // MARK: - Round/Match resets

    func resetForNewRound() {
        state.remainingDice = 7
        state.lastFaces = []
        state.turnsTaken = 0
        state.winnerIdx = nil
        state.suddenRound = 0
        state.suddenContenders = nil
        state.suddenRolls = nil
        state.phase = .normal
        for i in state.players.indices { state.players[i].picks.removeAll() }
    }

    func resetForNewMatch() {
        state.remainingDice = 7
        state.lastFaces = []
        state.phase = .normal
        state.turnsTaken = 0
        state.winnerIdx = nil
        state.suddenRound = 0
        state.suddenContenders = nil
        state.suddenRolls = nil
        for i in state.players.indices { state.players[i].picks.removeAll() }
    }

    // MARK: - Timeout behavior

    func handleTurnTimeout() {
        guard !isFinished,
              state.phase == .normal,
              state.turnIdx < state.players.count,
              !state.players[state.turnIdx].isBot
        else { return }

        if state.lastFaces.isEmpty { roll() }
        if !state.lastFaces.isEmpty { smartPick() }

        if !isFinished,
           state.phase == .normal,
           state.turnIdx < state.players.count,
           state.remainingDice > 0,
           state.lastFaces.isEmpty {
            roll()
        }
    }

    func onTimeout() { handleTurnTimeout() }

    // MARK: - Bot-like picking

    func smartPick() {
        guard !state.lastFaces.isEmpty else { return }

        let faces = state.lastFaces
        theLoop: do {
            let currentScore = totalPoints(for: state.players[state.turnIdx])
            let target = targetScoreToBeat()

            let idxs: [Int: [Int]] = Dictionary(grouping: faces.enumerated(), by: { $0.element })
                .mapValues { $0.map(\.offset) }

            let threes = idxs[3] ?? []
            let ones   = idxs[1] ?? []
            let twos   = idxs[2] ?? []
            let fours  = idxs[4] ?? []
            let fives  = idxs[5] ?? []
            let sixes  = idxs[6] ?? []

            func pickSingleLowest() {
                if let lowest = faces.enumerated().min(by: { score($0.element) < score($1.element) })?.offset {
                    pick(indices: [lowest])
                }
            }

            if let t = target {
                let scoreNeeded = t - currentScore - 1
                _ = expectedScoreFromDice(count: state.remainingDice - faces.count)

                if scoreNeeded < 0 {
                    if !threes.isEmpty { pick(indices: threes); break theLoop }
                    else if !ones.isEmpty { pick(indices: [ones[0]]); break theLoop }
                    else if !twos.isEmpty { pick(indices: [twos[0]]); break theLoop }
                    else if !fours.isEmpty { pick(indices: [fours[0]]); break theLoop }
                    else if !fives.isEmpty { pick(indices: [fives[0]]); break theLoop }
                    else if !sixes.isEmpty { pick(indices: [sixes[0]]); break theLoop }
                    else { pickSingleLowest(); break theLoop }
                } else {
                    if !threes.isEmpty { pick(indices: threes); break theLoop }
                    else if ones.count >= 2 { pick(indices: ones); break theLoop }
                    else if twos.count >= 2 { pick(indices: twos); break theLoop }
                    else { pickSingleLowest(); break theLoop }
                }
            } else {
                if !threes.isEmpty { pick(indices: threes); break theLoop }
                else if ones.count >= 2 { pick(indices: ones); break theLoop }
                else if twos.count >= 2 { pick(indices: twos); break theLoop }
                else if !ones.isEmpty { pick(indices: [ones[0]]); break theLoop }
                else if !twos.isEmpty { pick(indices: [twos[0]]); break theLoop }
                else { pickSingleLowest(); break theLoop }
            }
        }
    }

    func fallbackPick() {
        guard !isFinished, state.phase == .normal, !state.lastFaces.isEmpty else { return }
        smartPick()
    }

    // MARK: - Pot / Economy

    private func assemblePotFromPlayerWagers() {
        var pot = 0
        for i in state.players.indices {
            let wager = state.players[i].wagerCents
            let oldBankroll = state.players[i].bankrollCents
            state.players[i].bankrollCents -= wager

            // Centralized ledger (EventBus + legacy) AND concrete matchId to silence deprecation
            EconomyStore.shared.recordBuyIn(fromPlayer: displayName(i),
                                            amountCents: wager,
                                            matchId: matchUUID,
                                            matchIdString: matchId)

            if oldBankroll >= 0 && state.players[i].bankrollCents < 0 {
                let borrowedAmount = abs(state.players[i].bankrollCents)
                let penalty = Int(Double(borrowedAmount) * 0.20)
                EconomyStore.shared.recordBorrowPenalty(playerName: displayName(i),
                                                        cents: penalty,
                                                        matchId: matchUUID,
                                                        matchIdString: matchId)
                state.players[i].bankrollCents -= penalty
            }

            pot += wager
        }
        state.potCents = pot
        state.potDebited = true
    }

    // MARK: - Winner / Finalize

    private func computeWinnerIndex() -> Int? {
        let totals = state.players.map { totalPoints(for: $0) }
        guard let minTotal = totals.min() else { return nil }
        let tied = state.players.indices.filter { totals[$0] == minTotal }
        return tied.count == 1 ? tied[0] : nil
    }

    private func startSuddenDeath(with contenders: [Int]) {
        state.phase = .suddenDeath
        state.suddenContenders = contenders
        state.suddenRolls = nil
        state.suddenRound &+= 1

        let ids = contenders.map { playerId($0) }
        bus.emit(.sudden_death_started,
                 matchId: matchId,
                 body: SuddenDeathStartedPayload(
                    reason: "tie_at_top",
                    players: ids
                 ))
    }

    private func finalizeAndNotify() {
        guard state.phase != .finished, let w = state.winnerIdx else { return }
        state.phase = .finished

        state.players[w].bankrollCents += state.potCents

        // Legacy credit with concrete matchId (kills deprecation warning)
        Log.bankCredited(player: displayName(w),
                         amountCents: state.potCents,
                         reason: "match_win",
                         matchId: matchUUID)

        bus.emit(.match_ended,
                 matchId: matchId,
                 body: MatchEndedPayload(
                    winnerPlayerId: playerId(w),
                    potCents: state.potCents,
                    doubleCount: state.doubleCount
                 ))

        let humanWon = !state.players[w].isBot
        NotificationCenter.default.post(name: .humanWonMatch, object: humanWon)
    }
}
