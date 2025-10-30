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

final class GameEngine: ObservableObject {
    @Published private(set) var state: GameState
    private var rng = SystemRandomNumberGenerator()

    // MARK: - Init

    /// Main initializer — hydrates bankrolls from the leaderboard entries (if provided).
    init(players: [Player], youStart: Bool, leaders: LeaderboardStore) {
        var hydrated = players
        // Hydrate each player's bankroll from the leaderboard, if present
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

        // If it’s a 1v1 and wagers match, remember the base wager for double-or-nothing
        if hydrated.count == 2 && hydrated[0].wagerCents == hydrated[1].wagerCents {
            self.state.baseWagerCentsPerPlayer = hydrated[0].wagerCents
        } else if let first = hydrated.first {
            self.state.baseWagerCentsPerPlayer = first.wagerCents
        }

        // Debit wagers once and build the initial pot
        assemblePotFromPlayerWagers()
    }

    /// Convenience overload retained for older call sites
    convenience init(players: [Player], youStart: Bool) {
        let tmpLeaders = LeaderboardStore()
        self.init(players: players, youStart: youStart, leaders: tmpLeaders)
    }

    // MARK: - Helpers

    private func score(_ face: Int) -> Int { face == 3 ? 0 : face }

    private func totalPoints(for p: Player) -> Int {
        p.picks.reduce(0, +)
    }

    private var isFinished: Bool { state.phase == .finished }

    private func targetScoreToBeat() -> Int? {
        guard state.turnsTaken > 0 else { return nil }
        let completedTotals = state.players.prefix(state.turnsTaken).map(totalPoints(for:))
        return completedTotals.min()
    }

    private func expectedScoreFromDice(count: Int) -> Double {
        // EV per die for {1,2,0,4,5,6} is 3.0
        guard count > 0 else { return 0 }
        return Double(count) * 3.0
    }

    // MARK: - Public actions

    func roll() {
        guard !isFinished else { return }
        guard state.remainingDice > 0 else { return }
        guard state.lastFaces.isEmpty else { return } // must pick before rolling again

        let faces = (0..<state.remainingDice).map { _ in Int.random(in: 1...6, using: &rng) }
        state.lastFaces = faces
    }

    func pick(indices: [Int]) {
        guard !isFinished else { return }
        guard !state.lastFaces.isEmpty else { return }

        let uniq = Array(Set(indices)).sorted()
        guard !uniq.isEmpty, uniq.allSatisfy({ $0 >= 0 && $0 < state.lastFaces.count }) else { return }

        let scored = uniq.map { score(state.lastFaces[$0]) }
        state.players[state.turnIdx].picks.append(contentsOf: scored)
        state.remainingDice -= uniq.count
        state.lastFaces = []

        _ = endTurnIfDone()
    }

    @discardableResult
    func endTurnIfDone() -> Bool {
        guard state.remainingDice == 0 else { return false }

        state.turnsTaken &+= 1

        if state.turnsTaken >= state.players.count {
            // Everyone played: decide winner or go to sudden death
            if let wIdx = computeWinnerIndex() {
                state.winnerIdx = wIdx
                if shouldOfferDoubleNow() {
                    state.phase = .awaitDouble
                } else {
                    finalizeAndNotify()
                }
            } else {
                // Tie among lowest totals → sudden death among tied players
                let totals = state.players.map { totalPoints(for: $0) }
                let minTotal = totals.min()!
                let tied = state.players.indices.filter { totals[$0] == minTotal }
                startSuddenDeath(with: tied)
            }
        } else {
            // Next player's turn
            state.turnIdx = (state.turnIdx + 1) % state.players.count
            state.remainingDice = 7
            state.lastFaces = []
        }
        return true
    }

    // MARK: - Sudden Death

    /// Rolls once for all current sudden-death contenders; returns winner index if decided.
    func rollSuddenDeath() -> Int? {
        guard state.phase == .suddenDeath, var contenders = state.suddenContenders else { return nil }

        var rolls: [Int: Int] = [:]
        for idx in contenders {
            rolls[idx] = Int.random(in: 1...6, using: &rng)
        }
        state.suddenRolls = rolls

        // Lowest adjusted value wins (3→0)
        let minAdj = rolls.values.map(score).min()
        let lowest = rolls.filter { score($0.value) == minAdj }.map(\.key)

        if lowest.count == 1 {
            state.winnerIdx = lowest[0]
            finalizeAndNotify()
            return state.winnerIdx
        } else {
            // Tie persists → continue sudden death only among re-tied players
            contenders = lowest
            state.suddenContenders = contenders
            return nil
        }
    }

