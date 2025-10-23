import SwiftUI
import Foundation
import UIKit

// MARK: - Main GameView
struct GameView: View {
    @ObservedObject var engine: GameEngine
    @StateObject private var leaders = LeaderboardStore()

    @State private var botCtl: BotController?
    @State private var picked: Set<Int> = []
    @State private var rollShake: Int = 0
    @State private var showConfetti = false

    // 5:00 per turn
    @State private var timeLeft: Int = 300
    @State private var turnTimer: Timer?

    private var isYourTurn: Bool { !engine.state.players[engine.state.turnIdx].isBot }
    private var isFinished: Bool { engine.state.phase == .finished }

    var body: some View {
        ZStack {
            // ---- main content ----
            VStack(spacing: 16) {
                HUDView(engine: engine, timeLeft: timeLeft)

                // --- Dice area ---
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.15))

                    if engine.state.lastFaces.isEmpty {
                        Text("Roll to start")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        GeometryReader { geo in
                            let outerHPad: CGFloat = 32
                            let spacing: CGFloat = 14
                            let vPad: CGFloat = 20
                            let minDie: CGFloat = 78
                            let maxDiePhone: CGFloat = 112

                            let count = max(0, engine.state.lastFaces.count)
                            let rows = max(1, Int(ceil(Double(count) / 2.0)))

                            let usableW = max(0, geo.size.width - outerHPad)
                            let dieW = (usableW - spacing) / 2.0
                            let usableH = max(0, geo.size.height - vPad - CGFloat(max(0, rows - 1)) * spacing)
                            let dieH = usableH / CGFloat(rows)
                            let dieSize = max(minDie, min(maxDiePhone, floor(min(dieW, dieH))))

                            let columns: [GridItem] = [
                                GridItem(.fixed(dieSize), spacing: spacing, alignment: .center),
                                GridItem(.fixed(dieSize), spacing: spacing, alignment: .center),
                            ]

                            LazyVGrid(columns: columns, alignment: .center, spacing: spacing) {
                                ForEach(Array(engine.state.lastFaces.enumerated()), id: \.offset) { (i, f) in
                                    DiceView(face: f,
                                             selected: picked.contains(i),
                                             size: dieSize,
                                             shakeToken: rollShake)
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
                .frame(minHeight: 360)

                // --- Primary buttons (Roll + Set Aside) ---
                HStack(spacing: 20) {
                    Button {
                        guard isYourTurn, !isFinished, engine.state.lastFaces.isEmpty else { return }
                        // Trigger dice shake
                        withAnimation(.easeOut(duration: 0.45)) { rollShake &+= 1 }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            engine.roll()
                        }
                    } label: {
                        Label("Roll", systemImage: "dice.fill")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!isYourTurn || isFinished || !engine.state.lastFaces.isEmpty || engine.state.remainingDice == 0)

                    Button {
                        guard isYourTurn, !isFinished, !picked.isEmpty else { return }
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        engine.pick(indices: Array(picked))
                        picked.removeAll()
                    } label: {
                        Label("Set Aside", systemImage: "hand.tap.fill")
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!isYourTurn || isFinished || picked.isEmpty)
                }
                .padding(.horizontal)
                .padding(.top, 4)

                // --- Timeout fallback (secondary button) ---
                Button {
                    if engine.state.lastFaces.isEmpty && engine.state.remainingDice > 0 {
                        withAnimation(.easeOut(duration: 0.45)) { rollShake &+= 1 }
                        engine.roll()
                    }
                    engine.fallbackPick()
                } label: {
                    Text("Timeout Fallback")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.gray)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 20)
                        .background(Color(white: 0.15))
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
                .disabled(isFinished)

                // --- End of Game ---
                if isFinished {
                    // Winner = lowest total score (display assumes you have `display` and `totalScore`)
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

            // ---- confetti overlay (full screen) ----
            ConfettiView(isActive: $showConfetti, intensity: 1.2, fallDuration: 3.0)
                .allowsHitTesting(false)
                .ignoresSafeArea()
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
        // Listen for the engine's "human won" signal and fire confetti
        .onReceive(NotificationCenter.default.publisher(for: .humanWonMatch)) { note in
            if (note.object as? Bool) == true { fireConfetti() }
        }
        // Turn advanced
        .onChangeCompat(engine.state.turnIdx) { _, _ in
            picked.removeAll()
            scheduleTurnTimer()
            botCtl?.scheduleBotIfNeeded()
        }
        // When dice appear (after empty) trigger wiggle — works for bots too
        .onChangeCompat(engine.state.lastFaces) { oldFaces, newFaces in
            botCtl?.scheduleBotIfNeeded()
            if oldFaces.isEmpty && !newFaces.isEmpty {
                withAnimation(.easeOut(duration: 0.45)) { rollShake &+= 1 }
            }
        }
    }

    private func fireConfetti() {
        showConfetti = true
        let h = UINotificationFeedbackGenerator()
        h.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            showConfetti = false
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
                if engine.state.lastFaces.isEmpty && engine.state.remainingDice > 0 {
                    withAnimation(.easeOut(duration: 0.45)) { rollShake &+= 1 }
                    engine.roll()
                }
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

// MARK: - ShakeEffect (used by DiceView)
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit: CGFloat = 6
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}
