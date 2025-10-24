//
//  LeaderboardList.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/24/25.
//


// UI/LeaderboardList.swift
import SwiftUI

struct LeaderboardList: View {
    @ObservedObject var store: LeaderboardStore
    @Binding var metric: LeaderMetric
    @State private var pendingDelete: LeaderEntry?

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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { pendingDelete = e } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 220, maxHeight: 360) // give it its own scroll; tune as you like
            .alert("Remove \(pendingDelete?.name ?? "player")?",
                   isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Remove", role: .destructive) {
                    if let id = pendingDelete?.id { store.removeEntry(id: id) }
                    pendingDelete = nil
                }
            } message: {
                Text("This will remove them from all leaderboard views.")
            }
        }
    }
}