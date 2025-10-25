// UI/LeaderboardList.swift
import SwiftUI

struct LeaderboardList: View {
    @ObservedObject var store: LeaderboardStore
    @Binding var metric: LeaderMetric

    @State private var pendingDelete: LeaderEntry?
    @State private var pendingReset: LeaderEntry?     // NEW

    private let startingBankroll = 10_000             // $100 in cents

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All-Time Leaderboard")
                .font(.headline)
                .padding(.horizontal)

            if store.top10(by: metric).isEmpty {
                Text("No results yet. Play a game to start the board!")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            List {
                ForEach(Array(store.top10(by: metric).enumerated()), id: \.element.id) { idx, e in
                    LeaderRow(rank: idx + 1, entry: e, metric: metric)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // NEW: Reset Balance action
                            Button {
                                pendingReset = e
                            } label: {
                                Label("Reset Balance", systemImage: "arrow.counterclockwise")
                            }
                            .tint(.orange)

                            // Existing: Remove
                            Button(role: .destructive) {
                                pendingDelete = e
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 220, maxHeight: 360)

            // Delete confirm
            .alert("Remove \(pendingDelete?.name ?? "player")?",
                   isPresented: Binding(get: { pendingDelete != nil },
                                        set: { if !$0 { pendingDelete = nil } })) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Remove", role: .destructive) {
                    if let id = pendingDelete?.id { store.removeEntry(id: id) }
                    pendingDelete = nil
                }
            } message: {
                Text("This will remove them from all leaderboard views.")
            }

            // NEW: Reset balance confirm
            .alert("Reset \(pendingReset?.name ?? "player") balance?",
                   isPresented: Binding(get: { pendingReset != nil },
                                        set: { if !$0 { pendingReset = nil } })) {
                Button("Cancel", role: .cancel) { pendingReset = nil }
                Button("Reset", role: .none) {
                    if let entry = pendingReset {
                        store.updateBankroll(name: entry.name, bankrollCents: startingBankroll)
                    }
                    pendingReset = nil
                }
            } message: {
                Text("Sets their bankroll back to $\(startingBankroll/100). Other stats remain unchanged.")
            }
        }
    }
}
