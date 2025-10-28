// Analytics/AnalyticsEvent.swift
import Foundation

public struct AnalyticsEvent: Codable {
    public let ts: Date
    public let type: String                 // e.g. "match_started", "bet_placed"
    public let installId: String            // stable anon id (once per install)
    public let sessionId: String            // per app launch, regenerated at cold start
    public let appVersion: String
    public let buildNumber: String
    public let payload: [String: CodableValue] // flexible payload

    public init(type: String, payload: [String: CodableValue]) {
        self.ts = Date()
        self.type = type
        self.installId = InstallId.shared.id
        self.sessionId = SessionId.shared.id
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        self.payload = payload
    }
}

// A flexible value type for arbitrary payloads without making many structs
public enum CodableValue: Codable {
    case string(String), int(Int), double(Double), bool(Bool),
         array([CodableValue]), object([String: CodableValue]), `null`

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: CodableValue].self) { self = .object(v); return }
        if let v = try? c.decode([CodableValue].self) { self = .array(v); return }
        throw DecodingError.typeMismatch(
            CodableValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported type")
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

// Stable, anonymous install id stored once
public final class InstallId {
    public static let shared = InstallId()
    public let id: String

    private init() {
        let key = "analytics.install.id.v1"
        if let existing = UserDefaults.standard.string(forKey: key) {
            self.id = existing
        } else {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: key)
            self.id = new
        }
    }
}

// A per-launch session id
public final class SessionId {
    public static let shared = SessionId()
    public let id: String = UUID().uuidString
    private init() {}
}
