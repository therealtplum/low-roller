import SwiftUI
import UniformTypeIdentifiers

/// A simple file picker for analytics logs that returns a file URL to the parent,
/// which then triggers a `.fileExporter` using a URL-backed FileDocument.
struct AnalyticsExportView: View {
    /// Parent supplies this closure; we pass back the file URL + suggested filename.
    let onExportURL: (_ url: URL, _ filename: String) -> Void

    @State private var files: [URL] = []
    @State private var errorMessage: String? = nil
    @State private var isMerging = false

    var body: some View {
        List {
            Section {
                if files.isEmpty {
                    Text("No logs found yet. Play a game to generate events.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(files, id: \.self) { url in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.body.weight(.semibold))
                                    .lineLimit(1)
                                if let sizeStr = fileSizeString(url) {
                                    Text(sizeStr).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Button("Export (.json)") {
                                exportSingle(url)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            } header: {
                Text("Event Logs")
            } footer: {
                Text("Each line is one JSON event (JSONL). Exporting as .json keeps it widely compatible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if files.count >= 2 {
                Section {
                    Button {
                        exportMerged()
                    } label: {
                        if isMerging {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Text("Export All (merged .json)")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isMerging)
                } footer: {
                    Text("Merges all JSONL files into one JSON array for easy analysis.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Flush Now") {
                    AnalyticsLogger.shared.flush()
                    reloadFiles()
                }
                Button("Refresh List") {
                    reloadFiles()
                }
            }
        }
        .navigationTitle("Analytics")
        .onAppear { reloadFiles() }
        .alert("Export Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Actions

    private func reloadFiles() {
        files = AnalyticsLogger.shared.allLocalLogFiles()
    }

    /// Export a single JSONL file as a detached temp copy (renamed .json).
    /// Avoids locking the live file and prevents preview loops.
    private func exportSingle(_ url: URL) {
        do {
            // Make sure the writer flushed before we copy.
            AnalyticsLogger.shared.flush()

            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("AnalyticsShare", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

            let base = url.deletingPathExtension().lastPathComponent
            let dest = tmpDir.appendingPathComponent("\(base).json")

            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)

            // Defer state change one tick to avoid SwiftUI AttributeGraph cycles.
            DispatchQueue.main.async {
                onExportURL(dest, "\(base).json")
            }
        } catch {
            errorMessage = "Couldn’t prepare export: \(error.localizedDescription)"
        }
    }

    /// Stream JSONL files into a single JSON array file on disk (no big in-memory buffers).
    private func exportMerged() {
        isMerging = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tmpDir = FileManager.default.temporaryDirectory
                let outURL = tmpDir.appendingPathComponent("events-merged-\(UUID().uuidString).json")

                if FileManager.default.fileExists(atPath: outURL.path) {
                    try? FileManager.default.removeItem(at: outURL)
                }
                FileManager.default.createFile(atPath: outURL.path, contents: nil)

                guard let outHandle = try? FileHandle(forWritingTo: outURL) else {
                    throw NSError(domain: "Export", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Unable to open temp file"])
                }
                defer { try? outHandle.close() }

                let openBracket = Data("[\n".utf8)
                let closeBracket = Data("\n]".utf8)
                let commaNewline = Data(",\n".utf8)
                try outHandle.write(contentsOf: openBracket)

                var wroteOne = false
                let chunkSize = 256 * 1024 // 256 KB
                let newlineByte: UInt8 = 0x0A

                for url in files {
                    try autoreleasepool {
                        guard let inHandle = try? FileHandle(forReadingFrom: url) else { return }
                        defer { try? inHandle.close() }

                        var buffer = Data()
                        buffer.reserveCapacity(chunkSize)

                        while true {
                            let chunkOpt = try inHandle.read(upToCount: chunkSize)
                            guard let chunk = chunkOpt, !chunk.isEmpty else { break }
                            buffer.append(chunk)

                            while let nlIndex = buffer.firstIndex(of: newlineByte) {
                                let line = buffer[..<nlIndex]
                                buffer.removeSubrange(buffer.startIndex...nlIndex) // drop line + '\n'
                                if !line.isEmpty {
                                    if wroteOne { try outHandle.write(contentsOf: commaNewline) }
                                    try outHandle.write(contentsOf: Data(line))
                                    wroteOne = true
                                }
                            }

                            // Defensive bound if we somehow see a super long line
                            if buffer.count > (chunkSize * 2) {
                                if !buffer.isEmpty {
                                    if wroteOne { try outHandle.write(contentsOf: commaNewline) }
                                    try outHandle.write(contentsOf: buffer)
                                    wroteOne = true
                                    buffer.removeAll(keepingCapacity: true)
                                }
                            }
                        }

                        if !buffer.isEmpty {
                            if wroteOne { try outHandle.write(contentsOf: commaNewline) }
                            try outHandle.write(contentsOf: buffer)
                            wroteOne = true
                        }
                    }
                }

                try outHandle.write(contentsOf: closeBracket)

                DispatchQueue.main.async {
                    isMerging = false
                    onExportURL(outURL, "events-merged.json")
                }
            } catch {
                DispatchQueue.main.async {
                    isMerging = false
                    errorMessage = "Failed to merge: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Utils

    private func fileSizeString(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? NSNumber else { return nil }
        let b = bytes.doubleValue
        let kb = b / 1024.0
        let mb = kb / 1024.0
        if mb >= 1.0 { return String(format: "%.2f MB", mb) }
        if kb >= 1.0 { return String(format: "%.0f KB", kb) }
        return String(format: "%.0f B", b)
    }
}
