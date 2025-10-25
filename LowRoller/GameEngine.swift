//
//  GameEngine.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/22/25.
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
    private let economy = EconomyStore.shared

    // MARK: - Init

    /// Main initializer — hydrates bankrolls from the leaderboard.
    init(players: [Player], youStart: Bool, leaders: LeaderboardStore) {
        // Hydrate each player's bankroll from the leaderboard
        var hydrated = players
        for i in hydrated.indices {
            let name = hydrated[i].display.trimmingCharacters(in: .whitespacesAndNewlines)
            if let entry = leaders.entries.first(where: { $0.name.caseInsensitiveCompare(name.isEmpty ? "You" : name) == .orderedSame }) {
                hydrated[i].bankrollCents = entry.bankrollCents
            }
        }

        // Start game with empty pot — we’ll build it next
        var s = GameState(players: hydrated, potCents: 0)
        s.turnIdx = youStart ? 0 : Int.random(in: 0..<hydrated.count, using: &rng)
        self.state = s

        // Debit wagers + penalties (only once per match)
        assemblePotFromPlayerWagers()
    }

    /// Convenience overload for existing call sites (fallback: loads leaderboard fresh)
    convenience init(players: [Player], youStart: Bool) {
        let tmpLeaders = LeaderboardStore()
        self.init(players: players, youStart: youStart, leaders: tmpLeaders)
    }

    // MARK: - Helpers
    private func score(_ face: Int) -> Int { face == 3 ? 0 : face }
    private var isFinished: Bool { state.phase == .finished }

    /// Total points for a player (lower is better in Low Roller).
    private func totalPoints(for p: Player) -> Int { p.picks.reduce(0, +) }

    /// Winner is the player with the *lowest* total points.
    private func computeWinnerIndex() -> Int? {
        guard !state.players.isEmpty else { return nil }
        let totals = state.players.map { totalPoints(for: $0) }
        guard let minTotal = totals.min() else { return nil }
        let leaders = totals.enumerated().filter { $0.element == minTotal }
        return leaders.count == 1 ? leaders[0].offset : nil  // nil => tie
    }

    // MARK: - Economy / Pot assembly

    /// Assemble the pot from wagers, apply penalties if needed.
    private func assemblePotFromPlayerWagers() {
        guard !state.potDebited else { return }  // prevent double-debit
        var totalPot = 0

        for idx in state.players.indices {
            let base = state.players[idx].wagerCents
            guard base >= 0 else { continue }

            if state.players[idx].bankrollCents < 0 {
                // Borrow penalty if player is already negative
                let penalty = Int(Double(base) * 0.20)
                state.players[idx].bankrollCents -= (base + penalty)
                economy.recordBorrowPenalty(penalty)
            } else {
                state.players[idx].bankrollCents -= base
            }

            totalPot += base
        }

        state.potCents = totalPot
        state.potDebited = true
    }

    /// Pay pot to the winner exactly once; zero out pot to prevent double-pay.
    private func payWinnerIfNeeded() {
        assemblePotFromPlayerWagers()  // safety: ensure wagers were debited

        guard state.phase == .finished,
              let wIdx = state.winnerIdx,
              state.potCents > 0,
              wIdx >= 0 && wIdx < state.players.count
        else { return }

        let pot = state.potCents
        state.players[wIdx].bankrollCents += pot
        state.potCents = 0 // prevent double payout
    }

    // MARK: - Actions
    private func startSuddenDeath() {
        state.phase = .suddenDeath
        state.suddenRound &+= 1
        state.suddenFaces = SuddenFaces(p0: nil, p1: nil)
    }
    
    func roll() {
        guard !isFinished else { return }
        guard state.remainingDice > 0 else { return }
        guard state.lastFaces.isEmpty else { return } // must pick first
        state.lastFaces = (0..<state.remainingDice).map { _ in Int.random(in: 1...6, using: &rng) }
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
        state.turnsTaken += 1

        if state.turnsTaken >= state.players.count {
            // Match ends after each player has taken a turn.
            if let wIdx = computeWinnerIndex() {
                state.winnerIdx = wIdx
                state.phase = .finished

                // Payout + notify
                payWinnerIfNeeded()
                let humanWon = !state.players[wIdx].isBot
                NotificationCenter.default.post(name: .humanWonMatch, object: humanWon)
            } else {
                // Tie on totals => Sudden Death
                startSuddenDeath()
            }
        } else {
            // Next player's turn
            state.turnIdx = (state.turnIdx + 1) % state.players.count
            state.remainingDice = 7
            state.lastFaces = []
        }
        return true
    }

    @discardableResult
    func resolveSuddenDeathRoll() -> Int? {
        guard state.players.count >= 2 else { return nil }
        let p0Face = Int.random(in: 1...6, using: &rng)
        let p1Face = Int.random(in: 1...6, using: &rng)
        state.suddenFaces = SuddenFaces(p0: p0Face, p1: p1Face)

        let p0 = score(p0Face) // 3 -> 0
        let p1 = score(p1Face)

        if p0 == p1 {
            // tie again; remain in .suddenDeath and let UI roll again
            return nil
        }

        let winner = (p0 < p1) ? 0 : 1  // LOW score wins
        state.winnerIdx = winner
        state.phase = .finished

        payWinnerIfNeeded()
        let humanWon = !state.players[winner].isBot
        NotificationCenter.default.post(name: .humanWonMatch, object: humanWon)
        return winner
    }
    
    // Fallback/bot move: pick all 3s, else single lowest
    func fallbackPick() {
        guard !isFinished else { return }
        guard !state.lastFaces.isEmpty else { return }
        let faces = state.lastFaces
        let threes = faces.enumerated().filter { $0.element == 3 }.map(\.offset)
        if !threes.isEmpty { pick(indices: threes); return }
        let lowest = faces.enumerated().min(by: { score($0.element) < score($1.element) })!.offset
        pick(indices: [lowest])
    }
}
