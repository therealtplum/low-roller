//
//  EventBus.swift
//  LowRoller
//
//  A tiny, replay-focused event pipeline:
//  - Immutable event envelopes with eventSeq (per match), eventId, ts
//  - Idempotency guard (seen eventIds)
//  - Tamper-evident chain via hashPrev (per match)
//  - Pluggable sinks (disk ND-JSON by default; optional network sink)
//  - Safe to call from any thread
//

import Foundation
import CryptoKit

// MARK: - Type-erased Encodable
public struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    public init<T: Encodable>(_ wrapped: T) { _encode = wrapped.encode }
    public func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

// MARK: - Event Types (extend as needed)
public enum EventType: String, Codable {
    // Lifecycle
    case match_started, match_ended
    // Turn-level
    case turn_started, dice_rolled, decision_made, turn_ended
    // Special modes
    case sudden_death_started, sudden_death_rolled, sudden_death_ended
    case double_or_nothing_started, double_or_nothing_resolved
    // Banking (generic unified form)
    case bank_posted
    // Misc/diagnostics
    case health_ping, analytics_toggled
    // If you have legacy events, keep them and map to bank_posted, etc.
}

// MARK: - Envelope
public struct EventEnvelope: Encodable {
    public let type: EventType
    public let eventId: UUID
    public let ts: String
    public let appVersion: String
    public let buildNumber: String
    public let installId: String
    public let sessionId: String
    public let matchId: String
    public let eventSeq: Int
    public let hashPrev: String?      // SHA-256 of prior *canonical* envelope in this match (base64)
    public let body: AnyEncodable

    enum CodingKeys: String, CodingKey {
        case type, eventId, ts, appVersion, buildNumber, installId, sessionId, matchId, eventSeq, hashPrev, body
    }
}

// MARK: - Sink protocol (plug in HTTP, etc.)
public protocol EventSink {
    func send(_ dataLine: Data)
}

// Default Disk sink: writes ND-JSON in Application Support/Telemetry/YYYY-MM-DD.ndjson
public final class DiskSink: EventSink {
    private let ioQ = DispatchQueue(label: "EventBus.DiskSink")
    private let dirURL: URL

    public init(subdir: String = "Telemetry") {
        let fm = FileManager.default
        let appSup = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        dirURL = appSup.appendingPathComponent(subdir, isDirectory: true)
        try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
    }

    public func send(_ dataLine: Data) {
        ioQ.async {
            let dateStr = Self.dayStamp(Date())
            let fileURL = self.dirURL.appendingPathComponent("\(dateStr).ndjson")
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: dataLine)
                    try handle.write(contentsOf: Data([0x0A])) // newline
                } catch {
                    // Swallow disk errors in production; optionally add OSLog here
                }
            }
        }
    }

    private static func dayStamp(_ date: Date) -> String {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .iso8601)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }
}

// MARK: - EventBus
public final class EventBus {
    public static let shared = EventBus()

    // Thread safety
    private let q = DispatchQueue(label: "EventBus.state", qos: .userInitiated)

    // Stateful sequencing & chaining per match
    private var seqByMatch: [String: Int] = [:]
    private var prevHashByMatch: [String: String] = [:]

    // Idempotency
    private var seenEventIds = Set<UUID>()

    // Identity
    public private(set) var installId: String
    public private(set) var sessionId: String

    // App info
    public let appVersion: String
    public let buildNumber: String

    // Sinks
    private var sinks: [EventSink] = [DiskSink()] // default to disk

    // JSON encoder (canonical, stable)
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return e
    }()

    private init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "EventBus.installId") {
            installId = saved
        } else {
            let new = UUID().uuidString
            installId = new
            defaults.set(new, forKey: "EventBus.installId")
        }
        sessionId = UUID().uuidString

        if let info = Bundle.main.infoDictionary {
            appVersion = info["CFBundleShortVersionString"] as? String ?? "1.0"
            buildNumber = info["CFBundleVersion"] as? String ?? "1"
        } else {
            appVersion = "1.0"
            buildNumber = "1"
        }
    }

    // MARK: Public API

    /// Replace or add sinks (e.g., a network poster). Disk sink remains unless removed.
    public func setSinks(_ sinks: [EventSink]) {
        q.sync { self.sinks = sinks }
    }

    /// Start a new session (e.g., on app cold start or when you want to reset)
    public func startNewSession() {
        q.sync {
            sessionId = UUID().uuidString
        }
    }

    /// Emit a fully-typed event. Safe from any thread.
    @discardableResult
    public func emit<T: Encodable>(
        _ type: EventType,
        matchId: String,
        body: T,
        explicitEventId: UUID? = nil,
        explicitTimestamp: Date? = nil
    ) -> EventEnvelope {
        return q.sync {
            let now = explicitTimestamp ?? Date()
            let ts = Self.iso8601UTC(now)

            // Sequence per match
            let nextSeq = (seqByMatch[matchId] ?? 0) + 1
            seqByMatch[matchId] = nextSeq

            // Idempotent eventId
            let eventId = explicitEventId ?? UUID()
            guard !seenEventIds.contains(eventId) else {
                // Already emitted; craft a no-op envelope for caller (not re-sent)
                return EventEnvelope(
                    type: type,
                    eventId: eventId,
                    ts: ts,
                    appVersion: appVersion,
                    buildNumber: buildNumber,
                    installId: installId,
                    sessionId: sessionId,
                    matchId: matchId,
                    eventSeq: nextSeq,
                    hashPrev: prevHashByMatch[matchId],
                    body: AnyEncodable(body)
                )
            }
            seenEventIds.insert(eventId)

            // Prepare envelope
            let envelope = EventEnvelope(
                type: type,
                eventId: eventId,
                ts: ts,
                appVersion: appVersion,
                buildNumber: buildNumber,
                installId: installId,
                sessionId: sessionId,
                matchId: matchId,
                eventSeq: nextSeq,
                hashPrev: prevHashByMatch[matchId],
                body: AnyEncodable(body)
            )

            // Compute canonical JSON for chaining, then SHA256(base64)
            if let canonical = try? encoder.encode(envelope) {
                let digest = SHA256.hash(data: canonical)
                let b64 = Data(digest).base64EncodedString()
                prevHashByMatch[matchId] = b64
            }

            // Serialize line and ship to sinks
            do {
                let data = try encoder.encode(envelope)
                for sink in sinks { sink.send(data) }
            } catch {
                // Optionally add OSLog here
            }

            return envelope
        }
    }

    // Convenience overload when you only have a type rawValue at callsite
    @discardableResult
    public func emitRaw(
        typeRaw: String,
        matchId: String,
        body: [String: Any]
    ) -> EventEnvelope {
        // Wrap dictionary into Encodable
        struct DictBody: Encodable {
            let dict: [String: Any]
            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(JSONValue(dict))
            }
        }
        return emit(EventType(rawValue: typeRaw) ?? .health_ping, matchId: matchId, body: DictBody(dict: body))
    }

    // MARK: Helpers

    private static func iso8601UTC(_ date: Date) -> String {
        // RFC 3339 format
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date)
    }
}

