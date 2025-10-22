// UI/HUDView.swift
import SwiftUI

struct HUDView: View {
    @ObservedObject var engine: GameEngine
    var timeLeft: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pot: $\(engine.state.potCents/100)")
                Spacer()
                Text("⏱ \(timeLeft/60):\(String(format: "%02d", timeLeft%60))")
            }
            .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(engine.state.players.enumerated()), id: \.offset) { (i, p) in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.display + (p.isBot ? " 🤖" : ""))
                                .fontWeight(i == engine.state.turnIdx ? .bold : .regular)
                            Text("Total: \(p.totalScore)")
                                .font(.caption)
                            Text(p.picks.isEmpty ? "Picked: —" : "Picked: " + p.picks.map(String.init).joined(separator: ", "))
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
}
