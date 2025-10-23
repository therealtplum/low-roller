// UI/LeaderRow.swift
import SwiftUI

struct LeaderRow: View {
    let rank: Int
    let entry: LeaderEntry
    let metric: LeaderMetric

    // MARK: - Formatters
    private func currencyString(cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = dollars.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return nf.string(from: NSNumber(value: dollars)) ?? "$\(Int(dollars))"
    }

    // Right-aligned, large value
    private var rightText: String {
        switch metric {
        case .dollars: return currencyString(cents: entry.dollarsWonCents)
        case .wins:    return "\(entry.gamesWon)"
        case .streak:  return "\(entry.longestStreak)"
        }
    }

    // Small icon only (no caption text)
    private var metricIconName: String {
        switch metric {
        case .dollars: return "dollarsign.circle.fill"
        case .wins:    return "trophy.fill"
        case .streak:  return "flame.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank).")
                .font(.headline)
                .frame(width: 28, alignment: .trailing)

            // Icon + name
            HStack(spacing: 8) {
                Image(systemName: metricIconName)
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
                    .accessibilityHidden(true)
                Text(entry.name)
                    .font(.headline)
            }

            Spacer()

            // Only the big metric value on the right
            Text(rightText)
                .font(.headline)
                .monospacedDigit()
                .accessibilityLabel({
                    switch metric {
                    case .dollars: return Text("Total dollars won \(rightText)")
                    case .wins:    return Text("Total wins \(rightText)")
                    case .streak:  return Text("Longest streak \(rightText)")
                    }
                }())
        }
        .padding(.vertical, 6)
    }
}
