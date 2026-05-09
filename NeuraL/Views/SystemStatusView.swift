import SwiftUI

struct SystemStatusView: View {
    let chatState: ChatState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    panel("Device") { Text("iOS local runtime ready") }
                    panel("Memory") { Text("Optimized for on-device cognition workflows") }
                    panel("Inference") {
                        Text(chatState.isGenerating ? "Neural Pulse active" : "Idle")
                        Text("Mode: Local-only")
                    }
                }
                .padding()
            }
            .background(LinearGradient(colors: [Color.cyan.opacity(0.2), .white], startPoint: .topLeading, endPoint: .bottomTrailing))
            .navigationTitle("System")
        }
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
