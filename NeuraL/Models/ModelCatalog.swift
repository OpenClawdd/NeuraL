//
//  ModelCatalog.swift
//  NeuraL
//
//  Phase 3+ — Curated Model Catalog & Download Management
//
//  This module defines the pre-listed models that users can browse and download
//  directly from the app, plus the download management system.
//
//  Architecture:
//  - CatalogEntry: A model listing with HuggingFace URL, size, description, etc.
//  - ModelCatalog: Static catalog of recommended models
//  - ModelDownloadManager: Handles downloading, progress tracking, and storage
//  - DownloadState: Tracks the state of a model download
//
//  The catalog includes models that are:
//  1. Small enough to run on-device (1.5B–3B parameters)
//  2. Available in efficient quantizations (Q4_K_M recommended)
//  3. Well-tested with llama.cpp on iOS
//  4. Licensed for personal/research use
//
//  Users can also import their own .gguf files via the document picker.
//

import Foundation
import SwiftUI
import Observation

// MARK: - Catalog Entry

/// A single model entry in the browsable catalog.
///
/// Each entry contains enough information to:
/// 1. Display a card in the Models tab
/// 2. Download the model from HuggingFace
/// 3. Load it into the inference engine
struct CatalogEntry: Identifiable, Sendable {
    /// Unique identifier for this catalog entry.
    let id: String

    /// Human-readable display name (e.g., "Llama 3.2 1B Instruct").
    let displayName: String

    /// The model family (e.g., "Llama 3.2", "Gemma 2", "Phi-3").
    let family: String

    /// Brief one-line description.
    let tagline: String

    /// Longer description for the detail view.
    let description: String

    /// Parameter count string (e.g., "1B", "1.5B", "3B").
    let parameterCount: String

    /// Quantization method (e.g., "Q4_K_M", "Q5_K_S").
    let quantization: String

    /// Approximate download size in bytes.
    let downloadSizeBytes: UInt64

    /// The chat template format this model uses.
    let templateFormat: ChatTemplateFormat

    /// The HuggingFace download URL for the .gguf file.
    /// Uses the direct download format:
    ///   https://huggingface.co/{org}/{repo}/resolve/main/{filename}
    let downloadURL: URL

    /// The filename to save as locally (e.g., "llama-3.2-1b-instruct-q4_k_m.gguf").
    let localFilename: String

    /// Whether this model supports reasoning/thinking blocks (<think/>).
    let supportsThinkingBlocks: Bool

    /// Recommended context window size for this model.
    let recommendedContextLength: Int

    /// The minimum device tier required to run this model comfortably.
    let minimumDeviceTier: DeviceCapabilityTier

    /// Tags for filtering/categorization.
    let tags: [String]

    /// Whether this model supports vision/multimodal input (Phase 6.1).
    let supportsVision: Bool

    /// The filename of the multimodal projector (.mmproj), if vision is supported.
    let mmprojFilename: String?

    /// The HuggingFace download URL for the .mmproj file, if vision is supported.
    let mmprojDownloadURL: URL?

    /// Approximate download size of the .mmproj file in bytes.
    let mmprojDownloadSizeBytes: UInt64

    /// Formatted download size string.
    var downloadSizeString: String {
        let gb = Double(downloadSizeBytes) / 1_073_741_824
        let mb = Double(downloadSizeBytes) / 1_048_576
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }

    /// The local URL where this model will be stored after download.
    var localURL: URL {
        ModelDownloadManager.modelsDirectory.appendingPathComponent(localFilename)
    }

    /// Whether this model has already been downloaded.
    var isDownloaded: Bool {
        FileManager.default.fileExists(atPath: localURL.path)
    }
}

// MARK: - Model Catalog

/// The static catalog of recommended models.
///
/// These are curated models that are known to work well on-device with
/// llama.cpp on iOS. Each entry includes the HuggingFace download URL,
/// the correct chat template format, and device requirements.
enum ModelCatalog {

