import SwiftUI
import UIKit

struct ChatView: View {
    @ObservedObject var chatState: ChatState
    @State private var inputText = ""
    @State private var showPulse = true
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                if showPulse {
                                    NeuralPulseCard(
                                        pulse: chatState.pulse,
                                        mode: chatState.selectedMode,
                                        tokenCount: chatState.contextTokensUsed,
                                        pinnedCount: chatState.pinnedVisibleMessages.count,
                                        onUseSuggestion: useSuggestion
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.top, 14)
                                }

                                if chatState.visibleMessages.count <= 1 {
                                    StarterGrid(mode: chatState.selectedMode, onSelect: useSuggestion)
                                        .padding(.horizontal, 16)
                                }

                                ForEach(chatState.visibleMessages) { message in
                                    MessageBubble(
                                        message: message,
                                        isPinned: chatState.pinnedMessages.contains(message.id),
                                        onCopy: { copy(message.content) },
                                        onPin: { chatState.togglePin(message) },
                                        onRegenerate: { chatState.regenerateLastAssistant() }
                                    )
                                    .id(message.id)
                                    .padding(.horizontal, 16)
                                }

                                if chatState.isGenerating {
                                    ThinkingView(streamedText: chatState.streamingText)
                                        .id("thinking")
                                        .padding(.horizontal, 16)
                                }
                            }
                            .padding(.bottom, 12)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: chatState.messages.count) {
                            scrollToBottom(proxy)
                        }
                        .onChange(of: chatState.streamingText) {
                            scrollToBottom(proxy)
                        }
                    }

                    composer
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NeuraL")
                        .font(.title2.bold())
                    Text(chatState.conversationTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    withAnimation(.snappy) { showPulse.toggle() }
                } label: {
                    Image(systemName: showPulse ? "waveform.path.ecg.rectangle.fill" : "waveform.path.ecg.rectangle")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle Neural Pulse")

                Menu {
                    Button("Regenerate last answer", systemImage: "arrow.clockwise") {
                        chatState.regenerateLastAssistant()
                    }
                    Button("Clear workspace", systemImage: "trash", role: .destructive) {
                        chatState.clearConversation()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                }
                .buttonStyle(.plain)
            }

            ModeSelector(selectedMode: $chatState.selectedMode)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(.separator).opacity(0.25))
                .frame(height: 0.5)
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            QuickActionStrip(mode: chatState.selectedMode, onSelect: useSuggestion)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask NeuraL...", text: $inputText, axis: .vertical)
                    .focused($composerFocused)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(chatState.selectedMode.tint.opacity(composerFocused ? 0.5 : 0.12), lineWidth: 1)
                    }

                Button {
                    if chatState.isGenerating {
                        chatState.stopGeneration()
                    } else {
                        send()
                    }
                } label: {
                    Image(systemName: chatState.isGenerating ? "stop.fill" : "arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(chatState.isGenerating ? Color.red : chatState.selectedMode.tint, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!chatState.isGenerating && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(!chatState.isGenerating && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.separator).opacity(0.25))
                .frame(height: 0.5)
        }
    }

    private func send() {
        let text = inputText
        inputText = ""
        chatState.sendMessage(text)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func useSuggestion(_ text: String) {
        inputText = text
        composerFocused = true
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy) {
            if chatState.isGenerating {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let last = chatState.visibleMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

private struct ModeSelector: View {
    @Binding var selectedMode: NeuralMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NeuralMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.systemImage)
                            Text(mode.rawValue)
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                        .foregroundStyle(selectedMode == mode ? .white : mode.tint)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(selectedMode == mode ? mode.tint : Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct NeuralPulseCard: View {
    let pulse: NeuralPulse
    let mode: NeuralMode
    let tokenCount: Int
    let pinnedCount: Int
    let onUseSuggestion: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Neural Pulse", systemImage: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(mode.tint)
                Spacer()
                Text(mode.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(mode.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(mode.tint.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 10) {
                PulseMetric(title: "Intent", value: pulse.intent, icon: "scope")
                PulseMetric(title: "Momentum", value: pulse.momentum, icon: "bolt")
            }

            HStack(spacing: 10) {
                PulseMetric(
                    title: "Consensus",
                    value: "\(pulse.consensus) · \(Int(pulse.confidence * 100))%",
                    icon: "brain.head.profile"
                )
                PulseMetric(
                    title: "Token Burn",
                    value: tokenBurnLabel,
                    icon: "speedometer"
                )
            }

            PulseMetric(title: "Sandbox", value: pulse.sandboxStatus, icon: "macwindow.on.rectangle")

            if let shadowInsight = pulse.shadowInsight {
                PulseMetric(title: "Shadow Memory", value: shadowInsight, icon: "moon.stars")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Next Best Moves")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(pulse.nextMoves, id: \.self) { move in
                    Button {
                        onUseSuggestion(move)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.forward")
                                .font(.caption)
                                .foregroundStyle(mode.tint)
                            Text(move)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                Label("\(tokenCount) tokens", systemImage: "number")
                Label("\(pinnedCount) pinned", systemImage: "pin")
                Spacer()
                Text(pulse.caution)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(mode.tint.opacity(0.18), lineWidth: 1)
        }
    }

    private var tokenBurnLabel: String {
        let local = String(format: "L %.1f/s", pulse.localTokenRate)
        guard let remoteRate = pulse.remoteTokenRate else { return local }
        return local + " · " + String(format: "R %.1f/s", remoteRate)
    }
}

private struct PulseMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct StarterGrid: View {
    let mode: NeuralMode
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start fast")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(mode.starterPrompts, id: \.self) { prompt in
                Button {
                    onSelect(prompt)
                } label: {
                    HStack {
                        Image(systemName: mode.systemImage)
                            .foregroundStyle(mode.tint)
                        Text(prompt)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct QuickActionStrip: View {
    let mode: NeuralMode
    let onSelect: (String) -> Void

    private var actions: [(String, String)] {
        [
            ("wand.and.stars", "Improve this"),
            ("checklist", "Make a checklist"),
            ("doc.text.magnifyingglass", "Find gaps"),
            ("timer", "30-minute sprint")
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions, id: \.1) { icon, title in
                    Button {
                        onSelect(title)
                    } label: {
                        Label(title, systemImage: icon)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(mode.tint.opacity(0.1), in: Capsule())
                            .foregroundStyle(mode.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let isPinned: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onRegenerate: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            if message.role == .user { Spacer(minLength: 46) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .textSelection(.enabled)
                    .padding(14)
                    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(alignment: .topTrailing) {
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(7)
                        }
                    }

                if let artifact = message.artifact, message.role == .assistant {
                    ArtifactSandboxView(artifact: artifact)
                        .frame(maxWidth: 360)
                }

                HStack(spacing: 10) {
                    Text(message.timestamp, style: .time)
                    if let tokens = message.tokenInfo?.totalTokenCount {
                        Text("\(tokens) tok")
                    }
                    Button("Copy", action: onCopy)
                    Button(isPinned ? "Unpin" : "Pin", action: onPin)
                    if message.role == .assistant {
                        Button("Retry", action: onRegenerate)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            if message.role == .assistant { Spacer(minLength: 46) }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(Color.blue)
        }
        return AnyShapeStyle(Color(.secondarySystemGroupedBackground))
    }
}

struct ThinkingView: View {
    let streamedText: String
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.blue.opacity(dotCount == index ? 1 : 0.35))
                            .frame(width: 7, height: 7)
                    }
                    Text("Thinking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(streamedText.isEmpty ? "Preparing a response..." : streamedText)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

            Spacer(minLength: 46)
        }
        .onReceive(timer) { _ in
            withAnimation(.snappy) { dotCount = (dotCount + 1) % 3 }
        }
    }
}
