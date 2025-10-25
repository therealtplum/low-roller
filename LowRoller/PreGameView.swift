// UI/PreGameView.swift
import SwiftUI
import UIKit
import Foundation

// File-scoped so nested views (e.g., SeatRow) can use it
fileprivate func randomProWagerCents() -> Int {
    // $15–$85 in $5 steps → 15,20,...,85 (in cents)
    (Int.random(in: 3...17) * 5) * 100
}

struct PreGameView: View {
    // passed from App
    @State var youName: String
    let start: (_ engine: GameEngine) -> Void

    // Store + UI state
    @StateObject private var leaders = LeaderboardStore()
    @State private var metric: LeaderMetric = .dollars

    // lobby state
    @FocusState private var focusName: Bool
    @State private var youStart = false
    @State private var count = 2
    @State private var yourWagerCents = 500
    @State private var seats: [SeatCfg]

    // For leaderboard confirm delete / reset
    @State private var pendingDelete: LeaderEntry?
    @State private var pendingReset: LeaderEntry?

    // About sheet
    @State private var showAbout = false

    private let startingBankroll = 10_000 // $100 in cents

    // MARK: - Init
    init(youName: String, start: @escaping (_ engine: GameEngine) -> Void) {
        self.start = start
        _youName = State(initialValue: youName)

        var taken = Set<UUID>() // ensure unique bot identities across seats

        var initialSeats: [SeatCfg] = (2...8).map { i in
            var cfg = SeatCfg(
                isBot: true,                                 // default seats as bots
                botLevel: i == 2 ? .pro : .amateur,          // seat 2 starts Pro by default
                name: "",
                botId: nil,
                showPicker: false,
                wagerCents: 500                              // default amateur wager
            )

            if cfg.isBot {
                // Assign a random identity now so UI shows a real name
                let pick = BotRoster.random(level: cfg.botLevel, avoiding: taken)
                cfg.botId = pick.id
                cfg.name  = pick.name
                taken.insert(pick.id)

                // If Pro, set the random $15–$85 default wager (in $5 steps)
                if cfg.botLevel == .pro {
                    cfg.wagerCents = randomProWagerCents()
                }
            }

            return cfg
        }

        _seats = State(initialValue: initialSeats)
    }

    // Track all bot IDs currently used so randoms stay unique
    private var usedBotIds: Set<UUID> {
        Set(seats.compactMap { $0.botId })
    }

