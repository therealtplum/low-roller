// UI/LeaderRow.swift
import SwiftUI

struct LeaderRow: View {
    let rank: Int
    let entry: LeaderEntry
    let metric: LeaderMetric

    private var rightText: String {
        switch metric {
        case .dollars:
            return "$\(entry.dollarsWonCents / 100)"
        case .wins:
            return "\(entry.gamesWon) wins"
        case .streak:
            return "\(entry.longestStreak) streak"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank).")
                .font(.headline)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.headline)
                HStack(spacing: 12) {
                    Label("\(entry.gamesWon)", systemImage: "trophy.fill")
                        .font(.caption)
                    Label("$\(entry.dollarsWonCents/100)", systemImage: "dollarsign.circle.fill")
                        .font(.caption)
                    Label("\(entry.longestStreak)", systemImage: "flame.fill")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            Spacer()
            Text(rightText)
                .font(.headline)
        }
        .padding(.vertical, 6)
    }
}
