//
//  AnalyticsLogger.swift
//  LowRoller
//
//  Created by Thomas Plummer on 10/26/25.
//


// Analytics/AnalyticsLogger.swift
import Foundation
import os

final class AnalyticsLogger {
    static let shared = AnalyticsLogger()

    // Tune these to your liking
    private let flushInterval: TimeInterval = 2.0
    private let maxBufferCount = 64
    private let rotateAtBytes: Int64 = 5 * 1024 * 1024 // 5 MB per file

    private let queue = DispatchQueue(label: "analytics.logger.queue", qos: .utility)
    private var buffer: [AnalyticsEvent] = []
    private var fileHandle: FileHandle?
    private var currentFileURL: URL!
    private var bytesWritten: Int64 = 0
    private var flushTimer: DispatchSourceTimer?

    private init() {
        queue.sync {
            self.currentFileURL = Self.makeCurrentLogURL()
            self.openFile()
            self.startTimer()
        }
    }

    deinit { shutdown() }

    func log(_ event: AnalyticsEvent) {
        queue.async {
            self.buffer.append(event)
            if self.buffer.count >= self.maxBufferCount { self.flush_locked() }
        }
    }

    func flush() {
        queue.async { self.flush_locked() }
    }

    func shutdown() {
        queue.sync {
            self.flushTimer?.cancel()
            self.flush_locked()
            try? self.fileHandle?.close()
            self.fileHandle = nil
        }
    }

    // MARK: - Export helper
    func allLocalLogFiles() -> [URL] {
        let dir = Self.logsDir()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Private
    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        t.setEventHandler { [weak self] in self?.flush_locked() }
        t.resume()
        flushTimer = t
    }

    private func openFile() {
        if !FileManager.default.fileExists(atPath: currentFileURL.path) {
            FileManager.default.createFile(atPath: currentFileURL.path, contents: nil)
            bytesWritten = 0
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: currentFileURL.path)
            bytesWritten = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        fileHandle = try? FileHandle(forWritingTo: currentFileURL)
        _ = try? fileHandle?.seekToEnd()
    }

    private func flush_locked() {
        guard !buffer.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        data.reserveCapacity(1024 * buffer.count)

        for ev in buffer {
            if let line = try? encoder.encode(ev) {
                data.append(line)
                data.append(0x0A) // newline
            }
        }
        buffer.removeAll(keepingCapacity: true)

        if shouldRotate(additionalBytes: Int64(data.count)) {
            rotate_locked()
        }
        fileHandle?.write(data)
        bytesWritten += Int64(data.count)
        try? fileHandle?.synchronize() // still cheap; can remove if you want ultraspeed
    }

    private func shouldRotate(additionalBytes: Int64) -> Bool {
        bytesWritten + additionalBytes >= rotateAtBytes
    }

    private func rotate_locked() {
        try? fileHandle?.close()
        let ts = Int(Date().timeIntervalSince1970)
        let rotated = Self.logsDir().appendingPathComponent("events.\(ts).jsonl")
        try? FileManager.default.moveItem(at: currentFileURL, to: rotated)
        currentFileURL = Self.makeCurrentLogURL()
        openFile()
    }

    private static func logsDir() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Analytics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func makeCurrentLogURL() -> URL {
        logsDir().appendingPathComponent("events.current.jsonl")
    }
}
