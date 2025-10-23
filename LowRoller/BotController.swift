// BotController.swift
import Foundation
import Combine

final class BotController {
    private weak var engine: GameEngine?
    private var workItem: DispatchWorkItem?

    init(bind engine: GameEngine) {
        self.engine = engine
    }

    /// Call this on appear and whenever turn/lastFaces change.
    func scheduleBotIfNeeded() {
        workItem?.cancel()
        guard let eng = engine else { return }
        guard eng.state.phase != .finished else { return }

        let cur = eng.state.players[eng.state.turnIdx]
        guard cur.isBot else { return }

        let item = DispatchWorkItem { [weak self] in
            self?.stepLoop()
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func stepLoop() {
        guard let eng = engine else { return }
        guard eng.state.phase != .finished else { return }

        let cur = eng.state.players[eng.state.turnIdx]
        guard cur.isBot else { return }

        // 1) If bot hasn't started this turn, roll.
        if eng.state.lastFaces.isEmpty && eng.state.remainingDice > 0 {
            _ = eng.roll()
        } else {
            // 2) Otherwise, let the engine decide bot picks (amateur/pro logic inside)
            _ = eng.fallbackPick()
            // 3) End the turn when all dice are placed; may advance to next player.
            _ = eng.endTurnIfDone()
        }

        // If next player is also a bot, continue; otherwise stop.
        let moreBots =
            eng.state.phase != .finished &&
            eng.state.players[eng.state.turnIdx].isBot

        if moreBots {
            let item = DispatchWorkItem { [weak self] in self?.stepLoop() }
            workItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
        }
    }
}
