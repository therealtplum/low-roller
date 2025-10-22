//
//  GameEngine.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/22/25.
//


// Model/GameEngine.swift
import Foundation
import Combine    // ← add

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
    private var curIdx: Int { state.turnIdx }
    private var isFinished: Bool { state.phase == .finished }

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
            state.phase = .finished
        } else {
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
