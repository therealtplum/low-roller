//
//  BotController.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/22/25.
//


// Model/Bot.swift
import Foundation

final class BotController {
    private var timer: Timer?
    private var stepWork: (() -> Void)?
    private weak var engine: GameEngine?

    init(bind engine: GameEngine) { self.engine = engine }

    func scheduleBotIfNeeded() {
        guard let eng = engine else { return }
        let cur = eng.state.players[eng.state.turnIdx]
        guard cur.isBot, eng.state.phase == .normal else { return }

        stepWork = { [weak self] in
            guard let eng = self?.engine else { return }
            if eng.state.lastFaces.isEmpty && eng.state.remainingDice > 0 {
                eng.roll()
            } else {
                eng.fallbackPick()
            }
            if eng.state.players[eng.state.turnIdx].isBot && eng.state.phase == .normal {
                self?.scheduleBotIfNeeded()
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in
            self.stepWork?()
        }
    }
}