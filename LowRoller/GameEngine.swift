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
    private let economy = EconomyStore.shared

    // MARK: - Init

    /// Main initializer — hydrates bankrolls from the leaderboard.
    init(players: [Player], youStart: Bool, leaders: LeaderboardStore) {
        // Hydrate each player's bankroll from the leaderboard
        var hydrated = players
        for i in hydrated.indices {
            let name = hydrated[i].display.trimmingCharacters(in: .whitespacesAndNewlines)
            if let entry = leaders.entries.first(where: {
                $0.name.caseInsensitiveCompare(name.isEmpty ? "You" : name) == .orderedSame
            }) {
                hydrated[i].bankrollCents = entry.bankrollCents
            }
        }

        // Start game with empty pot — we’ll build it next
        var s = GameState(players: hydrated, potCents: 0)
        s.turnIdx = youStart ? 0 : Int.random(in: 0..<hydrated.count, using: &rng)

        // Create a stable per-match id for analytics
        let matchId = UUID()
        s.analyticsMatchId = matchId

        self.state = s

        // Record base wager per player for Double or Nothing logic
        if hydrated.count == 2 && hydrated[0].wagerCents == hydrated[1].wagerCents {
            self.state.baseWagerCentsPerPlayer = hydrated[0].wagerCents
        } else if let first = hydrated.first {
            self.state.baseWagerCentsPerPlayer = first.wagerCents
        }

        // Debit wagers + penalties (only once per match) — logs each bet
        assemblePotFromPlayerWagers()

        // Now that pot is known, emit match_started
        Log.matchStarted(
            matchId: matchId,
            players: state.players,
            potCents: state.potCents,
            youStart: youStart
        )
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

    /// Should we offer Double-or-Nothing *now*?
    /// Rule: only 1v1, exactly one human, and that human **lost** this round.
    private func shouldOfferDoubleNow() -> Bool {
        guard state.players.count == 2, let w = state.winnerIdx else { return false }
        let p0Human = !state.players[0].isBot
        let p1Human = !state.players[1].isBot
        // must be human vs bot
        guard p0Human != p1Human else { return false }
        let humanIdx = p0Human ? 0 : 1
        let loserIdx = (w == 0) ? 1 : 0
        return loserIdx == humanIdx
    }

    // MARK: - Economy / Pot assembly

    /// Assemble the pot from wagers, apply penalties if needed.
    /// Emits one `bet_placed` per player the first (and only) time this runs.
    private func assemblePotFromPlayerWagers() {
        guard !state.potDebited else { return }  // prevent double-debit
        var totalPot = 0

        for idx in state.players.indices {
            let base = state.players[idx].wagerCents
            guard base >= 0 else { continue }

            // Log the bet before mutating balances
            if let mid = state.analyticsMatchId {
                Log.betPlaced(matchId: mid, playerIdx: idx, wagerCents: base)
            }

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

    /// Finalize, log, pay, and notify — call only when the match *really* ends.
    private func finalizeAndNotify() {
        state.phase = .finished
        payWinnerIfNeeded()

        if let mid = state.analyticsMatchId, let wIdx = state.winnerIdx {
            let balances = state.players.map(\.bankrollCents)
            Log.matchEnded(matchId: mid,
                           winnerIdx: wIdx,
                           potCents: state.potCents,
                           balancesCents: balances)
            let humanWon = !state.players[wIdx].isBot
            NotificationCenter.default.post(name: .humanWonMatch, object: humanWon)
        }
    }

    // MARK: - Core Actions (normal play)

    func roll() {
        guard !isFinished else { return }
        guard state.remainingDice > 0 else { return }
        guard state.lastFaces.isEmpty else { return } // must pick first

        let faces = (0..<state.remainingDice).map { _ in Int.random(in: 1...6, using: &rng) }
        state.lastFaces = faces

        // Log the actual dice outcome for this roll
        if let mid = state.analyticsMatchId {
            Log.roll(matchId: mid, rollerIdx: state.turnIdx, faces: faces)
        }
    }

    func pick(indices: [Int]) {
        guard !isFinished else { return }
        guard !state.lastFaces.isEmpty else { return }
        let uniq = Array(Set(indices)).sorted()
        guard !uniq.isEmpty, uniq.allSatisfy({ $0 >= 0 && $0 < state.lastFaces.count }) else { return }

        // Log the player's pick decision with the faces they selected
        if let mid = state.analyticsMatchId {
            let pickedFaces = uniq.map { state.lastFaces[$0] }
            Log.decisionMade(matchId: mid,
                             playerIdx: state.turnIdx,
                             decision: "pick",
                             picked: pickedFaces)
        }

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
            // Match ends after each player has taken a turn.
            if let wIdx = computeWinnerIndex() {
                state.winnerIdx = wIdx
                // Offer Double-or-Nothing only if human lost vs bot in 1v1; else finalize.
                if shouldOfferDoubleNow() {
                    state.phase = .awaitDouble
                } else {
                    finalizeAndNotify()
                }
            } else {
                // Tie on totals => multi-way Sudden Death (LOWEST score wins; ties re-roll among tied lowest)
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

    // MARK: - Sudden Death (lowest score wins; ties among lowest re-roll)

    /// Enter sudden-death with the specified contenders (player indices).
    private func startSuddenDeath(with contenders: [Int]) {
        guard contenders.count >= 2 else { return }
        state.phase = .suddenDeath
        state.suddenRound &+= 1
        // Preserve stable order for UI
        state.suddenContenders = contenders.sorted()
        state.suddenRolls = nil

        // Keep legacy field around if UI reads it (clear it to avoid 2p visuals)
        state.suddenFaces = SuddenFaces(p0: nil, p1: nil)
    }

    /// Perform one sudden-death step: all current contenders roll once.
    /// - LOWEST adjusted score (3→0) **wins immediately**.
    /// - If multiple share the lowest, only they continue to a runoff.
    /// - Returns winner index *iff* match finishes this step.
    @discardableResult
    func rollSuddenDeath() -> Int? {
        guard state.phase == .suddenDeath,
              let contenders = state.suddenContenders,
              contenders.count >= 2
        else { return nil }

        // Everyone currently in contention rolls once
        var rolls: [Int: Int] = [:]  // playerIdx -> face (1...6)
        for idx in contenders {
            let face = Int.random(in: 1...6, using: &rng)
            rolls[idx] = face

            // Log each roll as its own event for analytics
            if let mid = state.analyticsMatchId {
                Log.roll(matchId: mid, rollerIdx: idx, faces: [face])
            }
        }

        state.suddenRolls = rolls

        // Determine the LOWEST adjusted score (3 -> 0). LOWEST WINS.
        let minScore = rolls.values.map(score).min()!
        let lowestPlayers = rolls.filter { score($0.value) == minScore }.map { $0.key }

        if lowestPlayers.count == 1 {
            // Single lowest -> WINNER
            let winner = lowestPlayers[0]
            state.winnerIdx = winner

            // Decide: offer Double-or-Nothing or finalize immediately
            if shouldOfferDoubleNow() {
                state.phase = .awaitDouble
            } else {
                finalizeAndNotify()
            }

            // Clear SD working sets
            state.suddenContenders = nil
            // (Optionally keep last `suddenRolls` for postmortem UI)
            state.suddenFaces = SuddenFaces(p0: nil, p1: nil)
            return winner
        } else {
            // Tie at lowest -> runoff only among those tied
            state.suddenContenders = lowestPlayers.sorted()
            return nil
        }
    }

    // Backwards compat: if older UI still calls this, forward to group SD.
    // Returns winner index if the step ended the match, else nil.
    @discardableResult
    func resolveSuddenDeathRoll() -> Int? {
        return rollSuddenDeath()
    }

    // MARK: - Double-or-Nothing (in-place chaining)

    /// Whether the UI should present the Double-or-Nothing choice *now*.
    func canOfferDoubleOrNothing() -> Bool {
        // Only when we’re explicitly awaiting and the policy says yes.
        guard state.phase == .awaitDouble else { return false }
        return shouldOfferDoubleNow()
    }

    /// Player declines Double-or-Nothing → finalize and pay out.
    func declineDoubleOrNothing() {
        guard state.phase == .awaitDouble else { return }

        if let mid = state.analyticsMatchId, let w = state.winnerIdx {
            Log.decisionMade(matchId: mid,
                             playerIdx: w,
                             decision: "double_declined",
                             picked: [])
        }

        finalizeAndNotify()
    }

    /// Player accepts Double-or-Nothing → double the pot and reset the round (not bankrolls).
    func acceptDoubleOrNothing() {
        guard state.phase == .awaitDouble else { return }

        if let mid = state.analyticsMatchId, let w = state.winnerIdx {
            Log.decisionMade(matchId: mid,
                             playerIdx: w,
                             decision: "double_accepted",
                             picked: [])
        }

        // 1) Escalate the stake without re-debiting bankrolls
        state.potCents &*= 2
        state.doubleCount &+= 1

        // 2) Choose who starts next. Use the *loser* of last round to start.
        let nextStarter: Int = {
            if let w = state.winnerIdx, state.players.count >= 2 { return (w == 0) ? 1 : 0 }
            return (state.turnIdx + 1) % state.players.count
        }()

        // 3) Reset just the round state; keep wagers/bankrolls/pot as-is
        state.turnsTaken = 0
        state.lastFaces = []
        state.remainingDice = 7
        state.suddenRound = 0
        state.suddenFaces = SuddenFaces(p0: nil, p1: nil)
        state.suddenContenders = nil
        state.suddenRolls = nil
        state.turnIdx = nextStarter
        state.winnerIdx = nil
        for i in state.players.indices {
            state.players[i].picks.removeAll(keepingCapacity: true)
        }

        // 4) Resume normal play
        state.phase = .normal
    }

    // MARK: - Fallback/bot move (used by BotController & timeout)

    // Fallback/bot move: pick all 3s, else single lowest
    func fallbackPick() {
        // Don't act if the match is over, we're in Sudden Death, or awaiting Double-or-Nothing
        guard !isFinished,
              state.phase != .suddenDeath,
              state.phase != .awaitDouble,
              !state.lastFaces.isEmpty
        else { return }

        let faces = state.lastFaces

        // Prefer setting aside all 3s (they score 0)
        let threes = faces.enumerated().filter { $0.element == 3 }.map(\.offset)
        if !threes.isEmpty {
            if let mid = state.analyticsMatchId {
                let pickedFaces = threes.map { faces[$0] }
                Log.decisionMade(matchId: mid,
                                 playerIdx: state.turnIdx,
                                 decision: "fallback_pick",
                                 picked: pickedFaces)
            }
            pick(indices: threes)
            return
        }

        // Otherwise set aside the single lowest-scoring die
        if let lowest = faces.enumerated().min(by: { score($0.element) < score($1.element) })?.offset {
            if let mid = state.analyticsMatchId {
                Log.decisionMade(matchId: mid,
                                 playerIdx: state.turnIdx,
                                 decision: "fallback_pick",
                                 picked: [faces[lowest]])
            }
            pick(indices: [lowest])
        }
    }

    // MARK: - Legacy helpers kept for compatibility

    /// Adopt another engine’s state and clear transient round state so the new match is clean.
    func adoptAndReset(from other: GameEngine) {
        self.state = other.state
        resetForNewMatch()
    }

    /// Clear per-round/transient fields; do NOT touch bankrolls or wagers.
    func resetForNewMatch() {
        state.remainingDice = 7
        state.lastFaces = []
        state.phase = .normal
        state.turnsTaken = 0
        state.winnerIdx = nil
        state.suddenRound = 0
        state.suddenFaces = SuddenFaces()
        state.suddenContenders = nil
        state.suddenRolls = nil
        for i in state.players.indices {
            state.players[i].picks.removeAll()
        }
        // Note: keep potDebited and potCents as-is unless starting a new match.
    }
}
