//
//  EconomyStore.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/24/25.
//


// Stores/EconomyStore.swift
import Foundation
import Combine

final class EconomyStore: ObservableObject {
    static let shared = EconomyStore()
    @Published private(set) var houseCents: Int = 0

    func recordBorrowPenalty(_ cents: Int) {
        guard cents > 0 else { return }
        houseCents += cents
    }

    func resetHouse() { houseCents = 0 }
}