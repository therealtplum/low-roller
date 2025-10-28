//
//  AnalyticsSwitch.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/26/25.
//


// Analytics/AnalyticsSwitch.swift
import Foundation

enum AnalyticsSwitch {
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "analytics.enabled.v1") }
        set { UserDefaults.standard.set(newValue, forKey: "analytics.enabled.v1") }
    }
}

extension AnalyticsLogger {
    func logIfEnabled(_ event: AnalyticsEvent) {
        guard AnalyticsSwitch.enabled else { return }
        log(event)
    }
}