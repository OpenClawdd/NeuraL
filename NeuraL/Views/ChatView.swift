import SwiftUI

enum AppTab: String, CaseIterable {
    case chat
    case models
    case knowledge
    case lab
    case system
}

struct ChatView: View {
    @State private var chatState: ChatState
    @Binding var selectedTab: AppTab
    @FocusState private var inputFocused: Bool

    init(chatState: ChatState = ChatState(), selectedTab: Binding<AppTab> = .constant(.chat)) {
        _chatState = State(initialValue: chatState)
        _selectedTab = selectedTab
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(hex: "#EAF8FF"), Color(hex: "#DDF3FF")], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    topStatus

                    if chatState.messages.isEmpty && !chatState.isGenerating {
                        starterPrompts
                    }

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(chatState.messages) { msg in
                                messageBubble(msg)
                            }
                            if chatState.isGenerating {
                                VStack(alignment: .leading, spacing: 6) {
                                    if chatState.isTracingReasoning, chatState.dreamSettings.traceVisibility != .never {
                                        NeuralTraceView(message: .assistantMessage(""), isTracing: true, rawTraceAccess: false, isInitiallyExpanded: chatState.dreamSettings.traceVisibility == .always)
                                    }
                                    Text(chatState.streamingText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }

                    DreamboardView(store: chatState.dreamStore, useAsPrompt: { text in
                        chatState.useDreamAsPrompt(text)
                        inputFocused = true
                    }, pinMemory: chatState.pinDreamMemory)

                    composer
                }
                .padding()
            }
            .navigationTitle("NeuraL")
        }
    }

    private var topStatus: some View {
        HStack {
            Label("Local-only", systemImage: "lock.shield")
            Spacer()
            if chatState.isGenerating { Text("Neural Pulse") }
        }
        .font(.caption)
        .padding(10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var starterPrompts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions").font(.headline)
            HStack {
                Button("Summarize notes") { chatState.inputText = "Summarize my notes into key bullets." }
                Button("Plan next step") { chatState.inputText = "Suggest the next best action." }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if msg.role == .assistant, msg.reasoningTrace?.isEmpty == false, chatState.dreamSettings.traceVisibility != .never {
                NeuralTraceView(message: msg, isTracing: false, rawTraceAccess: chatState.dreamSettings.rawTraceAccess, isInitiallyExpanded: chatState.dreamSettings.traceVisibility == .always)
            }
            Text(msg.content)
                .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message NeuraL", text: $chatState.inputText, axis: .vertical)
                .focused($inputFocused)
                .textFieldStyle(.roundedBorder)
            Button(action: chatState.sendCurrentInput) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .disabled(chatState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatState.isGenerating)
        }
    }
}
