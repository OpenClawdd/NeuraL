import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @ObservedObject var chatState: ChatState
    @State private var showFileImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if chatState.modelMetadata != nil {
                    ScrollView {
                        VStack(spacing: 20) {
                            modelHeader
                            metricsGrid
                            importCard
                        }
                        .padding(24)
                    }
                } else if !chatState.importedModelPath.isEmpty {
                    ScrollView {
                        VStack(spacing: 20) {
                            importedModelHeader
                            importCard
                        }
                        .padding(24)
                    }
                } else {
                    emptyState
                }
            }
            .background(LinearGradient(colors: [.white, Color.blue.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            .navigationTitle("Models")
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importError = nil
                    chatState.importModel(from: url)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cpu")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)
                .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)

            VStack(spacing: 12) {
                Text("Neural Engine Ready")
                    .font(.largeTitle.bold())

                Text("NeuraL needs a GGUF model file to begin on-device cognition. You can find these on community hubs like Hugging Face.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Text("Format: .gguf (Llama, Mistral, Gemma, etc.)")
                    .font(.caption.bold())
                    .foregroundStyle(.blue.opacity(0.8))
                    .padding(.top, 4)
            }

            Button {
                showFileImporter = true
            } label: {
                Label("Import GGUF Model", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Capsule())

            Spacer()
            Spacer()
        }
    }

    private var modelHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "cpu.fill")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text("Active Model")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text("Llama Engine")
                    .font(.title2.bold())
            }

            Spacer()

            Button(role: .destructive) {
                chatState.unloadModel()
            } label: {
                Label("Unload", systemImage: "eject.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
            card(title: "Runtime", icon: "bolt.shield") {
                Text("Local-only runtime. No API keys, no cloud bridge in default path.")
            }

            card(title: "Architecture", icon: "cpu") {
                if let meta = chatState.modelMetadata {
                    Text(meta.architecture)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }
            }

            card(title: "Quantization", icon: "scalemass") {
                if let meta = chatState.modelMetadata {
                    Text(meta.quantization.isEmpty ? "Unknown" : meta.quantization)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }
            }

            card(title: "Context", icon: "arrow.left.and.right.text.vertical") {
                if let meta = chatState.modelMetadata {
                    Text("\(meta.trainingContextLength) tokens")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var importedModelHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.zipper")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text("Imported File")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(chatState.importedModelPath)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    
                if case .error(let err) = chatState.engineState {
                    Text(err.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if case .loading(let p) = chatState.engineState {
                    Text("Loading... \(Int(p * 100))%")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()

            Button {
                chatState.loadModel()
            } label: {
                if case .loading = chatState.engineState {
                    ProgressView()
                } else {
                    Label("Load Engine", systemImage: "bolt.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(chatState.engineState == .loading(progress: 0))
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Upgrade Model", systemImage: "arrow.up.doc.fill")
                .font(.headline)

            Text("Switching models will reset the current inference session but preserve your conversation history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showFileImporter = true
            } label: {
                Label("Select New GGUF", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if let error = importError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func card<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.blue.opacity(0.1), lineWidth: 1)
        )
    }
}
