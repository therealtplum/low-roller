//
//  AnalyticsSwitch.swift
//

import Foundation

public enum AnalyticsSwitch {
    private static let key = "analytics.enabled.v1"
    private static let seededKey = "analytics.enabled.seeded.v1"

    /// Notification when the analytics toggle changes.
    public static let didChangeNotification = Notification.Name("analytics.enabled.changed")

    /// Default to ON on first run.
    private static func seedIfNeeded() {
        let ud = UserDefaults.standard
        if ud.bool(forKey: seededKey) == false && ud.object(forKey: key) == nil {
            ud.set(true, forKey: key)        // default ON
            ud.set(true, forKey: seededKey)  // mark seeded
        }
    }

    public static var enabled: Bool {
        get {
            seedIfNeeded()
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