    /// All available catalog entries.
    static let entries: [CatalogEntry] = [
        // ── Llama 3.2 Family ──────────────────────────────────────────
        CatalogEntry(
            id: "llama-3.2-1b-instruct-q4km",
            displayName: "Llama 3.2 1B Instruct",
            family: "Llama 3.2",
            tagline: "Fast & lightweight, great for quick tasks",
            description: "Meta's smallest instruction-tuned Llama 3.2 model. At just 1B parameters with Q4_K_M quantization, it runs at 42+ tokens/sec on iPhone 15 Pro. Excellent for simple Q&A, brainstorming, and quick lookups. The best starting point for on-device inference.",
            parameterCount: "1B",
            quantization: "Q4_K_M",
            downloadSizeBytes: 799_000_000,
            templateFormat: .llama3,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!,
            localFilename: "llama-3.2-1b-instruct-q4_k_m.gguf",
            supportsThinkingBlocks: false,
            recommendedContextLength: 2048,
            minimumDeviceTier: .standard,
            tags: ["recommended", "fast", "small"],
            supportsVision: false,
            mmprojFilename: nil,
            mmprojDownloadURL: nil,
            mmprojDownloadSizeBytes: 0
        ),

        CatalogEntry(
            id: "llama-3.2-3b-instruct-q4km",
            displayName: "Llama 3.2 3B Instruct",
            family: "Llama 3.2",
            tagline: "Best quality that fits on iPhone",
            description: "The 3B instruction-tuned model from Meta's Llama 3.2 family. Significantly smarter than the 1B variant — better at reasoning, coding, and following complex instructions. Runs at ~20 tok/s on iPhone 15 Pro with 2048 context. The sweet spot for quality vs. speed on mobile.",
            parameterCount: "3B",
            quantization: "Q4_K_M",
            downloadSizeBytes: 2_015_000_000,
            templateFormat: .llama3,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
            localFilename: "llama-3.2-3b-instruct-q4_k_m.gguf",
            supportsThinkingBlocks: false,
            recommendedContextLength: 2048,
            minimumDeviceTier: .premium,
            tags: ["recommended", "balanced"],
            supportsVision: false,
            mmprojFilename: nil,
            mmprojDownloadURL: nil,
            mmprojDownloadSizeBytes: 0
        ),

        // ── Gemma 2 Family ────────────────────────────────────────────
        CatalogEntry(
            id: "gemma-2-2b-it-q4km",
            displayName: "Gemma 2 2B IT",
            family: "Gemma 2",
            tagline: "Google's efficient instruction model",
            description: "Google's Gemma 2 2B instruction-tuned model. Known for excellent instruction following and multilingual capabilities. Uses the Gemma chat template format. A great alternative to Llama 3.2 1B with slightly better quality at the cost of a larger download.",
            parameterCount: "2B",
            quantization: "Q4_K_M",
            downloadSizeBytes: 1_420_000_000,
            templateFormat: .gemma,
            downloadURL: URL(string: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf")!,
            localFilename: "gemma-2-2b-it-q4_k_m.gguf",
            supportsThinkingBlocks: false,
            recommendedContextLength: 2048,
            minimumDeviceTier: .standard,
            tags: ["multilingual", "google"],
            supportsVision: false,
            mmprojFilename: nil,
            mmprojDownloadURL: nil,
            mmprojDownloadSizeBytes: 0
        ),

        // ── Phi-3 Family ──────────────────────────────────────────────
        CatalogEntry(
            id: "phi-3-mini-4k-instruct-q4km",
            displayName: "Phi-3 Mini 4K Instruct",
            family: "Phi-3",
            tagline: "Microsoft's compact reasoning model",
            description: "Microsoft's Phi-3 Mini model, trained specifically for reasoning and logic tasks. Despite its small size, it punches above its weight on math, coding, and analytical tasks. Uses the Gemma/Phi chat template format. Best for technical workloads.",
            parameterCount: "3.8B",
            quantization: "Q4_K_M",
            downloadSizeBytes: 2_340_000_000,
            templateFormat: .gemma,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q4_K_M.gguf")!,
            localFilename: "phi-3-mini-4k-instruct-q4_k_m.gguf",
            supportsThinkingBlocks: false,
            recommendedContextLength: 2048,
            minimumDeviceTier: .premium,
            tags: ["reasoning", "coding", "microsoft"],
            supportsVision: false,
            mmprojFilename: nil,
            mmprojDownloadURL: nil,
            mmprojDownloadSizeBytes: 0
        ),

        // ── Qwen 2.5 Family ──────────────────────────────────────────
        CatalogEntry(
            id: "qwen2.5-1.5b-instruct-q4km",
            displayName: "Qwen 2.5 1.5B Instruct",
            family: "Qwen 2.5",
            tagline: "Alibaba's multilingual champion",
            description: "Alibaba's Qwen 2.5 1.5B instruction-tuned model. Exceptional multilingual support including Chinese, Japanese, Korean, and European languages. Uses the Llama-3 chat template format. Great for non-English use cases and cross-lingual tasks.",
            parameterCount: "1.5B",
            quantization: "Q4_K_M",
            downloadSizeBytes: 990_000_000,
            templateFormat: .llama3,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf")!,
            localFilename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            supportsThinkingBlocks: false,
            recommendedContextLength: 2048,
            minimumDeviceTier: .standard,
            tags: ["multilingual", "chinese", "alibaba"],
            supportsVision: false,
            mmprojFilename: nil,
            mmprojDownloadURL: nil,
            mmprojDownloadSizeBytes: 0
        ),

        CatalogEntry(
            id: "qwen2.5-3b-instruct-q4km",
            displayName: "Qwen 2.5 3B Instruct",
            family: "Qwen 2.5",
            tagline: "Larger Qwen for better quality",
            description: "The 3B variant of Qwen 2.5 Instruct. Better reasoning and generation quality than the 1.5B, with the same excellent multilingual support. A strong competitor to Llama 3.2 3B, especially for non-English languages. Requires a premium device.",
            parameterCount: "3B",
            quantization: "Q4_K_M",
            downloadSizeBytes: 1_950_000_000,
            templateFormat: .llama3,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf")!,
            localFilename: "qwen2.5-3b-instruct-q4_k_m.gguf",
            supportsThinkingBlocks: false,
            recommendedContextLength: 2048,
            minimumDeviceTier: .premium,
            tags: ["multilingual", "balanced", "chinese", "alibaba"],
            supportsVision: false,
            mmprojFilename: nil,
            mmprojDownloadURL: nil,
            mmprojDownloadSizeBytes: 0
        ),

        // ── Vision Models (Phase 6.1) ───────────────────────────────────
        CatalogEntry(
            id: "llama-3.2-11b-vision-instruct-q4km",
            displayName: "Llama 3.2 11B Vision",
            family: "Llama 3.2 Vision",
            tagline: "See and understand images on-device",
            description: "Meta's multimodal Llama 3.2 Vision model that can analyze images alongside text. Requires both the base model and the .mmproj projector file. Supports visual question answering, image description, and OCR. Best on premium devices with 8GB+ RAM.",
            parameterCount: "11B",
            quantization: "Q4_K_M",
            downloadSizeBytes: 6_400_000_000,
            templateFormat: .llama3,
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-11B-Vision-Instruct-GGUF/resolve/main/Llama-3.2-11B-Vision-Instruct-Q4_K_M.gguf")!,
            localFilename: "llama-3.2-11b-vision-instruct-q4_k_m.gguf",
            supportsThinkingBlocks: false,
            recommendedContextLength: 2048,
            minimumDeviceTier: .extended,
            tags: ["vision", "multimodal", "recommended"],
            supportsVision: true,
            mmprojFilename: "llama-3.2-11b-vision-mmproj.gguf",
            mmprojDownloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-11B-Vision-Instruct-GGUF/resolve/main/mmproj-model-f16.gguf")!,
            mmprojDownloadSizeBytes: 200_000_000
        ),
    ]

    /// Entries grouped by family for display.
    static var groupedByFamily: [(family: String, entries: [CatalogEntry])] {
        let grouped = Dictionary(grouping: entries, by: \.family)
        return grouped.map { (family: $0.key, entries: $0.value) }
            .sorted { $0.family < $1.family }
    }

    /// Find a catalog entry by its ID.
    static func entry(for id: String) -> CatalogEntry? {
        entries.first { $0.id == id }
    }

    /// All unique families in the catalog.
    static var families: [String] {
        Array(Set(entries.map(\.family))).sorted()
    }
}

// MARK: - Download State

/// The current state of a model download.
enum DownloadState: Sendable, Equatable {
    /// No download in progress.
    case idle
    /// Download is in progress. The associated float is progress (0.0–1.0).
    case downloading(progress: Float)
    /// Download completed successfully.
    case completed
    /// Download failed with an error.
    case failed(error: String)
    /// The downloaded file is being validated.
    case validating

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}

// MARK: - Download Resume Info

/// Persists download progress information across app sessions so that
/// interrupted downloads can be resumed from the last byte offset.
/// Uses UserDefaults for lightweight storage.
enum DownloadResumeInfo {
    private static let defaults = UserDefaults.standard
    private static let offsetKey = "neural.download.offset"
    private static let totalSizeKey = "neural.download.totalsize"

