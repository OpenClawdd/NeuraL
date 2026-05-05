import SwiftUI

struct ModelsView: View {
    let chatState: ChatState

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
                            Text("Quantization: \(meta.quantization)")
                            Text("Context: \(meta.trainingContextLength)")
                        } else {
                            Text("No model loaded. App still operates in local fallback mode.")
                        }
                    }
                    card(title: "Guidance", icon: "info.circle") {
                        Text("Import/load GGUF models from your local environment. This screen intentionally hides remote/API-key configuration.")
                    }
                }
                .padding()
            }
            .background(LinearGradient(colors: [.white, Color.blue.opacity(0.1)], startPoint: .top, endPoint: .bottom))
            .navigationTitle("Models")
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
