import SwiftUI
import UIKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Helper
fileprivate func randomProWagerCents() -> Int {
    // $15–$85 in $5 steps → 15,20,...,85 (in cents)
    (Int.random(in: 3...17) * 5) * 100
}

// MARK: - Main Lobby View
struct PreGameView: View {
    @State var youName: String
    let start: (_ engine: GameEngine) -> Void

    // Store + UI state
    @StateObject private var leaders = LeaderboardStore()
    @State private var metric: LeaderMetric = .dollars

    // Lobby state
    @FocusState private var focusName: Bool
    @State private var youStart = false
    @State private var count = 2
    @State private var yourWagerCents = 500
    @State private var seats: [SeatCfg]
    @State private var expandedRows: Set<Int> = []

    // Leaderboard actions
    @State private var pendingDelete: LeaderEntry?
    @State private var pendingReset: LeaderEntry?

    // About sheet
    @State private var showAbout = false
    
    // Animation states
    @State private var appearAnimation = false
    @State private var buttonScale = 1.0

    private let startingBankroll = 10_000 // $100 in cents

    // MARK: - Init
    init(youName: String, start: @escaping (_ engine: GameEngine) -> Void) {
        self.start = start
        _youName = State(initialValue: youName)
        _seats = State(initialValue: PreGameView.seedSeats())
    }

    private static func seedSeats() -> [SeatCfg] {
        var taken = Set<UUID>()
        var result: [SeatCfg] = []
        for _ in 2...8 {
            var cfg = SeatCfg(
                isBot: true,
                botLevel: .pro,
                name: "",
                botId: nil,
                showPicker: false,
                wagerCents: 500
            )
            if cfg.isBot {
                let pick = BotRoster.random(level: cfg.botLevel, avoiding: taken)
                cfg.botId = pick.id
                cfg.name  = pick.name
                taken.insert(pick.id)
                if cfg.botLevel == .pro {
                    cfg.wagerCents = randomProWagerCents()
                }
            }
            result.append(cfg)
        }
        return result
    }

    // Active "in use" bot IDs. Optionally exclude the row being edited.
    private func usedBotIds(excluding idx: Int? = nil) -> Set<UUID> {
        let active = Array(seats.prefix(max(0, count - 1)))
        if let idx {
            return Set(active.enumerated().compactMap { $0.offset == idx ? nil : $0.element.botId })
        } else {
            return Set(active.compactMap { $0.botId })
        }
    }

