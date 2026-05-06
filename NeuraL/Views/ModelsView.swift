import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @ObservedObject var chatState: ChatState
    @State private var isImporterPresented = false
    @State private var importError: String?

    private var ggufType: UTType {
        UTType(filenameExtension: "gguf") ?? .data
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    card(title: "Runtime", icon: "bolt.shield") {
                        Text("Local-only runtime. No API keys, no cloud bridge in default path.")
                    }

                    card(title: "Model Status", icon: "cpu") {
                        if let meta = chatState.modelMetadata {
                            Text("Architecture: \(meta.architecture)")
                            Text("Quantization: \(meta.quantization.isEmpty ? "Local GGUF" : meta.quantization)")
                            Text("Context: \(meta.trainingContextLength)")
                        } else {
                            Text("No model loaded. Import a local GGUF model to generate on device.")
                        }

                        if let error = chatState.lastError {
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if let importError {
                            Text(importError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    card(title: "Local Model", icon: "folder.badge.plus") {
                        Button {
                            isImporterPresented = true
                        } label: {
                            Label("Load GGUF Model", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Choose a text-generation .gguf file from Files. NeuraL copies it into app storage, then loads it locally through llama.cpp.")
                            .font(.caption)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("On iPhone:")
                                .font(.caption.bold())
                            Text("1. Save your DeepSeek/Qwen GGUF in Files, iCloud Drive, or On My iPhone.")
                            Text("2. Tap Load GGUF Model and select the file.")
                            Text("3. Wait for model status, then switch to Chat.")
                        }
                        .font(.caption)
                    }
                }
                .padding()
            }
            .background(LinearGradient(colors: [.white, Color.blue.opacity(0.1)], startPoint: .top, endPoint: .bottom))
            .navigationTitle("Models")
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [ggufType],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let localURL = try copyModelIntoAppSupport(from: url)
                importError = nil
                chatState.loadModel(from: localURL)
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func copyModelIntoAppSupport(from sourceURL: URL) throws -> URL {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let modelsDirectory = appSupport.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destination = modelsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private func card<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            content().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
