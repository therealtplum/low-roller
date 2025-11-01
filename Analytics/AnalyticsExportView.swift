// AnalyticsExportView.swift
import SwiftUI
import UniformTypeIdentifiers

struct AnalyticsExportView: View {
    // Optional callback for custom handling; defaults to nil so init() is valid.
    let onExportURL: ((_ url: URL, _ filename: String) -> Void)?

    @State private var files: [URL] = []
    @State private var errorMessage: String?
    @State private var isProcessing = false

    // Share sheet
    @State private var shareItem: URL?
    @State private var showShareSheet = false

    init(onExportURL: ((_ url: URL, _ filename: String) -> Void)? = nil) {
        self.onExportURL = onExportURL
    }

    var body: some View {
        List {
            Section("Log Files") {
                if files.isEmpty {
                    ContentUnavailableView("No logs yet", systemImage: "doc.text.fill", description: Text("Play a game or toggle analytics to generate events."))
                } else {
                    ForEach(files, id: \.self) { url in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.lastPathComponent)
                                    .font(.subheadline.bold())
                                Text(fileSizeString(url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                share(url)
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Actions") {
                Button {
                    flushLogs()
                } label: {
                    Label("Flush Logs to Disk", systemImage: "arrow.down.doc")
                }
                .disabled(isProcessing)

                Button {
                    refreshFiles()
                } label: {
                    Label("Refresh List", systemImage: "arrow.clockwise")
                }
                .disabled(isProcessing)

                Button {
                    Task { await mergeAndShareAll() }
                } label: {
                    Label("Merge All & Share (.json)", systemImage: "doc.richtext")
                }
                .disabled(isProcessing || files.isEmpty)
            }
        }
        .navigationTitle("Analytics Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Defer to next runloop so any singleton init has completed.
            DispatchQueue.main.async {
                refreshFiles()
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareItem {
                ShareView(activityItems: [shareItem])
            }
        }
    }

    // MARK: - Actions

    private func refreshFiles() {
        isProcessing = true
        // Make sure anything buffered is flushed before listing
        AnalyticsLogger.shared.flush()
        files = AnalyticsLogger.shared.allLocalLogFiles()
        isProcessing = false
    }

    private func flushLogs() {
        isProcessing = true
        AnalyticsLogger.shared.flush()
        // quick bounce to show updated sizes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            refreshFiles()
        }
    }

    private func share(_ url: URL) {
        // If the caller provided a hook, use it
        if let onExportURL {
            onExportURL(url, url.lastPathComponent)
            return
        }
        // Otherwise present the system share sheet
        shareItem = url
        showShareSheet = true
    }

    private func fileSizeString(_ url: URL) -> String {
        let b = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let kb = Double(b) / 1024.0
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.2f MB", kb / 1024.0)
    }

    private func uniqueTempFile(_ name: String) -> URL {
        let ts = Int(Date().timeIntervalSince1970)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("Analytics-\(ts)-\(name)")
    }

    private func makeMergedJSON(from files: [URL]) throws -> URL {
        let outURL = uniqueTempFile("merged.json")
        let fm = FileManager.default
        fm.createFile(atPath: outURL.path, contents: Data("{\n\"events\": [\n".utf8))

        guard let outHandle = try? FileHandle(forWritingTo: outURL) else {
            throw NSError(domain: "AnalyticsExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open output file."])
        }
        defer { try? outHandle.close() }

        var isFirst = true

        for fileURL in files {
            guard let inHandle = try? FileHandle(forReadingFrom: fileURL),
                  let data = try? inHandle.readToEnd()
            else { continue }
            try? inHandle.close()

            for line in data.split(separator: 0x0A) where !line.isEmpty {
                if !isFirst { try outHandle.write(contentsOf: Data(",\n".utf8)) }
                try outHandle.write(contentsOf: line)
                isFirst = false
            }
        }

        try outHandle.write(contentsOf: Data("\n]\n}\n".utf8))
        return outURL
    }

    private func mergeAndShareAll() async {
        isProcessing = true
        AnalyticsLogger.shared.flush()
        let urls = AnalyticsLogger.shared.allLocalLogFiles()
        do {
            let merged = try makeMergedJSON(from: urls)
            share(merged)
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }
}

// MARK: - UIActivityViewController wrapper
private struct ShareView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
