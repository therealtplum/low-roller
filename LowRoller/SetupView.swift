// UI/SetupView.swift
import SwiftUI

struct SetupView: View {
    // 7 bot-capable seats (human is separate elsewhere)
    @State private var seats: [SeatCfg] = (1...7).map { i in
        SeatCfg(isBot: false, name: "Player \(i + 1)", wagerCents: 500)
    }

    // Track all bot IDs currently used so randoms stay unique
    private var usedBotIds: Set<UUID> {
        Set(seats.compactMap { $0.botId })
    }

    var body: some View {
        List {
            ForEach(Array(seats.indices), id: \.self) { i in
                HStack {
                    // Bot toggle
                    Toggle("Bot", isOn: Binding(
                        get: { seats[i].isBot },
                        set: { newVal in
                            seats[i].isBot = newVal
                            if newVal {
                                assignRandomBot(forIndex: i, preferUnique: true)
                            } else {
                                seats[i].botId = nil
                                if seats[i].name.isEmpty { seats[i].name = "Player \(i + 1)" }
                            }
                        }
                    ))

                    if seats[i].isBot {
                        // Difficulty
                        Picker("Level", selection: Binding(
                            get: { seats[i].botLevel },
                            set: { newLevel in
                                seats[i].botLevel = newLevel
                                assignRandomBot(forIndex: i, preferUnique: true)
                            }
                        )) {
                            Text("Amateur").tag(AIBotLevel.amateur)
                            Text("Pro").tag(AIBotLevel.pro)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 220)

                        Spacer(minLength: 12)

                        // Hidden "choose opponent" dropdown
                        Menu {
                            let options = BotRoster.all(for: seats[i].botLevel)
                            ForEach(options) { bot in
                                Button(bot.name) {
                                    seats[i].botId = bot.id
                                    seats[i].name  = bot.name
                                }
                            }
                            Divider()
                            Button("Surprise me again") {
                                assignRandomBot(forIndex: i, preferUnique: true)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.crop.circle")
                                Text(seats[i].name.isEmpty ? "Choose Opponent…" : seats[i].name)
                                    .fontWeight(.semibold)
                            }
                            .contentShape(Rectangle()) // bigger tap target
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .animation(.easeInOut, value: seats[i].name)
                    } else {
                        TextField("Player name", text: Binding(
                            get: { seats[i].name },
                            set: { seats[i].name = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            // Validate name when user finishes editing
                            if !NameValidator.isValidName(seats[i].name) {
                                seats[i].name = NameValidator.sanitizeName(
                                    seats[i].name,
                                    fallback: "Player \(i + 2)"  // +2 because Player 1 is "You"
                                )
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Ensure non-bot seats have a default label
            for i in seats.indices where !seats[i].isBot && seats[i].name.isEmpty {
                seats[i].name = "Player \(i + 1)"
            }
        }
        .navigationTitle("Setup")
    }

    // MARK: - Helpers
    private func assignRandomBot(forIndex i: Int, preferUnique: Bool = true) {
        let currentId = seats[i].botId
        var avoid = usedBotIds
        if let currentId { avoid.remove(currentId) } // allow keeping same seat's current bot
        let pick = BotRoster.random(level: seats[i].botLevel, avoiding: preferUnique ? avoid : [])
        seats[i].botId = pick.id
        seats[i].name  = pick.name
    }
}
