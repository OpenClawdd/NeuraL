//
//  ModelsView.swift
//  NeuraL
//
//  Phase 3+ — The Models Tab
//
//  A dedicated tab for browsing, downloading, and importing GGUF models.
//  This view provides:
//
//  1. A curated catalog of recommended models with download buttons
//  2. A custom import flow for bringing your own .gguf files
//  3. Storage management (see how much space models take, delete old ones)
//  4. Currently loaded model indicator
//  5. Device compatibility badges
//
//  Architecture:
//  - The view reads from ModelCatalog for the browsable list
//  - Downloads are managed by ModelDownloadManager (shared singleton)
//  - Loading a model goes through ChatState.loadModel()
//  - Custom import uses UIDocumentPickerViewController via the
//    representable wrapper
//
//  Styling: Frutiger Aero — frosted glass cards, glossy highlights,
//  soft blue gradients, shimmer progress rings, gold accents.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Models View

/// The main Models tab view. Shows catalog + imported models + storage info.
/// Styled with the Frutiger Aero aesthetic: frosted glass, gloss, soft blues.
struct ModelsView: View {
    let chatState: ChatState

    private let downloadManager = ModelDownloadManager.shared
    @State private var showImporter = false
    @State private var importedFileURL: URL?
    @State private var showImportSuccess = false
    @State private var importedFileName = ""
    @State private var selectedEntry: CatalogEntry?
    @State private var showDetail = false
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: URL?
    @State private var showURLImport = false
    @State private var urlImportText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Soft blue gradient background
                FrutigerAeroTheme.shared.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // -- Currently Loaded Model Card
                        loadedModelCard

                        // -- Catalog Section
                        catalogSection

                        // -- Custom Import Section
                        importSection

                        // -- Imported Models Section
                        importedModelsSection

