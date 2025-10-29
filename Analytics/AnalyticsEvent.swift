// AnalyticsEvent.swift
import Foundation

public struct AnalyticsEvent: Codable {
    public let ts: Date
    public let type: String
    public let installId: String
    public let sessionId: String
    public let appVersion: String
    public let buildNumber: String
    public let payload: [String: CodableValue]
    
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

public enum CodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([CodableValue])
    case object([String: CodableValue])
    case `null`
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
            return
        }
        
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        
        if let value = try? container.decode([String: CodableValue].self) {
            self = .object(value)
            return
        }
        
        if let value = try? container.decode([CodableValue].self) {
            self = .array(value)
            return
        }
        
        throw DecodingError.typeMismatch(
            CodableValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported type"
            )
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

public final class InstallId {
    public static let shared = InstallId()
    public let id: String
    
    private init() {
        let key = "analytics.install.id.v1"
        if let existing = UserDefaults.standard.string(forKey: key) {
            self.id = existing
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: key)
            self.id = newId
        }
    }
}

public final class SessionId {
    public static let shared = SessionId()
    public let id: String = UUID().uuidString
    private init() {}
}
