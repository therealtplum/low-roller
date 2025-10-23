// Models/LeaderboardStore.swift
import Foundation
import Combine   // ✅ Needed for ObservableObject / @Published

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

final class LeaderboardStore: ObservableObject {  // ✅ Conforms here
    @Published private(set) var entries: [LeaderEntry] = []  // ✅ Published

    private let storageKey = "lowroller_leaders_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() { load() }

    // Call after a game ends
    func recordWinner(name: String, potCents: Int) {
        var map = Dictionary(uniqueKeysWithValues: entries.map { ($0.name.lowercased(), $0) })
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "You" : name
        var e = map[key.lowercased()] ?? LeaderEntry(name: key)

        e.gamesWon += 1
        e.dollarsWonCents += max(0, potCents)
        e.currentStreak += 1
        e.longestStreak = max(e.longestStreak, e.currentStreak)
        e.lastWinAt = Date()

        map[key.lowercased()] = e
        entries = map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        save()
    }

    func resetAll() {
        entries.removeAll()
        save()
    }

    func top10(by metric: LeaderMetric) -> [LeaderEntry] {
        let sorted: [LeaderEntry]
        switch metric {
        case .dollars:
            sorted = entries.sorted {
                if $0.dollarsWonCents == $1.dollarsWonCents {
                    return ($0.gamesWon, $0.longestStreak) > ($1.gamesWon, $1.longestStreak)
                }
                return $0.dollarsWonCents > $1.dollarsWonCents
            }
        case .wins:
            sorted = entries.sorted {
                if $0.gamesWon == $1.gamesWon {
                    return ($0.dollarsWonCents, $0.longestStreak) > ($1.dollarsWonCents, $1.longestStreak)
                }
                return $0.gamesWon > $1.gamesWon
            }
        case .streak:
            sorted = entries.sorted {
                if $0.longestStreak == $1.longestStreak {
                    return ($0.gamesWon, $0.dollarsWonCents) > ($1.gamesWon, $1.dollarsWonCents)
                }
                return $0.longestStreak > $1.longestStreak
            }
        }
        return Array(sorted.prefix(10))
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
}
