//
//  BotController_Fixed.swift
//  LowRoller
//

import Foundation
import Combine

final class BotController: ObservableObject {
    private weak var engine: GameEngine?
    private var workItem: DispatchWorkItem?

    // Optional: publish bot activity for UI
    @Published private(set) var isProcessing = false

    init(bind engine: GameEngine) {
        self.engine = engine
    }

    deinit {
        workItem?.cancel()
    }

    /// Call this on appear and whenever turn/phase/lastFaces change.
    func scheduleBotIfNeeded() {
        workItem?.cancel()
        guard let eng = engine else { return }

        // ⬇️ ONLY drive in normal phase
        guard eng.state.phase == .normal else {
            isProcessing = false
            return
        }

        guard eng.state.phase != .finished else { isProcessing = false; return }

        let cur = eng.state.players[eng.state.turnIdx]
        guard cur.isBot else {
            isProcessing = false
            return
        }

        isProcessing = true
        let item = DispatchWorkItem { [weak self] in self?.stepLoop() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func stepLoop() {
        guard let eng = engine else {
            isProcessing = false
            return
        }

        // ⬇️ ONLY drive in normal phase
        guard eng.state.phase == .normal else {
            isProcessing = false
            return
        }

        guard eng.state.phase != .finished else {
            isProcessing = false
            return
        }

        let cur = eng.state.players[eng.state.turnIdx]
        guard cur.isBot else {
            isProcessing = false
            return
        }

        // 1) If bot hasn't started this turn, roll.
        if eng.state.lastFaces.isEmpty && eng.state.remainingDice > 0 {
            eng.roll()
        } else {
            // 2) Otherwise, let the engine decide bot picks
            eng.fallbackPick()
            // 3) End the turn when all dice are placed
            _ = eng.endTurnIfDone()
        }

        // If next player is also a bot, continue; otherwise stop.
        let moreBots =
            eng.state.phase == .normal &&
            eng.state.players[eng.state.turnIdx].isBot

        if moreBots {
            let item = DispatchWorkItem { [weak self] in self?.stepLoop() }
            workItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
        } else {
            isProcessing = false
        }
    }
}
