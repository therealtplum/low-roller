//
//  GameView.swift
//  LowRoller
//

import SwiftUI
import Combine
import SceneKit

struct GameView: View {
    @ObservedObject var engine: GameEngine
    @State private var botController: BotController?
    @StateObject private var leaderboard = LeaderboardStore()
    
    // MARK: - State
    @State private var selectedDice = Set<Int>()
    @State private var timeLeft = 20
    @State private var timer: Timer?
    @State private var showConfetti = false
    @State private var rollButtonScale: CGFloat = 1.0
    @State private var showingRules = false
    @State private var botRevealing = false
    @State private var lastBotRevealToken = 0
    
    @State private var isSuddenRolling = false
    @State private var suddenRollToken = 0
    
    /// Debounce UI actions so the same engine call can't fire twice quickly.
    @State private var isActionBusy = false
    
    /// Subtle shake when a normal roll lands (empty → non-empty faces).
    @State private var rollShakeToken = 0
    
    /// Visible "face roll" overlay during normal rolls.
    @State private var isRolling = false
    
    /// ZERO HERO easter egg state
    @State private var showZeroHero = false            // overlay on/off
    @State private var zeroHeroToken = 0               // animation token for overlays/glow
    @State private var zeroRoundAllThrees = true       // tracking across picks in a round
    
    /// Sudden Death result hold (to keep faces visible before winner screen)
    @State private var showSuddenRevealHold = false
    @State private var suddenRevealToken = 0
    
    // MARK: - Haptics
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    // MARK: - Animation Namespace
    @Namespace private var animation
    
