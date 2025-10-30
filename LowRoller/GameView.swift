import SwiftUI
import Foundation
import UIKit

// MARK: - Main GameView
struct GameView: View {
    @ObservedObject var engine: GameEngine
    @StateObject private var leaders = LeaderboardStore()

    // Observe House (if you show any house metrics in HUD)
    @ObservedObject private var economy = EconomyStore.shared

    @State private var botCtl: BotController?
    @State private var picked: Set<Int> = Set<Int>()   // avoid inference choke
    @State private var rollShake: Int = 0
    @State private var showConfetti = false

    // 5:00 per turn (using 30s here for testing)
    @State private var timeLeft: Int = 30
    @State private var turnTimer: Timer?

    // Ensure leaderboard is written once per game
    @State private var wroteOutcome = false

    // Track the (growing) pre-payout pot so we record/display correct winnings
    @State private var startingPotCents: Int = 0

    // Sudden Death animation overlay state (multi-way)
    @State private var sdShowOverlay = false
    @State private var sdRolling = false
    @State private var sdAnimFaces: [Int:Int] = [:]     // playerIdx -> face while spinning
    @State private var sdRollTimer: Timer?

    // Anti-flash / anti-retrigger flags
    @State private var sdHasRevealed = false
    @State private var sdRevealAt: Date? = nil

    // Snapshot of the final SD faces (so UI can still display after engine advances phase)
    @State private var sdResultFacesSnap: [Int:Int] = [:]     // playerIdx -> rolled face (1...6)
    @State private var sdResultOrderSnap: [Int] = []          // stable order of players to show

    private var isYourTurn: Bool { !engine.state.players[engine.state.turnIdx].isBot }
    private var isFinished: Bool { engine.state.phase == .finished }
    private var isSuddenDeath: Bool { engine.state.phase == .suddenDeath }
    private var inAwaitDouble: Bool { engine.state.phase == .awaitDouble }

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
                                        guard isYourTurn, !isFinished, !inAwaitDouble else { return }
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