    /// Save the current byte offset for a model download.
    static func saveOffset(entryId: String, offset: Int64) {
        defaults.set(offset, forKey: "\(offsetKey).\(entryId)")
    }

    /// Load the saved byte offset for a model download.
    static func loadOffset(entryId: String) -> Int64 {
        Int64(defaults.integer(forKey: "\(offsetKey).\(entryId)"))
    }

    /// Save the total expected size for a model download.
    static func saveTotalSize(entryId: String, size: Int64) {
        defaults.set(size, forKey: "\(totalSizeKey).\(entryId)")
    }

    /// Load the saved total size for a model download.
    static func loadTotalSize(entryId: String) -> Int64 {
        Int64(defaults.integer(forKey: "\(totalSizeKey).\(entryId)"))
    }

    /// Clear the resume info for a model download.
    static func clear(entryId: String) {
        defaults.removeObject(forKey: "\(offsetKey).\(entryId)")
        defaults.removeObject(forKey: "\(totalSizeKey).\(entryId)")
    }
}

// MARK: - Download Manager

/// Manages model downloads, progress tracking, and local storage.
///
/// This is an @Observable @MainActor class for direct SwiftUI binding.
/// Downloads support:
/// - **Resumable downloads**: If a download is interrupted, it can resume
///   from the last saved byte offset using HTTP Range requests.
/// - **Background downloads**: Uses a background URLSession configuration
///   so downloads can continue when the app is backgrounded.
/// - **Streaming to disk**: Data is written to a `.download` temp file
///   and only moved to the final location after validation.
@MainActor
@Observable
final class ModelDownloadManager {

