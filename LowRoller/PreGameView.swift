// UI/PreGameView.swift
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

    // Leaderboard actions
    @State private var pendingDelete: LeaderEntry?
    @State private var pendingReset: LeaderEntry?

    // About sheet
    @State private var showAbout = false

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
        for i in 2...8 {
            var cfg = SeatCfg(
                isBot: true,
                botLevel: (i == 2) ? .pro : .amateur,
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

    private var usedBotIds: Set<UUID> {
        Set(seats.compactMap { $0.botId })
    }

    var potPreview: Int {
        let others = seats.prefix(max(0, count - 1)).map(\.wagerCents).reduce(0, +)
        return yourWagerCents + others
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                // --- YOU ---
                Section {
                    TextField("Your name", text: $youName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !NameValidator.isValidName(youName) {
                                youName = NameValidator.sanitizeName(youName, fallback: "You")
                            }
                        }

                    Stepper(value: $yourWagerCents, in: 500...10000, step: 500) {
                        HStack { Text("Your buy-in"); Spacer(); Text("$\(yourWagerCents / 100)") }
                    }

                    Toggle("You start (random if off)", isOn: $youStart)
                } header: {
                    Text("You")
                }

                // --- PLAYERS ---
                Section {
                    Stepper(value: $count, in: 2...8) {
                        Text("Count: \(count)")
                    }

                    // Break up complex generics so the compiler is happy
                    let seatsToShow = Array(seats.prefix(max(0, count - 1)))
                    ForEach(Array(seatsToShow.enumerated()), id: \.offset) { pair in
                        let i = pair.offset
                        SeatRow(
                            seat: $seats[i],
                            usedBotIds: usedBotIds,
                            onSurpriseMe: { assignRandomBotReturning(forIndex: i, preferUnique: true) },
                            onPick: { bot in
                                seats[i].botId = bot.id
                                seats[i].name  = bot.name
                            },
                            onLevelChange: { newLevel in
                                let pick = assignRandomBotReturning(forIndex: i, to: newLevel, preferUnique: true)
                                if newLevel == .pro {
                                    seats[i].wagerCents = randomProWagerCents()
                                }
                                return pick
                            },
                            onToggleBot: { isOn in
                                if isOn {
                                    let pick = assignRandomBotReturning(forIndex: i, preferUnique: true)
                                    if seats[i].botLevel == .pro {
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
                    }
                } header: {
                    Text("Players (\(count))")
                }

                // --- POT & START BUTTON ---
                Section {
                    VStack(spacing: 12) {
                        PotPreviewCard(potCents: potPreview, playerCount: count)
                            .padding(.horizontal, 20)
                        Button {
                            focusName = false
                            UIApplication.shared.endEditing()

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

                            let engine = GameEngine(players: players, youStart: youStart, leaders: leaders)
                            start(engine)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("Start Game").font(.headline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                            )
                            .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 20)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                // --- LEADERBOARD ---
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
                    } else {
                        ForEach(Array(top.enumerated()), id: \.element.id) { (i, e) in
                            LeaderRow(rank: i + 1, entry: e, metric: metric)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        pendingDelete = e
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    Button {
                                        pendingReset = e
                                    } label: {
                                        Label("Reset Balance", systemImage: "arrow.counterclockwise")
                                    }.tint(.orange)
                                }
                        }
                    }
                } header: {
                    Text("All-Time Leaderboard")
                } footer: {
                    Text("Swipe left to reset or remove a player.")
                }

                // --- ABOUT ---
                Section {
                    Button {
                        showAbout = true
                    } label: {
                        Label("About & Rules", systemImage: "info.circle")
                            .fontWeight(.semibold)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Low Roller")
            .scrollDismissesKeyboard(.interactively)
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
            .sheet(isPresented: $showAbout) {
                AboutSheet()
            }
        }
    }

    // MARK: - Helpers
    @discardableResult
    private func assignRandomBotReturning(forIndex i: Int, to level: AIBotLevel, preferUnique: Bool = true) -> BotIdentity {
        var avoid = usedBotIds
        if let currentId = seats[i].botId { avoid.remove(currentId) }
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

// MARK: - SeatRow
struct SeatRow: View {
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
                    set: { newValue in
                        seat.botLevel = newValue
                        let pick = onLevelChange(newValue)
                        seat.botId = pick.id
                        seat.name  = pick.name
                    }
                )) {
                    Text("Amateur").tag(AIBotLevel.amateur)
                    Text("Pro").tag(AIBotLevel.pro)
                }
                .pickerStyle(.segmented)

                Button {
                    showOpponentPicker = true
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text(seat.name.isEmpty ? "Choose Opponent…" : seat.name)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(.secondary)
                    }
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

// MARK: - OpponentPickerView
private struct OpponentPickerView: View {
    let level: AIBotLevel
    let onPick: (BotIdentity) -> Void
    let onSurprise: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { onSurprise() } label: {
                        Label("Surprise me", systemImage: "sparkles")
                    }
                } header: {
                    Text("Actions")
                }

                Section {
                    ForEach(BotRoster.all(for: level)) { bot in
                        Button {
                            onPick(bot)
                        } label: {
                            HStack {
                                Image(systemName: "person.fill").foregroundStyle(.secondary)
                                Text(bot.name)
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("Opponents")
                }
            }
            .navigationTitle("Choose Opponent")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - AboutSheet (Settings hidden in Release)
private struct AboutSheet: View {
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

    @AppStorage("analytics.enabled.v1") private var analyticsOn: Bool = true

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let v, let b { return "\(v) (\(b))" }
        if let v { return v }
        if let b { return "(\(b))" }
        return "—"
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch tab {
                    case .rules:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                GameRulesView()
                            }.padding()
                        }
                    case .about:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 12) {
                                    Image(systemName: "dice.fill").imageScale(.large)
                                    Text("Low Roller").font(.title3).bold()
                                    Spacer()
                                }
                                if appVersion != "—" {
                                    Text("Version: \(appVersion)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text("A minimalist dice game built in SwiftUI by Thomas Plummer.")
                                Divider()
                                Link("GitHub Repository", destination: URL(string: "https://github.com/therealtplum/low-roller")!)
                                Link("Developer (@therealtplum)", destination: URL(string: "https://github.com/therealtplum")!)
                            }.padding()
                        }
                    #if DEBUG
                    case .settings:
                        NavigationStack {
                            List {
                                Section {
                                    Toggle(isOn: $analyticsOn) {
                                        VStack(alignment: .leading) {
                                            Text("Enable Analytics")
                                            Text("Write lightweight JSONL event logs on-device.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .onChange(of: analyticsOn) { _, newVal in
                                        AnalyticsSwitch.enabled = newVal
                                    }

                                    NavigationLink("Export Event Logs") {
                                        AnalyticsExportView(onExportURL: nil)
                                    }
                                } header: {
                                    Text("Analytics")
                                } footer: {
                                    Text("Export logs via Share Sheet to Files, AirDrop, or other apps.")
                                        .font(.footnote)
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
            }
            .navigationTitle("About")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - PotPreviewCard
struct PotPreviewCard: View {
    let potCents: Int
    let playerCount: Int

    @State private var pulse = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.green.opacity(0.85), Color.teal.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.25)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(pulse ? 0.6 : 0.2), lineWidth: 2)
                        .shadow(radius: pulse ? 14 : 6)
                        .animation(.easeInOut(duration: 0.6), value: pulse)
                )
                .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 10)

            HStack(spacing: 16) {
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("POT")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.85))
                        .tracking(2)

                    Text(formatCents(potCents))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

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
        .onChange(of: potCents) { _, _ in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { pulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.3)) { pulse = false }
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
