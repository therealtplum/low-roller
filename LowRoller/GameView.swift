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

    // Ensure leaderboard is written once per game
    @State private var wroteOutcome = false

    // Sudden Death animation overlay state
    @State private var sdShowOverlay = false
    @State private var sdRolling = false
    @State private var sdUserAnimFace: Int = 1
    @State private var sdBotAnimFace: Int = 1
    @State private var sdRollTimer: Timer?

    private var isYourTurn: Bool { !engine.state.players[engine.state.turnIdx].isBot }
    private var isFinished: Bool { engine.state.phase == .finished }
    private var isSuddenDeath: Bool { engine.state.phase == .suddenDeath }

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

                // --- Sudden Death UI ---
                if isSuddenDeath {
                    VStack(spacing: 10) {
                        Text("Sudden Death!")
                            .font(.title2).bold()
                        Text("One roll each. Low score wins.")
                            .foregroundStyle(.secondary)

                        // Show most recent results (if any) below the button in the normal flow
                        if let a = engine.state.suddenFaces.p0, let b = engine.state.suddenFaces.p1 {
                            let aAdj = (a == 3) ? 0 : a
                            let bAdj = (b == 3) ? 0 : b
                            Text("Last: You \(a) → \(aAdj)   •   Bot \(b) → \(bAdj)")
                                .monospaced()
                        }

                        Button {
                            startSuddenDeathAnimationAndResolve()
                        } label: {
                            Text(engine.state.suddenFaces.p0 == nil ? "Roll Sudden Death" : "Roll Again")
                                .font(.title3.weight(.bold))
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .padding(.horizontal)
                    }
                }

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
                    .disabled(!isYourTurn || isFinished || isSuddenDeath || !engine.state.lastFaces.isEmpty || engine.state.remainingDice == 0)

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
                    .disabled(!isYourTurn || isFinished || isSuddenDeath || picked.isEmpty)
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
                .disabled(isFinished || isSuddenDeath)

                // --- End of Game UI (read-only) ---
                if isFinished {
                    // Prefer the engine's winnerIdx (covers Sudden Death),
                    // fall back to lowest total if somehow nil.
                    let winner: Player = {
                        if let idx = engine.state.winnerIdx,
                           engine.state.players.indices.contains(idx) {
                            return engine.state.players[idx]
                        } else {
                            return engine.state.players.min(by: { $0.totalScore < $1.totalScore })!
                        }
                    }()

                    VStack(spacing: 6) {
                        Text("Game Over").font(.headline)
                        Text("Winner: \(winner.display) • Total: \(winner.totalScore) • Pot: $\(engine.state.potCents/100)")
                            .multilineTextAlignment(.center)
                        Button("Back to Lobby") {
                            // No leaderboard writes here (handled once in onChange below)
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

            // ---- Sudden Death animation overlay (on top even if phase flips to .finished) ----
            if sdShowOverlay {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text(sdRolling ? "Rolling…" : "Sudden Death Result")
                        .font(.title3.weight(.semibold))

                    HStack(spacing: 28) {
                        VStack(spacing: 8) {
                            Text("You").font(.caption).foregroundStyle(.secondary)
                            DiceView(face: sdRolling ? sdUserAnimFace : (engine.state.suddenFaces.p0 ?? sdUserAnimFace),
                                     selected: false,
                                     size: 96,
                                     shakeToken: rollShake)
                        }
                        VStack(spacing: 8) {
                            Text("Bot").font(.caption).foregroundStyle(.secondary)
                            DiceView(face: sdRolling ? sdBotAnimFace : (engine.state.suddenFaces.p1 ?? sdBotAnimFace),
                                     selected: false,
                                     size: 96,
                                     shakeToken: rollShake)
                        }
                    }

                    if !sdRolling, let a = engine.state.suddenFaces.p0, let b = engine.state.suddenFaces.p1 {
                        let aAdj = (a == 3) ? 0 : a
                        let bAdj = (b == 3) ? 0 : b
                        Text("You \(a) → \(aAdj)   •   Bot \(b) → \(bAdj)")
                            .monospaced()
                            .padding(.top, 2)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.12))
                        .shadow(radius: 12)
                )
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.2), value: sdShowOverlay)
            }
        }
        .onAppear {
            wroteOutcome = false
            let b = BotController(bind: engine)
            botCtl = b
            scheduleTurnTimer()
            b.scheduleBotIfNeeded()
        }
        .onDisappear {
            turnTimer?.invalidate(); turnTimer = nil
            stopSuddenDeathRollTimer()
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
        // Write leaderboard exactly once when the game reaches .finished
        .onChangeCompat(engine.state.phase) { _, newPhase in
            if newPhase == .finished {
                writeOutcomeIfNeeded()
            } else {
                // Any non-finished phase resets the guard for the next game
                wroteOutcome = false
            }
        }
    }

    // MARK: - Sudden Death animation driver
    private func startSuddenDeathAnimationAndResolve() {
        // Prepare overlay
        sdShowOverlay = true
        sdRolling = true
        withAnimation(.easeOut(duration: 0.2)) { rollShake &+= 1 }

        // Spin the dice faces rapidly until we reveal the true result
        stopSuddenDeathRollTimer()
        sdRollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            sdUserAnimFace = Int.random(in: 1...6)
            sdBotAnimFace = Int.random(in: 1...6)
        }
        if let t = sdRollTimer { RunLoop.main.add(t, forMode: .common) }

        // After a short delay, resolve in the engine and reveal the result
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            _ = engine.resolveSuddenDeathRoll()
            impact.impactOccurred()

            // Stop rolling visuals and show the actual faces for a beat
            stopSuddenDeathRollTimer()
            sdRolling = false

            // Let the user see the result before transitioning to Game Over
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    sdShowOverlay = false
                }
            }
        }
    }

    private func stopSuddenDeathRollTimer() {
        sdRollTimer?.invalidate()
        sdRollTimer = nil
    }

    private func writeOutcomeIfNeeded() {
        guard !wroteOutcome else { return }

        let players = engine.state.players
        guard !players.isEmpty else { return }

        // Prefer engine's winnerIdx (covers Sudden Death),
        // fallback to lowest total for legacy states.
        let winnerIdx = engine.state.winnerIdx
            ?? (players.indices.min { players[$0].totalScore < players[$1].totalScore } ?? 0)

        // Use canonical display names for storage
        let winnerDisplay = players[winnerIdx].display
        let losers = players.enumerated()
            .filter { $0.offset != winnerIdx }
            .map { $0.element.display }

        leaders.recordMatch(
            winnerName: winnerDisplay,
            loserNames: losers,
            potCents: engine.state.potCents
        )

        wroteOutcome = true
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
