//
//  GameRulesView.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/28/25.
//


import SwiftUI

// Separate view component for the game rules
// This can be imported and used in your main ContentView
struct GameRulesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How to Play").font(.title3).bold()
                
                // Setup Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("**Setup**")
                        .font(.headline)
                    Text("• Each player contributes an ante to the pot before starting")
                    Text("• Players take turns in clockwise order")
                    Text("• Each player starts their turn with 7 dice")
                }
                
                // Turn Mechanics
                VStack(alignment: .leading, spacing: 12) {
                    Text("**On Your Turn**")
                        .font(.headline)
                    Text("• Tap **Roll** to roll all your remaining dice")
                    Text("• You **MUST** set aside at least one die after each roll (tap to select)")
                    Text("• Continue rolling remaining dice until all 7 are set aside")
                    Text("• Your turn ends when all dice are set aside")
                }
                
                // Scoring Rules
                VStack(alignment: .leading, spacing: 12) {
                    Text("**Scoring**")
                        .font(.headline)
                    Text("• **3s are wild** - they count as ZERO points (best value!)")
                    Text("• All other dice count as face value:")
                    Text("  - Die showing 1 = 1 point")
                    Text("  - Die showing 2 = 2 points")
                    Text("  - Die showing 4 = 4 points")
                    Text("  - Die showing 5 = 5 points")
                    Text("  - Die showing 6 = 6 points")
                    Text("• **LOWEST total score wins** the entire pot")
                    Text("• Perfect score is 0 (rolling seven threes)")
                }
                
                // Special Rules
                VStack(alignment: .leading, spacing: 12) {
                    Text("**Special Rules**")
                        .font(.headline)
                    Text("• **Sudden Death:** When players tie for lowest score one die will be rolled, winner take all")
                }
            }
            .padding()
        }
    }
}

// Preview for testing
struct GameRulesView_Previews: PreviewProvider {
    static var previews: some View {
        GameRulesView()
    }
}
