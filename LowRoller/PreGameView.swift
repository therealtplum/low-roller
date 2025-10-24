import SwiftUI
import UIKit
import Foundation

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

    // For leaderboard confirm delete
    @State private var pendingDelete: LeaderEntry?

    // MARK: - Init
    init(youName: String, start: @escaping (_ engine: GameEngine) -> Void) {
        self.start = start
        _youName = State(initialValue: youName)

        // Build seats with Player 2..8 labels; make seat 2 a bot by default
        var initialSeats: [SeatCfg] = (2...8).map { i in
            SeatCfg(isBot: i == 2, name: "Player \(i)", wagerCents: 500)
        }

        // Assign pun names immediately for any seats that start as bots (unique across lobby)
        var used = Set<UUID>()
        for idx in initialSeats.indices where initialSeats[idx].isBot {
            let pick = BotRoster.random(level: initialSeats[idx].botLevel, avoiding: used)
            used.insert(pick.id)
            initialSeats[idx].botId = pick.id
            initialSeats[idx].name  = pick.name
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
                                assignRandomBotReturning(forIndex: i, to: newLevel, preferUnique: true)
                            },

                            onToggleBot: { isOn in
                                if isOn {
                                    _ = assignRandomBotReturning(forIndex: i, preferUnique: true)
                                } else {
                                    seats[i].botId = nil
                                    if seats[i].name.isEmpty { seats[i].name = "Player \(i + 2)" }
                                }
                            }
                        )
                    }
                }

                // --- Start ---
                Section {
                    HStack { Text("Pot preview"); Spacer(); Text("$\(potPreview / 100)") }

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

                        let engine = GameEngine(players: players, youStart: youStart)
                        start(engine)
                    } label: {
                        Label("Start Game", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
                    Text("Swipe left on a row to remove a player from all leaderboard views.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Low Roller")
            .scrollDismissesKeyboard(.interactively)
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

    // Provided from parent; useful if you later want to gray out taken names
    let usedBotIds: Set<UUID>

    // Callbacks from parent (return identity so the row can update immediately)
    let onSurpriseMe: () -> BotIdentity
    let onPick: (BotIdentity) -> Void
    let onLevelChange: (AIBotLevel) -> BotIdentity
    let onToggleBot: (Bool) -> Void

    @State private var showOpponentPicker = false   // ← sheet trigger

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

                // Button opens a sheet with the opponents list (no UIContextMenu involved)
                Button {
                    showOpponentPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                        Text(seat.name.isEmpty ? "Choose Opponent…" : seat.name)
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down") // affordance for a chooser
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

// If you don’t already have this helper elsewhere:
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
