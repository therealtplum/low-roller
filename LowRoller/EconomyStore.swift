//
//  EconomyStore.swift
//  LowRoller
//
//  Persists the House balance across launches using UserDefaults,
//  logs an auditable ledger of credits/debits for the House, and
//  exposes helpers you can call when player banks change.
//
//  NOTES:
//  - Logging for borrow penalties, buy-ins, and match payouts is centralized HERE.
//    Do not also log those in GameEngine or UI layers.
//  - A lightweight dedupe prevents identical events (same type, player, reason,
//    amount, matchId) from being emitted twice within a short window.
//

import Foundation
import Combine

final class EconomyStore: ObservableObject {
    // MARK: - Singleton
    static let shared = EconomyStore()

    // MARK: - Persistence Keys
    private let houseKey  = "economy.house.cents.v1"
    private let seededKey = "economy.seeded.v1"

    // MARK: - Published state
    @Published private(set) var houseCents: Int = 0

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    private init() {
        seedIfNeeded()
        houseCents = defaults.integer(forKey: houseKey)

        // Persist on change
        $houseCents
            .sink { [weak self] newVal in
                guard let self else { return }
                self.defaults.set(newVal, forKey: self.houseKey)
            }
            .store(in: &cancellables)
    }

    private func seedIfNeeded() {
        if defaults.object(forKey: seededKey) == nil {
            // Start House at 0 by default
            defaults.set(true, forKey: seededKey)
            defaults.set(0, forKey: houseKey)
        }
    }

    // MARK: - Lightweight idempotency for log events

    /// Short window to drop perfect duplicate events (type+player+reason+amount+matchId).
    private let dedupeWindow: TimeInterval = 1.0
    private var recentFingerprints: [String: Date] = [:]
    private let recentLock = NSLock()

    private func makeFingerprint(
        type: String,
        player: String?,
        reason: String,
        amountCents: Int,
        matchId: UUID?
    ) -> String {
        // String that uniquely identifies a logical event
        let pid = player ?? "-"
        let mid = matchId?.uuidString ?? "-"
        return "\(type)|\(pid)|\(reason)|\(amountCents)|\(mid)"
    }

    private func shouldEmit(
        type: String,
        player: String?,
        reason: String,
        amountCents: Int,
        matchId: UUID?
    ) -> Bool {
        let fp = makeFingerprint(type: type, player: player, reason: reason, amountCents: amountCents, matchId: matchId)
        let now = Date()

        recentLock.lock()
        defer { recentLock.unlock() }

        if let firstSeen = recentFingerprints[fp], now.timeIntervalSince(firstSeen) < dedupeWindow {
            // Duplicate within window — drop it
            return false
        }
        recentFingerprints[fp] = now
        return true
    }

    // MARK: - Centralized logging wrappers (use these to emit)

    private func emitHouseCredited(_ cents: Int, reason: String, matchId: UUID?) {
        guard cents > 0 else { return }
        guard shouldEmit(type: "house_credited", player: nil, reason: reason, amountCents: cents, matchId: matchId) else { return }
        Log.houseCredited(amountCents: cents, reason: reason, matchId: matchId)
    }

    private func emitHouseDebited(_ cents: Int, reason: String, matchId: UUID?) {
        guard cents > 0 else { return }
        guard shouldEmit(type: "house_debited", player: nil, reason: reason, amountCents: cents, matchId: matchId) else { return }
        Log.houseDebited(amountCents: cents, reason: reason, matchId: matchId)
    }

    private func emitPlayerDebited(_ player: String, cents: Int, reason: String, matchId: UUID?) {
        guard cents > 0 else { return }
        guard shouldEmit(type: "bank_debited", player: player, reason: reason, amountCents: cents, matchId: matchId) else { return }
        Log.bankDebited(player: player, amountCents: cents, reason: reason, matchId: matchId)
    }

    private func emitPlayerCredited(_ player: String, cents: Int, reason: String, matchId: UUID?) {
        guard cents > 0 else { return }
        guard shouldEmit(type: "bank_credited", player: player, reason: reason, amountCents: cents, matchId: matchId) else { return }
        Log.bankCredited(player: player, amountCents: cents, reason: reason, matchId: matchId)
    }

    // MARK: - House mutations (with centralized logging)

    /// Credit (increase) House balance. Also logs `house_credited`.
    func creditHouse(_ cents: Int, reason: String, matchId: UUID? = nil) {
        guard cents > 0 else { return }
        houseCents &+= cents
        emitHouseCredited(cents, reason: reason, matchId: matchId)
    }

    /// Debit (decrease) House balance. Also logs `house_debited`.
    func debitHouse(_ cents: Int, reason: String, matchId: UUID? = nil) {
        guard cents > 0 else { return }
        houseCents &-= cents
        emitHouseDebited(cents, reason: reason, matchId: matchId)
    }

    // MARK: - High-level economic events (one-stop APIs)

    /// Use this when a player pays a penalty/fee to the House.
    /// Records a House credit and a player debit event for auditability.
    func recordBorrowPenalty(playerName: String?,
                             cents: Int,
                             matchId: UUID? = nil) {
        guard cents > 0 else { return }
        creditHouse(cents, reason: "borrow_penalty", matchId: matchId)
        if let name = playerName {
            emitPlayerDebited(name, cents: cents, reason: "borrow_penalty", matchId: matchId)
        }
    }

    /// Use this when House pays out a pot to the winner.
    func recordMatchPayout(toWinner winnerName: String,
                           amountCents: Int,
                           matchId: UUID) {
        guard amountCents > 0 else { return }
        debitHouse(amountCents, reason: "match_payout", matchId: matchId)
        emitPlayerCredited(winnerName, cents: amountCents, reason: "match_win", matchId: matchId)
    }

    /// Use this when buy-ins go **to the House** (if you model it that way).
    func recordBuyIn(fromPlayer playerName: String,
                     amountCents: Int,
                     matchId: UUID? = nil) {
        guard amountCents > 0 else { return }
        creditHouse(amountCents, reason: "buy_in", matchId: matchId)
        emitPlayerDebited(playerName, cents: amountCents, reason: "buy_in", matchId: matchId)
    }

    /// Resets House to 0 and logs a special event so you can see it in the ledger.
    func resetHouse() {
        let old = houseCents
        houseCents = 0
        Log.write(type: "house_reset", payload: ["previousCents": old])
    }

    // MARK: - UI helper

    func formattedHouseBalance(locale: Locale = .current) -> String {
        let dollars = Double(houseCents) / 100.0
        let nf = NumberFormatter()
        nf.locale = locale
        nf.numberStyle = .currency
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = dollars.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return nf.string(from: NSNumber(value: dollars)) ?? String(format: "$%.2f", dollars)
    }
}
