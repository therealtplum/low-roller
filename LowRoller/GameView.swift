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
                    GeometryReader { geo in
                        // Big dice: ~2 per row, adaptive to width
                        let w: CGFloat = geo.size.width
                        let horizontalPadding: CGFloat = 32
                        let targetPerRow: CGFloat = 2
                        let spacing: CGFloat = 12
                        let usable = max(0, w - horizontalPadding)
                        let rawCell = (usable / targetPerRow)
                        let minSize = max(CGFloat(90), min(CGFloat(180), rawCell - spacing))
                        let columns: [GridItem] = [ GridItem(.adaptive(minimum: minSize), spacing: spacing) ]

                        ScrollView {
                            LazyVGrid(columns: columns, alignment: .center, spacing: spacing) {
                                ForEach(Array(engine.state.lastFaces.enumerated()), id: \.offset) { (i, f) in
                                    DiceView(face: f, selected: picked.contains(i), size: minSize)
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
                        }
                    }
                    .frame(minHeight: 240)
                }
            }
            .padding(.horizontal)

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
        // iOS 16/17-friendly onChange (see extension below)
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
