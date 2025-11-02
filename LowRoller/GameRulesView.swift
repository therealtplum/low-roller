//
//  GameRulesView.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/28/25.
//

import SwiftUI

/// Standalone rules screen used from GameView's sheet.
struct GameRulesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text("How to Play")
                    .font(.title3).bold()

                // Setup
                SectionHeader("Setup")
                VStack(alignment: .leading, spacing: 8) {
                    Bullet("Each player contributes an ante to the pot before starting.")
                    Bullet("Players take turns in clockwise order.")
                    Bullet("Each player starts their turn with 7 dice.")
                }

                // Turn Mechanics
                SectionHeader("On Your Turn")
                VStack(alignment: .leading, spacing: 8) {
                    Bullet("Tap **Roll** to roll all your remaining dice.")
                    Bullet("You **must** set aside at least one die after each roll (tap to select).")
                    Bullet("Continue rolling remaining dice until all 7 are set aside.")
                    Bullet("Your turn ends when all dice are set aside.")
                }

                // Scoring
                SectionHeader("Scoring")
                VStack(alignment: .leading, spacing: 8) {
                    Bullet("**3s are wild** — they count as **0 points** (best value).")
                    Bullet("All other dice count as their face value:")
                    Indented("• 1 → 1 point\n• 2 → 2 points\n• 4 → 4 points\n• 5 → 5 points\n• 6 → 6 points")
                    Bullet("**Lowest total score wins** the entire pot.")
                    Bullet("Perfect score is **0** (rolling seven threes).")
                }

                // Special Rules
                SectionHeader("Special Rules")
                VStack(alignment: .leading, spacing: 8) {
                    Bullet("**Sudden Death:** If players tie for lowest score, each rolls a single die; lowest face wins the match (3 still counts as 0).")
                    Bullet("**Double or Nothing:** In some head-to-head matches, the loser may be offered a rematch for an additional ante to double the pot.")
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Small UI helpers

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct Bullet: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").bold()
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Indented: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text)
            .padding(.leading, 18)
            .foregroundStyle(.secondary)
    }
}
