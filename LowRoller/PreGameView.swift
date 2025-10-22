// UI/PreGameView.swift
import SwiftUI

struct PreGameView: View {
    // incoming args from LowRollerApp
    @State var youName: String
    let start: (_ engine: GameEngine) -> Void

    // ✅ explicit init so LowRollerApp can call PreGameView(youName:start:)
    init(youName: String, start: @escaping (_ engine: GameEngine) -> Void) {
        self.start = start
        _youName = State(initialValue: youName)
    }

    // local UI state
    @State private var youStart = true
    @State private var count = 2
    @State private var yourWagerCents = 500            // $5
    @State private var seats: [SeatCfg] = (2...8).map { i in
        SeatCfg(isBot: i == 2, name: "Player \(i)", wagerCents: 500)
    }

    // derived
    var potPreview: Int {
        yourWagerCents + seats.prefix(count - 1).map(\.wagerCents).reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            Form {
                // You
                Section("You") {
                    TextField("Your name", text: $youName)

                    Stepper(value: $yourWagerCents, in: 500...10000, step: 500) {
                        HStack { Text("Your buy-in"); Spacer(); Text("$\(yourWagerCents / 100)") }
                    }

                    Toggle("You start (random if off)", isOn: $youStart)
                }

                // Players
                Section("Players (\(count))") {
                    Stepper(value: $count, in: 2...8) { Text("Count: \(count)") }

                    ForEach(Array(seats.prefix(count - 1).enumerated()), id: \.element.id) { (i, _) in
                        SeatRow(seat: $seats[i], baseHuman: yourWagerCents)
                    }
                }

                // Start
                Section {
                    HStack { Text("Pot preview"); Spacer(); Text("$\(potPreview / 100)") }

                    Button {
                        var players: [Player] = []

                        // you
                        players.append(
                            Player(
                                id: UUID(),
                                display: youName.isEmpty ? "You" : youName,
                                isBot: false,
                                botLevel: nil,
                                wagerCents: yourWagerCents
                            )
                        )

                        // others
                        for s in seats.prefix(count - 1) {
                            if s.isBot {
                                players.append(
                                    Player(
                                        id: UUID(),
                                        display: "\(s.botLevel == .pro ? "Pro" : "Amateur") 🤖",
                                        isBot: true,
                                        botLevel: s.botLevel,
                                        wagerCents: s.wagerCents
                                    )
                                )
                            } else {
                                players.append(
                                    Player(
                                        id: UUID(),
                                        display: s.name.isEmpty ? "Player" : s.name,
                                        isBot: false,
                                        botLevel: nil,
                                        wagerCents: s.wagerCents
                                    )
                                )
                            }
                        }

                        let engine = GameEngine(players: players, youStart: youStart)
                        start(engine)
                    } label: {
                        Label("Start Game", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .navigationTitle("Low Roller")
        }
    }
}

// MARK: - Seat row UI
private struct SeatRow: View {
    @Binding var seat: SeatCfg
    let baseHuman: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Seat (bot)", isOn: $seat.isBot)

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
