// Models/LeaderboardStore.swift
import Foundation
import Combine

// Single source of truth for the House NPC display name
enum HouseNPC {
    static let displayName = "🎰 Casino (House)"
}

// MARK: - Model

struct LeaderEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var gamesWon: Int
    var dollarsWonCents: Int
    var longestStreak: Int
    var currentStreak: Int
    var lastWinAt: Date?
    var bankrollCents: Int = 10_000

    init(id: UUID = UUID(),
         name: String,
         gamesWon: Int = 0,
         dollarsWonCents: Int = 0,
         longestStreak: Int = 0,
         currentStreak: Int = 0,
         lastWinAt: Date? = nil,
         bankrollCents: Int = 10_000) {
        self.id = id
        self.name = name
        self.gamesWon = gamesWon
        self.dollarsWonCents = dollarsWonCents
        self.longestStreak = longestStreak
        self.currentStreak = currentStreak
        self.lastWinAt = lastWinAt
        self.bankrollCents = bankrollCents
    }
}

// Safe migration: default bankrollCents = 10_000 if missing in old saves
extension LeaderEntry {
    private enum CodingKeys: String, CodingKey {
        case id, name, gamesWon, dollarsWonCents, longestStreak, currentStreak, lastWinAt, bankrollCents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        gamesWon = try c.decode(Int.self, forKey: .gamesWon)
        dollarsWonCents = try c.decode(Int.self, forKey: .dollarsWonCents)
        longestStreak = try c.decode(Int.self, forKey: .longestStreak)
        currentStreak = try c.decode(Int.self, forKey: .currentStreak)
        lastWinAt = try c.decodeIfPresent(Date.self, forKey: .lastWinAt)
        bankrollCents = try c.decodeIfPresent(Int.self, forKey: .bankrollCents) ?? 10_000
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(gamesWon, forKey: .gamesWon)
        try c.encode(dollarsWonCents, forKey: .dollarsWonCents)
        try c.encode(longestStreak, forKey: .longestStreak)
        try c.encode(currentStreak, forKey: .currentStreak)
        try c.encodeIfPresent(lastWinAt, forKey: .lastWinAt)
        try c.encode(bankrollCents, forKey: .bankrollCents)
    }
}

enum LeaderMetric: String, CaseIterable, Identifiable {
    case dollars = "Most $ Won"
    case wins = "Most Wins"
    case streak = "Longest Streak"
    case balance = "Current Balance"
    var id: String { rawValue }
}

// MARK: - Store

final class LeaderboardStore: ObservableObject {
    @Published private(set) var entries: [LeaderEntry] = []

