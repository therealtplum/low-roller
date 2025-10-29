// AnalyticsExportView_ShareSheet.swift
import SwiftUI
import UniformTypeIdentifiers

struct AnalyticsExportView: View {
    // Change the callback to be optional - we'll use share sheet instead
    let onExportURL: ((_ url: URL, _ filename: String) -> Void)?
    
    @State private var files: [URL] = []
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var isMerging = false
    @State private var isProcessing = false
    
    // Share sheet state
    @State private var shareItem: ShareItem? = nil
    @State private var showShareSheet = false
    
    var body: some View {
        List {
            // Status Section
            if let successMessage = successMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            // Files Section
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
                                
                                Text(fileSizeString(url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer(minLength: 8)
                            
                            Button("Share") {
                                shareFile(url)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isProcessing)
                        }
                    }
                }
            } header: {
                Text("Event Logs (\(files.count) files)")
            } footer: {
                Text("Tap Share to export via AirDrop, Files, or other apps")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            // Merge Section
            if files.count >= 2 {
                Section {
                    Button(action: mergeAndShare) {
                        HStack {
                            if isMerging {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                                Text("Merging...")
                            } else {
                                Image(systemName: "arrow.triangle.merge")
                                Text("Merge & Share All")
                            }
                        }
                    }
                    .disabled(isMerging || isProcessing)
                } footer: {
                    Text("Combines all log files into a single JSON array")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Actions Section
            Section("Actions") {
                Button(action: flushLogs) {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text("Flush Logs to Disk")
                    }
                }
                .disabled(isProcessing)
                
                Button(action: refreshFileList) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh File List")
                    }
                }
                .disabled(isProcessing)
                
                #if DEBUG
                Button(action: createTestEvent) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Create Test Event")
                    }
                }
                .foregroundColor(.orange)
                .disabled(isProcessing)
                #endif
            }
            
            // Debug Info Section
            #if DEBUG
            Section("Debug Info") {
                if let firstFile = files.first {
                    Text("First file path:")
                        .font(.caption)
                    Text(firstFile.path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button("Test Direct Share") {
                        testDirectShare()
                    }
                }
            }
            #endif
        }
        .navigationTitle("Analytics Export")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshFileList()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareItem = shareItem {
                ActivityView(activityItems: [shareItem.url])
                    .presentationDetents([.medium, .large])
            }
        }
    }
    
    // MARK: - Share Functions
    
    private func shareFile(_ url: URL) {
        isProcessing = true
        
        // Ensure logs are flushed
        AnalyticsLogger.shared.flush()
        
        Task {
            do {
                // Create a copy with .json extension for better compatibility
                let tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("AnalyticsShare", isDirectory: true)
                
                try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                
                let baseName = url.deletingPathExtension().lastPathComponent
                let jsonURL = tmpDir.appendingPathComponent("\(baseName).json")
                
                // Remove if exists
                try? FileManager.default.removeItem(at: jsonURL)
                
                // Copy with new extension
                try FileManager.default.copyItem(at: url, to: jsonURL)
                
                await MainActor.run {
                    self.shareItem = ShareItem(url: jsonURL, filename: "\(baseName).json")
                    self.showShareSheet = true
                    self.isProcessing = false
                    self.successMessage = "Ready to share"
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to prepare file: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func mergeAndShare() {
        guard !files.isEmpty else { return }
        
        isMerging = true
        isProcessing = true
        
        Task {
            do {
                let mergedURL = try await performMerge(files: files)
                
                await MainActor.run {
                    self.shareItem = ShareItem(url: mergedURL, filename: "analytics_merged.json")
                    self.showShareSheet = true
                    self.isMerging = false
                    self.isProcessing = false
                    self.successMessage = "Ready to share merged file"
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Merge failed: \(error.localizedDescription)"
                    self.isMerging = false
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func testDirectShare() {
        // Create a simple test file
        let testContent = """
        {"test": true, "timestamp": "\(Date.now.ISO8601Format())", "message": "Direct share test"}
        """
        
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_share.json")
        
        do {
            try testContent.write(to: tmpURL, atomically: true, encoding: .utf8)
            shareItem = ShareItem(url: tmpURL, filename: "test_share.json")
            showShareSheet = true
            successMessage = "Test file created and sharing"
        } catch {
            errorMessage = "Test failed: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Original Actions
    
    private func flushLogs() {
        isProcessing = true
        successMessage = nil
        
        DispatchQueue.main.async {
            AnalyticsLogger.shared.flush()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.refreshFileList()
                self.successMessage = "Logs flushed successfully"
                self.isProcessing = false
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.successMessage = nil
                }
            }
        }
    }
    
    private func refreshFileList() {
        files = AnalyticsLogger.shared.allLocalLogFiles()
        successMessage = "Found \(files.count) log file(s)"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            successMessage = nil
        }
    }
    
    private func createTestEvent() {
        let testEvent = AnalyticsEvent(
            type: "test_event",
            payload: [
                "timestamp": .string(ISO8601DateFormatter().string(from: Date())),
                "random": .int(Int.random(in: 1...100)),
                "message": .string("Test event from export view")
            ]
        )
        
        AnalyticsLogger.shared.log(testEvent)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AnalyticsLogger.shared.flush()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.refreshFileList()
            }
        }
    }
    
    private func performMerge(files: [URL]) async throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyticsShare", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        
        let mergedURL = tmpDir.appendingPathComponent("analytics_merged.json")
        
        // Remove if exists
        try? FileManager.default.removeItem(at: mergedURL)
        
        // Create output file
        FileManager.default.createFile(atPath: mergedURL.path, contents: nil, attributes: nil)
        
        let outHandle = try FileHandle(forWritingTo: mergedURL)
        defer { try? outHandle.close() }
        
        // Write opening bracket
        try outHandle.write(contentsOf: Data("[\n".utf8))
        
        var isFirstEntry = true
        
        for fileURL in files {
            guard let inHandle = try? FileHandle(forReadingFrom: fileURL) else { continue }
            defer { try? inHandle.close() }
            
            // Read file line by line
            if let data = try? inHandle.readToEnd() {
                let lines = data.split(separator: 0x0A) // newline
                
                for line in lines {
                    if !line.isEmpty {
                        if !isFirstEntry {
                            try outHandle.write(contentsOf: Data(",\n".utf8))
                        }
                        try outHandle.write(contentsOf: Data(line))
                        isFirstEntry = false
                    }
                }
            }
        }
        
        // Write closing bracket
        try outHandle.write(contentsOf: Data("\n]".utf8))
        
        return mergedURL
    }
    
    private func fileSizeString(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return "Unknown size"
        }
        
        let bytes = fileSize.int64Value
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Share Item
struct ShareItem {
    let url: URL
    let filename: String
}

// MARK: - Activity View Controller
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // Exclude irrelevant activities
        controller.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks,
            .postToFacebook,
            .postToTwitter,
            .postToWeibo,
            .postToFlickr,
            .postToVimeo,
            .postToTencentWeibo
        ]
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing to update
    }
}

// MARK: - Alternative: Simple Copy to Clipboard
extension AnalyticsExportView {
    private func copyFileContentsToClipboard(_ url: URL) {
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            UIPasteboard.general.string = contents
            successMessage = "Copied to clipboard!"
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }
}
