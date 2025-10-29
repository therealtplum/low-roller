// AnalyticsSwitch.swift
import Foundation

enum AnalyticsSwitch {
    static var enabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "analytics.enabled.v1")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "analytics.enabled.v1")
        }
    }
}
