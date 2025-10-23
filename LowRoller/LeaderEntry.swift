// Models/LeaderboardStore.swift
import Foundation
import Combine   // ✅ Needed for ObservableObject / @Published

// MARK: - Model

struct LeaderEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var gamesWon: Int
    var dollarsWonCents: Int
    var longestStreak: Int
    var currentStreak: Int
    var lastWinAt: Date?

    init(id: UUID = UUID(),
         name: String,
         gamesWon: Int = 0,
         dollarsWonCents: Int = 0,
         longestStreak: Int = 0,
         currentStreak: Int = 0,
         lastWinAt: Date? = nil) {
        self.id = id
        self.name = name
        self.gamesWon = gamesWon
        self.dollarsWonCents = dollarsWonCents
        self.longestStreak = longestStreak
        self.currentStreak = currentStreak
        self.lastWinAt = lastWinAt
    }
}

enum LeaderMetric: String, CaseIterable, Identifiable {
    case dollars = "Most $ Won"
    case wins = "Most Wins"
    case streak = "Longest Streak"
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

    /// Call when `name` won the game.
    private func recordWinner(name: String, potCents: Int) {
        let key = normalizeName(name)
        if let i = indexOfName(key) {
            // In-place update: no merge ambiguity
            entries[i].gamesWon += 1
            entries[i].dollarsWonCents += max(0, potCents)
            entries[i].currentStreak += 1
            if entries[i].currentStreak > entries[i].longestStreak {
                entries[i].longestStreak = entries[i].currentStreak
            }
            entries[i].lastWinAt = Date()
        } else {
            // First time winner
            entries.append(LeaderEntry(
                name: key,
                gamesWon: 1,
                dollarsWonCents: max(0, potCents),
                longestStreak: 1,
                currentStreak: 1,
                lastWinAt: Date()
            ))
        }
        sortAndSave()
    }

    /// Call when `name` did NOT win (loss/draw), to break their current streak.
    private func recordLoss(name: String) {
        let key = normalizeName(name)
        if let i = indexOfName(key), entries[i].currentStreak != 0 {
            entries[i].currentStreak = 0
            sortAndSave()
        }
    }

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

    /// Remove everything.
    func resetAll() {
        entries.removeAll()
        save()
    }

    /// Top 10 by metric, with deterministic tie-breakers.
    func top10(by metric: LeaderMetric) -> [LeaderEntry] {
        let sorted: [LeaderEntry]
        switch metric {
        case .dollars:
            sorted = entries.sorted {
                if $0.dollarsWonCents == $1.dollarsWonCents {
                    return ($0.gamesWon, $0.longestStreak, $0.name.lowercased())
                        > ($1.gamesWon, $1.longestStreak, $1.name.lowercased())
                }
                return $0.dollarsWonCents > $1.dollarsWonCents
            }
        case .wins:
            sorted = entries.sorted {
                if $0.gamesWon == $1.gamesWon {
                    return ($0.dollarsWonCents, $0.longestStreak, $0.name.lowercased())
                        > ($1.dollarsWonCents, $1.longestStreak, $1.name.lowercased())
                }
                return $0.gamesWon > $1.gamesWon
            }
        case .streak:
            sorted = entries.sorted {
                if $0.longestStreak == $1.longestStreak {
                    return ($0.gamesWon, $0.dollarsWonCents, $0.name.lowercased())
                        > ($1.gamesWon, $1.dollarsWonCents, $1.name.lowercased())
                }
                return $0.longestStreak > $1.longestStreak
            }
        }
        return Array(sorted.prefix(10))
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

    // MARK: - Internals

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
