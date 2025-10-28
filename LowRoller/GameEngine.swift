//
//  GameEngine.swift
//  LowRoller
//  FINAL VERSION - Fixed unused variable warnings
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

        // Start game with empty pot — we'll build it next
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
    /// NEW: Also check that we haven't already done a double-or-nothing this match.
    private func shouldOfferDoubleNow() -> Bool {
        // NEW: Only allow one double-or-nothing per match
        guard state.doubleCount == 0 else { return false }
        
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
                // Use proper rounding instead of truncation
                let penalty = Int((Double(base) * 0.20).rounded())
                
                // Check for integer overflow before applying
                let totalDebit = base + penalty
                if state.players[idx].bankrollCents < Int.min + totalDebit {
                    // Would overflow - cap at Int.min
                    state.players[idx].bankrollCents = Int.min
                } else {
                    state.players[idx].bankrollCents -= totalDebit
                }
                
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
        
        // Check for integer overflow before crediting
        if state.players[wIdx].bankrollCents > Int.max - pot {
            state.players[wIdx].bankrollCents = Int.max
        } else {
            state.players[wIdx].bankrollCents += pot
        }
        
        state.potCents = 0 // prevent double payout
    }

    /// Finalize, log, pay, and notify — call only when the match *really* ends.
    private func finalizeAndNotify() {
        // Set phase first to prevent race conditions
        state.phase = .finished
        
        // Pay winner before notifications
        payWinnerIfNeeded()

        if let mid = state.analyticsMatchId, let wIdx = state.winnerIdx {
            let balances = state.players.map(\.bankrollCents)
            Log.matchEnded(matchId: mid,
                           winnerIdx: wIdx,
                           potCents: 0,  // Already paid out, so 0
                           balancesCents: balances)
            
            // Ensure UI has time to update before notification
            let humanWon = !state.players[wIdx].isBot
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .humanWonMatch, object: humanWon)
            }
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
        // Handle edge cases properly
        guard contenders.count >= 2 else {
            // If somehow we get here with 0 or 1 contender, declare them the winner
            if contenders.count == 1 {
                state.winnerIdx = contenders[0]
                finalizeAndNotify()
            }
            return
        }
        
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

            // Clear ALL SD working sets properly
            state.suddenContenders = nil
            state.suddenRolls = nil
            state.suddenFaces = SuddenFaces(p0: nil, p1: nil)
            return winner
        } else {
            // Tie at lowest -> runoff only among those tied
            // This naturally handles any number of players (2, 3, or more)
            state.suddenContenders = lowestPlayers.sorted()
            state.suddenRound &+= 1  // Increment round for next sudden death
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
        // Only when we're explicitly awaiting and the policy says yes.
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

        // Safe pot doubling with overflow check
        let (newPot, overflow) = state.potCents.multipliedReportingOverflow(by: 2)
        if overflow {
            // Cap at maximum if would overflow
            state.potCents = Int.max
        } else {
            state.potCents = newPot
        }
        
        state.doubleCount &+= 1

        // Better logic for determining next starter that works for any player count
        let nextStarter: Int = {
            // In 2-player games, the loser starts
            if state.players.count == 2, let w = state.winnerIdx {
                return (w == 0) ? 1 : 0
            }
            // For multi-player games, rotate from current turn
            return (state.turnIdx + 1) % state.players.count
        }()

        // Reset just the round state; keep wagers/bankrolls/pot as-is
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

        // Resume normal play
        state.phase = .normal
    }

    // MARK: - Smarter Bot Strategy

    /// Calculate the minimum score to beat among players who have finished
    private func getTargetScoreToBeat() -> Int? {
        // Only consider players who have finished their turns
        let finishedPlayers = state.players.enumerated().filter { idx, _ in
            idx < state.turnsTaken
        }
        
        guard !finishedPlayers.isEmpty else { return nil }
        
        let scores = finishedPlayers.map { _, player in totalPoints(for: player) }
        return scores.min()
    }

    /// Estimate expected score from remaining dice
    private func expectedScoreFromDice(count: Int) -> Double {
        // Average die value: (1+2+0+4+5+6)/6 = 3.0 (remember 3 scores as 0)
        return Double(count) * 3.0
    }

    /// Smart pick strategy considering game state
    private func smartPick() {
        guard !state.lastFaces.isEmpty else { return }
        
        let faces = state.lastFaces
        let currentScore = totalPoints(for: state.players[state.turnIdx])
        let targetScore = getTargetScoreToBeat()
        
        // Group dice by value
        let threes = faces.enumerated().filter { $0.element == 3 }.map(\.offset)
        let ones = faces.enumerated().filter { $0.element == 1 }.map(\.offset)
        let twos = faces.enumerated().filter { $0.element == 2 }.map(\.offset)
        let fours = faces.enumerated().filter { $0.element == 4 }.map(\.offset)
        let fives = faces.enumerated().filter { $0.element == 5 }.map(\.offset)
        let sixes = faces.enumerated().filter { $0.element == 6 }.map(\.offset)
        
        // Helper to find single lowest die when no good options exist
        let pickSingleLowest = {
            if let lowest = faces.enumerated().min(by: { self.score($0.element) < self.score($1.element) })?.offset {
                self.pick(indices: [lowest])
            }
        }
        
        // Strategy depends on whether we need to beat someone
        if let target = targetScore {
            // We know what score we need to beat
            let scoreNeeded = target - currentScore - 1  // -1 because we need to be lower
            let expectedFromRemaining = expectedScoreFromDice(count: state.remainingDice - faces.count)
            
            if scoreNeeded < 0 {
                // We're already winning, play conservatively
                // Pick all 3s (best), then pick lowest singles
                if !threes.isEmpty {
                    pick(indices: threes)
                } else if !ones.isEmpty {
                    pick(indices: [ones[0]])
                } else if !twos.isEmpty {
                    pick(indices: [twos[0]])
                } else if !fours.isEmpty {
                    pick(indices: [fours[0]])
                } else if !fives.isEmpty {
                    pick(indices: [fives[0]])
                } else if !sixes.isEmpty {
                    pick(indices: [sixes[0]])
                } else {
                    // Fallback - should never reach here but just in case
                    pickSingleLowest()
                }
            } else if Double(scoreNeeded) > expectedFromRemaining {
                // We need to be aggressive - keep more dice for more rolls
                // Only pick 3s or single very low values
                if !threes.isEmpty {
                    pick(indices: threes)
                } else if !ones.isEmpty && ones.count > 2 {
                    // Only pick ones if we have many
                    pick(indices: ones)
                } else {
                    // Pick just one die to keep more chances
                    pickSingleLowest()
                }
            } else {
                // We're on track - balanced approach
                if !threes.isEmpty {
                    pick(indices: threes)
                } else if !ones.isEmpty && ones.count >= 2 {
                    pick(indices: ones)
                } else if !twos.isEmpty && twos.count >= 2 {
                    pick(indices: twos)
                } else {
                    // Pick single lowest (handles 4, 5, 6 cases)
                    pickSingleLowest()
                }
            }
        } else {
            // We're going first or everyone else is still playing
            // Play a balanced strategy - not too aggressive, not too conservative
            
            // Always pick all 3s (they're worth 0)
            if !threes.isEmpty {
                pick(indices: threes)
            } else if ones.count >= 2 {
                // Pick multiple 1s if available
                pick(indices: ones)
            } else if twos.count >= 2 {
                // Pick multiple 2s if available
                pick(indices: twos)
            } else if !ones.isEmpty {
                // Pick single 1
                pick(indices: [ones[0]])
            } else if !twos.isEmpty {
                // Pick single 2
                pick(indices: [twos[0]])
            } else {
                // No low options - pick single lowest (handles 4, 5, 6)
                pickSingleLowest()
            }
        }
    }

    // MARK: - Fallback/bot move (used by BotController & timeout)

    // Updated bot move with smarter strategy
    func fallbackPick() {
        // Don't act if the match is over, we're in Sudden Death, or awaiting Double-or-Nothing
        guard !isFinished,
              state.phase != .suddenDeath,
              state.phase != .awaitDouble,
              !state.lastFaces.isEmpty
        else { return }

        // Use smart picking strategy instead of simple fallback
        smartPick()
    }

    // MARK: - Legacy helpers kept for compatibility

    /// Adopt another engine's state and clear transient round state so the new match is clean.
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