// MARK: - JSONValue (Encodable Any)
private enum JSONValue: Encodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(_ any: Any) {
        switch any {
        case let v as String: self = .string(v)
        case let v as Int: self = .number(Double(v))
        case let v as Int8: self = .number(Double(v))
        case let v as Int16: self = .number(Double(v))
        case let v as Int32: self = .number(Double(v))
        case let v as Int64: self = .number(Double(v))
        case let v as UInt: self = .number(Double(v))
        case let v as UInt8: self = .number(Double(v))
        case let v as UInt16: self = .number(Double(v))
        case let v as UInt32: self = .number(Double(v))
        case let v as UInt64: self = .number(Double(v))
        case let v as Float: self = .number(Double(v))
        case let v as Double: self = .number(v)
        case let v as Bool: self = .bool(v)
        case let v as [Any]:
            self = .array(v.map { JSONValue($0) })
        case let v as [String: Any]:
            self = .object(v.mapValues { JSONValue($0) })
        case _ as NSNull:
            self = .null
        default:
            // Fallback to string for unknown types
            self = .string(String(describing: any))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let s):
            var c = encoder.singleValueContainer(); try c.encode(s)
        case .number(let n):
            var c = encoder.singleValueContainer(); try c.encode(n)
        case .bool(let b):
            var c = encoder.singleValueContainer(); try c.encode(b)
        case .object(let o):
            var c = encoder.container(keyedBy: DynamicCodingKeys.self)
            for (k, v) in o { try c.encode(v, forKey: DynamicCodingKeys(k)) }
        case .array(let a):
            var c = encoder.unkeyedContainer()
            for v in a { try c.encode(v) }
        case .null:
            var c = encoder.singleValueContainer(); try c.encodeNil()
        }
    }

    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init(_ string: String) { self.stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }
}

// MARK: - Example payload structs you’ll likely use

public struct MatchStartedPayload: Codable {
    public let players: [PlayerSeat]
    public let stakesCents: Int?
    public let tableMode: String?
    public let houseRules: [String: Bool]?
    public init(players: [PlayerSeat], stakesCents: Int? = nil, tableMode: String? = nil, houseRules: [String: Bool]? = nil) {
        self.players = players
        self.stakesCents = stakesCents
        self.tableMode = tableMode
        self.houseRules = houseRules
    }
}

public struct PlayerSeat: Codable {
    public let playerId: String
    public let name: String
    public let seat: Int
    public init(playerId: String, name: String, seat: Int) {
        self.playerId = playerId
        self.name = name
        self.seat = seat
    }
}

public struct DiceRolledPayload: Codable {
    public let turn: Int
    public let rollerPlayerId: String
    public let faces: [Int]
    public let diceBefore: Int
    public let diceAfter: Int
}

public struct DecisionMadePayload: Codable {
    public let turn: Int
    public let playerId: String
    public let picked: [Int]
    public let keptIndices: [Int]?
    public let keptTallies: [String: Int]?
    public let diceRemaining: Int
}

public struct BankPostedPayload: Codable {
    public let journalId: String
    public let txnId: String
    public let account: String        // e.g., "player:p0" or "house:pot"
    public let direction: String      // "debit" | "credit"
    public let amountCents: Int
    public let reason: String         // "buy_in" | "match_win" | …
    public let relatedMatchId: String?
    public let memo: String?
}

// MARK: - Usage (example)
// let bus = EventBus.shared
// let matchId = UUID().uuidString
// bus.emit(.match_started, matchId: matchId, body: MatchStartedPayload(players: [...], stakesCents: 500))
// bus.emit(.dice_rolled, matchId: matchId, body: DiceRolledPayload(turn: 1, rollerPlayerId: "p0", faces: [4,2,1,3,3,2,4], diceBefore: 7, diceAfter: 7))
// bus.emit(.decision_made, matchId: matchId, body: DecisionMadePayload(turn: 1, playerId: "p0", picked: [3,3], keptIndices: [3,4], keptTallies: ["3":2], diceRemaining: 5))
