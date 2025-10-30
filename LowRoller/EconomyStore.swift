//
//  EconomyStore.swift
//  LowRoller
//
//  Persists the House balance across launches using UserDefaults,
//  while keeping the original API: `houseCents`, `recordBorrowPenalty`, `resetHouse`.
//

import Foundation
import Combine

final class EconomyStore: ObservableObject {
    // MARK: - Singleton
    static let shared = EconomyStore()

    // MARK: - Persistence Keys
    private enum Keys {
        static let balance = "economy.houseCents.v1"
        static let lastUpdated = "economy.house.lastUpdated.v1"
    }

    // MARK: - Published State
    /// House balance in cents. Any change is saved immediately.
    @Published private(set) var houseCents: Int {
        didSet { saveToDefaults() }
    }

    /// Timestamp of last write
    @Published private(set) var lastUpdated: TimeInterval

    // MARK: - Init
    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.balance) == nil {
            self.houseCents = 0
            self.lastUpdated = Date().timeIntervalSince1970
            saveToDefaults() // persist initial 0
        } else {
            self.houseCents = defaults.integer(forKey: Keys.balance)
            let ts = defaults.double(forKey: Keys.lastUpdated)
            self.lastUpdated = ts == 0 ? Date().timeIntervalSince1970 : ts
            if ts == 0 { saveToDefaults() }
        }
    }

    // MARK: - Original API (kept for compatibility)
    /// Add a positive borrow penalty to the House.
    func recordBorrowPenalty(_ cents: Int) {
        guard cents > 0 else { return }
        houseCents &+= cents
        // didSet persists
    }

    /// Reset the House balance (default 0).
    func resetHouse(to newValueCents: Int = 0) {
        houseCents = newValueCents
        // didSet persists
    }

    // MARK: - Extra helpers (optional to use)
    func credit(_ amountCents: Int) {
        guard amountCents != 0 else { return }
        houseCents &+= amountCents
    }

    func debit(_ amountCents: Int) {
        guard amountCents != 0 else { return }
        houseCents &-= amountCents
    }

    // MARK: - Persistence
    private func saveToDefaults() {
        let defaults = UserDefaults.standard
        lastUpdated = Date().timeIntervalSince1970
        defaults.set(houseCents, forKey: Keys.balance)
        defaults.set(lastUpdated, forKey: Keys.lastUpdated)
        defaults.synchronize() // fine on older iOS; no-op on modern
    }

    // MARK: - UI helper
    func formattedHouseBalance(locale: Locale = .current) -> String {
        let dollars = Double(houseCents) / 100.0
        let nf = NumberFormatter()
        nf.locale = locale
        nf.numberStyle = .currency
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = (dollars.truncatingRemainder(dividingBy: 1) == 0) ? 0 : 2
        return nf.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}