                // --- Sudden Death UI (multi-way) ---
                if isSuddenDeath {
                    VStack(spacing: 10) {
                        Text("Sudden Death!")
                            .font(.title2).bold()
                        if let contenders = engine.state.suddenContenders {
                            Text(contenders.count == 2 ? "Lowest roll is eliminated (re-roll ties)." :
                                 "Group sudden death: lowest roll is eliminated (re-roll ties).")
                                .foregroundStyle(.secondary)

                            // Show most recent results (if any)
                            if let rolls = engine.state.suddenRolls {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(contenders, id: \.self) { idx in
                                        let name = engine.state.players[idx].display
                                        let face = rolls[idx]
                                        HStack {
                                            Text(name).font(.subheadline.weight(.medium))
                                            Spacer()
                                            if let f = face {
                                                let adj = (f == 3) ? 0 : f
                                                Text("\(f) → \(adj)").monospaced()
                                            } else {
                                                Text("—").monospaced()
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        Button {
                            guard engine.state.phase == .suddenDeath else { return }
                            startSuddenDeathAnimationAndResolve()
                        } label: {
                            Text((engine.state.suddenRolls == nil) ? "Roll Sudden Death" : "Roll Again")
                                .font(.title3.weight(.bold))
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .padding(.horizontal)
                        .disabled(sdShowOverlay || sdHasRevealed)
                    }
                }

                // --- Double-or-Nothing decision (centered vertical layout) ---
                if inAwaitDouble {
                    VStack(spacing: 12) {
                        Text(doubleHeadline)
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        // Big centered primary button
                        Button {
                            engine.acceptDoubleOrNothing()
                            // Reset local UI state for fresh round
                            picked.removeAll()
                            rollShake = 0
                            sdShowOverlay = false
                            sdRolling = false
                            sdAnimFaces.removeAll()
                            stopSuddenDeathRollTimer()
                            showConfetti = false
                            scheduleTurnTimer()
                        } label: {
                            Text(doubleButtonTitle)
                                .font(.title2.weight(.bold))
                                .padding(.vertical, 14)
                                .frame(maxWidth: 360)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .frame(maxWidth: .infinity)

                        // Smaller centered secondary action underneath
                        Button {
                            // Finalize payout, then pop straight back to lobby
                            engine.declineDoubleOrNothing()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                NotificationCenter.default.post(name: .lowRollerBackToLobby, object: nil)
                            }
                        } label: {
                            Text("Settle Now")
                                .font(.headline)
                                .padding(.vertical, 10)
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut(duration: 0.2), value: inAwaitDouble)
                }

                // --- Primary buttons (Roll + Set Aside) ---
                if !inAwaitDouble {
                    HStack(spacing: 20) {
                        Button {
                            guard isYourTurn, !isFinished, engine.state.lastFaces.isEmpty else { return }
                            withAnimation(.easeOut(duration: 0.45)) { rollShake &+= 1 }
                            resetTurnCountdownIfHuman()          // ← restart countdown on every human roll
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { engine.roll() }
                        } label: {
                            Label("Roll", systemImage: "dice.fill")
                                .font(.title3.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(!isYourTurn || isFinished || isSuddenDeath || engine.state.remainingDice == 0)

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
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: inAwaitDouble)
                }

                // --- End of Game UI (read-only) ---
                if isFinished {
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
                        Text("Winner: \(winner.display) • Total: \(winner.totalScore) • Pot: \(currency(startingPotCents))")
                            .multilineTextAlignment(.center)

                        Button("Back to Lobby") {
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

            // ---- Sudden Death animation overlay (multi-way) ----
            if sdShowOverlay {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text(sdRolling ? "Rolling…" : "Sudden Death Result")
                        .font(.title3.weight(.semibold))

                    // Prefer live engine SD state; if engine has advanced, show the snapshot
                    let contenders = engine.state.suddenContenders ?? sdResultOrderSnap
                    let faceSource: (Int) -> Int? = { idx in
                        if sdRolling {
                            return sdAnimFaces[idx]
                        } else {
                            return engine.state.suddenRolls?[idx] ?? sdResultFacesSnap[idx]
                        }
                    }

                    if !contenders.isEmpty {
                        GeometryReader { geo in
                            let count = contenders.count
                            // Columns: 1 for single, 2 fixed for two, adaptive for 3+
                            let columns: [GridItem] = {
                                if count <= 1 { return [GridItem(.flexible(), spacing: 16)] }
                                if count == 2 { return [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)] }
                                return [GridItem(.adaptive(minimum: 72), spacing: 16)]
                            }()

                            // Die size: bigger when only 1–2 contenders
                            let dieSize: CGFloat = {
                                if count <= 1 { return min(140, max(90, geo.size.width * 0.35)) }
                                if count == 2 { return min(120, max(84, geo.size.width * 0.28)) }
                                return 72
                            }()

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(contenders, id: \.self) { idx in
                                    let name = engine.state.players.indices.contains(idx)
                                        ? engine.state.players[idx].display
                                        : "Player \(idx+1)"
                                    let faceToShow = faceSource(idx) ?? 1
                                    VStack(spacing: 6) {
                                        DiceView(face: faceToShow,
                                                 selected: false,
                                                 size: dieSize,
                                                 shakeToken: rollShake)
                                        Text(name).font(.caption).lineLimit(1).truncationMode(.tail)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                        .frame(height: 200)
                        .padding(.top, 6)

                        if !sdRolling {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(contenders, id: \.self) { idx in
                                    if let f = faceSource(idx) {
                                        let adj = (f == 3) ? 0 : f
                                        let name = engine.state.players.indices.contains(idx)
                                            ? engine.state.players[idx].display
                                            : "Player \(idx+1)"
                                        Text("\(name): \(f) → \(adj)")
                                            .monospaced()
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    if !sdRolling {
                        Text("Tap to continue")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
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
                // Allow dismiss by tap (only after result is shown, and lingered a bit)
                .onTapGesture {
                    guard !sdRolling else { return }
                    let minHold: TimeInterval = 1.0
                    let lingered = (sdRevealAt.map { Date().timeIntervalSince($0) } ?? 0) >= minHold
                    if sdHasRevealed && lingered {
                        sdShowOverlay = false
                    }
                }
            }
        }
        .onAppear {
            wroteOutcome = false
            // Capture current pot; we’ll keep the *max* pot as doubles happen
            startingPotCents = engine.state.potCents

            let b = BotController(bind: engine)
            botCtl = b
            scheduleTurnTimer()
            if !inAwaitDouble { b.scheduleBotIfNeeded() }
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
            if !inAwaitDouble { botCtl?.scheduleBotIfNeeded() }
        }
        // When dice appear (after empty) trigger wiggle — works for bots too
        .onChangeCompat(engine.state.lastFaces) { oldFaces, newFaces in
            if !inAwaitDouble { botCtl?.scheduleBotIfNeeded() }
            if oldFaces.isEmpty && !newFaces.isEmpty {
                withAnimation(.easeOut(duration: 0.45)) { rollShake &+= 1 }
                resetTurnCountdownIfHuman()      // ← restart countdown whenever a human roll produces faces
            }
        }
        // Keep a running *max* of the pot so Game Over shows the doubled amount
        .onChangeCompat(engine.state.potCents) { _, newVal in
            if newVal > startingPotCents { startingPotCents = newVal }
        }
        // Phase transitions: write outcome, and stop timers while awaiting decision
        .onChangeCompat(engine.state.phase) { _, newPhase in
            if newPhase == .finished {
                writeOutcomeIfNeeded()
            } else {
                // Any non-finished phase resets the guard for the next game
                wroteOutcome = false
            }
            if newPhase == .awaitDouble {
                // Halt timers/bots so we don't re-enter SD or auto-advance
                turnTimer?.invalidate(); turnTimer = nil
            }
        }
    }

    // MARK: - Sudden Death animation driver (multi-way)
    private func startSuddenDeathAnimationAndResolve() {
        // Prevent post-resolution re-entry and mid-animation retrigger
        guard engine.state.phase == .suddenDeath else { return }
        guard !sdShowOverlay && !sdRolling else { return }

        // Tunables
        let spinDuration: TimeInterval = 1.25   // longer spin to build suspense
        let revealDelay: TimeInterval = 0.12    // small beat so SwiftUI publishes faces

        // Prepare overlay
        sdHasRevealed = false
        sdRevealAt = nil
        sdResultFacesSnap = [:]
        sdResultOrderSnap = []
        sdShowOverlay = true
        sdRolling = true
        withAnimation(.easeOut(duration: 0.2)) { rollShake &+= 1 }

        // Initialize anim faces for current contenders
        if let contenders = engine.state.suddenContenders {
            for idx in contenders { sdAnimFaces[idx] = Int.random(in: 1...6) }
        }

        // Spin the dice faces rapidly until we reveal the true result
        stopSuddenDeathRollTimer()
        sdRollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            if let contenders = engine.state.suddenContenders {
                for idx in contenders { sdAnimFaces[idx] = Int.random(in: 1...6) }
            }
        }
        if let t = sdRollTimer { RunLoop.main.add(t, forMode: .common) }

        // Resolve, then reveal after a short pause so faces are definitely in state
        let impact = UIImpactFeedbackGenerator(style: .heavy)
        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration) {
            _ = engine.rollSuddenDeath()
            impact.impactOccurred()

            stopSuddenDeathRollTimer()

            // Give SwiftUI a brief beat to publish suddenRolls, then show the result
            DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) {
                // SNAPSHOT the faces right now (before engine potentially advances again)
                if let liveRolls = engine.state.suddenRolls {
                    sdResultFacesSnap = liveRolls
                    if let liveOrder = engine.state.suddenContenders {
                        sdResultOrderSnap = liveOrder
                    } else {
                        // fallback: stable order from keys
                        sdResultOrderSnap = Array(liveRolls.keys).sorted()
                    }
                } else if let liveOrder = engine.state.suddenContenders {
                    // If rolls somehow nil, snapshot anim faces so UI still shows something
                    sdResultFacesSnap = Dictionary(uniqueKeysWithValues: liveOrder.map { ($0, sdAnimFaces[$0] ?? 1) })
                    sdResultOrderSnap = liveOrder
                }

                sdRolling = false
                sdHasRevealed = true
                sdRevealAt = Date()

                // If the engine already moved on (winner decided), gently auto-dismiss
                if engine.state.phase != .suddenDeath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation(.easeOut(duration: 0.3)) { sdShowOverlay = false }
                    }
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

        let winnerDisplay = players[winnerIdx].display
        let losers = players.enumerated()
            .filter { $0.offset != winnerIdx }
            .map { $0.element.display }

        // Record the match with the *final (possibly doubled)* pot we tracked
        leaders.recordMatch(
            winnerName: winnerDisplay,
            loserNames: losers,
            potCents: startingPotCents
        )

        // Sync all bankrolls back to leaderboard
        for p in players {
            leaders.updateBankroll(name: p.display, bankrollCents: p.bankrollCents)
        }

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

    // MARK: - Turn timer (5:00 with engine-driven timeout)
    private func scheduleTurnTimer() {
        turnTimer?.invalidate()
        timeLeft = 30

        // Only count down during normal play (not finished / sudden death / await double)
        guard !isFinished && !isSuddenDeath && !inAwaitDouble else { return }

        turnTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            timeLeft -= 1
            if timeLeft <= 0 {
                t.invalidate()

                // Engine decides what to do on timeout:
                engine.handleTurnTimeout()

                // If we're still in a normal round and it's a human turn, restart the countdown window
                if engine.state.phase == .normal,
                   engine.state.turnIdx < engine.state.players.count,
                   !engine.state.players[engine.state.turnIdx].isBot,
                   !isFinished {
                    timeLeft = 30
                    scheduleTurnTimer()
                }
            }
        }
        if let t = turnTimer { RunLoop.main.add(t, forMode: .common) }
    }

    // MARK: - Timer reset helper (called on every human roll)
    private func resetTurnCountdownIfHuman() {
        guard isYourTurn, !isFinished, !isSuddenDeath, !inAwaitDouble else { return }
        turnTimer?.invalidate()
        timeLeft = 30
        scheduleTurnTimer()
    }

    // MARK: - Small helpers
    private func currency(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let absVal = abs(cents)
        return "\(sign)$\(absVal/100).\(String(format: "%02d", absVal % 100))"
    }

    // Double-or-Nothing labels
    private var doubleHeadline: String {
        if let w = engine.state.winnerIdx,
           engine.state.players.indices.contains(w) {
            let name = engine.state.players[w].display
            return "\(name) is ahead. Double or Nothing?"
        }
        return "Double or Nothing?"
    }

    private var doubleButtonTitle: String {
        let n = engine.state.doubleCount
        return n == 0 ? "Double the Pot" : "Double Again (x\(n + 1))"
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