                        // -- Storage Info
                        storageInfoSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Models")
            .sheet(isPresented: $showImporter) {
                DocumentPickerView { url in
                    handleImportedFile(url)
                }
            }
            .sheet(isPresented: $showURLImport) {
                URLImportSheet { url in
                    downloadFromURL(url)
                }
            }
            .sheet(item: $selectedEntry) { entry in
                ModelDetailSheet(
                    entry: entry,
                    chatState: chatState,
                    downloadManager: downloadManager
                )
            }
            .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    modelToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let url = modelToDelete {
                        let entry = CatalogEntry(supportsVision: false, mmprojFilename: nil, mmprojDownloadURL: nil, mmprojDownloadSizeBytes: 0,
                            id: url.lastPathComponent,
                            displayName: url.deletingPathExtension().lastPathComponent,
                            family: "Imported",
                            tagline: "",
                            description: "",
                            parameterCount: "?",
                            quantization: "",
                            downloadSizeBytes: 0,
                            templateFormat: .llama3,
                            downloadURL: URL(string: "https://example.com")!,
                            localFilename: url.lastPathComponent,
                            supportsThinkingBlocks: false,
                            recommendedContextLength: 2048,
                            minimumDeviceTier: .standard,
                            tags: []
                        )
                        try? downloadManager.deleteDownloadedModel(entry: entry)
                    }
                    modelToDelete = nil
                }
            } message: {
                Text("This model file will be permanently deleted. You will need to download or import it again to use it.")
            }
            .alert("Model Imported", isPresented: $showImportSuccess) {
                Button("OK") {}
            } message: {
                Text("Successfully imported \(importedFileName)")
            }
        }
    }

    // MARK: - Loaded Model Card

    /// Shows which model is currently loaded, with an unload button.
    /// Active model gets a neon blue glow border; inactive gets frosted glass.
    private var loadedModelCard: some View {
        Group {
            if let metadata = chatState.modelMetadata {
                HStack(spacing: 12) {
                    // Model icon — glossy neon blue circle
                    ZStack {
                        Circle()
                            .fill(FrutigerAeroTheme.shared.neonBlue.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .fill(FrutigerAeroTheme.shared.subtleGloss)
                            )

                        Image(systemName: "cpu.fill")
                            .font(.title3)
                            .foregroundStyle(FrutigerAeroTheme.shared.neonBlue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Model")
                            .font(.caption2)
                            .foregroundStyle(FrutigerAeroTheme.shared.softTeal)

                        Text(metadata.architecture.prefix(1).uppercased() + metadata.architecture.dropFirst())
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            Text(metadata.quantization)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text(String(format: "%.1f GB", Double(metadata.fileSize) / 1_073_741_824))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        FrutigerAeroTheme.shared.lightHaptic()
                        chatState.unloadModel()
                    } label: {
                        Text("Unload")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.red.opacity(0.7))
                                    .overlay(
                                        Capsule()
                                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(FrutigerAeroTheme.shared.glossHighlight)
                        .opacity(0.4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(FrutigerAeroTheme.shared.neonBlue.opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3), radius: 10, x: 0, y: 4)
            } else {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .fill(FrutigerAeroTheme.shared.subtleGloss)
                            )

                        Image(systemName: "cpu")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Model Loaded")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Download or import a model below")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(FrutigerAeroTheme.shared.glossHighlight)
                        .opacity(0.3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 8, x: 0, y: 4)
            }
        }
    }

    // MARK: - Catalog Section

    /// Browsable list of recommended models.
    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recommended Models", icon: "star.fill")

            ForEach(ModelCatalog.entries) { entry in
                CatalogEntryCard(
                    entry: entry,
                    downloadState: downloadManager.downloadStates[entry.id] ?? .idle,
                    isLoaded: isModelLoaded(entry),
                    onLoad: { loadCatalogEntry(entry) },
                    onDownload: { downloadManager.download(entry: entry) },
                    onTap: { selectedEntry = entry }
                )
            }
        }
    }

    // MARK: - Import Section

    /// Custom model import via document picker.
    /// Import buttons use glassy styling with gold accent.
    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Import Your Own", icon: "square.and.arrow.down.fill")

            Button {
                FrutigerAeroTheme.shared.lightHaptic()
                showImporter = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(FrutigerAeroTheme.shared.goldAccent.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(FrutigerAeroTheme.shared.subtleGloss)
                            )

                        Image(systemName: "doc.badge.plus")
                            .font(.callout)
                            .foregroundStyle(FrutigerAeroTheme.shared.goldAccent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import GGUF File")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        Text("Select a .gguf model from Files app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(FrutigerAeroTheme.shared.glossHighlight)
                        .opacity(0.3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(FrutigerAeroTheme.shared.goldAccent.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)

            // Import from URL
            Button {
                FrutigerAeroTheme.shared.lightHaptic()
                showURLImport = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(FrutigerAeroTheme.shared.goldAccent.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(FrutigerAeroTheme.shared.subtleGloss)
                            )

                        Image(systemName: "link")
                            .font(.callout)
                            .foregroundStyle(FrutigerAeroTheme.shared.goldAccent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from URL")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        Text("Paste a direct GGUF download link")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(FrutigerAeroTheme.shared.glossHighlight)
                        .opacity(0.3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(FrutigerAeroTheme.shared.goldAccent.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)

            // Tip about sideloading
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption2)
                    .foregroundStyle(FrutigerAeroTheme.shared.goldAccent.opacity(0.8))

                Text("You can also place .gguf files in the app's Documents directory via Finder or SSH disk.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Imported Models Section

    /// Shows models found in the Models directory that aren't in the catalog.
    private var importedModelsSection: some View {
        let importedFiles = downloadManager.listImportedModels()
        let catalogFilenames = Set(ModelCatalog.entries.map(\.localFilename))

        return Group {
            let nonCatalogFiles = importedFiles.filter { !catalogFilenames.contains($0.lastPathComponent) }

            if !nonCatalogFiles.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("Imported Models", icon: "folder.fill")

                    ForEach(nonCatalogFiles, id: \.path) { url in
                        ImportedModelCard(
                            url: url,
                            isLoaded: isFileLoaded(url),
                            onLoad: { loadImportedModel(url) },
                            onDelete: {
                                modelToDelete = url
                                showDeleteConfirmation = true
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Storage Info

    /// Storage info displayed in a frosted glass pill.
    private var storageInfoSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "internaldrive")
                .font(.caption)
                .foregroundStyle(FrutigerAeroTheme.shared.softTeal)

            Text("Models storage: \(downloadManager.totalStorageUsedString)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            let totalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
            let tierDesc: String
            switch totalGB {
            case ..<4:   tierDesc = "Limited (≤4GB)"
            case ..<8:   tierDesc = "Standard (6-8GB)"
            case ..<16:  tierDesc = "Premium (8-16GB)"
            default:     tierDesc = "Extended (16GB+)"
            }
            Text("Device: \(tierDesc)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .fill(FrutigerAeroTheme.shared.glossHighlight)
                .opacity(0.25)
        )
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 4, x: 0, y: 2)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(FrutigerAeroTheme.shared.neonBlue)

            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
        }
    }

    private func isModelLoaded(_ entry: CatalogEntry) -> Bool {
        guard chatState.loadedModelURL != nil else { return false }
        return chatState.loadedModelURL == entry.localURL
    }

    private func isFileLoaded(_ url: URL) -> Bool {
        guard chatState.loadedModelURL != nil else { return false }
        return chatState.loadedModelURL == url
    }

    private func loadCatalogEntry(_ entry: CatalogEntry) {
        guard entry.isDownloaded else { return }
        FrutigerAeroTheme.shared.lightHaptic()
        chatState.setTemplateFormat(entry.templateFormat)
        chatState.loadModel(from: entry.localURL)
    }

    private func loadImportedModel(_ url: URL) {
        // Try to auto-detect the template format from the filename
        let filename = url.lastPathComponent.lowercased()
        let format: ChatTemplateFormat
        if filename.contains("gemma") || filename.contains("phi") {
            format = .gemma
        } else if filename.contains("chatml") || filename.contains("mistral") {
            format = .chatML
        } else {
            format = .llama3  // Default
        }
        FrutigerAeroTheme.shared.lightHaptic()
        chatState.setTemplateFormat(format)
        chatState.loadModel(from: url)
    }

    private func handleImportedFile(_ url: URL) {
        // Copy the file to the Models directory
        let fileName = url.lastPathComponent
        let destURL = ModelDownloadManager.modelsDirectory.appendingPathComponent(fileName)

        do {
            // Access the security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)

            importedFileName = fileName
            importedFileURL = destURL
            showImportSuccess = true
        } catch {
            // Could show an error alert here
            print("Failed to import model: \(error)")
        }
    }

    private func downloadFromURL(_ url: URL) {
        // Download the GGUF file from the provided URL
        let filename = url.lastPathComponent
        let destURL = ModelDownloadManager.modelsDirectory.appendingPathComponent(filename)

        Task {
            do {
                let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    return
                }

                let tempURL = destURL.appendingPathExtension("download")
                FileManager.default.createFile(atPath: tempURL.path, contents: nil)
                let fileHandle = try FileHandle(forWritingTo: tempURL)
                var buffer = Data()
                let bufferSize = 64 * 1024

                for try await byte in asyncBytes {
                    buffer.append(byte)
                    if buffer.count >= bufferSize {
                        try fileHandle.write(contentsOf: buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                }
                if !buffer.isEmpty {
                    try fileHandle.write(contentsOf: buffer)
                }
                try fileHandle.close()

                // Validate
                let result = GGUFValidator.validate(url: tempURL)
                switch result {
                case .success:
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    importedFileName = filename
                    showImportSuccess = true
                case .failure:
                    try? FileManager.default.removeItem(at: tempURL)
                }
            } catch {
                // Silently fail for now
            }
        }
    }
}

// MARK: - URL Import Sheet

/// A sheet for importing a GGUF model from a direct download URL.
/// Styled with Frutiger Aero: frosted glass, gold accent button.
struct URLImportSheet: View {
    let onImport: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Frosted glass background for the sheet
                FrutigerAeroTheme.shared.backgroundGradient
                    .ignoresSafeArea()

                Form {
                    Section("Download URL") {
                        TextField("https://huggingface.co/...", text: $urlText)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        Text("Paste a direct link to a .gguf file. HuggingFace URLs in the format huggingface.co/{org}/{repo}/resolve/main/{file}.gguf work best.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button {
                            if let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                FrutigerAeroTheme.shared.lightHaptic()
                                onImport(url)
                                dismiss()
                            }
                        } label: {
                            Label("Download", systemImage: "arrow.down.circle.fill")
                                .font(.body.bold())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .disabled(!isValidURL)
                        .listRowBackground(
                            Capsule()
                                .fill(FrutigerAeroTheme.shared.goldAccent.opacity(isValidURL ? 0.85 : 0.3))
                                .overlay(
                                    Capsule()
                                        .fill(FrutigerAeroTheme.shared.subtleGloss)
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                                )
                                .shadow(
                                    color: FrutigerAeroTheme.shared.goldAccent.opacity(isValidURL ? 0.3 : 0),
                                    radius: 6, x: 0, y: 3
                                )
                        )
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        FrutigerAeroTheme.shared.lightHaptic()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isValidURL: Bool {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return url.scheme == "https" || url.scheme == "http"
    }
}

// MARK: - Catalog Entry Card

/// A card displaying a single catalog model with download/load actions.
/// Frosted glass with gloss highlight, white stroke border, soft shadow.
struct CatalogEntryCard: View {
    let entry: CatalogEntry
    let downloadState: DownloadState
    let isLoaded: Bool
    let onLoad: () -> Void
    let onDownload: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button {
            FrutigerAeroTheme.shared.lightHaptic()
            onTap()
        } label: {
            HStack(spacing: 12) {
                // Model family icon — glossy with FrutigerAeroTheme colors
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(familyColor.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(FrutigerAeroTheme.shared.subtleGloss)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(familyColor.opacity(0.3), lineWidth: 0.5)
                        )

                    Image(systemName: familyIcon)
                        .font(.title3)
                        .foregroundStyle(familyColor)
                }

                // Model info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)

                        // Tags
                        if entry.tags.contains("recommended") {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(FrutigerAeroTheme.shared.neonBlue)
                                        .overlay(
                                            Capsule()
                                                .fill(FrutigerAeroTheme.shared.subtleGloss)
                                        )
                                )
                        }
                    }

                    Text(entry.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label(entry.parameterCount, systemImage: "memorychip")
                        Label(entry.downloadSizeString, systemImage: "arrow.down.doc")
                        Label(entry.quantization, systemImage: "slider.horizontal.3")
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                // Action button
                actionButton
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .fill(FrutigerAeroTheme.shared.glossHighlight)
                .opacity(0.35)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isLoaded
                    ? FrutigerAeroTheme.shared.neonBlue.opacity(0.6)
                    : Color.white.opacity(0.3),
                    lineWidth: isLoaded ? 1.5 : 0.5
                )
        )
        .shadow(
            color: isLoaded
                ? FrutigerAeroTheme.shared.neonBlue.opacity(0.25)
                : FrutigerAeroTheme.shared.buttonShadow,
            radius: isLoaded ? 10 : 8, x: 0, y: 4
        )
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        if isLoaded {
            // Model is currently loaded — glossy green checkmark
            ZStack {
                Circle()
                    .fill(FrutigerAeroTheme.shared.vibrantCyan.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                    )

                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(FrutigerAeroTheme.shared.neonBlue)
            }
        } else if entry.isDownloaded {
            // Downloaded, can be loaded — glossy button
            Button {
                FrutigerAeroTheme.shared.lightHaptic()
                onLoad()
            } label: {
                Text("Load")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(FrutigerAeroTheme.shared.buttonGradient)
                    )
                    .overlay(
                        Capsule()
                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(
                        color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3),
                        radius: 4, x: 0, y: 2
                    )
            }
            .buttonStyle(.plain)
        } else if case .downloading(let progress) = downloadState {
            // Download in progress — glossy progress ring with shimmer
            VStack(spacing: 2) {
                ZStack {
                    // Track ring
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 3)
                        .frame(width: 32, height: 32)

                    // Filled arc with gradient
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            FrutigerAeroTheme.shared.neonBlue,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))

                    // Shimmer overlay on the filled arc
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            FrutigerAeroTheme.shared.vibrantCyan.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round)
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))

                    // Percentage text
                    Text("\(Int(progress * 100))")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .overlay(
                    Circle()
                        .fill(FrutigerAeroTheme.shared.subtleGloss)
                        .opacity(0.15)
                )

                Text("Downloading")
                    .font(.system(size: 8))
                    .foregroundStyle(FrutigerAeroTheme.shared.softTeal)
            }
        } else if case .validating = downloadState {
            ProgressView()
                .controlSize(.small)
                .tint(FrutigerAeroTheme.shared.neonBlue)
        } else if case .failed(let error) = downloadState {
            VStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)

                Text("Retry")
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
            }
        } else {
            // Not downloaded yet — glossy download button
            Button {
                FrutigerAeroTheme.shared.lightHaptic()
                onDownload()
            } label: {
                ZStack {
                    Circle()
                        .fill(FrutigerAeroTheme.shared.buttonGradient)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .fill(FrutigerAeroTheme.shared.subtleGloss)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                        )
                        .shadow(
                            color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3),
                            radius: 4, x: 0, y: 2
                        )

                    Image(systemName: "arrow.down")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Family Styling

    /// Color associated with the model family — uses FrutigerAeroTheme palette.
    private var familyColor: Color {
        switch entry.family {
        case "Llama 3.2": return FrutigerAeroTheme.shared.neonBlue
        case "Gemma 2":   return FrutigerAeroTheme.shared.vibrantCyan
        case "Phi-3":     return FrutigerAeroTheme.shared.deepOcean
        case "Qwen 2.5":  return FrutigerAeroTheme.shared.goldAccent
        default:           return FrutigerAeroTheme.shared.softTeal
        }
    }

    /// Icon associated with the model family.
    private var familyIcon: String {
        switch entry.family {
        case "Llama 3.2": return "hare.fill"
        case "Gemma 2":   return "diamond.fill"
        case "Phi-3":     return "atom"
        case "Qwen 2.5":  return "globe.asia.australia.fill"
        default:           return "cube.box.fill"
        }
    }
}

// MARK: - Imported Model Card

/// A card for a user-imported .gguf model file.
/// Frosted glass with gold accent styling.
struct ImportedModelCard: View {
    let url: URL
    let isLoaded: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void

    @State private var fileSize: UInt64 = 0

    var body: some View {
        HStack(spacing: 12) {
            // Gold-accented document icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(FrutigerAeroTheme.shared.goldAccent.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(FrutigerAeroTheme.shared.goldAccent.opacity(0.3), lineWidth: 0.5)
                    )

                Image(systemName: "doc.fill")
                    .font(.title3)
                    .foregroundStyle(FrutigerAeroTheme.shared.goldAccent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(
                        String(format: "%.1f GB", Double(fileSize) / 1_073_741_824),
                        systemImage: "internaldrive"
                    )
                }
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Load button — glossy
            Button {
                FrutigerAeroTheme.shared.lightHaptic()
                onLoad()
            } label: {
                Text("Load")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(FrutigerAeroTheme.shared.buttonGradient)
                    )
                    .overlay(
                        Capsule()
                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(
                        color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3),
                        radius: 4, x: 0, y: 2
                    )
            }
            .buttonStyle(.plain)

            // Delete button
            Button {
                FrutigerAeroTheme.shared.lightHaptic()
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.7))
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .overlay(
                                Circle()
                                    .fill(FrutigerAeroTheme.shared.subtleGloss)
                                    .opacity(0.2)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete model")
            .accessibilityHint("Delete this model file from your device")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .fill(FrutigerAeroTheme.shared.glossHighlight)
                .opacity(0.35)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isLoaded
                    ? FrutigerAeroTheme.shared.neonBlue.opacity(0.6)
                    : Color.white.opacity(0.3),
                    lineWidth: isLoaded ? 1.5 : 0.5
                )
        )
        .shadow(
            color: isLoaded
                ? FrutigerAeroTheme.shared.neonBlue.opacity(0.25)
                : FrutigerAeroTheme.shared.buttonShadow,
            radius: isLoaded ? 10 : 8, x: 0, y: 4
        )
        .onAppear {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = (attrs?[.size] as? UInt64) ?? 0
        }
    }
}

