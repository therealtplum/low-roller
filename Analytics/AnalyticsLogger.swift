// AnalyticsLogger.swift
import Foundation
import os

final class AnalyticsLogger {
    static let shared = AnalyticsLogger()
    
    private let logger = Logger(subsystem: "com.app.analytics", category: "logger")
    
    // Configuration
    private let flushInterval: TimeInterval = 2.0
    private let maxBufferCount = 64
    private let rotateAtBytes: Int64 = 5 * 1024 * 1024 // 5 MB
    
    // Thread safety
    private let queue = DispatchQueue(label: "analytics.logger.queue", qos: .utility)
    private var buffer: [AnalyticsEvent] = []
    private var fileHandle: FileHandle?
    private var currentFileURL: URL!
    private var bytesWritten: Int64 = 0
    private var flushTimer: DispatchSourceTimer?
    private var isShuttingDown = false
    
    private init() {
        self.currentFileURL = Self.makeCurrentLogURL()
        self.openFile()
        self.startTimer()
    }
    
    deinit {
        shutdown()
    }
    
    // MARK: - Public API
    
    func log(_ event: AnalyticsEvent) {
        queue.async { [weak self] in
            guard let self = self, !self.isShuttingDown else { return }
            self.buffer.append(event)
            if self.buffer.count >= self.maxBufferCount {
                self.flushInternal()
            }
        }
    }
    
    func logIfEnabled(_ event: AnalyticsEvent) {
        guard AnalyticsSwitch.enabled else { return }
        log(event)
    }
    
    func flush() {
        queue.sync {
            self.flushInternal()
        }
    }
    
    func shutdown() {
        queue.sync {
            guard !self.isShuttingDown else { return }
            self.isShuttingDown = true
            self.flushTimer?.cancel()
            self.flushTimer = nil
            self.flushInternal()
            self.closeFile()
        }
    }
    
    func allLocalLogFiles() -> [URL] {
        let dir = Self.logsDir()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        )) ?? []
        
        return files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    // MARK: - Private Methods
    
    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        timer.setEventHandler { [weak self] in
            self?.flushInternal()
        }
        timer.resume()
        flushTimer = timer
    }
    
    private func openFile() {
        do {
            if !FileManager.default.fileExists(atPath: currentFileURL.path) {
                FileManager.default.createFile(atPath: currentFileURL.path, contents: nil)
                bytesWritten = 0
            } else {
                let attrs = try FileManager.default.attributesOfItem(atPath: currentFileURL.path)
                bytesWritten = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            }
            
            fileHandle = try FileHandle(forWritingTo: currentFileURL)
            try fileHandle?.seekToEnd()
        } catch {
            logger.error("Failed to open log file: \(error.localizedDescription)")
            fileHandle = nil
        }
    }
    
    private func closeFile() {
        do {
            try fileHandle?.close()
        } catch {
            logger.error("Failed to close file: \(error.localizedDescription)")
        }
        fileHandle = nil
    }
    
    private func flushInternal() {
        guard !buffer.isEmpty else { return }
        guard !isShuttingDown else { return }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        var data = Data()
        data.reserveCapacity(1024 * buffer.count)
        
        for event in buffer {
            do {
                let line = try encoder.encode(event)
                data.append(line)
                data.append(0x0A) // newline
            } catch {
                logger.error("Failed to encode event: \(error.localizedDescription)")
            }
        }
        
        buffer.removeAll(keepingCapacity: true)
        
        if shouldRotate(additionalBytes: Int64(data.count)) {
            rotate()
        }
        
        do {
            if fileHandle == nil {
                openFile()
            }
            
            guard let handle = fileHandle else {
                logger.error("No file handle available for writing")
                return
            }
            
            try handle.write(contentsOf: data)
            bytesWritten += Int64(data.count)
            
            // Optional: sync to disk
            if #available(iOS 13.4, *) {
                try handle.synchronize()
            }
        } catch {
            logger.error("Failed to write to log file: \(error.localizedDescription)")
            closeFile()
        }
    }
    
    private func shouldRotate(additionalBytes: Int64) -> Bool {
        return bytesWritten + additionalBytes >= rotateAtBytes
    }
    
    private func rotate() {
        closeFile()
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let rotatedURL = Self.logsDir().appendingPathComponent("events.\(timestamp).jsonl")
        
        do {
            try FileManager.default.moveItem(at: currentFileURL, to: rotatedURL)
            logger.info("Rotated log file to: \(rotatedURL.lastPathComponent)")
        } catch {
            logger.error("Failed to rotate log file: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: currentFileURL)
        }
        
        currentFileURL = Self.makeCurrentLogURL()
        bytesWritten = 0
        openFile()
    }
    
    private static func logsDir() -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logsDir = documentsDir.appendingPathComponent("Analytics", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: logsDir.path) {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        
        return logsDir
    }
    
    private static func makeCurrentLogURL() -> URL {
        return logsDir().appendingPathComponent("events.current.jsonl")
    }
}
