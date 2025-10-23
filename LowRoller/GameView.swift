// UI/GameView.swift
import SwiftUI
import Foundation
import UIKit

struct GameView: View {
    @ObservedObject var engine: GameEngine
    @StateObject private var leaders = LeaderboardStore()

    @State private var botCtl: BotController?
    @State private var picked: Set<Int> = []

    // 5:00 per turn
    @State private var timeLeft: Int = 300
    @State private var turnTimer: Timer?

    private var isYourTurn: Bool { !engine.state.players[engine.state.turnIdx].isBot }
    private var isFinished: Bool { engine.state.phase == .finished }

    var body: some View {
        VStack(spacing: 12) {
            HUDView(engine: engine, timeLeft: timeLeft)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.15))

                if engine.state.lastFaces.isEmpty {
                    Text("Roll to start")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    // --- 2 columns, ALWAYS fits up to 7 dice on screen (no scrolling needed) ---
                    GeometryReader { geo in
                        // Layout constants
                        let outerHPad: CGFloat = 32      // must match container .padding(.horizontal) below
                        let spacing: CGFloat = 14        // gap between dice and rows
                        let vPad: CGFloat = 20           // extra vertical breathing room inside grid
                        let minDie: CGFloat = 78         // lower bound so dice stay tappable
                        let maxDiePhone: CGFloat = 112   // upper bound so 4 rows always fit on iPhone portrait

                        // Content counts
                        let count = max(0, engine.state.lastFaces.count)
                        let rows = max(1, Int(ceil(Double(count) / 2.0)))  // 2 per row → up to 4 rows for 7 dice

                        // Width-constrained size (2 cols)
                        let usableW = max(0, geo.size.width - outerHPad)
                        let dieW = (usableW - spacing) / 2.0

                        // Height-constrained size (rows tall)
                        let usableH = max(0, geo.size.height - vPad - CGFloat(max(0, rows - 1)) * spacing)
                        let dieH = usableH / CGFloat(rows)

                        // Final die size: respect both axes and clamp to safe range
                        let dieSize = max(minDie, min(maxDiePhone, floor(min(dieW, dieH))))

                        let columns: [GridItem] = [
                            GridItem(.fixed(dieSize), spacing: spacing, alignment: .center),
                            GridItem(.fixed(dieSize), spacing: spacing, alignment: .center),
                        ]

                        LazyVGrid(columns: columns, alignment: .center, spacing: spacing) {
                            ForEach(Array(engine.state.lastFaces.enumerated()), id: \.offset) { (i, f) in
                                DiceView(face: f, selected: picked.contains(i), size: dieSize)
                                    .onTapGesture {
                                        guard isYourTurn, !isFinished else { return }
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            if picked.contains(i) { picked.remove(i) } else { picked.insert(i) }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .padding(.horizontal)
            .frame(minHeight: 360) // give the dice zone enough room on small phones

            HStack {
                Button("Roll") {
                    guard isYourTurn, !isFinished, engine.state.lastFaces.isEmpty else { return }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { engine.roll() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isYourTurn || isFinished || !engine.state.lastFaces.isEmpty || engine.state.remainingDice == 0)

                Button("Set Aside") {
                    guard isYourTurn, !isFinished, !picked.isEmpty else { return }
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    engine.pick(indices: Array(picked))
                    picked.removeAll()
                }
                .disabled(!isYourTurn || isFinished || picked.isEmpty)

                Button("Timeout Fallback") {
                    if engine.state.lastFaces.isEmpty && engine.state.remainingDice > 0 { engine.roll() }
                    engine.fallbackPick()
                }
                .buttonStyle(.bordered)
                .disabled(isFinished)
            }
            .padding(.top, 4)

            if isFinished {
                let winner = engine.state.players.min(by: { $0.totalScore < $1.totalScore })!
                VStack(spacing: 6) {
                    Text("Game Over").font(.headline)
                    Text("Winner: \(winner.display) • Total: \(winner.totalScore) • Pot: $\(engine.state.potCents/100)")
                        .multilineTextAlignment(.center)
                    Button("Back to Lobby") {
                        leaders.recordWinner(name: winner.display, potCents: engine.state.potCents)
                        NotificationCenter.default.post(name: .lowRollerBackToLobby, object: nil)
                    }
                    .padding(.top, 6)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 8)
        }
        .onAppear {
            let b = BotController(bind: engine)
            botCtl = b
            scheduleTurnTimer()
            b.scheduleBotIfNeeded()
        }
        .onDisappear {
            turnTimer?.invalidate(); turnTimer = nil
        }
        .onChangeCompat(engine.state.turnIdx) { _, _ in
            picked.removeAll()
            scheduleTurnTimer()
            botCtl?.scheduleBotIfNeeded()
        }
        .onChangeCompat(engine.state.lastFaces) { _, _ in
            botCtl?.scheduleBotIfNeeded()
        }
    }

    // MARK: - Turn timer (5:00 with fallback)
    private func scheduleTurnTimer() {
        turnTimer?.invalidate()
        timeLeft = 300
        guard !isFinished else { return }
        turnTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            timeLeft -= 1
            if timeLeft <= 0 {
                t.invalidate()
                if engine.state.lastFaces.isEmpty && engine.state.remainingDice > 0 { engine.roll() }
                engine.fallbackPick()
            }
        }
        if let t = turnTimer { RunLoop.main.add(t, forMode: .common) }
    }
}

// MARK: - iOS 16/17 compatible onChange helper
@available(iOS 13.0, *)
extension View {
    @ViewBuilder
    func onChangeCompat<V: Equatable>(
        _ value: V,
        perform: @escaping (_ old: V, _ new: V) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { oldValue, newValue in perform(oldValue, newValue) }
        } else {
            self.onChange(of: value) { newValue in perform(newValue, newValue) }
        }
    }
}