// MARK: - Model Detail Sheet

/// A sheet showing detailed information about a catalog model.
/// Frosted glass cards, gloss highlights, FrutigerAeroTheme family colors.
struct ModelDetailSheet: View {
    let entry: CatalogEntry
    let chatState: ChatState
    let downloadManager: ModelDownloadManager

    @Environment(\.dismiss) private var dismiss
    @State private var downloadState: DownloadState = .idle

    var body: some View {
        NavigationStack {
            ZStack {
                // Soft blue gradient background for the sheet
                FrutigerAeroTheme.shared.backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Hero section — glossy icon
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(familyColor.opacity(0.2))
                                    .frame(width: 72, height: 72)
                                    .overlay(
                                        Circle()
                                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                                    )
                                    .overlay(
                                        Circle()
                                            .strokeBorder(familyColor.opacity(0.3), lineWidth: 1)
                                    )
                                    .shadow(color: familyColor.opacity(0.3), radius: 10, x: 0, y: 4)

                                Image(systemName: familyIcon)
                                    .font(.largeTitle)
                                    .foregroundStyle(familyColor)
                            }

                            Text(entry.displayName)
                                .font(.title2.bold())

                            Text(entry.tagline)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        // Description
                        Text(entry.description)
                            .font(.body)
                            .foregroundStyle(.secondary)

                        // Specs grid — frosted glass card
                        VStack(spacing: 10) {
                            specRow("Parameters", value: entry.parameterCount, icon: "memorychip")
                            specRow("Quantization", value: entry.quantization, icon: "slider.horizontal.3")
                            specRow("Download Size", value: entry.downloadSizeString, icon: "arrow.down.doc")
                            specRow("Context Window", value: "\(entry.recommendedContextLength) tokens", icon: "text.bubble.fill")
                            specRow("Chat Format", value: entry.templateFormat.description, icon: "text.format")
                            specRow("Min Device", value: entry.minimumDeviceTier.description, icon: "iphone")
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(FrutigerAeroTheme.shared.glossHighlight)
                                .opacity(0.3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                        )
                        .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 8, x: 0, y: 4)

                        // Tags — frosted capsules
                        if !entry.tags.isEmpty {
                            WrappingHStack(
                                items: entry.tags,
                                spacing: 6
                            ) { tag in
                                Text(tag.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(familyColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(
                                        Capsule()
                                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                                            .opacity(0.3)
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(familyColor.opacity(0.3), lineWidth: 0.5)
                                    )
                            }
                        }

                        // Action button
                        actionButton
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Model Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        FrutigerAeroTheme.shared.lightHaptic()
                        dismiss()
                    }
                }
            }
            .onAppear {
                downloadState = downloadManager.downloadStates[entry.id] ?? .idle
            }
            .onChange(of: downloadManager.downloadStates[entry.id]) { _, newState in
                if let newState = newState {
                    downloadState = newState
                }
            }
        }
    }

    // MARK: - Helpers

    private func specRow(_ label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(FrutigerAeroTheme.shared.softTeal)

            Spacer()

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if entry.isDownloaded && chatState.isReady {
            // Already downloaded and a model is loaded
            if let metadata = chatState.modelMetadata {
                // Some model is loaded — offer to load this one instead
                Button {
                    FrutigerAeroTheme.shared.lightHaptic()
                    chatState.setTemplateFormat(entry.templateFormat)
                    chatState.loadModel(from: entry.localURL)
                    dismiss()
                } label: {
                    Label("Switch to This Model", systemImage: "arrow.triangle.swap")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(FrutigerAeroTheme.shared.buttonGradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(FrutigerAeroTheme.shared.subtleGloss)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(
                    color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3),
                    radius: 6, x: 0, y: 3
                )
                .controlSize(.large)
            } else {
                Button {
                    FrutigerAeroTheme.shared.lightHaptic()
                    chatState.setTemplateFormat(entry.templateFormat)
                    chatState.loadModel(from: entry.localURL)
                    dismiss()
                } label: {
                    Label("Load This Model", systemImage: "play.fill")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(FrutigerAeroTheme.shared.buttonGradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(FrutigerAeroTheme.shared.subtleGloss)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(
                    color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3),
                    radius: 6, x: 0, y: 3
                )
                .controlSize(.large)
            }
        } else if entry.isDownloaded {
            Button {
                FrutigerAeroTheme.shared.lightHaptic()
                chatState.setTemplateFormat(entry.templateFormat)
                chatState.loadModel(from: entry.localURL)
                dismiss()
            } label: {
                Label("Load This Model", systemImage: "play.fill")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(FrutigerAeroTheme.shared.buttonGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .fill(FrutigerAeroTheme.shared.subtleGloss)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(
                color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3),
                radius: 6, x: 0, y: 3
            )
            .controlSize(.large)
        } else if case .downloading(let progress) = downloadState {
            VStack(spacing: 8) {
                // Glossy linear progress bar
                ProgressView(value: progress)
                    .progressViewStyle(AeroProgressStyle())
                    .tint(FrutigerAeroTheme.shared.neonBlue)

                Text("Downloading... \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(FrutigerAeroTheme.shared.softTeal)
            }
        } else if case .failed(let error) = downloadState {
            VStack(spacing: 8) {
                Text("Download failed: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)

                Button {
                    FrutigerAeroTheme.shared.lightHaptic()
                    downloadManager.download(entry: entry)
                } label: {
                    Label("Retry Download", systemImage: "arrow.clockwise")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(FrutigerAeroTheme.shared.buttonGradient)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(FrutigerAeroTheme.shared.subtleGloss)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(
                    color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3),
                    radius: 6, x: 0, y: 3
                )
                .controlSize(.large)
            }
        } else {
            Button {
                FrutigerAeroTheme.shared.lightHaptic()
                downloadManager.download(entry: entry)
            } label: {
                Label("Download \(entry.downloadSizeString)", systemImage: "arrow.down.circle.fill")
                    .font(.body.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(FrutigerAeroTheme.shared.buttonGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .fill(FrutigerAeroTheme.shared.subtleGloss)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(
                color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3),
                radius: 6, x: 0, y: 3
            )
            .controlSize(.large)
        }
    }

    /// Color associated with the model family — uses FrutigerAeroTheme palette.
    private var familyColor: Color {
        switch entry.family {
        case "Llama 3.2": return FrutigerAeroTheme.shared.neonBlue
        case "Gemma 2":   return FrutigerAeroTheme.shared.vibrantCyan
        case "Phi-3":     return FrutigerAeroTheme.shared.deepOcean
        case "Qwen 2.5":  return FrutigerAeroTheme.shared.goldAccent
        default:           return FrutigerAeroTheme.shared.softTeal
        }
    }

    /// Icon associated with the model family.
    private var familyIcon: String {
        switch entry.family {
        case "Llama 3.2": return "hare.fill"
        case "Gemma 2":   return "diamond.fill"
        case "Phi-3":     return "atom"
        case "Qwen 2.5":  return "globe.asia.australia.fill"
        default:           return "cube.box.fill"
        }
    }
}

// MARK: - Wrapping HStack

/// A horizontal stack that wraps to the next line when items overflow.
/// Uses the Layout protocol for iOS 16+ to properly position tags.
struct WrappingHStack<Item: Hashable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: spacing) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

// MARK: - Flow Layout

/// A custom Layout that arranges views in a flowing horizontal pattern,
/// wrapping to the next line when items exceed the available width.
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangementResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalSize: CGSize = .zero

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        totalSize = CGSize(
            width: maxWidth == .infinity ? currentX : maxWidth,
            height: currentY + rowHeight
        )

        return ArrangementResult(positions: positions, size: totalSize)
    }
}

// MARK: - Document Picker

/// A UIViewControllerRepresentable that wraps UIDocumentPickerViewController
/// for selecting .gguf files from the Files app.
struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [
                UTType(filenameExtension: "gguf") ?? .data,
                .data
            ],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                onPick(url)
            }
        }
    }
}

// MARK: - Preview

#Preview("Models View") {
    ModelsView(chatState: ChatState())
}

#Preview("Catalog Entry Card") {
    CatalogEntryCard(
        entry: ModelCatalog.entries[0],
        downloadState: .idle,
        isLoaded: false,
        onLoad: {},
        onDownload: {},
        onTap: {}
    )
    .padding()
}
