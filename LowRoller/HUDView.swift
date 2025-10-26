// UI/HUDView.swift
import SwiftUI

struct HUDView: View {
    @ObservedObject var engine: GameEngine
    var timeLeft: Int

    // NEW: observe House
    @ObservedObject private var economy = EconomyStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row: Pot • House • Timer
            HStack {
                // Pot amount
                Text("💰 Pot: \(currency(engine.state.potCents))")

                Spacer(minLength: 12)

                // House bank
                Text("🏦 Bank: \(currency(engine.state.potCents))")

                Spacer(minLength: 12)

                // Timer
                Text("⏱ \(timeLeft / 60):\(String(format: "%02d", timeLeft % 60))")
                    .monospacedDigit()
            }
            .font(.headline)
            // Players strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(engine.state.players.enumerated()), id: \.offset) { (i, p) in
                        VStack(alignment: .leading, spacing: 4) {
                            // Name + turn highlight
                            Text(p.display + (p.isBot ? " 🤖" : ""))
                                .fontWeight(i == engine.state.turnIdx ? .bold : .regular)

                            // Bankroll (colored)
                            Text(currency(p.bankrollCents))
                                .font(.caption)
                                .foregroundStyle(p.bankrollCents >= 0 ? .green : .red)
                                .monospacedDigit()

                            // Total + picks
                            Text("Total: \(p.totalScore)")
                                .font(.caption)
                            Text(p.picks.isEmpty ? "Picked: —"
                                 : "Picked: " + p.picks.map(String.init).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(i == engine.state.turnIdx ? .yellow : .white.opacity(0.15))
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Local currency helper
    private func currency(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let absVal = abs(cents)
        return "\(sign)$\(absVal/100).\(String(format: "%02d", absVal % 100))"
    }
}
