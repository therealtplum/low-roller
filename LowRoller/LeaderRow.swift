//
//  LeaderRow.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/22/25.
//


// Model/LeaderboardStore.swift
import Foundation
import Combine    // ← add

struct LeaderRow: Codable, Identifiable {
    var id = UUID()
    var player: String
    var games: Int
    var wonCents: Int
    var streak: Int
}

final class LeaderboardStore: ObservableObject {
    @Published var rows: [LeaderRow] = []
    private let key = "lowroller_leaderboard_ios"

    init() { load() }
    func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let r = try? JSONDecoder().decode([LeaderRow].self, from: d) { rows = r }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(rows) {
            UserDefaults.standard.set(d, forKey: key)
        }
    }
    func recordWinner(name: String, potCents: Int) {
        if let i = rows.firstIndex(where: { $0.player == name }) {
            rows[i].games += 1
            rows[i].wonCents += potCents
            rows[i].streak += 1
        } else {
            rows.append(.init(player: name, games: 1, wonCents: potCents, streak: 1))
        }
        // reset everyone else’s streaks
        for idx in rows.indices where rows[idx].player != name {
            rows[idx].streak = 0
        }
        save()
    }
    func reset() { rows = []; save() }
}
