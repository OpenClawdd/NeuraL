import SwiftUI

struct ModelsView: View {
    @ObservedObject var chatState: ChatState
    @State private var selectedModel = "Llama 3.2 3B"
    @State private var temperature = 0.7
    @State private var contextLength = 2048.0
    @State private var privateMode = true
    @AppStorage("neural.openrouter.apiKey") private var openRouterAPIKey = ""

    private let models = [
        ModelCard(name: "Llama 3.2 1B", size: "1.3 GB", speed: "Fast", bestFor: "Quick drafts, summaries, low memory", tier: "Everyday"),
        ModelCard(name: "Llama 3.2 3B", size: "2.4 GB", speed: "Balanced", bestFor: "Reasoning, coding help, richer chat", tier: "Recommended"),
        ModelCard(name: "Phi 3 Mini", size: "2.2 GB", speed: "Fast", bestFor: "Structured answers and technical work", tier: "Pro"),
        ModelCard(name: "Gemma 2 2B", size: "1.8 GB", speed: "Efficient", bestFor: "Creative writing and instruction following", tier: "Creative")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusPanel
                    swarmPanel
                    modelList
                    tuningPanel
                    privacyPanel
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Models")
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Runtime", systemImage: "cpu")
                    .font(.headline)
                Spacer()
                Text(chatState.engineState.capitalized)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 10) {
                ModelMetric(title: "Selected", value: selectedModel, icon: "cube")
                ModelMetric(title: "Context", value: "\(Int(contextLength))", icon: "rectangle.stack")
            }
        }
        .panelStyle()
    }

    private var modelList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model Fleet")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(models) { model in
                Button {
                    selectedModel = model.name
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(model.name == selectedModel ? Color.blue.opacity(0.14) : Color(.tertiarySystemGroupedBackground))
                                .frame(width: 44, height: 44)
                            Image(systemName: model.name == selectedModel ? "checkmark.seal.fill" : "cube.transparent")
                                .foregroundStyle(model.name == selectedModel ? .blue : .secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(model.name)
                                    .font(.subheadline.bold())
                                Text(model.tier)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.1), in: Capsule())
                            }
                            Text(model.bestFor)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(model.speed)
                                .font(.caption.bold())
                            Text(model.size)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(model.name == selectedModel ? Color.blue.opacity(0.45) : .clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var swarmPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("HiveMind Protocol", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            Text("Copilot and Builder can pair a local supervisor with an OpenRouter remote generator. The local node scores alignment while the remote node streams.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("OpenRouter API key", text: $openRouterAPIKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Label(openRouterAPIKey.isEmpty ? "Remote node inactive" : "Remote node armed", systemImage: openRouterAPIKey.isEmpty ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(openRouterAPIKey.isEmpty ? .secondary : .green)
                Spacer()
                Text("DeepSeek-R1")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
        }
        .panelStyle()
    }

    private var tuningPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Generation Tuning", systemImage: "slider.horizontal.3")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.1f", temperature))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $temperature, in: 0.1...1.2, step: 0.1)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Context Window")
                    Spacer()
                    Text("\(Int(contextLength)) tokens")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $contextLength, in: 1024...8192, step: 512)
            }
        }
        .panelStyle()
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $privateMode) {
                Label("Privacy Lock", systemImage: privateMode ? "lock.shield.fill" : "lock.open")
                    .font(.headline)
            }

            Text(privateMode ? "Chat, document search, and model execution stay local-first." : "External integrations can be enabled later from settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var statusColor: Color {
        chatState.isGenerating ? .orange : .green
    }
}

private struct ModelCard: Identifiable {
    var id: String { name }
    let name: String
    let size: String
    let speed: String
    let bestFor: String
    let tier: String
}

private struct ModelMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension View {
    func panelStyle() -> some View {
        padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
