//
//  AnalyticsLogger.swift
//  LowRoller
//
//  Lightweight JSONL logger with safe rotation and export support.
//  - Writes one JSON object per line to Documents/Analytics/events.current.jsonl
//  - Rotates to events.<unix_ts>.jsonl at 5 MB
//  - Flushes on a 2s timer, app lifecycle, and on demand
//  - NO re-entrancy during init (health ping deferred to next runloop)
//

import Foundation
import UIKit

public final class AnalyticsLogger {

    public static let shared = AnalyticsLogger()

    // MARK: - Config

    private let dirName = "Analytics"
    private let currentFileName = "events.current.jsonl"
    private let rotateAtBytes: Int = 5 * 1024 * 1024   // 5 MB
    private let flushInterval: TimeInterval = 2.0      // background flush cadence

    // MARK: - State

    private let q = DispatchQueue(label: "analytics.logger.queue", qos: .utility)
    private var buffer = Data()
    private var timer: DispatchSourceTimer?
    private var fileHandle: FileHandle?
    private var isShutDown = false

    private var currentURL: URL { folderURL.appendingPathComponent(currentFileName) }

    private init() {
        createFolderIfNeeded()
        openCurrentFile()
        startTimer()
        installLifecycleObservers()
        installToggleObserver()

        // Defer any log that might route back through AnalyticsLogger.shared until after init
        DispatchQueue.main.async {
            // If you keep a Log.appForegrounded() helper, you can call it here safely,
            // or use this built-in ping to prove the logger is alive:
            self.healthPing()
        }

        flushAsync()
    }

    deinit {
        shutdown()
    }

    // MARK: - Public API

    /// Primary low-level write. Accepts any dictionary that is JSON-serializable.
    /// If `bypassGate` is false and analytics are disabled, this is ignored.
    public func write(_ dict: [String: Any], bypassGate: Bool = false) {
        q.async {
            guard !self.isShutDown else { return }
            if !bypassGate && !AnalyticsSwitch.enabled { return }

            // Remove any helper flag if present
            var d = dict
            d.removeValue(forKey: "_bypassGate")

            if let data = Self.jsonLine(from: d) {
                self.buffer.append(data)
                // If buffer gets large, flush early
                if self.buffer.count >= 64 * 1024 {
                    self.flushLocked()
                }
            }
        }
    }

    /// Convenience helper: writes a simple event line with a name and optional payload.
    /// Uses the gate (respects AnalyticsSwitch.enabled).
    public func writeEvent(name: String, payload: [String: Any] = [:]) {
        var line: [String: Any] = [
            "type": name,
            "ts": ISO8601DateFormatter().string(from: Date()),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "buildNumber": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        ]
        payload.forEach { line[$0.key] = $0.value }
        write(line, bypassGate: false)
    }

    /// Force a flush synchronously (blocks the caller’s thread until complete).
    public func flush() {
        q.sync {
            self.flushLocked()
        }
    }

    /// Force a flush asynchronously.
    public func flushAsync() {
        q.async {
            self.flushLocked()
        }
    }

    /// Clean shutdown (flush + close handle + stop timer).
    public func shutdown() {
        q.sync {
            guard !self.isShutDown else { return }
            self.flushLocked()
            try? self.fileHandle?.close()
            self.fileHandle = nil
            self.timer?.cancel()
            self.timer = nil
            self.isShutDown = true
        }
    }

    /// List all .jsonl files (current + rotated), sorted by filename.
    public func allLocalLogFiles() -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return items
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Simple write to verify health. Always bypasses the analytics gate.
    public func healthPing() {
        write([
            "type": "health_ping",
            "ts": ISO8601DateFormatter().string(from: Date()),
            "_bypassGate": true
        ], bypassGate: true)
    }

    // MARK: - Internals

    private var folderURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(dirName, isDirectory: true)
    }

    private func createFolderIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: folderURL.path) {
            _ = try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
    }

    private func openCurrentFile() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: currentURL.path) {
            fm.createFile(atPath: currentURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: currentURL)
        if let handle = fileHandle {
            do {
                try handle.seekToEnd()
            } catch {
                // If seeking fails, try reopening
                fileHandle = try? FileHandle(forWritingTo: currentURL)
            }
        }
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        t.setEventHandler { [weak self] in self?.flushLocked() }
        t.resume()
        timer = t
    }

    private func installLifecycleObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appWillResignActive),  name: UIApplication.willResignActiveNotification,  object: nil)
        nc.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification,   object: nil)
        nc.addObserver(self, selector: #selector(appWillTerminate),     name: UIApplication.willTerminateNotification,        object: nil)
        nc.addObserver(self, selector: #selector(appDidBecomeActive),   name: UIApplication.didBecomeActiveNotification,      object: nil)
    }

    private func installToggleObserver() {
        NotificationCenter.default.addObserver(forName: AnalyticsSwitch.didChangeNotification, object: nil, queue: nil) { _ in
            // Always log the toggle, even if turning OFF; defer to main to avoid any chance
            // of running during static init paths.
            DispatchQueue.main.async {
                // If you have a `Log.analyticsToggled` helper, call it; otherwise write directly:
                self.writeEvent(name: "analytics_toggled", payload: ["enabled": AnalyticsSwitch.enabled])
                self.flushAsync()
            }
        }
    }

    @objc private func appWillResignActive() {
        flushAsync()
    }

    @objc private func appDidEnterBackground() {
        // Try to complete a flush during backgrounding
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "analytics.flush") {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }
        flush()
        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }
    }

    @objc private func appWillTerminate() {
        shutdown()
    }

    @objc private func appDidBecomeActive() {
        // Optional: emit a foreground ping using the public helper
        healthPing()
        flushAsync()
    }

    /// Must be called on `q`
    private func flushLocked() {
        guard buffer.count > 0 else { return }
        guard fileHandle != nil else { return }

        // Rotate if needed considering the new bytes
        rotateIfNeeded(additionalBytes: buffer.count)

        guard let handle = fileHandle else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        } catch {
            // If write fails, drop buffer to avoid growth; try to reopen handle
            buffer.removeAll(keepingCapacity: false)
            fileHandle = try? FileHandle(forWritingTo: currentURL)
        }
    }

    /// Must be called on `q`
    private func rotateIfNeeded(additionalBytes: Int) {
        do {
            let size = try currentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if size + additionalBytes >= rotateAtBytes {
                try fileHandle?.close()
                fileHandle = nil

                let ts = Int(Date().timeIntervalSince1970)
                let rotated = folderURL.appendingPathComponent("events.\(ts).jsonl")
                try FileManager.default.moveItem(at: currentURL, to: rotated)

                FileManager.default.createFile(atPath: currentURL.path, contents: nil)
                fileHandle = try FileHandle(forWritingTo: currentURL)
            }
        } catch {
            // If rotation fails, attempt to reopen the current file so logging continues
            fileHandle = try? FileHandle(forWritingTo: currentURL)
        }
    }

    private static func jsonLine(from dict: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(dict) else { return nil }
        do {
            var data = try JSONSerialization.data(withJSONObject: dict, options: [])
            data.append(0x0A) // newline
            return data
        } catch {
            return nil
        }
    }
}