    init(engine: GameEngine) { self.engine = engine }
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 0) {
                HUDView(engine: engine, timeLeft: timeLeft)
                    .padding(.top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                
                DiceStage()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal)
                
                if engine.state.phase != .finished {
                    VStack(spacing: 12) {
                        if engine.state.phase == .normal || engine.state.phase == .suddenDeath {
                            BottomInfoBar(scoreToBeat: targetScoreToBeat(), onShowRules: { showingRules = true })
                        }
                        actionButtons
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                    .transition(.opacity)
                }
            }
            
            if showConfetti {
                ConfettiView(isActive: $showConfetti)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            
            // ZERO HERO celebratory overlay
            if showZeroHero {
                ZeroHeroCelebration3D()
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showZeroHero)
                    .zIndex(10)
            }
        }
        .onAppear {
            setupGame()
            ensureTimerForCurrentTurn()   // ← start/stop based on whose turn it is
        }
        .onChange(of: engine.state.turnIdx) { _, _ in
            botController?.scheduleBotIfNeeded()
            ensureTimerForCurrentTurn()
            zeroRoundAllThrees = true
        }
        .onChange(of: engine.state.phase) { oldPhase, newPhase in
            botController?.scheduleBotIfNeeded()
            
            // Clear SD roll state when leaving SD
            if newPhase != .suddenDeath {
                isSuddenRolling = false
                suddenRollToken &+= 1
            }
            
            // Linger on the revealed dice when Sudden Death ends
            if oldPhase == .suddenDeath && newPhase == .finished {
                showSuddenRevealHold = true
                suddenRevealToken &+= 1
                let tok = suddenRevealToken
                let linger: TimeInterval = 1.2   // tweak 0.8–1.5s to taste
                DispatchQueue.main.asyncAfter(deadline: .now() + linger) {
                    if tok == suddenRevealToken {
                        showSuddenRevealHold = false
                    }
                }
            }
        }
        .onChange(of: engine.state.lastFaces) { oldFaces, newFaces in
            // Bot reveal spinner for non-empty rolls
            if (currentPlayer?.isBot ?? false), !newFaces.isEmpty {
                lastBotRevealToken &+= 1
                let token = lastBotRevealToken
                botRevealing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    if token == lastBotRevealToken { botRevealing = false }
                }
            }
            
            // small shake when a normal roll lands (empty -> non-empty)
            if engine.state.phase == .normal, oldFaces.isEmpty, !newFaces.isEmpty {
                rollShakeToken &+= 1
            }
            
            // stop the pre-roll spinners immediately once faces arrive
            if engine.state.phase == .normal, !newFaces.isEmpty {
                isRolling = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .humanWonMatch)) { notification in
            handleMatchEnd(humanWon: notification.object as? Bool ?? false)
        }
        .sheet(isPresented: $showingRules) {
            NavigationView {
                GameRulesView()
                    .navigationTitle("How to Play")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showingRules = false }
                        }
                    }
            }
        }
    }
    
    // MARK: - Background
    @ViewBuilder
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.1, blue: 0.15),
                Color(red: 0.02, green: 0.05, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(
            GeometryReader { geometry in
                ForEach(0..<5) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.02), Color.clear],
                                center: .center,
                                startRadius: 50,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .offset(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        )
                        .animation(
                            Animation.linear(duration: Double.random(in: 20...40))
                                .repeatForever(autoreverses: true),
                            value: index
                        )
                }
            }
                .allowsHitTesting(false)
        )
    }
    
    // MARK: - Bottom info bar (locked)
    @ViewBuilder
    private func BottomInfoBar(scoreToBeat: Int?, onShowRules: @escaping () -> Void) -> some View {
        HStack {
            if let target = scoreToBeat {
                Label {
                    Text("Score to Beat: \(target)")
                        .font(.subheadline).fontWeight(.semibold)
                } icon: {
                    Image(systemName: "flag.checkered")
                }
                .foregroundColor(.yellow)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.35), lineWidth: 1)
                )
                .transition(.opacity)
            } else {
                Color.clear.frame(height: 36).cornerRadius(10)
            }
            
            Spacer()
            
            Button(action: onShowRules) {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(width: 44, height: 44)
        }
    }
    
    // MARK: - Stage switcher (only the middle changes)
    @ViewBuilder
    private func DiceStage() -> some View {
        Group {
            // Hold on Sudden Death results briefly even if engine has moved to .finished
            if engine.state.phase == .finished && showSuddenRevealHold {
                suddenDeathView
            } else {
                switch engine.state.phase {
                case .normal:
                    normalGameView
                case .suddenDeath:
                    suddenDeathView
                case .awaitDouble:
                    doubleOrNothingView
                case .finished:
                    finishedView
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: engine.state.phase)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: engine.state.lastFaces)
    }
    
    // MARK: - Normal Game View
    @ViewBuilder
    private var normalGameView: some View {
        Group {
            if isRolling {
                rollingGrid
            } else if !engine.state.lastFaces.isEmpty {
                diceGrid
                    .transition(.scale.combined(with: .opacity))
            } else if engine.state.remainingDice > 0 {
                emptyDiceIndicator
            } else {
                Color.clear.frame(height: 160)
            }
        }
    }
    
    // MARK: - Rolling Grid (pre-roll face spinners)
    @ViewBuilder
    private var rollingGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90, maximum: 110))],
            spacing: 10
        ) {
            // one spinner per die yet-to-roll (fallback to at least 1 to avoid empty grid)
            ForEach(0..<max(engine.state.remainingDice, 1), id: \.self) { _ in
                DiceRollerView(size: 90)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Dice Grid
    @ViewBuilder
    private var diceGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90, maximum: 110))],
            spacing: 10
        ) {
            ForEach(Array(engine.state.lastFaces.enumerated()), id: \.offset) { idx, face in
                DiceButton(
                    face: face,
                    isSelected: selectedDice.contains(idx),
                    size: 90,
                    shakeToken: rollShakeToken,
                    festiveToken: showZeroHero ? zeroHeroToken : 0   // add glow during Zero Hero
                ) {
                    toggleDiceSelection(at: idx)
                } onLongPress: {
                    selectAllMatchingDice(face: face)
                }
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity).animation(.spring().delay(Double(idx) * 0.05)),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
        .padding()
        // Optional: whole-grid wiggle on roll
        // .modifier(ShakeEffect(animatableData: CGFloat(rollShakeToken)))
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Empty Dice Indicator
    @ViewBuilder
    private var emptyDiceIndicator: some View {
        VStack(spacing: 12) {
            Image(systemName: "dice.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("Tap Roll to throw \(engine.state.remainingDice) dice")
                .font(.headline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }
    
    // MARK: - Action Buttons
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Group {
                if !isBotsTurn {
                    if engine.state.phase == .normal {
                        if engine.state.lastFaces.isEmpty && engine.state.remainingDice > 0 {
                            rollButton
                        } else if !engine.state.lastFaces.isEmpty {
                            pickButton
                        } else {
                            botActionPlaceholder
                        }
                    } else if engine.state.phase == .suddenDeath {
                        botActionPlaceholder
                    } else if engine.state.phase == .awaitDouble {
                        Color.clear.frame(height: 0)
                    } else {
                        Color.clear.frame(height: 0)
                    }
                } else {
                    botActionPlaceholder
                }
            }
        }
        .frame(minHeight: 56)
        .animation(.easeInOut(duration: 0.2), value: isBotsTurn)
        .animation(.easeInOut(duration: 0.2), value: engine.state.phase)
    }
    
    // MARK: - Buttons
    @ViewBuilder
    private var rollButton: some View {
        Button(action: rollDice) {
            HStack(spacing: 12) {
                Image(systemName: "dice.fill").font(.title2)
                Text("Roll \(engine.state.remainingDice) Dice").font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.blue.opacity(0.3), radius: 8, y: 4)
        }
        .scaleEffect(rollButtonScale)
        .disabled(!canRoll || (currentPlayer?.isBot ?? false) || isActionBusy)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height < -30 && canRoll &&
                        !(currentPlayer?.isBot ?? false) && !isActionBusy {
                        rollDice()
                    }
                }
        )
    }
    
    @ViewBuilder
    private var pickButton: some View {
        Button(action: pickSelectedDice) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.title2)
                Text(selectedDice.isEmpty ? "Set Aside Dice" : "Keep \(selectedDice.count)")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: selectedDice.isEmpty
                            ? [Color.gray.opacity(0.6), Color.gray.opacity(0.4)]
                            : [Color.green, Color.green.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.green.opacity(0.3), radius: 8, y: 4)
        }
        .disabled(selectedDice.isEmpty || (currentPlayer?.isBot ?? false) || isActionBusy)
        .animation(.spring(), value: selectedDice.isEmpty)
    }
    
    // MARK: - Helpers for bot placeholder text/spinner
    private var botPlaceholderText: String {
        switch engine.state.phase {
        case .suddenDeath: return "Sudden Death…"
        case .finished:    return "Game Over"
        default:           return "Bot is rolling…"
        }
    }
    
    private var showBotSpinner: Bool { engine.state.phase != .finished }
    
    // MARK: - Bot Placeholder
    private var botActionPlaceholder: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.title3)
                .foregroundColor(.white.opacity(0.85))
            
            Text(botPlaceholderText)
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            if showBotSpinner { ProgressView().progressViewStyle(.circular) }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .transition(.opacity)
    }
    
    // MARK: - Actions
    private func rollDice() {
        guard !isActionBusy else { return }
        isActionBusy = true
        
        mediumImpact.prepare()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            rollButtonScale = 0.9
        }
        
        // BEGIN pre-roll spinning UI
        isRolling = true
        
        // Let the rollers spin briefly before committing the engine roll
        let spinDuration: TimeInterval = 0.45
        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration) {
            engine.roll()
            mediumImpact.impactOccurred()
            
            // Return the roll button to normal scale
            withAnimation(.spring()) { rollButtonScale = 1.0 }
            
            // If faces didn't arrive yet via onChange (unlikely), hide the spinner shortly after
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isRolling = false
            }
            
            // Re-enable actions (buffer to avoid double taps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                isActionBusy = false
            }
            
            ensureTimerForCurrentTurn()  // ← reset+tick only for human
        }
    }
    
    private func toggleDiceSelection(at index: Int) {
        guard !(currentPlayer?.isBot ?? false) else { return }
        lightImpact.prepare()
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            if selectedDice.contains(index) {
                selectedDice.remove(index)
            } else {
                selectedDice.insert(index)
            }
        }
        lightImpact.impactOccurred()
    }
    
    private func selectAllMatchingDice(face: Int) {
        guard !(currentPlayer?.isBot ?? false) else { return }
        heavyImpact.prepare()
        
        let matchingIndices = engine.state.lastFaces.enumerated()
            .filter { $0.element == face }
            .map { $0.offset }
        
        withAnimation(.spring()) {
            matchingIndices.forEach { selectedDice.insert($0) }
        }
        heavyImpact.impactOccurred(intensity: 0.8)
    }
    
    private func pickSelectedDice() {
        guard !selectedDice.isEmpty else { return }
        guard !isActionBusy else { return }
        isActionBusy = true
        
        notificationFeedback.prepare()
        
        // Capture the faces being picked now
        let indices = Array(selectedDice).sorted()
        let facesBeingPicked = indices.map { engine.state.lastFaces[$0] }
        
        // If any picked face isn't a 3, this round can no longer be a Zero Hero
        if facesBeingPicked.contains(where: { $0 != 3 }) {
            zeroRoundAllThrees = false
        }
        
        engine.pick(indices: indices)
        
        withAnimation(.spring()) {
            selectedDice.removeAll()
        }
        notificationFeedback.notificationOccurred(.success)
        
        // After engine state updates, check if the round has ended with only 3s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // A "Zero Hero" triggers when: human turn, normal phase, no dice remaining this round, and we never picked a non-3
            if engine.state.phase == .normal,
               !(currentPlayer?.isBot ?? false),
               engine.state.remainingDice == 0,
               zeroRoundAllThrees {
                
                triggerZeroHero()
            }
            
            // Re-enable actions
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                isActionBusy = false
            }
        }
        
        ensureTimerForCurrentTurn()  // ← reset+tick only for human
    }
    
    private func triggerZeroHero() {
        zeroHeroToken &+= 1
        showZeroHero = true
        notificationFeedback.notificationOccurred(.success)
        heavyImpact.impactOccurred()
        
        let myTok = zeroHeroToken
        // Auto-hide after 4.0s if not superseded
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if myTok == zeroHeroToken {
                showZeroHero = false
            }
        }
    }
    
    // MARK: - Helpers
    private var currentPlayer: Player? {
        guard engine.state.turnIdx < engine.state.players.count else { return nil }
        return engine.state.players[engine.state.turnIdx]
    }
    
    private var isBotsTurn: Bool { currentPlayer?.isBot ?? false }
    
    private var canRoll: Bool {
        engine.state.remainingDice > 0 &&
        engine.state.lastFaces.isEmpty &&
        engine.state.phase == .normal
    }
    
    private func targetScoreToBeat() -> Int? {
        let currentIdx = engine.state.turnIdx
        let opponentScores = engine.state.players.enumerated()
            .filter { $0.offset != currentIdx }
            .map { $0.element.totalScore }
            .filter { $0 > 0 }
        
        if let minNonZero = opponentScores.min() { return minNonZero }
        
        let anyZeroOpponent = engine.state.players.enumerated()
            .contains { $0.offset != currentIdx && $0.element.totalScore == 0 }
        
        return anyZeroOpponent ? 0 : nil
    }
    
    private func setupGame() {
        if botController == nil { botController = BotController(bind: engine) }
        botController?.scheduleBotIfNeeded()
        // Timer setup moved to onAppear/ensureTimerForCurrentTurn()
    }
    
    // Unified timer controller: resets and starts/stops based on whose turn it is.
    private func ensureTimerForCurrentTurn() {
        // Always reset the visible time for a new/changed turn or action.
        timeLeft = 20
        
        // If it's a bot's turn, stop any running timer and bail.
        if isBotsTurn {
            timer?.invalidate()
            timer = nil
            return
        }
        
        // Human turn → start (or restart) a ticking timer.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeLeft > 0 {
                timeLeft -= 1
                if timeLeft == 5 {
                    notificationFeedback.notificationOccurred(.warning)
                }
            } else {
                handleTimeout()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    
    // periphery:ignore - wired from Roll/Pick soon
    // Keep old signature; now delegates to the unified helper.
    
    private func handleTimeout() {
        if !(currentPlayer?.isBot ?? false) {
            engine.handleTurnTimeout()
        }
        ensureTimerForCurrentTurn()
    }
    
    private func handleMatchEnd(humanWon: Bool) {
        timer?.invalidate()
        
        // Slight delay to reveal final dice before confetti.
        let delay: TimeInterval = humanWon ? 0.35 : 0.0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if humanWon {
                // 🔽 NEW: match-level zero-game Easter egg (even if no "all 3s" round happened)
                if let human = engine.state.players.first(where: { !$0.isBot }),
                   human.totalScore == 0 {
                    triggerZeroHero()
                }
                
                showConfetti = true
                notificationFeedback.notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    showConfetti = false
                }
            } else {
                notificationFeedback.notificationOccurred(.error)
            }
            updateLeaderboard()
        }
    }
    
    private func updateLeaderboard() {
        guard let winnerIdx = engine.state.winnerIdx else { return }
        let winner = engine.state.players[winnerIdx]
        let losers = engine.state.players.enumerated()
            .filter { $0.offset != winnerIdx }
            .map { $0.element }
        
        leaderboard.recordWinner(name: winner.display, potCents: engine.state.potCents)
        leaderboard.updateBankroll(name: winner.display, bankrollCents: winner.bankrollCents)
        
        for loser in losers {
            leaderboard.recordLoss(name: loser.display)
            leaderboard.updateBankroll(name: loser.display, bankrollCents: loser.bankrollCents)
        }
    }
    
    // MARK: - SUDDEN DEATH
    @ViewBuilder
    private var suddenDeathView: some View {
        VStack(spacing: 22) {
            Text("SUDDEN DEATH")
                .font(.largeTitle).fontWeight(.bold)
                .foregroundColor(.yellow)
                .transition(.opacity)
            
            Text("Lowest roll wins!")
                .font(.headline).foregroundColor(.white)
                .transition(.opacity)
            
            if let contenders = engine.state.suddenContenders {
                VStack(spacing: 10) {
                    ForEach(contenders, id: \.self) { idx in
                        let name = engine.state.players[idx].display
                        let revealed = engine.state.suddenRolls?[idx] ?? nil
                        HStack {
                            Text(name)
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Group {
                                if isSuddenRolling {
                                    DiceRollerView(size: 50)
                                        .matchedGeometryEffect(id: "sd-\(idx)", in: animation)
                                        .transition(.scale.combined(with: .opacity))
                                } else if let face = revealed {
                                    DiceView(face: face, size: 50, shakeToken: 0)
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    DiceView(face: 1, size: 50, shakeToken: 0)
                                        .opacity(0.25)
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .transition(.opacity)
                    }
                }
            }
            
            Button(action: startSuddenDeathAnimation) {
                HStack(spacing: 10) {
                    Image(systemName: isSuddenRolling ? "hourglass" : "dice").font(.headline)
                    Text(isSuddenRolling ? "Rolling…" : "Roll for Sudden Death!").font(.headline)
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(isSuddenRolling ? Color.gray : Color.red)
                .cornerRadius(12)
            }
            .disabled(isSuddenRolling)
            .animation(.easeInOut(duration: 0.2), value: isSuddenRolling)
        }
        .padding()
    }
    
    private func startSuddenDeathAnimation() {
        guard !isSuddenRolling else { return }
        heavyImpact.impactOccurred()
        
        isSuddenRolling = true
        suddenRollToken &+= 1
        let myToken = suddenRollToken
        
        let spinDuration: TimeInterval = 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration) {
            guard myToken == suddenRollToken else { return }
            _ = engine.rollSuddenDeath()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                guard myToken == suddenRollToken else { return }
                isSuddenRolling = false
            }
        }
    }
    
    // MARK: - Double or Nothing View
    @ViewBuilder
    private var doubleOrNothingView: some View {
        VStack(spacing: 24) {
            Text("💰 DOUBLE OR NOTHING? 💰")
                .font(.largeTitle).fontWeight(.bold)
                .foregroundColor(.yellow)
            
            Text("Risk it all for double the pot!")
                .font(.headline).foregroundColor(.white)
            
            Text("Current Pot: \(formatCurrency(engine.state.potCents))")
                .font(.title2).foregroundColor(.green)
            
            HStack(spacing: 20) {
                Button("Accept") {
                    notificationFeedback.notificationOccurred(.success)
                    engine.acceptDoubleOrNothing()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green)
                .cornerRadius(12)
                
                Button("Decline") {
                    notificationFeedback.notificationOccurred(.warning)
                    engine.declineDoubleOrNothing()
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .cornerRadius(12)
            }
        }
        .padding()
    }
    
    // MARK: - Finished View
    @ViewBuilder
    private var finishedView: some View {
        VStack(spacing: 20) {
            if let winnerIdx = engine.state.winnerIdx {
                let winner = engine.state.players[winnerIdx]
                
                Text("🎉 Game Over! 🎉")
                    .font(.largeTitle).fontWeight(.bold)
                
                Text("\(winner.display) Wins!")
                    .font(.title).foregroundColor(.yellow)
                
                Text("Pot Won: \(formatCurrency(engine.state.potCents))")
                    .font(.title2).foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Final Scores:")
                        .font(.headline).foregroundColor(.white)
                    
                    ForEach(engine.state.players.indices.sorted(by: {
                        engine.state.players[$0].totalScore < engine.state.players[$1].totalScore
                    }), id: \.self) { idx in
                        HStack {
                            Text(engine.state.players[idx].display)
                            Spacer()
                            Text("\(engine.state.players[idx].totalScore)")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(idx == winnerIdx ? .yellow : .white.opacity(0.7))
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1))
                )
            }
            
            Button(action: {
                NotificationCenter.default.post(name: .lowRollerBackToLobby, object: nil)
            }) {
                Text("Back to Lobby")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
        .padding()
    }
    
    private func formatCurrency(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = dollars.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return nf.string(from: NSNumber(value: dollars)) ?? String(format: "$%.2f", dollars)
    }
    
    // MARK: - 3D Dice Fountain (SceneKit)
    private struct DiceChaosView: UIViewRepresentable {
        let playToken: Int
        
        func makeUIView(context: Context) -> SCNView {
            let v = SCNView()
            v.backgroundColor = .clear
            v.antialiasingMode = .multisampling4X
            v.allowsCameraControl = false
            v.isPlaying = true
            v.scene = buildScene()
            context.coordinator.lastToken = playToken
            return v
        }
        
        func updateUIView(_ v: SCNView, context: Context) {
            // Rebuild when token changes so the burst replays
            if context.coordinator.lastToken != playToken {
                v.scene = buildScene()
                context.coordinator.lastToken = playToken
            }
        }
        
        func makeCoordinator() -> Coordinator { Coordinator() }
        final class Coordinator { var lastToken = 0 }
        
        // Build a fresh scene with camera, lights, floor + dice burst
        private func buildScene() -> SCNScene {
            let scene = SCNScene()
            
            // Camera
            let cam = SCNCamera()
            cam.fieldOfView = 55
            cam.wantsHDR = true
            let camNode = SCNNode()
            camNode.camera = cam
            camNode.position = SCNVector3(0, 0, 8)
            scene.rootNode.addChildNode(camNode)
            
            // Lights
            func omni(_ pos: SCNVector3, intensity: CGFloat) -> SCNNode {
                let l = SCNLight()
                l.type = .omni
                l.intensity = intensity
                let n = SCNNode()
                n.light = l
                n.position = pos
                return n
            }
            scene.rootNode.addChildNode(omni(SCNVector3(-6, 8, 10), intensity: 900))
            scene.rootNode.addChildNode(omni(SCNVector3( 6, 4,  6), intensity: 600))
            let amb = SCNLight(); amb.type = .ambient; amb.intensity = 300
            let ambNode = SCNNode(); ambNode.light = amb
            scene.rootNode.addChildNode(ambNode)
            
            // Invisible floor so dice bounce & settle
            let floor = SCNFloor()
            floor.reflectivity = 0
            floor.firstMaterial?.diffuse.contents = UIColor.clear
            let floorNode = SCNNode(geometry: floor)
            floorNode.physicsBody = .static()
            scene.rootNode.addChildNode(floorNode)
            
            // Physics
            scene.physicsWorld.gravity = SCNVector3(0, -14, 0)
            
            // Spawn a burst of dice with impulses & torque
            let count = 28
            for i in 0..<count {
                let die = makeDie(size: 0.55)
                die.position = SCNVector3(
                    Float.random(in: -2.5...2.5),
                    Float.random(in:  1.5...4.5),
                    Float.random(in: -1.0...1.5)
                )
                die.opacity = 0
                scene.rootNode.addChildNode(die)
                
                // Stagger fade-in for fountain feel
                let delay = 0.02 * Double(i)
                die.runAction(.sequence([
                    .wait(duration: delay),
                    .fadeOpacity(to: 1.0, duration: 0.05)
                ]))
                
                // Throw + spin
                die.physicsBody?.applyForce(
                    SCNVector3(
                        Float.random(in: -2.5...2.5),
                        Float.random(in: 6.0...10.0),
                        Float.random(in: -3.0...(-1.0))
                    ),
                    asImpulse: true
                )
                die.physicsBody?.applyTorque(
                    SCNVector4(
                        Float.random(in: -1.0...1.0),
                        Float.random(in: -1.0...1.0),
                        Float.random(in: -1.0...1.0),
                        Float.random(in: 8.0...16.0)
                    ),
                    asImpulse: true
                )
            }
            
            // Cleanup actions (optional)
            scene.rootNode.runAction(.sequence([
                .wait(duration: 5.5),
                .run { _ in scene.rootNode.childNodes.forEach { $0.removeAllActions() } }
            ]))
            
            return scene
        }
        
        // One beveled die with PBR material and per-face pips
        private func makeDie(size: CGFloat) -> SCNNode {
            let box = SCNBox(width: size, height: size, length: size, chamferRadius: size * 0.08)
            box.chamferSegmentCount = 4
            box.firstMaterial?.lightingModel = .physicallyBased
            box.firstMaterial?.diffuse.contents = UIColor.white
            box.firstMaterial?.roughness.contents = 0.35
            box.firstMaterial?.metalness.contents = 0.05
            
            // Materials for faces 1..6
            box.materials = (1...6).map { face in
                let m = SCNMaterial()
                m.isDoubleSided = true
                m.lightingModel = .physicallyBased
                m.diffuse.contents = pipImage(face: face)
                m.roughness.contents = 0.35
                m.metalness.contents = 0.0
                return m
            }
            
            let node = SCNNode(geometry: box)
            let body = SCNPhysicsBody.dynamic()
            body.mass = 1
            body.friction = 0.6
            body.rollingFriction = 0.9
            body.restitution = 0.25
            node.physicsBody = body
            return node
        }
        
        // Draw pip layout procedurally (no assets)
        private func pipImage(face: Int) -> UIImage {
            let size = CGSize(width: 256, height: 256)
            let r = UIGraphicsImageRenderer(size: size)
            return r.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                
                let pipColor = UIColor.black
                let pipRadius: CGFloat = 16
                func dot(_ x: CGFloat, _ y: CGFloat) {
                    let rect = CGRect(x: x - pipRadius, y: y - pipRadius, width: pipRadius*2, height: pipRadius*2)
                    ctx.cgContext.setFillColor(pipColor.cgColor)
                    ctx.cgContext.fillEllipse(in: rect)
                }
                
                let w = size.width, h = size.height
                let gx: [CGFloat] = [w*0.22, w*0.5, w*0.78]
                let gy: [CGFloat] = [h*0.22, h*0.5, h*0.78]
                
                switch face {
                case 1:
                    dot(gx[1], gy[1])
                case 2:
                    dot(gx[0], gy[0]); dot(gx[2], gy[2])
                case 3:
                    dot(gx[0], gy[0]); dot(gx[1], gy[1]); dot(gx[2], gy[2])
                case 4:
                    dot(gx[0], gy[0]); dot(gx[2], gy[0]); dot(gx[0], gy[2]); dot(gx[2], gy[2])
                case 5:
                    dot(gx[0], gy[0]); dot(gx[2], gy[0]); dot(gx[1], gy[1]); dot(gx[0], gy[2]); dot(gx[2], gy[2])
                default: // 6
                    dot(gx[0], gy[0]); dot(gx[2], gy[0]); dot(gx[0], gy[1]); dot(gx[2], gy[1]); dot(gx[0], gy[2]); dot(gx[2], gy[2])
                }
            }
        }
    }
}

// MARK: - Dice Button Component (with Zero Hero glow)
struct DiceButton: View {
    let face: Int
    let isSelected: Bool
    let size: CGFloat
    let shakeToken: Int
    let festiveToken: Int   // >0 when Zero Hero overlay is active
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            DiceView(face: face, selected: isSelected, size: size, shakeToken: shakeToken)
                .scaleEffect(isPressed ? 0.9 : 1.0)
                .animation(.spring(response: 0.2), value: isPressed)

            // Pulsing purple-gold aura when in Zero Hero celebration
            if festiveToken != 0 {
                RoundedRectangle(cornerRadius: max(8, size * 0.18))
                    .stroke(
                        LinearGradient(
                            colors: [Color.purple, Color.yellow, Color.purple],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .padding(4)
                    .shadow(color: .purple.opacity(0.6), radius: 10)
                    .shadow(color: .yellow.opacity(0.5), radius: 6)
                    .scaleEffect(pulse ? 1.06 : 0.98)
                    .animation(
                        .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                        value: pulse
                    )
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(
            minimumDuration: 0.5,
            pressing: { pressing in withAnimation { isPressed = pressing } },
            perform: onLongPress
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dice showing \(face == 3 ? "3, worth 0 points" : "\(face)")")
        .accessibilityHint(isSelected ? "Selected. Tap to deselect" : "Tap to select. Long press to select all \(face)s")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Rolling Dice Cycler (used in Sudden Death + normal pre-roll)
private struct DiceRollerView: View {
    let size: CGFloat
    @State private var face: Int = 1
    @State private var tick = 0

    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        DiceView(face: face, size: size, shakeToken: tick)
            .onReceive(timer) { _ in
                face = (face % 6) + 1
                tick += 1
            }
    }
}

// MARK: - Shake Effect for dice animations (optional whole-grid wiggle)
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(animatableData * .pi * 4) * 5
        return ProjectionTransform(
            CGAffineTransform(translationX: offset, y: 0)
        )
    }
}