    private let storageKey = "lowroller_leaders_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        load()
        // One-time safety: coalesce any legacy duplicates already persisted
        let repaired = coalesce(entries)
        if repaired != entries {
            entries = repaired
            save()
        }
    }

    // MARK: - Public API

    /// Convenience: record an explicit result in one call.
    func recordResult(name: String, didWin: Bool, potCents: Int = 0) {
        if didWin { recordWinner(name: name, potCents: potCents) }
        else { recordLoss(name: name) }
    }

    /// All losers at once (optional helper).
    func recordMatch(winnerName: String, loserNames: [String], potCents: Int) {
        recordWinner(name: winnerName, potCents: potCents)
        for l in loserNames { recordLoss(name: l) }
    }

    /// Update/persist a player's bankroll (used after each match).
    func updateBankroll(name: String, bankrollCents: Int) {
        let key = normalizeName(name)
        if let i = indexOfName(key) {
            entries[i].bankrollCents = bankrollCents
        } else {
            entries.append(LeaderEntry(
                name: key,
                gamesWon: 0,
                dollarsWonCents: 0,
                longestStreak: 0,
                currentStreak: 0,
                lastWinAt: nil,
                bankrollCents: bankrollCents
            ))
        }
        sortAndSave()
    }

    /// Remove everything.
    func resetAll() {
        entries.removeAll()
        save()
    }

    /// Remove a single entry everywhere (by stable id).
    func removeEntry(id: UUID) {
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries.remove(at: i)
            save()
        }
    }

    /// Optional convenience: remove by display name (case-insensitive).
    func removeByName(_ name: String) {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if let i = indexOfName(key) {
            entries.remove(at: i)
            save()
        }
    }

    /// Top 10 by metric, with deterministic tie-breakers.
    /// For `.balance`, inject a synthetic "Casino (House)" row reflecting EconomyStore.shared.houseCents.
    func top10(by metric: LeaderMetric) -> [LeaderEntry] {
        // Start with the persisted human entries.
        var list = entries

        // Never keep a stale House row if it ever got persisted by accident.
        list.removeAll { $0.name.caseInsensitiveCompare(HouseNPC.displayName) == .orderedSame }

        // Inject the House *only* for "Current Balance".
        if metric == .balance {
            let house = LeaderEntry(
                name: HouseNPC.displayName,
                gamesWon: 0,
                dollarsWonCents: 0,
                longestStreak: 0,
                currentStreak: 0,
                lastWinAt: nil,
                bankrollCents: EconomyStore.shared.houseCents
            )
            list.append(house)
        }

        let sorted: [LeaderEntry]
        switch metric {
        case .dollars:
            sorted = list.sorted {
                if $0.dollarsWonCents == $1.dollarsWonCents {
                    return ($0.gamesWon, $0.longestStreak, $0.name.lowercased())
                        > ($1.gamesWon, $1.longestStreak, $1.name.lowercased())
                }
                return $0.dollarsWonCents > $1.dollarsWonCents
            }

        case .wins:
            sorted = list.sorted {
                if $0.gamesWon == $1.gamesWon {
                    return ($0.dollarsWonCents, $0.longestStreak, $0.name.lowercased())
                        > ($1.dollarsWonCents, $1.longestStreak, $1.name.lowercased())
                }
                return $0.gamesWon > $1.gamesWon
            }

        case .streak:
            sorted = list.sorted {
                if $0.longestStreak == $1.longestStreak {
                    return ($0.gamesWon, $0.dollarsWonCents, $0.name.lowercased())
                        > ($1.gamesWon, $1.dollarsWonCents, $1.name.lowercased())
                }
                return $0.longestStreak > $1.longestStreak
            }

        case .balance:
            sorted = list.sorted {
                if $0.bankrollCents == $1.bankrollCents {
                    return ($0.dollarsWonCents, $0.gamesWon, $0.name.lowercased())
                        > ($1.dollarsWonCents, $1.gamesWon, $1.name.lowercased())
                }
                return $0.bankrollCents > $1.bankrollCents
            }
        }

        // For balance we show the full list (so the House can appear anywhere).
        // For others, keep the top 10.
        return (metric == .balance) ? sorted : Array(sorted.prefix(10))
    }

    // MARK: - Optional migration for old bug
    func migrateFixLongestStreakIfMirrorsWins() {
        var changed = false
        var newEntries: [LeaderEntry] = []
        for var e in entries {
            if e.longestStreak == e.gamesWon, e.currentStreak < e.longestStreak {
                e.longestStreak = max(e.currentStreak, min(e.longestStreak, e.gamesWon))
                changed = true
            }
            newEntries.append(e)
        }
        if changed {
            entries = newEntries
            save()
        }
    }

    // MARK: - Recording Methods (CHANGED FROM PRIVATE TO INTERNAL/PUBLIC)
    
    // FIX: Changed from 'private func' to just 'func' so GameView can access it
    func recordWinner(name: String, potCents: Int) {
        let key = normalizeName(name)
        if let i = indexOfName(key) {
            entries[i].gamesWon += 1
            entries[i].dollarsWonCents += max(0, potCents)
            entries[i].currentStreak += 1
            if entries[i].currentStreak > entries[i].longestStreak {
                entries[i].longestStreak = entries[i].currentStreak
            }
            entries[i].lastWinAt = Date()
        } else {
            entries.append(LeaderEntry(
                name: key,
                gamesWon: 1,
                dollarsWonCents: max(0, potCents),
                longestStreak: 1,
                currentStreak: 1,
                lastWinAt: Date(),
                bankrollCents: 10_000
            ))
        }
        sortAndSave()
    }

    // FIX: Changed from 'private func' to just 'func' so GameView can access it
    func recordLoss(name: String) {
        let key = normalizeName(name)
        if let i = indexOfName(key), entries[i].currentStreak != 0 {
            entries[i].currentStreak = 0
            sortAndSave()
        }
    }

    // MARK: - Private Helper Methods (these remain private)
    
    private func normalizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You" : trimmed
    }

    private func indexOfName(_ key: String) -> Int? {
        entries.firstIndex { $0.name.caseInsensitiveCompare(key) == .orderedSame }
    }

    private func sortAndSave() {
        entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let list = try? decoder.decode([LeaderEntry].self, from: data) {
            entries = list
        }
    }

    private func save() {
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Dedup / Merge Helpers (used only at init)
    
    private func coalesce(_ list: [LeaderEntry]) -> [LeaderEntry] {
        var map: [String: LeaderEntry] = [:]  // key = lowercased name
        for e in list {
            let k = e.name.lowercased()
            if let existing = map[k] {
                map[k] = merge(existing, e)
            } else {
                map[k] = e
            }
        }
        return map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func merge(_ a: LeaderEntry, _ b: LeaderEntry) -> LeaderEntry {
        // Deterministic id: keep the older UUID alphabetically
        var base = (a.id.uuidString < b.id.uuidString) ? a : b
        let other = (base.id == a.id) ? b : a

        base.gamesWon        += other.gamesWon
        base.dollarsWonCents += other.dollarsWonCents
        base.longestStreak    = max(base.longestStreak, other.longestStreak)

        // Current streak preference: take from the entry with the latest lastWinAt if present, else max
        let latest = maxDate(base.lastWinAt, other.lastWinAt)
        if latest == base.lastWinAt {
            base.currentStreak = max(base.currentStreak, other.currentStreak)
        } else if latest == other.lastWinAt {
            base.currentStreak = max(other.currentStreak, base.currentStreak)
        } else {
            base.currentStreak = max(base.currentStreak, other.currentStreak)
        }

        // Bankroll—prefer the higher of the two to avoid accidental loss
        base.bankrollCents = max(base.bankrollCents, other.bankrollCents)

        base.lastWinAt = latest
        return base
    }

    private func maxDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case let (x?, y?): return max(x, y)
        case let (x?, nil): return x
        case let (nil, y?): return y
        default: return nil
        }
    }
}
