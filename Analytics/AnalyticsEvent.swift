//
//  AnalyticsEvent.swift
//

import Foundation

/// Simple helpers to build consistent JSON-able dictionaries.
/// We intentionally use [String: Any] and JSONSerialization for .jsonl output.
public enum AnalyticsEvent {
    static func base(
        type: String,
        payload: [String: Any] = [:],
        bypassGate: Bool = false
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "installId": DeviceIdentity.installId,
            "buildNumber": AppIdentity.buildNumber,
            "appVersion": AppIdentity.appVersion,
            "sessionId": SessionIdentity.shared.sessionId,
            "ts": ISO8601DateFormatter.analytics.string(from: Date()),
            "type": type,
            "payload": payload
        ]
        if bypassGate {
            // mark lines that are allowed to log even if disabled
            dict["_bypassGate"] = true
        }
        return dict
    }
}

/// Common identity helpers
enum AppIdentity {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}

enum DeviceIdentity {
    private static let installIdKey = "analytics.installId.v1"
    static var installId: String = {
        let ud = UserDefaults.standard
        if let existing = ud.string(forKey: installIdKey) {
            return existing
        }
        let id = UUID().uuidString.uppercased()
        ud.set(id, forKey: installIdKey)
        return id
    }()
}

final class SessionIdentity {
    static let shared = SessionIdentity()
    let sessionId: String
    private init() { sessionId = UUID().uuidString.uppercased() }
}

extension ISO8601DateFormatter {
    static let analytics: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
