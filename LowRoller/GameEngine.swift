//
//  GameEngine.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/22/25.
//

// Model/GameEngine.swift
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

    init(players: [Player], youStart: Bool) {
        let pot = players.map(\.wagerCents).reduce(0, +)
        var s = GameState(players: players, potCents: pot)
        s.turnIdx = youStart ? 0 : Int.random(in: 0..<players.count, using: &rng)
        self.state = s
    }

    // MARK: - Helpers
    private func score(_ face: Int) -> Int { face == 3 ? 0 : face }
    private var isFinished: Bool { state.phase == .finished }

    /// Total points for a player (lower is better in Low Roller).
    private func totalPoints(for p: Player) -> Int {
        p.picks.reduce(0, +)
    }

    /// Winner is the player with the *lowest* total points.
    /// Tie-breaker: earliest player in order (adjust if you have different rules).
    private func computeWinnerIndex() -> Int? {
        guard !state.players.isEmpty else { return nil }
        return state.players.enumerated()
            .min(by: { totalPoints(for: $0.element) < totalPoints(for: $1.element) })?
            .offset
    }

    // MARK: - Actions
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
            state.phase = .finished

            // Compute winner *now* and broadcast whether a human won.
            if let wIdx = computeWinnerIndex() {
                let humanWon = !state.players[wIdx].isBot
                NotificationCenter.default.post(name: .humanWonMatch, object: humanWon)
            } else {
                // Edge case: no winner (shouldn't happen), broadcast false.
                NotificationCenter.default.post(name: .humanWonMatch, object: false)
            }

        } else {
            // Next player's turn
            state.turnIdx = (state.turnIdx + 1) % state.players.count
            state.remainingDice = 7
            state.lastFaces = []
        }
        return true
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
