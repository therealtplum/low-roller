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
                    Text("• Each player contributes an equal ante to the pot before starting")
                    Text("• Players take turns in clockwise order")
                    Text("• Each player starts their turn with 7 dice")
                }
                
                // Turn Mechanics
                VStack(alignment: .leading, spacing: 12) {
                    Text("**On Your Turn**")
                        .font(.headline)
                    Text("• Tap **Roll** to roll all your remaining dice")
                    Text("• You **MUST** set aside at least one die after each roll (tap to select)")
                    Text("• Selected dice will turn green and are locked in")
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
                    Text("• Perfect score is 0 (rolling five threes)")
                }
                
                // Special Rules
                VStack(alignment: .leading, spacing: 12) {
                    Text("**Special Rules**")
                        .font(.headline)
                    Text("• **Sudden Death:** When players tie for lowest score")
                    Text("• Only tied players participate in sudden death round")
                    Text("• Sudden death continues until one clear winner emerges")
                    Text("• Winner takes the ENTIRE pot - no splitting!")
                }
                
                // Strategy Tips
                VStack(alignment: .leading, spacing: 12) {
                    Text("**Strategy Tips**")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Text("• Always set aside 3s immediately (they're worth zero!)")
                    Text("• Consider setting aside 1s and 2s early for safety")
                    Text("• You can gamble by re-rolling 4s, 5s, and 6s hoping for 3s")
                    Text("• Remember: you MUST keep at least one die each roll")
                    Text("• Watch opponents' scores to gauge your risk tolerance")
                }
                
                // Quick Examples
                VStack(alignment: .leading, spacing: 12) {
                    Text("**Example Turn**")
                        .font(.headline)
                        .foregroundColor(.green)
                    Text("Roll 1: You get [3, 3, 6, 4, 2]")
                    Text("→ Keep both 3s (0 points so far)")
                    Text("Roll 2: Rolling 3 dice, you get [1, 5, 6]")
                    Text("→ Keep the 1 (now at 1 point total)")
                    Text("Roll 3: Rolling 2 dice, you get [3, 4]")
                    Text("→ Keep the 3, re-roll the 4")
                    Text("Roll 4: Last die shows 2")
                    Text("→ Must keep it. Final score: 3 points!")
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
