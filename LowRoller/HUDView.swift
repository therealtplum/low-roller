// UI/HUDView.swift
import SwiftUI

struct HUDView: View {
    @ObservedObject var engine: GameEngine
    var timeLeft: Int

    // Observe House
    @ObservedObject private var economy = EconomyStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Top row: Pot • House • Timer
            HStack {
                // Pot amount
                Text("💰 Pot: \(currency(engine.state.potCents))")

                Spacer(minLength: 12)

                // House bank
                Text("🏦 Bank: \(currency(economy.houseCents))")

                Spacer(minLength: 12)

                // Timer
                Text("⏱ \(timeLeft / 60):\(String(format: "%02d", timeLeft % 60))")
                    .monospacedDigit()
            }
            .font(.headline)

            // Players strip - scrollable & auto-centering
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(engine.state.players.enumerated()), id: \.offset) { (i, p) in
                            VStack(alignment: .leading, spacing: 4) {
                                // Name + bot tag + bold if current turn
                                Text(p.display + (p.isBot ? " 🤖" : ""))
                                    .fontWeight(i == engine.state.turnIdx ? .bold : .regular)

                                // Bankroll (colored)
                                Text("Balance: \(currency(p.bankrollCents))")
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
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(i == engine.state.turnIdx ? .yellow : .white.opacity(0.15))
                            )
                            // Subtle visual emphasis for current player
                            .scaleEffect(i == engine.state.turnIdx ? 1.06 : 1.0)
                            .opacity(i == engine.state.turnIdx ? 1.0 : 0.9)
                            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: engine.state.turnIdx)
                            .id(i)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
                .scrollClipDisabled()
                // Auto-center on initial appearance
                .onAppear {
                    centerOnCurrentTurn(proxy: proxy, animated: false)
                }
                // Updated iOS 17 onChange syntax
                .onChange(of: engine.state.turnIdx) { oldValue, newValue in
                    centerOnCurrentTurn(proxy: proxy, animated: true)
                }
                .onChange(of: engine.state.players.count) { oldValue, newValue in
                    centerOnCurrentTurn(proxy: proxy, animated: true)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func centerOnCurrentTurn(proxy: ScrollViewProxy, animated: Bool) {
        let idx = engine.state.turnIdx
        guard idx >= 0 && idx < engine.state.players.count else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(idx, anchor: .center)
            }
        } else {
            proxy.scrollTo(idx, anchor: .center)
        }
    }

    private func currency(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let absVal = abs(cents)
        return "\(sign)$\(absVal / 100).\(String(format: "%02d", absVal % 100))"
    }
}
