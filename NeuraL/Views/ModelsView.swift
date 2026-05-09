import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    let chatState: ChatState
    @State private var showFileImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    card(title: "Runtime", icon: "bolt.shield") {
                        Text("Local-only runtime. No API keys, no cloud bridge in default path.")
                    }
                    card(title: "Model Status", icon: "cpu") {
                        if let meta = chatState.modelMetadata {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Architecture: \(meta.architecture)")
                                Text("Quantization: \(meta.quantization)")
                                Text("Context: \(meta.trainingContextLength)")
                            }
                        } else {
                            Text("No model loaded. App still operates in local fallback mode.")
                        }
                    }
                    card(title: "Import Model", icon: "square.and.arrow.down") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Load a local GGUF model file for on-device inference.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                showFileImporter = true
                            } label: {
                                Label("Select GGUF File", systemImage: "doc.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)

                            if let error = importError {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }

                            if chatState.modelMetadata != nil {
                                Button(role: .destructive) {
                                    chatState.unloadModel()
                                } label: {
                                    Label("Unload Model", systemImage: "eject")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(LinearGradient(colors: [.white, Color.blue.opacity(0.1)], startPoint: .top, endPoint: .bottom))
            .navigationTitle("Models")
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else {
                        importError = "Permission denied — cannot access the selected file."
                        return
                    }
                    defer { url.stopAccessingSecurityScopedResource() }
                    importError = nil
                    chatState.loadModel(from: url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
        }
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