    var potPreview: Int {
        let others = seats.prefix(max(0, count - 1)).map(\.wagerCents).reduce(0, +)
        return yourWagerCents + others
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            mainContent
                .sheet(isPresented: $showAbout) {
                    AboutSheet()
                }
                .alert("Remove \(pendingDelete?.name ?? "player")?", isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } })
                ) {
                    Button("Cancel", role: .cancel) { pendingDelete = nil }
                    Button("Remove", role: .destructive) {
                        if let id = pendingDelete?.id { leaders.removeEntry(id: id) }
                        pendingDelete = nil
                    }
                }
                .alert("Reset \(pendingReset?.name ?? "player") balance?", isPresented: Binding(
                    get: { pendingReset != nil },
                    set: { if !$0 { pendingReset = nil } })
                ) {
                    Button("Cancel", role: .cancel) { pendingReset = nil }
                    Button("Reset") {
                        if let entry = pendingReset {
                            leaders.updateBankroll(name: entry.name, bankrollCents: startingBankroll)
                        }
                        pendingReset = nil
                    }
                } message: {
                    Text("Resets their bankroll to $\(startingBankroll/100). Wins and streaks remain unchanged.")
                }
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) {
                        appearAnimation = true
                    }
                }
        }
    }
    
    // MARK: - Main Content
    private var mainContent: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.systemGray6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Enhanced header
                    headerSection
                        .padding(.top)
                    
                    // Player configuration cards
                    VStack(spacing: 16) {
                        yourPlayerCard
                        opponentsCard
                    }
                    .padding(.horizontal)
                    
                    // Enhanced pot preview and start
                    potAndStartSection
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    // Leaderboard section
                    leaderboardSection
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        ZStack {
            // Info button in top-right corner
            HStack {
                Spacer()
                Button {
                    showAbout = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .opacity(appearAnimation ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: appearAnimation)
                }
                .padding(.trailing, 8)
            }
            
            // Main header content
            VStack(spacing: 12) {
                Image(systemName: "dice.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 10)
                    .scaleEffect(appearAnimation ? 1 : 0.5)
                    .opacity(appearAnimation ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appearAnimation)
                
                Text("Low Roller")
                    .font(.largeTitle.bold())
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, .primary.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(appearAnimation ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.1), value: appearAnimation)
            }
        }
    }
    
    // MARK: - Your Player Card
    private var yourPlayerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Your Setup", systemImage: "person.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "crown.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
            
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "person.text.rectangle")
                        .foregroundStyle(.secondary)
                    TextField("Your name", text: $youName)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($focusName)
                        .onSubmit {
                            if !NameValidator.isValidName(youName) {
                                youName = NameValidator.sanitizeName(youName, fallback: "You")
                            }
                        }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                // Wager stepper with visual feedback
                HStack {
                    Label("Buy-in", systemImage: "dollarsign.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    HStack(spacing: 16) {
                        Button {
                            if yourWagerCents > 500 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    yourWagerCents -= 500
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(yourWagerCents > 500 ? .blue : .gray)
                        }
                        .disabled(yourWagerCents <= 500)
                        
                        Text("$\(yourWagerCents / 100)")
                            .font(.title3.bold())
                            .frame(minWidth: 60)
                            .animation(.none, value: yourWagerCents)
                        
                        Button {
                            if yourWagerCents < 10000 {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    yourWagerCents += 500
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(yourWagerCents < 10000 ? .blue : .gray)
                        }
                        .disabled(yourWagerCents >= 10000)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
    }
    
    // MARK: - Opponents Card
    private var opponentsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Total Players", systemImage: "person.3.fill")
                    .font(.headline)
                    .fixedSize()
                Spacer()
                
                // Player count +/- controls
                HStack(spacing: 16) {
                    Button {
                        if count > 2 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                count -= 1
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(count > 2 ? .blue : .gray)
                    }
                    .disabled(count <= 2)
                    
                    Text("\(count)")
                        .font(.title3.bold())
                        .frame(minWidth: 30)
                        .animation(.none, value: count)
                    
                    Button {
                        if count < 8 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                count += 1
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(count < 8 ? .blue : .gray)
                    }
                    .disabled(count >= 8)
                }
            }
            
            // Seats list with enhanced row styling
            VStack(spacing: 12) {
                ForEach(0..<max(0, count - 1), id: \.self) { i in
                    EnhancedSeatRow(
                        index: i,
                        seat: $seats[i],
                        usedBotIds: usedBotIds(excluding: i),
                        expandedRows: $expandedRows,
                        onSurpriseMe: { assignRandomBotReturning(forIndex: i, preferUnique: true) },
                        onPick: { bot in
                            seats[i].botId = bot.id
                            seats[i].name  = bot.name
                        },
                        onLevelChange: { newLevel in
                            // Preserve user-set wagers on level switch.
                            seats[i].botLevel = newLevel
                            // If moving to Pro from default $5, bump to a Pro-style random buy-in once.
                            if newLevel == .pro, seats[i].wagerCents == 500 {
                                seats[i].wagerCents = randomProWagerCents()
                            }
                            // Do not downshift on Pro → Amateur; keep the user's value.
                            return assignRandomBotReturning(forIndex: i, to: newLevel, preferUnique: true)
                        },
                        onToggleBot: { isOn in
                            if isOn {
                                let pick = assignRandomBotReturning(forIndex: i, preferUnique: true)
                                if seats[i].botLevel == .pro, seats[i].wagerCents == 500 {
                                    seats[i].wagerCents = randomProWagerCents()
                                }
                                seats[i].botId = pick.id
                                seats[i].name  = pick.name
                            } else {
                                seats[i].botId = nil
                                if seats[i].name.isEmpty { seats[i].name = "Player \(i + 2)" }
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: count)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
    }
    
    // MARK: - Pot and Start Section
    private var potAndStartSection: some View {
        VStack(spacing: 16) {
            EnhancedPotPreviewCard(potCents: potPreview, playerCount: count)
            
            Button {
                focusName = false
                UIApplication.shared.endEditing()
                
                // Haptic feedback
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                
                // Scale animation
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    buttonScale = 0.95
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        buttonScale = 1.0
                    }
                }

                var players: [Player] = []
                
                // Validate "You" player name
                let validatedYouName = NameValidator.isValidName(youName)
                    ? youName
                    : NameValidator.sanitizeName(youName, fallback: "You")
                
                players.append(Player(
                    id: UUID(),
                    display: validatedYouName.isEmpty ? "You" : validatedYouName,
                    isBot: false,
                    botLevel: nil,
                    wagerCents: yourWagerCents
                ))

                for s in seats.prefix(max(0, count - 1)) {
                    if s.isBot {
                        players.append(Player(
                            id: UUID(),
                            display: s.name.isEmpty
                                ? (s.botLevel == .pro ? "Pro Bot" : "Amateur Bot")
                                : s.name,
                            isBot: true,
                            botLevel: s.botLevel,
                            wagerCents: s.wagerCents
                        ))
                    } else {
                        // Validate human player names
                        let validatedName = NameValidator.isValidName(s.name)
                            ? s.name
                            : NameValidator.sanitizeName(s.name, fallback: "Player")
                        
                        players.append(Player(
                            id: UUID(),
                            display: validatedName.isEmpty ? "Player" : validatedName,
                            isBot: false,
                            botLevel: nil,
                            wagerCents: s.wagerCents
                        ))
                    }
                }

                // The game engine will handle pot distribution
                let engine = GameEngine(players: players, youStart: youStart, leaders: leaders)
                start(engine)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.title3)
                    Text("Start Game")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: .blue.opacity(0.3), radius: 10, y: 4)
            }
            .scaleEffect(buttonScale)
            .disabled(youName.isEmpty)
            .opacity(youName.isEmpty ? 0.6 : 1.0)
        }
    }
    
    // MARK: - Leaderboard Section
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header outside the card
            Label("Leaderboard", systemImage: "trophy.fill")
                .font(.headline)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.horizontal, 4)
            
            // Content inside the card
            VStack(spacing: 0) {
                // Picker inside the card at the top
                Picker("Metric", selection: $metric) {
                    ForEach(LeaderMetric.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                
                let top = leaders.top10(by: metric)
                if top.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trophy")
                            .font(.system(size: 48))
                            .foregroundStyle(.quaternary)
                        Text("No games played yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Complete a game to see stats")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .padding(.horizontal, 20)
                } else {
                    List {
                        ForEach(Array(top.enumerated()), id: \.element.id) { (i, entry) in
                            EnhancedLeaderRow(
                                rank: i + 1,
                                entry: entry,
                                metric: metric,
                                onDelete: { pendingDelete = entry },
                                onReset: { pendingReset = entry }
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollDisabled(true)
                    .frame(height: CGFloat(min(top.count, 10)) * 60)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            )
        }
    }

    // MARK: - Helper Methods
    @discardableResult
    private func assignRandomBotReturning(
        forIndex i: Int,
        to level: AIBotLevel? = nil,
        preferUnique: Bool
    ) -> BotIdentity {
        let actualLevel = level ?? seats[i].botLevel
        let avoiding: Set<UUID> = preferUnique ? usedBotIds() : Set<UUID>()
        let pick = BotRoster.random(level: actualLevel, avoiding: avoiding)
        seats[i].botId = pick.id
        seats[i].name = pick.name
        if let level { seats[i].botLevel = level }
        return pick
    }
}

// MARK: - Enhanced Seat Row (BUY-IN EDITABLE FOR AMATEUR+PRO)
struct EnhancedSeatRow: View {
    let index: Int
    @Binding var seat: SeatCfg
    let usedBotIds: Set<UUID>
    @Binding var expandedRows: Set<Int>
    
    let onSurpriseMe: () -> BotIdentity
    let onPick: (BotIdentity) -> Void
    let onLevelChange: (AIBotLevel) -> BotIdentity
    let onToggleBot: (Bool) -> Void
    
    private var isExpanded: Bool {
        expandedRows.contains(index)
    }
    
    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if expandedRows.contains(index) {
                expandedRows.remove(index)
            } else {
                expandedRows.insert(index)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                // Main content area (tappable)
                Button {
                    toggleExpanded()
                } label: {
                    HStack {
                        // Player indicator
                        Circle()
                            .fill(seat.isBot ? Color.blue.opacity(0.2) : Color.green.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .strokeBorder(seat.isBot ? Color.blue.opacity(0.4) : Color.green.opacity(0.5), lineWidth: 2)
                            )
                            .overlay(
                                Image(systemName: seat.isBot ? "cpu" : "person.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(seat.isBot ? .blue : .green)
                            )
                        
                        // Name/Type
                        VStack(alignment: .leading, spacing: 2) {
                            if seat.isBot {
                                Text(seat.name.isEmpty ? "Bot \(index + 2)" : seat.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text(seat.botLevel == .pro ? "Pro AI" : "Amateur AI")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(seat.name.isEmpty ? "Player \(index + 2)" : seat.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text("Human Player")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        Spacer()
                        
                        // Wager display
                        HStack(spacing: 4) {
                            Text("$\(seat.wagerCents / 100)")
                                .font(.subheadline.bold())
                                .foregroundStyle(.green)
                            Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green.opacity(0.7))
                        }
                        .padding(.trailing, 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Bot toggle - separated from button
                Toggle("", isOn: $seat.isBot)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .scaleEffect(0.8)
                    .frame(width: 60)
                    .onChange(of: seat.isBot) { _, newValue in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            onToggleBot(newValue)
                        }
                    }
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(seat.isBot ? Color(.systemGray6) : Color.green.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(seat.isBot ? Color.clear : Color.green.opacity(0.2), lineWidth: 1)
                    )
            )
            
            // Expanded controls
            if isExpanded {
                VStack(spacing: 12) {
                    if seat.isBot {
                        // Bot controls
                        Picker("Level", selection: $seat.botLevel) {
                            Text("Amateur").tag(AIBotLevel.amateur)
                            Text("Pro").tag(AIBotLevel.pro)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: seat.botLevel) { _, newLevel in
                            _ = onLevelChange(newLevel)
                        }
                        
                        HStack(spacing: 8) {
                            Button {
                                _ = onSurpriseMe()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Label("Random", systemImage: "shuffle")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                seat.showPicker.toggle()
                            } label: {
                                Label("Choose", systemImage: "person.crop.circle.badge.plus")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Stepper(value: $seat.wagerCents, in: 500...10000, step: 500) {
                            Label("Buy-in: $\(seat.wagerCents / 100)", systemImage: "dollarsign.circle")
                                .font(.caption)
                        }
                    } else {
                        // Human controls
                        HStack {
                            Text("Name:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Player \(index + 2) name", text: $seat.name)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline)
                        }
                        
                        HStack {
                            Text("Buy-in:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            HStack(spacing: 12) {
                                Button {
                                    if seat.wagerCents > 500 {
                                        seat.wagerCents -= 500
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(seat.wagerCents > 500 ? .green : .gray)
                                }
                                .disabled(seat.wagerCents <= 500)
                                
                                Text("$\(seat.wagerCents / 100)")
                                    .font(.subheadline.bold())
                                    .frame(minWidth: 60)
                                
                                Button {
                                    if seat.wagerCents < 10000 {
                                        seat.wagerCents += 500
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(seat.wagerCents < 10000 ? .green : .gray)
                                }
                                .disabled(seat.wagerCents >= 10000)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $seat.showPicker) {
            BotPicker(
                level: seat.botLevel,
                usedBotIds: usedBotIds,
                selection: seat.botId,
                onPick: onPick
            )
        }
    }
}

// MARK: - Enhanced Pot Preview Card
struct EnhancedPotPreviewCard: View {
    let potCents: Int
    let playerCount: Int
    
    @State private var pulse = false
    @State private var shimmer = false
    
    var body: some View {
        ZStack {
            // Background with animated gradient
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.9),
                            Color.teal.opacity(0.85),
                            Color.blue.opacity(0.8)
                        ],
                        startPoint: shimmer ? .topLeading : .bottomLeading,
                        endPoint: shimmer ? .bottomTrailing : .topTrailing
                    )
                )
                .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: shimmer)
            
            // Glass overlay
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.3)
            
            // Animated border
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .shadow(color: .white.opacity(pulse ? 0.5 : 0.2), radius: pulse ? 20 : 10)
                .animation(.easeInOut(duration: 0.8), value: pulse)
            
            HStack(spacing: 20) {
                // Icon stack with animation
                VStack(spacing: 8) {
                    ZStack {
                        Image(systemName: "die.face.5.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(pulse ? -10 : 10))
                            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
                        
                        Image(systemName: "sparkle")
                            .font(.system(size: 20))
                            .foregroundStyle(.yellow)
                            .offset(x: -20, y: -20)
                            .opacity(pulse ? 1 : 0.3)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                    }
                    
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .scaleEffect(pulse ? 1.1 : 1.0)
                        .animation(.spring(response: 1, dampingFraction: 0.5).repeatForever(autoreverses: true), value: pulse)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("TOTAL POT")
                        .font(.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(.white.opacity(0.9))
                        .tracking(3)
                    
                    Text(formatCents(potCents))
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    
                    HStack(spacing: 12) {
                        Label("\(playerCount)", systemImage: "person.3.fill")
                            .font(.footnote.bold())
                            .foregroundStyle(.white.opacity(0.95))
                        
                        Divider()
                            .frame(height: 16)
                            .overlay(Color.white.opacity(0.3))
                        
                        Label("\(formatCents(potCents / max(playerCount, 1)))/player", systemImage: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                
                Spacer(minLength: 8)
            }
            .padding(20)
        }
        .frame(height: 140)
        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
        .onAppear {
            pulse = true
            shimmer = true
        }
        .onChange(of: potCents) { _, _ in
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            
            // Bounce animation on change
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                pulse = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    pulse = true
                }
            }
        }
    }
}

// MARK: - Enhanced Leader Row
struct EnhancedLeaderRow: View {
    let rank: Int
    let entry: LeaderEntry
    let metric: LeaderMetric
    let onDelete: () -> Void
    let onReset: () -> Void
        
    private let startingBankroll = 10_000 // $100 in cents

    private var metricValue: String {
        switch metric {
        case .dollars:
            return formatCents(entry.dollarsWonCents)
        case .wins:
            return "\(entry.gamesWon) win\(entry.gamesWon == 1 ? "" : "s")"
        case .streak:
            return "\(entry.longestStreak) streak"
        case .balance:
            return formatCents(entry.bankrollCents)
        }
    }

    private var valueStyle: AnyShapeStyle {
        guard metric == .balance else { return AnyShapeStyle(.primary) }
        if entry.bankrollCents < 0 {
            return AnyShapeStyle(Color.red)
        } else if entry.bankrollCents > startingBankroll {
            return AnyShapeStyle(Color.green)
        } else {
            return AnyShapeStyle(.primary) // black in light, white in dark
        }
    }
    
    var body: some View {
        HStack {
            // Rank badge
            ZStack {
                Circle()
                    .fill(rank <= 3 ? Color.yellow.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 28, height: 28)
                Text("\(rank)")
                    .font(.caption.bold())
                    .foregroundStyle(rank <= 3 ? .orange : .secondary)
            }
            
            // Name
            Text(entry.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            
            Spacer()
            
            // Metric value
            Text(metricValue)
                .font(.subheadline)
                .bold()
                .foregroundStyle(valueStyle) // ← fixed color logic
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                onReset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .tint(.orange)
        }
    }
}

// MARK: - Supporting Types
// BotPicker is specific to this view
struct BotPicker: View {
    let level: AIBotLevel
    let usedBotIds: Set<UUID>
    let selection: UUID?
    let onPick: (BotIdentity) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                let bots = BotRoster.all(for: level)
                ForEach(bots) { bot in
                    Button {
                        onPick(bot)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                            Text(bot.name)
                                .font(.headline)
                            Spacer()
                            if bot.id == selection {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            } else if usedBotIds.contains(bot.id) {
                                Text("In Use")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose \(level == .pro ? "Pro" : "Amateur") Bot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - About Sheet (Enhanced)
struct AboutSheet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case rules = "Rules"
        case about = "About"
        #if DEBUG
        case settings = "Settings"
        #endif
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .rules
    @State private var appearAnimation = false
    @AppStorage("analytics.enabled.v1") private var analyticsOn: Bool = true

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let v, let b { return "\(v) (\(b))" }
        if let v { return v }
        if let b { return "(\(b))" }
        return "—"
    }

    // Split out content so #if DEBUG doesn't break if/else chains
    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .rules:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GameRulesView()
                }
                .padding()
                .opacity(appearAnimation ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: appearAnimation)
            }

        case .about:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // App info card
                    VStack(alignment: .center, spacing: 16) {
                        Image(systemName: "dice.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(appearAnimation ? 1 : 0.5)
                            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appearAnimation)

                        Text("Low Roller")
                            .font(.title.bold())

                        if appVersion != "—" {
                            Text("Version \(appVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("A minimalist dice game built in SwiftUI")
                            .font(.body)
                        Text("Created by Thomas Plummer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Link(destination: URL(string: "https://github.com/therealtplum/low-roller")!) {
                            HStack {
                                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)

                        Link(destination: URL(string: "https://github.com/therealtplum")!) {
                            HStack {
                                Label("Follow @therealtplum", systemImage: "person.circle")
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top)
                }
                .padding()
                .opacity(appearAnimation ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.1), value: appearAnimation)
            }

        #if DEBUG
        case .settings:
            NavigationStack {
                List {
                    Section {
                        Toggle(isOn: $analyticsOn) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Analytics")
                                Text("Write lightweight JSONL event logs on-device")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: analyticsOn) { _, newVal in
                            AnalyticsSwitch.enabled = newVal
                        }

                        NavigationLink("Export Event Logs") {
                            AnalyticsExportView()
                        }
                    } header: {
                        Text("Analytics")
                    } footer: {
                        Text("Export logs via Share Sheet to Files, AirDrop, or other apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear {
                    AnalyticsSwitch.enabled = analyticsOn
                }
            }
        #endif
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom segmented control
                HStack(spacing: 0) {
                    ForEach(Tab.allCases) { t in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                tab = t
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Text(t.rawValue)
                                    .font(.subheadline.bold())
                                    .foregroundColor(tab == t ? .primary : .secondary)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(tab == t ? Color.blue : Color.clear)
                                    .frame(height: 3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                Divider()
                    .padding(.top, 8)

                tabContent
                    .animation(.easeInOut(duration: 0.2), value: tab)
            }
            .navigationTitle("Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.bold())
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            withAnimation { appearAnimation = true }
        }
    }
}

// MARK: - Formatting Helpers
private let _currencyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f
}()

private func formatCents(_ cents: Int) -> String {
    let dollars = Double(cents) / 100.0
    return _currencyFormatter.string(from: NSNumber(value: round(dollars))) ?? "$\(Int(round(dollars)))"
}

// MARK: - Extensions
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
