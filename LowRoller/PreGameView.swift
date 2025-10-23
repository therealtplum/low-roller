// UI/PreGameView.swift
import SwiftUI
import UIKit

struct PreGameView: View {
    // passed from App
    @State var youName: String
    let start: (_ engine: GameEngine) -> Void

    init(youName: String, start: @escaping (_ engine: GameEngine) -> Void) {
        self.start = start
        _youName = State(initialValue: youName)
    }

    // Store + UI state
    @StateObject private var leaders = LeaderboardStore()
    @State private var metric: LeaderMetric = .dollars

    // lobby state
    @FocusState private var focusName: Bool
    @State private var youStart = false
    @State private var count = 2
    @State private var yourWagerCents = 500
    @State private var seats: [SeatCfg] = (2...8).map { i in
        SeatCfg(isBot: i == 2, name: "Player \(i)", wagerCents: 500)
    }

    var potPreview: Int {
        yourWagerCents + seats.prefix(count - 1).map(\.wagerCents).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            Form {
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
                    ForEach(Array(seats.prefix(count - 1).enumerated()), id: \.element.id) { (i, _) in
                        SeatRow(seat: $seats[i])
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

                        var botCount = 0
                        for s in seats.prefix(count - 1) {
                            if s.isBot {
                                botCount += 1
                                let levelTitle = (s.botLevel == .pro) ? "Pro" : "Amateur"
                                let label = botCount == 1 ? "\(levelTitle)" : "\(levelTitle) #\(botCount)"
                                players.append(Player(
                                    id: UUID(),
                                    display: label,
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

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            let engine = GameEngine(players: players, youStart: youStart)
                            start(engine)
                        }
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
                        }
                    }
                } header: {
                    Text("All-Time Leaderboard")
                } footer: {
                    Text("Shows the top 10 by the selected metric.")
                }
            }
            .navigationTitle("Low Roller")
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - SeatRow remains unchanged
private struct SeatRow: View {
    @Binding var seat: SeatCfg

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Seat is a bot", isOn: $seat.isBot)

            if seat.isBot {
                Picker("Level", selection: $seat.botLevel) {
                    Text("Amateur").tag(BotLevel.amateur)
                    Text("Pro").tag(BotLevel.pro)
                }
                .pickerStyle(.segmented)
            } else {
                TextField("Name", text: $seat.name)
            }

            Stepper(value: $seat.wagerCents, in: 500...10000, step: 500) {
                HStack { Text("Buy-in"); Spacer(); Text("$\(seat.wagerCents / 100)") }
            }
        }
        .padding(.vertical, 4)
    }
}

// If you don’t already have this helper elsewhere:
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
