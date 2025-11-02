//
//  EconomyStore.swift
//  LowRoller
//

import Foundation
import Combine

final class EconomyStore: ObservableObject {
    static let shared = EconomyStore()

    private let houseKey  = "economy.house.cents.v1"
    private let seededKey = "economy.seeded.v1"

    @Published private(set) var houseCents: Int = 0

    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    // EventBus
    private let bus = EventBus.shared

    private init() {
        seedIfNeeded()
        houseCents = defaults.integer(forKey: houseKey)
        $houseCents
            .sink { [weak self] newVal in
                guard let self else { return }
                self.defaults.set(newVal, forKey: self.houseKey)
            }
            .store(in: &cancellables)
    }

    private func seedIfNeeded() {
        if defaults.object(forKey: seededKey) == nil {
            defaults.set(true, forKey: seededKey)
            defaults.set(0, forKey: houseKey)
        }
    }

    // MARK: - Lightweight idempotency for legacy Log.* echo

    private let dedupeWindow: TimeInterval = 1.0
    private var recentFingerprints: [String: Date] = [:]
    private let recentLock = NSLock()

    private func makeFingerprint(type: String, player: String?, reason: String, amountCents: Int, matchId: UUID?) -> String {
        let pid = player ?? "-"
        let mid = matchId?.uuidString ?? "-"
        return "\(type)|\(pid)|\(reason)|\(amountCents)|\(mid)"
    }

    private func shouldEmitLegacy(type: String, player: String?, reason: String, amountCents: Int, matchId: UUID?) -> Bool {
        let fp = makeFingerprint(type: type, player: player, reason: reason, amountCents: amountCents, matchId: matchId)
        let now = Date()
        recentLock.lock(); defer { recentLock.unlock() }
        if let first = recentFingerprints[fp], now.timeIntervalSince(first) < dedupeWindow { return false }
        recentFingerprints[fp] = now
        return true
    }

    // MARK: - EventBus posting

    private func newJournalId() -> String { UUID().uuidString }
    private func newTxnId() -> String { UUID().uuidString }

    private func post(matchIdString: String,
                      journalId: String,
                      account: String,
                      direction: String,
                      amountCents: Int,
                      reason: String,
                      memo: String? = nil) {
        let payload = BankPostedPayload(
            journalId: journalId,
            txnId: newTxnId(),
            account: account,
            direction: direction,
            amountCents: amountCents,
            reason: reason,
            relatedMatchId: matchIdString,
            memo: memo
        )
        bus.emit(.bank_posted, matchId: matchIdString, body: payload)
    }

    // MARK: - House mutations

    func creditHouse(_ cents: Int,
                     reason: String,
                     matchId: UUID? = nil,
                     journalId: String? = nil,
                     matchIdString: String? = nil,
                     houseAccount: String = "house:pot") {
        guard cents > 0 else { return }
        houseCents &+= cents

        // Legacy (only if we have a concrete match UUID to avoid deprecation)
        if let mid = matchId,
           shouldEmitLegacy(type: "house_credited", player: nil, reason: reason, amountCents: cents, matchId: mid) {
            Log.houseCredited(amountCents: cents, reason: reason, matchId: mid)
        }

        // EventBus
        if let m = matchIdString {
            let j = journalId ?? newJournalId()
            post(matchIdString: m, journalId: j, account: houseAccount, direction: "credit", amountCents: cents, reason: reason)
        }
    }

    func debitHouse(_ cents: Int,
                    reason: String,
                    matchId: UUID? = nil,
                    journalId: String? = nil,
                    matchIdString: String? = nil,
                    houseAccount: String = "house:pot") {
        guard cents > 0 else { return }
        houseCents &-= cents

        if let mid = matchId,
           shouldEmitLegacy(type: "house_debited", player: nil, reason: reason, amountCents: cents, matchId: mid) {
            Log.houseDebited(amountCents: cents, reason: reason, matchId: mid)
        }

        if let m = matchIdString {
            let j = journalId ?? newJournalId()
            post(matchIdString: m, journalId: j, account: houseAccount, direction: "debit", amountCents: cents, reason: reason)
        }
    }

    // MARK: - High-level economic events

    func recordBorrowPenalty(playerName: String?,
                             cents: Int,
                             matchId: UUID? = nil,
                             matchIdString: String? = nil) {
        guard cents > 0 else { return }
        let j = newJournalId()

        creditHouse(cents, reason: "borrow_penalty", matchId: matchId, journalId: j, matchIdString: matchIdString, houseAccount: "house:penalties")

        if let name = playerName {
            if let mid = matchId,
               shouldEmitLegacy(type: "bank_debited", player: name, reason: "borrow_penalty", amountCents: cents, matchId: mid) {
                Log.bankDebited(player: name, amountCents: cents, reason: "borrow_penalty", matchId: mid)
            }
            if let m = matchIdString {
                post(matchIdString: m, journalId: j, account: "player:\(name)", direction: "debit", amountCents: cents, reason: "borrow_penalty")
            }
        }
    }

    func recordMatchPayout(toWinner winnerName: String,
                           amountCents: Int,
                           matchId: UUID,
                           matchIdString: String) {
        guard amountCents > 0 else { return }
        let j = newJournalId()

        debitHouse(amountCents, reason: "match_payout", matchId: matchId, journalId: j, matchIdString: matchIdString, houseAccount: "house:pot")

        if shouldEmitLegacy(type: "bank_credited", player: winnerName, reason: "match_win", amountCents: amountCents, matchId: matchId) {
            Log.bankCredited(player: winnerName, amountCents: amountCents, reason: "match_win", matchId: matchId)
        }
        post(matchIdString: matchIdString, journalId: j, account: "player:\(winnerName)", direction: "credit", amountCents: amountCents, reason: "match_win")
    }

    func recordBuyIn(fromPlayer playerName: String,
                     amountCents: Int,
                     matchId: UUID? = nil,
                     matchIdString: String? = nil,
                     journalId: String? = nil) {
        guard amountCents > 0 else { return }
        let j = journalId ?? newJournalId()

        creditHouse(amountCents, reason: "buy_in", matchId: matchId, journalId: j, matchIdString: matchIdString, houseAccount: "house:pot")

        if let mid = matchId,
           shouldEmitLegacy(type: "bank_debited", player: playerName, reason: "buy_in", amountCents: amountCents, matchId: mid) {
            Log.bankDebited(player: playerName, amountCents: amountCents, reason: "buy_in", matchId: mid)
        }
        if let m = matchIdString {
            post(matchIdString: m, journalId: j, account: "player:\(playerName)", direction: "debit", amountCents: amountCents, reason: "buy_in")
        }
    }

    func recordBuyInsBatch(players: [(name: String, cents: Int)],
                           matchId: UUID? = nil,
                           matchIdString: String) {
        let j = newJournalId()
        for (name, cents) in players where cents > 0 {
            recordBuyIn(fromPlayer: name, amountCents: cents, matchId: matchId, matchIdString: matchIdString, journalId: j)
        }
    }

    func collectRake(fromPotCents pot: Int,
                     pct: Double,
                     matchId: UUID? = nil,
                     matchIdString: String) -> Int {
        let rake = Int((Double(pot) * pct).rounded())
        guard rake > 0 else { return 0 }
        let j = newJournalId()

        debitHouse(rake, reason: "rake", matchId: matchId, journalId: j, matchIdString: matchIdString, houseAccount: "house:pot")
        creditHouse(rake, reason: "rake", matchId: matchId, journalId: j, matchIdString: matchIdString, houseAccount: "house:rake")
        return rake
    }

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