    // MARK: - Double or Nothing

    /// Only 1v1, human vs bot, and the human lost — and only once per match.
    private func shouldOfferDoubleNow() -> Bool {
        guard state.doubleCount == 0 else { return false }
        guard state.players.count == 2, let w = state.winnerIdx else { return false }

        let p0Human = !state.players[0].isBot
        let p1Human = !state.players[1].isBot
        guard p0Human != p1Human else { return false } // must be human vs bot

        let humanIdx = p0Human ? 0 : 1
        let loserIdx = (w == 0) ? 1 : 0
        return loserIdx == humanIdx
    }

    func acceptDoubleOrNothing() {
        guard state.phase == .awaitDouble,
              let winner = state.winnerIdx,
              state.players.count == 2 else { return }

        state.doubleCount += 1

        // Both players match the original base wager again
        let wager = state.baseWagerCentsPerPlayer
        for i in state.players.indices { state.players[i].bankrollCents -= wager }
        state.potCents += 2 * wager

        // Reset the round
        resetForNewRound()

        // Let the next turn start (you can keep "winner+1" or pick loser to start — this keeps winner+1)
        state.turnIdx = (winner + 1) % state.players.count
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
        // Note: pot remains as-is unless a new match is constructed externally.
    }

    // MARK: - Timeout behavior (called by GameView when the UI timer hits 0)

    /// If it's a HUMAN's turn in normal play:
    /// 1) roll if needed, 2) pick using smart bot logic, 3) if turn not done, roll again.
    func handleTurnTimeout() {
        guard !isFinished,
              state.phase == .normal,
              state.turnIdx < state.players.count,
              !state.players[state.turnIdx].isBot
        else { return }

        if state.lastFaces.isEmpty { roll() }
        if !state.lastFaces.isEmpty { smartPick() }

        // If still mid-turn, roll again to keep flow (UI restarts its own countdown)
        if !isFinished,
           state.phase == .normal,
           state.turnIdx < state.players.count,
           state.remainingDice > 0,
           state.lastFaces.isEmpty {
            roll()
        }
    }

    /// Back-compat alias (some sites might still call this)
    func onTimeout() { handleTurnTimeout() }

    // MARK: - Bot-like picking (also used by timeout)

    func smartPick() {
        guard !state.lastFaces.isEmpty else { return }

        let faces = state.lastFaces
        let currentScore = totalPoints(for: state.players[state.turnIdx])
        let target = targetScoreToBeat()

        // Indices by face
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
            let _ = expectedScoreFromDice(count: state.remainingDice - faces.count)

            if scoreNeeded < 0 {
                // Already beating target → play safe
                if !threes.isEmpty { pick(indices: threes) }
                else if !ones.isEmpty { pick(indices: [ones[0]]) }
                else if !twos.isEmpty { pick(indices: [twos[0]]) }
                else if !fours.isEmpty { pick(indices: [fours[0]]) }
                else if !fives.isEmpty { pick(indices: [fives[0]]) }
                else if !sixes.isEmpty { pick(indices: [sixes[0]]) }
                else { pickSingleLowest() }
            } else {
                // Balanced-to-aggressive: secure best lows, otherwise keep options
                if !threes.isEmpty { pick(indices: threes) }
                else if ones.count >= 2 { pick(indices: ones) }
                else if twos.count >= 2 { pick(indices: twos) }
                else { pickSingleLowest() }
            }
        } else {
            // First player: generally take best lows, else a single low
            if !threes.isEmpty { pick(indices: threes) }
            else if ones.count >= 2 { pick(indices: ones) }
            else if twos.count >= 2 { pick(indices: twos) }
            else if !ones.isEmpty { pick(indices: [ones[0]]) }
            else if !twos.isEmpty { pick(indices: [twos[0]]) }
            else { pickSingleLowest() }
        }
    }

    /// Kept for BotController compatibility — uses smartPick.
    func fallbackPick() {
        guard !isFinished,
              state.phase == .normal,
              !state.lastFaces.isEmpty else { return }
        smartPick()
    }

    // MARK: - Pot / Economy

    private func assemblePotFromPlayerWagers() {
        var pot = 0
        for i in state.players.indices {
            let wager = state.players[i].wagerCents
            state.players[i].bankrollCents -= wager
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
    }

    private func finalizeAndNotify() {
        guard let w = state.winnerIdx else { return }

        // Winner takes the pot
        state.players[w].bankrollCents += state.potCents
        state.phase = .finished

        // Let the UI know if a human won (confetti)
        let humanWon = !state.players[w].isBot
        NotificationCenter.default.post(name: .humanWonMatch, object: humanWon)
    }
}