    /// Shared singleton.
    static let shared = ModelDownloadManager()

    /// The directory where downloaded models are stored.
    static var modelsDirectory: URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        let modelsDir = documentsDir.appendingPathComponent("Models", isDirectory: true)

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(
                at: modelsDir,
                withIntermediateDirectories: true
            )
        }

        return modelsDir
    }

    /// Current download states for each catalog entry ID.
    var downloadStates: [String: DownloadState] = [:]

    /// Active download tasks.
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    /// Background URLSession for downloads that continue when app is backgrounded.
    /// Uses a unique identifier so the system can reconnect to the session
    /// after the app is relaunched.
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.neural.download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.httpShouldUsePipelining = true
        config.timeoutIntervalForResource = 3600  // 1 hour for large files
        return URLSession(configuration: config, delegate: nil, delegateQueue: nil)
    }()

    /// Download a model from the catalog with resume support.
    ///
    /// If a partial `.download` file exists from a previous interrupted
    /// download, this method uses HTTP Range requests to resume from the
    /// last saved byte offset. The offset is persisted in UserDefaults
    /// so it survives app restarts.
    ///
    /// - Parameter entry: The catalog entry to download.
    func download(entry: CatalogEntry) {
        // Guard: don't start a download if one is already in progress
        if case .downloading = downloadStates[entry.id] { return }
        guard !entry.isDownloaded else {
            downloadStates[entry.id] = .completed
            return
        }

        downloadStates[entry.id] = .downloading(progress: 0)

        downloadTasks[entry.id] = Task { [weak self] in
            guard let self = self else { return }

            do {
                let tempURL = ModelDownloadManager.modelsDirectory
                    .appendingPathComponent("\(entry.localFilename).download")

                // ── Resume support: check for existing partial download ──
                var resumeOffset: Int64 = 0
                var existingFileSize: Int64 = 0

                if FileManager.default.fileExists(atPath: tempURL.path) {
                    // Get the size of the existing partial file
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
                       let size = attrs[.size] as? Int64 {
                        existingFileSize = size
                    }

                    // Check if we have a saved offset from a previous session
                    let savedOffset = DownloadResumeInfo.loadOffset(entryId: entry.id)
                    if savedOffset > 0 && savedOffset <= existingFileSize {
                        resumeOffset = savedOffset
                        print("[DownloadManager] Resuming download from offset \(resumeOffset) bytes")
                    } else if existingFileSize > 0 {
                        // Use the file size as the resume offset
                        resumeOffset = existingFileSize
                        print("[DownloadManager] Resuming download from file size \(resumeOffset) bytes")
                    }
                }

                // ── Open or create the temp file ──
                let fileHandle: FileHandle
                if resumeOffset > 0 && FileManager.default.fileExists(atPath: tempURL.path) {
                    // Append to existing partial download
                    fileHandle = try FileHandle(forWritingTo: tempURL)
                    try fileHandle.seekToEnd()
                } else {
                    // Fresh download — remove any leftover temp file
                    try? FileManager.default.removeItem(at: tempURL)
                    FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                    fileHandle = try FileHandle(forWritingTo: tempURL)
                }

                defer {
                    try? fileHandle.close()
                }

                // ── Build the URL request with Range header if resuming ──
                var request = URLRequest(url: entry.downloadURL)
                request.timeoutInterval = 600  // 10 minute timeout for large files

                if resumeOffset > 0 {
                    request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
                }

                // ── Use the standard URLSession for foreground downloads ──
                // Background session is used for large models when the app
                // might be backgrounded. For now, we use the shared session
                // with manual Range support for simplicity and reliability.
                let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    try? FileManager.default.removeItem(at: tempURL)
                    self.downloadStates[entry.id] = .failed(
                        error: "Invalid response type from server"
                    )
                    return
                }

                // Check for 206 Partial Content (resume) or 200 OK (fresh)
                let isResuming = httpResponse.statusCode == 206
                if !(isResuming || (200...299).contains(httpResponse.statusCode)) {
                    try? FileManager.default.removeItem(at: tempURL)
                    self.downloadStates[entry.id] = .failed(
                        error: "Server returned error: \(httpResponse.statusCode)"
                    )
                    return
                }

                // If server returned 200 instead of 206, it doesn't support Range.
                // Start from scratch.
                if httpResponse.statusCode == 200 {
                    resumeOffset = 0
                    try? fileHandle.truncate(atOffset: 0)
                    try? fileHandle.seek(toOffset: 0)
                }

                // ── Compute total expected size ──
                let totalExpectedSize: Int64
                if let contentRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
                   let slashIndex = contentRange.lastIndex(of: "/"),
                   let total = Int64(contentRange[contentRange.index(after: slashIndex)...]) {
                    totalExpectedSize = total
                } else if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                          let length = Int64(contentLength) {
                    totalExpectedSize = resumeOffset + length
                } else {
                    totalExpectedSize = response.expectedContentLength > 0
                        ? resumeOffset + response.expectedContentLength
                        : Int64(entry.downloadSizeBytes)
                }

                // Save total size for future resume attempts
                DownloadResumeInfo.saveTotalSize(entryId: entry.id, size: totalExpectedSize)

                // ── Stream bytes to disk ──
                var receivedBytes: Int64 = resumeOffset
                var buffer = Data()
                let bufferSize = 64 * 1024  // 64 KB flush buffer

                for try await byte in asyncBytes {
                    if Task.isCancelled {
                        // Save the current offset so we can resume later
                        DownloadResumeInfo.saveOffset(entryId: entry.id, offset: receivedBytes)
                        try? fileHandle.close()
                        // Keep the .download file — it contains partial data
                        self.downloadStates[entry.id] = .idle
                        print("[DownloadManager] Download cancelled. Saved offset: \(receivedBytes) bytes")
                        return
                    }

                    buffer.append(byte)
                    receivedBytes += 1

                    // Flush to disk every 64 KB to keep memory usage low
                    if buffer.count >= bufferSize {
                        try fileHandle.write(contentsOf: buffer)
                        buffer.removeAll(keepingCapacity: true)

                        // Persist offset periodically for crash recovery
                        DownloadResumeInfo.saveOffset(entryId: entry.id, offset: receivedBytes)
                    }

                    // Update progress
                    if totalExpectedSize > 0 && receivedBytes % 100_000 == 0 {
                        let progress = Float(receivedBytes) / Float(totalExpectedSize)
                        self.downloadStates[entry.id] = .downloading(progress: min(progress, 0.99))
                    }
                }

                // Flush any remaining bytes
                if !buffer.isEmpty {
                    try fileHandle.write(contentsOf: buffer)
                }
                try fileHandle.close()

                // ── Validate the downloaded file ──
                self.downloadStates[entry.id] = .validating

                let validationResult = GGUFValidator.validate(url: tempURL)
                switch validationResult {
                case .success:
                    // Move to final location
                    let finalURL = entry.localURL
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: finalURL)

                    // Clear resume info on successful download
                    DownloadResumeInfo.clear(entryId: entry.id)

                    self.downloadStates[entry.id] = .completed

                case .failure(let error):
                    // Delete the invalid download
                    try? FileManager.default.removeItem(at: tempURL)
                    DownloadResumeInfo.clear(entryId: entry.id)
                    self.downloadStates[entry.id] = .failed(
                        error: "Downloaded file is not a valid GGUF: \(error)"
                    )
                }

            } catch {
                // On error, don't delete the partial file — it may be resumable
                // Save the current progress for resume
                DownloadResumeInfo.saveOffset(entryId: entry.id, offset: 0) // Will use file size on next resume
                self.downloadStates[entry.id] = .failed(error: error.localizedDescription)
            }
        }
    }

    /// Check if a partial download exists that can be resumed.
    ///
    /// - Parameter entry: The catalog entry to check.
    /// - Returns: The byte offset of the partial download, or 0 if none.
    func resumableOffset(for entry: CatalogEntry) -> Int64 {
        let tempURL = ModelDownloadManager.modelsDirectory
            .appendingPathComponent("\(entry.localFilename).download")

        guard FileManager.default.fileExists(atPath: tempURL.path) else { return 0 }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
           let size = attrs[.size] as? Int64, size > 0 {
            return size
        }
        return 0
    }

    /// Cancel an active download. Keeps the partial file for resume.
    func cancelDownload(entryId: String) {
        downloadTasks[entryId]?.cancel()
        downloadTasks.removeValue(forKey: entryId)
        // Don't clear the resume info — the partial file is still on disk
        downloadStates[entryId] = .idle
    }

    /// Delete a downloaded model file.
    func deleteDownloadedModel(entry: CatalogEntry) throws {
        let url = entry.localURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        // Also remove any partial download file
        let tempURL = ModelDownloadManager.modelsDirectory
            .appendingPathComponent("\(entry.localFilename).download")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        DownloadResumeInfo.clear(entryId: entry.id)
        downloadStates[entry.id] = .idle
    }

    /// List all .gguf files in the Models directory.
    func listImportedModels() -> [URL] {
        let dir = ModelDownloadManager.modelsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        return files.filter { $0.pathExtension == "gguf" }
    }

    /// Get the file size for a model at the given URL.
    func fileSize(for url: URL) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else {
            return 0
        }
        return size
    }

    /// Get total storage used by downloaded models.
    var totalStorageUsed: UInt64 {
        let urls = listImportedModels()
        return urls.reduce(0) { $0 + fileSize(for: $1) }
    }

    /// Formatted total storage string.
    var totalStorageUsedString: String {
        let gb = Double(totalStorageUsed) / 1_073_741_824
        let mb = Double(totalStorageUsed) / 1_048_576
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }
}
