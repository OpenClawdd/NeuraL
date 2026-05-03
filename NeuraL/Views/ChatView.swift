import SwiftUI

struct ChatView: View {
    @StateObject private var chatState = ChatState()
    @State private var inputText = ""
    @State private var backgroundAngle: Double = 0
    private let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Animated background
            AngularGradient(colors: [.blue, .purple, .pink, .cyan, .blue], center: .center)
                .hueRotation(.degrees(backgroundAngle))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatState.messages) { msg in
                                MessageBubble(message: msg)
                            }

                            // Special Thinking View
                            if chatState.isGenerating {
                                ThinkingView(streamedText: chatState.streamingText)
                                    .id("thinking")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chatState.messages.count) {
                        withAnimation { proxy.scrollTo(chatState.messages.last?.id, anchor: .bottom) }
                    }
                    .onChange(of: chatState.streamingText) {
                        withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                    }
                }

                // Input bar
                HStack(spacing: 8) {
                    TextField("Message...", text: $inputText)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(25)

                    Button {
                        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        chatState.sendMessage(inputText)
                        inputText = ""
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.linear(duration: 0.05)) {
                backgroundAngle += 0.15
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }
            Text(message.content)
                .padding(14)
                .background(message.role == .user ? Color.blue.opacity(0.8) : Color.white.opacity(0.2))
                .foregroundColor(message.role == .user ? .white : .primary)
                .cornerRadius(22)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            if message.role == .assistant { Spacer() }
        }
    }
}

// MARK: - Special Thinking View

struct ThinkingView: View {
    let streamedText: String
    @State private var shimmerPhase: CGFloat = 0
    @State private var dotCount = 0

    private let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    private let shimmerTimer = Timer.publish(every: 0.02, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Shimmer glow header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.cyan.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .scaleEffect(dotCount >= 1 ? 1.2 : 0.8)
                Circle()
                    .fill(Color.mint.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .scaleEffect(dotCount >= 2 ? 1.2 : 0.8)
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .scaleEffect(dotCount >= 3 ? 1.2 : 0.8)
                Text("Thinking…")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            // Streaming text with shimmer
            Text(streamedText.isEmpty ? "..." : streamedText)
                .font(.body)
                .foregroundColor(.primary)
                .padding(12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.6), .blue.opacity(0.2), .cyan.opacity(0.6)],
                                    startPoint: UnitPoint(x: shimmerPhase, y: 0),
                                    endPoint: UnitPoint(x: shimmerPhase + 1, y: 0)
                                ),
                                lineWidth: 1.5
                            )
                    }
                )
                .shadow(color: .cyan.opacity(0.15), radius: 8, y: 2)
        }
        .onReceive(timer) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                dotCount = (dotCount + 1) % 4
            }
        }
        .onReceive(shimmerTimer) { _ in
            withAnimation(.linear(duration: 0.02)) {
                shimmerPhase += 0.01
                if shimmerPhase > 1 { shimmerPhase = 0 }
            }
        }
    }
}