    var potPreview: Int {
        yourWagerCents + seats.prefix(count - 1).map(\.wagerCents).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            List {
                // --- You ---
                Section("You") {
                    TextField("Your name", text: $youName)
                        .focused($focusName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    Stepper(value: $yourWagerCents, in: 500...10000, step: 500) {
                        HStack { Text("Your buy-in"); Spacer(); Text("$\(yourWagerCents / 100)") }
                    }

                    Toggle("You start (random if off)", isOn: $youStart)
                }

                // --- Players ---
                Section("Players (\(count))") {
                    Stepper(value: $count, in: 2...8) { Text("Count: \(count)") }

                    ForEach(Array(seats.prefix(count - 1).indices), id: \.self) { i in
                        SeatRow(
                            seat: $seats[i],
                            usedBotIds: usedBotIds,

                            // Return the picked identity so the row can update its UI immediately
                            onSurpriseMe: { assignRandomBotReturning(forIndex: i, preferUnique: true) },

                            onPick: { bot in
                                seats[i].botId = bot.id
                                seats[i].name  = bot.name
                            },

                            // Pass the level down, pick at parent (for uniqueness), return the identity
                            onLevelChange: { newLevel in
                                let pick = assignRandomBotReturning(forIndex: i, to: newLevel, preferUnique: true)
                                // If switching to Pro, give the random default wager immediately
                                if newLevel == .pro {
                                    seats[i].wagerCents = randomProWagerCents()
                                }
                                return pick
                            },

                            onToggleBot: { isOn in
                                if isOn {
                                    let pick = assignRandomBotReturning(forIndex: i, preferUnique: true)
                                    // If this seat is Pro already, apply the random default wager
                                    if seats[i].botLevel == .pro {
                                        seats[i].wagerCents = randomProWagerCents()
                                    }
                                    // Ensure UI reflects identity immediately
                                    seats[i].botId = pick.id
                                    seats[i].name  = pick.name
                                } else {
                                    seats[i].botId = nil
                                    if seats[i].name.isEmpty { seats[i].name = "Player \(i + 2)" }
                                }
                            }
                        )
                    }
                }

                // --- Start (Pot + Button as a single row) ---
                Section {
                    VStack(spacing: 12) {
                        PotPreviewCard(
                            potCents: potPreview,
                            playerCount: count
                        )
                        .padding(.horizontal, 20) // match button edge

                        Button {
                            focusName = false
                            UIApplication.shared.endEditing()

                            var players: [Player] = []
                            players.append(Player(
                                id: UUID(),
                                display: youName.isEmpty ? "You" : youName,
                                isBot: false,
                                botLevel: nil,
                                wagerCents: yourWagerCents
                            ))

                            for s in seats.prefix(count - 1) {
                                if s.isBot {
                                    players.append(Player(
                                        id: UUID(),
                                        display: s.name.isEmpty
                                            ? (s.botLevel == .pro ? "Pro Bot" : "Amateur Bot")
                                            : s.name, // pun name if chosen/assigned
                                        isBot: true,
                                        botLevel: s.botLevel,
                                        wagerCents: s.wagerCents
                                    ))
                                } else {
                                    players.append(Player(
                                        id: UUID(),
                                        display: s.name.isEmpty ? "Player" : s.name,
                                        isBot: false,
                                        botLevel: nil,
                                        wagerCents: s.wagerCents
                                    ))
                                }
                            }

                            // Pass the same leaderboard store so bankrolls hydrate properly
                            let engine = GameEngine(players: players, youStart: youStart, leaders: leaders)
                            start(engine)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                    .font(.headline.weight(.bold))
                                Text("Start Game")
                                    .font(.headline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 3)
                            )
                            .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 20)
                    }
                    // Make the whole pot+button group a single, edge-to-edge row
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // --- All-Time Leaderboard (Top 10) ---
                Section {
                    Picker("Rank by", selection: $metric) {
                        ForEach(LeaderMetric.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    let top = leaders.top10(by: metric)
                    if top.isEmpty {
                        Text("No results yet. Play a game to start the board!")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(top.enumerated()), id: \.element.id) { (i, e) in
                            LeaderRow(rank: i + 1, entry: e, metric: metric)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    // Reset Balance
                                    Button {
                                        pendingReset = e
                                    } label: {
                                        Label("Reset Balance", systemImage: "arrow.counterclockwise")
                                    }
                                    .tint(.orange)

                                    // Remove
                                    Button(role: .destructive) {
                                        pendingDelete = e
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                } header: {
                    Text("All-Time Leaderboard")
                } footer: {
                    Text("Swipe left on a row to reset a bankroll or remove a player from the board.")
                }

                // --- About (Bottom) ---
                Section {
                    Button {
                        showAbout = true
                    } label: {
                        Label("About & Rules", systemImage: "info.circle")
                            .fontWeight(.semibold)
                    }
                }
            } // <-- close List
            .listStyle(.insetGrouped)
            .navigationTitle("Low Roller")
            .scrollDismissesKeyboard(.interactively)

            // Delete confirm
            .alert(
                "Remove \(pendingDelete?.name ?? "player")?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Remove", role: .destructive) {
                    if let id = pendingDelete?.id {
                        leaders.removeEntry(id: id)
                    }
                    pendingDelete = nil
                }
            } message: {
                Text("This will remove them from all leaderboard views.")
            }

            // Reset balance confirm
            .alert(
                "Reset \(pendingReset?.name ?? "player") balance?",
                isPresented: Binding(
                    get: { pendingReset != nil },
                    set: { if !$0 { pendingReset = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { pendingReset = nil }
                Button("Reset") {
                    if let entry = pendingReset {
                        leaders.updateBankroll(name: entry.name, bankrollCents: startingBankroll)
                    }
                    pendingReset = nil
                }
            } message: {
                Text("Sets their bankroll back to $\(startingBankroll/100). Wins and streaks remain unchanged.")
            }
            .sheet(isPresented: $showAbout) {
                AboutSheet()
            }
        }
    }

    // MARK: - Helpers (now return the chosen identity)
    @discardableResult
    private func assignRandomBotReturning(forIndex i: Int, to level: AIBotLevel, preferUnique: Bool = true) -> BotIdentity {
        var avoid = usedBotIds
        if let currentId = seats[i].botId { avoid.remove(currentId) } // allow this seat to change
        let pick = BotRoster.random(level: level, avoiding: preferUnique ? avoid : [])
        seats[i].botLevel = level
        seats[i].botId    = pick.id
        seats[i].name     = pick.name
        return pick
    }

    @discardableResult
    private func assignRandomBotReturning(forIndex i: Int, preferUnique: Bool = true) -> BotIdentity {
        assignRandomBotReturning(forIndex: i, to: seats[i].botLevel, preferUnique: preferUnique)
    }
}

// MARK: - SeatRow (sheet-based opponent picker; no context-menu warnings)
private struct SeatRow: View {
    @Binding var seat: SeatCfg
    let usedBotIds: Set<UUID>
    let onSurpriseMe: () -> BotIdentity
    let onPick: (BotIdentity) -> Void
    let onLevelChange: (AIBotLevel) -> BotIdentity
    let onToggleBot: (Bool) -> Void

    @State private var showOpponentPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Seat is a bot", isOn: Binding(
                get: { seat.isBot },
                set: { newVal in
                    onToggleBot(newVal)
                    seat.isBot = newVal
                    if newVal && (seat.name.isEmpty || seat.name.hasPrefix("Player")) {
                        let pick = onSurpriseMe()
                        seat.botId = pick.id
                        seat.name  = pick.name
                        if seat.botLevel == .pro {
                            seat.wagerCents = randomProWagerCents()
                        }
                    }
                }
            ))

            if seat.isBot {
                Picker("Level", selection: Binding(
                    get: { seat.botLevel },
                    set: { newLevel in
                        seat.botLevel = newLevel
                        let pick = onLevelChange(newLevel)
                        seat.botId = pick.id
                        seat.name  = pick.name
                    }
                )) {
                    Text("Amateur").tag(AIBotLevel.amateur)
                    Text("Pro").tag(AIBotLevel.pro)
                }
                .pickerStyle(.segmented)
                .onChange(of: seat.botLevel) { oldValue, newValue in
                    guard seat.isBot else { return }
                    if newValue == .pro {
                        seat.wagerCents = randomProWagerCents()
                    }
                }

                Button {
                    showOpponentPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                        Text(seat.name.isEmpty ? "Choose Opponent…" : seat.name)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showOpponentPicker) {
                    OpponentPickerView(
                        level: seat.botLevel,
                        onPick: { bot in
                            onPick(bot)
                            seat.botId = bot.id
                            seat.name  = bot.name
                            showOpponentPicker = false
                        },
                        onSurprise: {
                            let pick = onSurpriseMe()
                            seat.botId = pick.id
                            seat.name  = pick.name
                            showOpponentPicker = false
                        }
                    )
                    .presentationDetents([.medium, .large])
                }
            } else {
                TextField("Name", text: $seat.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            Stepper(value: $seat.wagerCents, in: 500...10000, step: 500) {
                HStack {
                    Text("Buy-in")
                    Spacer()
                    Text("$\(seat.wagerCents / 100)")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - OpponentPickerView (sheet content)
private struct OpponentPickerView: View {
    let level: AIBotLevel
    let onPick: (BotIdentity) -> Void
    let onSurprise: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSurprise()
                    } label: {
                        Label("Surprise me", systemImage: "sparkles")
                    }
                }

                Section("Opponents") {
                    ForEach(BotRoster.all(for: level)) { bot in
                        Button {
                            onPick(bot)
                        } label: {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                                Text(bot.name)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Opponent")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - AboutSheet
private struct AboutSheet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case rules = "Rules"
        case about = "About"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .rules

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return [v, b].compactMap { $0 }.joined(separator: " (\(Bundle.main.displayName)) build ")
            .isEmpty ? "—" : "\(v ?? "—") (\(b ?? "—"))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch tab {
                    case .rules:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("How to Play")
                                    .font(.title3).bold()
                                Text("""
                                • Each player begins with 7 dice and has to antes into the **Pot** at the start.
                                • Turns proceed clockwise. On your turn, tap **Roll**.
                                • After each roll, players must set aside _at least_ one die and as many as all the dice on the board.
                                • The lowest total after rolling all dice wins the pot.
                                • KEY! 3s count as 0 :)
                                • **Ties** trigger **Sudden Death**: tied players roll again until one wins.
                                • Bankroll persists between games (when enabled by your leaderboard store).
                                """)
                                .fixedSize(horizontal: false, vertical: true)

                                Divider().padding(.vertical, 8)

                                Text("House Rules (optional)")
                                    .font(.headline)
                                Text("""
                                • Double Pot on Tie: If enabled, first tie doubles the pot before roll-off.
                                • You Start: If toggled in the lobby, the human starts; otherwise random.
                                """)
                            }
                            .padding()
                        }

                    case .about:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 12) {
                                    Image(systemName: "dice.fill")
                                        .imageScale(.large)
                                    Text("Low Roller")
                                        .font(.title3).bold()
                                    Spacer()
                                }

                                if appVersion != "—" {
                                    Text("Version: \(appVersion)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Text("""
                                A minimalist dice game with buttery-smooth SwiftUI animations, playful bots, and a persistent leaderboard.
                                Built by Thomas Plummer.
                                """)
                                .fixedSize(horizontal: false, vertical: true)

                                Divider()

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Links").font(.headline)
                                    Link("GitHub Repository", destination: URL(string: "https://github.com/therealtplum/low-roller")!)
                                    Link("Developer on GitHub (@therealtplum)", destination: URL(string: "https://github.com/therealtplum")!)
                                }

                                Spacer(minLength: 8)
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private extension Bundle {
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
        object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App"
    }
}

// MARK: - PotPreviewCard
private struct PotPreviewCard: View {
    let potCents: Int
    let playerCount: Int

    @State private var pulse = false
    @State private var lastPotCents = 0

    var body: some View {
        ZStack {
            // Gradient base
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.85), Color.teal.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // Subtle glossy overlay
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.25)
                )
                .overlay(
                    // Neon stroke that breathes when pot changes
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    pulse ? .white.opacity(0.9) : .white.opacity(0.25),
                                    .white.opacity(0.05),
                                    pulse ? .white.opacity(0.6) : .white.opacity(0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .shadow(radius: pulse ? 14 : 6)
                        .animation(.easeInOut(duration: 0.6), value: pulse)
                )
                .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 10)

            // Content
            HStack(spacing: 16) {
                // Left: Symbols stack
                VStack(spacing: 10) {
                    Image(systemName: "die.face.5.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(radius: 4)

                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.leading, 6)

                // Right: Text
                VStack(alignment: .leading, spacing: 6) {
                    Text("POT")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(2)

                    // Big dollar amount
                    Text(formatCents(potCents))
#if compiler(>=5.9)
                        .contentTransition(.numericText())
#endif
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    // Subline: players + avg
                    HStack(spacing: 10) {
                        Label("\(playerCount) players", systemImage: "person.3.fill")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .labelStyle(.titleAndIcon)
                }

                Spacer(minLength: 8)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .padding(.horizontal, 16)
        .onAppear { lastPotCents = potCents }
        .onChange(of: potCents) { oldValue, newValue in
            if newValue != oldValue {
                // Pulse + light haptic on change
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { pulse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.easeOut(duration: 0.3)) { pulse = false }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pot preview")
    }
}

// MARK: - Formatting
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

// If you don’t already have this helper elsewhere:
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
