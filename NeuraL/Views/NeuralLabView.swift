import SwiftUI

struct NeuralLabView: View {
    @ObservedObject var chatState: ChatState
    @State private var activeFeature: LabFeature.ID?
    @State private var memoryEnabled = true
    @State private var sourceLensEnabled = true
    @State private var pulseCoachEnabled = true

    private let features = [
        LabFeature(
            title: "Neural Pulse",
            subtitle: "Live intent, momentum, and next-move tracking inside chat.",
            icon: "waveform.path.ecg",
            tint: .blue
        ),
        LabFeature(
            title: "Source Lens",
            subtitle: "Document-aware answers with local citations and gaps.",
            icon: "doc.text.magnifyingglass",
            tint: .teal
        ),
        LabFeature(
            title: "Memory Pins",
            subtitle: "Pin key answers so the workspace keeps what matters visible.",
            icon: "pin.fill",
            tint: .orange
        ),
        LabFeature(
            title: "Mode Morphing",
            subtitle: "Switch between Copilot, Research, Builder, and Coach without starting over.",
            icon: "switch.2",
            tint: .purple
        )
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    overview
                    swarmStatus
                    featureGrid
                    controls
                    pinnedPanel
                    shadowPanel
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lab")
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Competitive Edge", systemImage: "sparkles")
                .font(.headline)
            Text("The app's signature mechanic is a live workspace layer around the model: Pulse for direction, Pins for memory, and modes that change the assistant's behavior without hiding the chat.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .labPanel()
    }

    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(features) { feature in
                Button {
                    activeFeature = feature.id
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: feature.icon)
                            .font(.title3)
                            .foregroundStyle(feature.tint)
                            .frame(width: 36, height: 36)
                            .background(feature.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                        Text(feature.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(feature.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(activeFeature == feature.id ? feature.tint.opacity(0.45) : .clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var swarmStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("HiveMind Status", systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
                Text(chatState.swarmSnapshot.state.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }

            HStack(spacing: 10) {
                LabMetric(
                    title: "Local",
                    value: String(format: "%.1f tok/s", chatState.swarmSnapshot.local.tokensPerSecond),
                    icon: "iphone"
                )
                LabMetric(
                    title: "Consensus",
                    value: "\(Int(chatState.swarmSnapshot.consensusScore * 100))%",
                    icon: "checkmark.seal"
                )
            }

            if let remote = chatState.swarmSnapshot.remote {
                LabMetric(
                    title: "Remote",
                    value: "\(remote.modelName) · \(String(format: "%.1f tok/s", remote.tokensPerSecond))",
                    icon: "cloud"
                )
            }

            Text(chatState.swarmSnapshot.critique)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .labPanel()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Experience Toggles", systemImage: "switch.2")
                .font(.headline)
            Toggle("Pulse Coach Suggestions", isOn: $pulseCoachEnabled)
            Toggle("Source Lens for documents", isOn: $sourceLensEnabled)
            Toggle("Memory Pins", isOn: $memoryEnabled)
        }
        .labPanel()
    }

    private var pinnedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pinned Memory", systemImage: "pin")
                    .font(.headline)
                Spacer()
                Text("\(chatState.pinnedVisibleMessages.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

            if chatState.pinnedVisibleMessages.isEmpty {
                Text("Pinned answers from chat will appear here for quick review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(chatState.pinnedVisibleMessages) { message in
                    Text(message.content)
                        .font(.caption)
                        .lineLimit(3)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .labPanel()
    }

    private var shadowPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Shadow Memory", systemImage: "moon.stars")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    chatState.runShadowSynthesis()
                }
                .font(.caption.bold())
            }

            if chatState.shadowInsights.isEmpty {
                Text("Open the app after a conversation or background the app to let synthesis prepare proactive insights.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(chatState.shadowInsights) { insight in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(insight.title)
                            .font(.subheadline.bold())
                        Text(insight.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(Int(insight.confidence * 100))% confidence")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .labPanel()
    }
}

private struct LabFeature: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
}

private struct LabMetric: View {
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
    func labPanel() -> some View {
        padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
