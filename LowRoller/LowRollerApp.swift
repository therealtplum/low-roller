// LowRollerApp.swift
import SwiftUI
import Combine
import Foundation

// Keep this single definition in the project (remove duplicates elsewhere).
extension Notification.Name {
    static let lowRollerBackToLobby = Notification.Name("lowRollerBackToLobby")
}

@main
struct LowRollerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @State private var engine: GameEngine? = nil
    @AppStorage("lowroller_name_ios") private var storedName: String = "You"

    init() {
        // Turn analytics on (optional: gate behind a Settings toggle)
        AnalyticsSwitch.enabled = true
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let engine {
                    GameView(engine: engine)
                        .onReceive(NotificationCenter.default.publisher(for: .lowRollerBackToLobby)) { _ in
                            self.engine = nil
                        }
                } else {
                    // Lobby → builds engine and hands it back
                    PreGameView(youName: storedName) { newEngine in
                        if let newName = newEngine.state.players.first?.display, !newName.isEmpty {
                            self.storedName = newName
                        }
                        self.engine = newEngine
                    }
                }
            }
            .preferredColorScheme(.dark)
            // Quiet keyboard/RTI warnings by dismissing focus on lifecycle changes
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .inactive, .background:
                    UIApplication.shared.endEditing()
                    AnalyticsLogger.shared.flush()
                default:
                    break
                }
            }
        }
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
