//
//  ChatView.swift
//  NeuraL
//
//  Phase 3 — The Native SwiftUI Chat Interface
//  Frutiger Aero Edition — Glassy, Glossy, Vibrant, Translucent
//
//  This is the primary user-facing view. It provides:
//
//  1. Message list with role-based bubble styling (user right, assistant left)
//  2. Live streaming text with blinking cursor during generation
//  3. Markdown rendering for finalized assistant messages
//  4. Context/memory indicator bar at the top
//  5. Text input with send/stop button at the bottom
//  6. Auto-scroll to bottom as new tokens arrive (debounced during streaming)
//  7. Model loading state with progress indicator
//  8. Eviction notification banner
//  9. Empty/onboarding state when no model is loaded
//  10. Regenerate button on last assistant message
//  11. Keyboard-aware layout with dismiss-on-scroll
//
//  Architecture:
//  - ChatView owns the ChatState object
//  - All state reads happen through @Observable property access
//  - All mutations happen through ChatState methods (MainActor-bound)
//  - The view never touches the InferenceOrchestrator directly
//
//  Frutiger Aero Styling:
//  - Soft blue gradient background with slow-moving RadialGradient
//  - Frosted glass bubbles (ultraThinMaterial/regularMaterial)
//  - Gloss highlight overlays on all interactive elements
//  - GPU-safe: decorative animations pause when isGenerating is true
//  - Haptic feedback on button taps
//  - Rounded system fonts for friendly appearance
//

import SwiftUI

// MARK: - Chat View

struct ChatView: View {
    @State private var chatState: ChatState
    @Binding var selectedTab: AppTab

    // Auto-scroll state
    @State private var scrollProxy: ScrollViewProxy?
    @FocusState private var isInputFocused: Bool

    // Debounce timer for auto-scroll during streaming
    @State private var scrollDebounceTask: Task<Void, Never>?

    // Frutiger Aero: background animation state
    @State private var bgGradientShift: CGFloat = 0.0

    // Frutiger Aero: button press states
    @State private var sidebarPressed = false
    @State private var exportPressed = false
    @State private var clearPressed = false
    @State private var sendPressed = false
    @State private var stopPressed = false
    @State private var goToModelsPressed = false

    @MainActor init(chatState: ChatState = ChatState(), selectedTab: Binding<AppTab> = .constant(.chat)) {
        self._chatState = State(initialValue: chatState)
        self._selectedTab = selectedTab
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // ── Frutiger Aero Background ──────────────────────────
                // Soft blue gradient with subtle RadialGradient that shifts slowly.
                // PAUSE the gradient shift when generating to free GPU.
                LinearGradient(
                    colors: [
                        Color(hex: "#E0F7FA"),
                        Color(hex: "#B2EBF2")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Subtle slow-moving radial glow (paused when generating)
                if !chatState.isGenerating {
                    RadialGradient(
                        colors: [
                            FrutigerAeroTheme.shared.vibrantCyan.opacity(0.12),
                            Color.white.opacity(0.0)
                        ],
                        center: UnitPoint(
                            x: 0.5 + sin(bgGradientShift) * 0.15,
                            y: 0.4 + cos(bgGradientShift * 0.7) * 0.1
                        ),
                        startRadius: 50,
                        endRadius: 500
                    )
                    .ignoresSafeArea()
                    .onAppear {
                        withAnimation(
                            .linear(duration: 12.0).repeatForever(autoreverses: true)
                        ) {
                            bgGradientShift = .pi * 2
                        }
                    }
                } else {
                    // Static version when generating — no animation
                    RadialGradient(
                        colors: [
                            FrutigerAeroTheme.shared.vibrantCyan.opacity(0.08),
                            Color.white.opacity(0.0)
                        ],
                        center: UnitPoint(x: 0.5, y: 0.4),
                        startRadius: 50,
                        endRadius: 500
                    )
                    .ignoresSafeArea()
                }

                // ── Main Content ──────────────────────────────────────
                VStack(spacing: 0) {
                    // -- Top Bar: Context & Memory Indicator
                    contextIndicatorBar

                    // -- Memory Pressure Warning
                    if chatState.isUnderMemoryPressure {
                        memoryPressureBanner
                    }

                    // -- Eviction Notice Banner
                    if chatState.lastEvictionNotice != nil {
                        evictionBanner
                    }

                    // -- Main Content Area
                    if chatState.conversation.conversationalMessages.isEmpty
                        && chatState.streamingText.isEmpty
                        && !chatState.isGenerating
                        && chatState.thinkingText.isEmpty {
                        // Empty / onboarding state
                        emptyState
                    } else {
                        // Message list
                        messageList
                    }

                    // -- Error Banner
                    if chatState.lastError != nil {
                        errorBanner
                    }

                    // -- Input Bar
                    inputBar
                }
            }
            .navigationTitle("NeuraL")
            .navigationBarTitleDisplayMode(.inline)
            // Phase 7.1: Apply theme
            .preferredColorScheme(ThemeManager.shared.preferredColorScheme)
            .tint(ThemeManager.shared.accentColorValue)
            .toolbar(id: "main") {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        FrutigerAeroTheme.shared.lightHaptic()
                        showConversations = true
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .accessibilityLabel("Conversation list")
                    .accessibilityHint("Open conversation sidebar to browse history")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    exportButton
                    modelStatusButton
                    clearButton
                }
            }
            .sheet(isPresented: $showModelLoader) {
                // In the tab-based app, this sheet is a shortcut to the Models tab.
                // We show a simple prompt to switch tabs.
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "cube.box.fill")
                            .font(.system(size: 48, weight: .light, design: .rounded))
                            .foregroundStyle(FrutigerAeroTheme.shared.neonBlue)

                        Text("Manage Models")
                            .font(.system(.title2, design: .rounded).bold())

                        Text("Switch to the Models tab to browse, download, or import GGUF models.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .navigationTitle("Load Model")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(id: "main") {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showModelLoader = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showConversations) {
                ConversationsSidebar(chatState: $chatState)
            }
            .sheet(isPresented: $showExportSheet) {
                ExportSheet(conversation: chatState.conversation)
            }
            // Phase 7.3: Reaction picker overlay
            .overlay {
                if let messageId = chatState.showReactionPickerFor {
                    ReactionPicker { emoji in
                        chatState.addReaction(emoji: emoji, to: messageId)
                        chatState.showReactionPickerFor = nil
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 100)
                    .background(Color.black.opacity(0.2).ignoresSafeArea().onTapGesture {
                        chatState.showReactionPickerFor = nil
                    })
                }
            }
        }
    }

    // MARK: - Sheet State

    @State private var showModelLoader = false
    @State private var showConversations = false
    @State private var showExportSheet = false

    // MARK: - Context Indicator Bar

    /// A thin bar at the top showing context window utilization and memory.
    /// Frutiger Aero: capsule with .regularMaterial, glowing border when >80% context used.
    private var contextIndicatorBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                // Context tokens
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("Tokens: \(chatState.contextTokensUsed)/\(chatState.maxContextTokens)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Context: \(chatState.contextTokensUsed) of \(chatState.maxContextTokens) tokens used")
                .accessibilityValue("\(Int(chatState.contextUtilization * 100)) percent")

                // Context utilization bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.gray.opacity(0.2))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(contextBarColor)
                            .frame(width: geo.size.width * min(1.0, chatState.contextUtilization))
                    }
                }
                .frame(height: 4)

                // Memory indicator
                if let snapshot = chatState.memorySnapshot {
                    HStack(spacing: 4) {
                        Image(systemName: "memorychip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(String(format: "%.0f MB", Double(snapshot.availableBytes) / 1_048_576))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        // Frutiger Aero: frosted capsule with glowing border when context >80%
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    chatState.contextUtilization > 0.8
                        ? FrutigerAeroTheme.shared.neonBlue.opacity(0.6)
                        : Color.white.opacity(0.2),
                    lineWidth: chatState.contextUtilization > 0.8 ? 1.5 : 0.5
                )
        )
        .shadow(
            color: chatState.contextUtilization > 0.8
                ? FrutigerAeroTheme.shared.neonBlue
                : Color.clear,
            radius: 4
        )
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    /// Color for the context utilization bar based on usage level.
    private var contextBarColor: Color {
        switch chatState.contextUtilization {
        case ..<0.5:  return .green
        case ..<0.75: return .yellow
        case ..<0.9:  return .orange
        default:       return .red
        }
    }

    // MARK: - Memory Pressure Banner

    /// Frutiger Aero: frosted glass with colored left border accent.
    private var memoryPressureBanner: some View {
        HStack(spacing: 8) {
            // Left accent border
            RoundedRectangle(cornerRadius: 2)
                .fill(.orange)
                .frame(width: 3)

            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Low Memory Warning")
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundStyle(.primary)

                if let draft = chatState.memoryPressureDraft {
                    Text("Your message was saved as a draft: \"\(draft.prefix(50))\u{2026}\"")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("The device is low on memory. Generation was stopped to prevent data loss.")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                FrutigerAeroTheme.shared.lightHaptic()
                chatState.isUnderMemoryPressure = false
                chatState.memoryPressureDraft = nil
                Task {
                    await MemoryManager.shared.setUnderMemoryPressure(false)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss memory warning")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 4, x: 0, y: 2)
        .padding(.horizontal, 12)
    }

    // MARK: - Eviction Banner

    /// Frutiger Aero: frosted glass with colored left border accent.
    private var evictionBanner: some View {
        HStack(spacing: 8) {
            // Left accent border
            RoundedRectangle(cornerRadius: 2)
                .fill(.orange)
                .frame(width: 3)

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.orange)

            Text(chatState.lastEvictionNotice ?? "")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                FrutigerAeroTheme.shared.lightHaptic()
                chatState.lastEvictionNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 4, x: 0, y: 2)
        .padding(.horizontal, 12)
    }

    // MARK: - Empty / Onboarding State

    /// Shown when no model is loaded and no messages exist.
    /// Provides clear instructions for the user to get started.
    /// Frutiger Aero: large icon with shimmer (STOP shimmer when inference active).
    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon / branding area — glossy interlocking N logo
            // GPU-safe: shimmer pauses during inference
            AppIconView(size: 120, isGenerating: chatState.isGenerating)

            VStack(spacing: 8) {
                Text("NeuraL")
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundStyle(.primary)

                Text("Private, on-device AI inference")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            if !chatState.isReady {
                // No model loaded — prompt to go to Models tab
                VStack(spacing: 12) {
                    Text("Download or import a GGUF model to begin chatting")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        FrutigerAeroTheme.shared.lightHaptic()
                        selectedTab = .models
                    } label: {
                        Label("Go to Models", systemImage: "cube.box.fill")
                            .font(.system(.body, design: .rounded).bold())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(FrutigerAeroButtonStyle(isPressed: $goToModelsPressed))
                    .controlSize(.large)
                }
                .padding(.horizontal, 40)

                // Supported models hint
                VStack(alignment: .leading, spacing: 6) {
                    Text("Supported Models")
                        .font(.system(.caption, design: .rounded).bold())
                        .foregroundStyle(.tertiary)

                    VStack(alignment: .leading, spacing: 4) {
                        modelHintRow("Llama-3.2-1B-Instruct Q4_K_M", size: "~762 MB")
                        modelHintRow("Llama-3.2-3B-Instruct Q4_K_M", size: "~2.0 GB")
                        modelHintRow("Gemma-2-2B-it Q4_K_M", size: "~1.4 GB")
                        modelHintRow("Phi-3-mini-4k-instruct Q4_K_M", size: "~2.4 GB")
                    }
                }
                .padding(.horizontal, 40)
            } else {
                // Model loaded, just no messages yet
                Text("Type a message below to start chatting")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func modelHintRow(_ name: String, size: String) -> some View {
        HStack {
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(size)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Message List

    /// Thinking phase tracker for the live animation
    @State private var thinkingTracker = ThinkingPhaseTracker()

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // System prompt (if present)
                    if let systemMsg = chatState.conversation.systemPrompt {
                        SystemMessageBubble(message: systemMsg)
                            .id(systemMsg.id)
                    }

                    // Conversational messages
                    ForEach(Array(chatState.conversation.conversationalMessages.enumerated()), id: \.element.id) { index, message in
                        let isLastAssistant = message.role == .assistant &&
                            index == chatState.conversation.conversationalMessages.count - 1

                        // Thinking summary above assistant messages that had reasoning
                        if message.role == .assistant, let reasoning = message.thinkingText {
                            ThinkingSummaryView(
                                reasoningText: reasoning,
                                durationSeconds: message.thinkingDurationSeconds
                            )
                            .id("thinking-summary-\(message.id)")
                            .padding(.leading, 12)
                            .accessibilityLabel("Reasoning: thought for \(String(format: "%.1f", message.thinkingDurationSeconds)) seconds")
                            .accessibilityHint("Double tap to expand reasoning details")
                        }

                        MessageBubbleView(
                            message: message,
                            style: message.role == .user ? .user : .assistant,
                            showRegenerate: isLastAssistant && !chatState.isGenerating,
                            onRegenerate: {
                                chatState.regenerateLastResponse()
                            }
                        )
                        .id(message.id)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(message.role == .user ? "User" : "Assistant") message: \(message.content.prefix(200))")
                        .accessibilityHint(message.role == .assistant ? "Assistant response" : "Your message")
                        // Phase 7.3: Context menu for branching, editing, reactions
                        .contextMenu {
                            if message.role == .assistant {
                                Button {
                                    chatState.regenerateFromMessage(id: message.id)
                                } label: {
                                    Label("Regenerate from Here", systemImage: "arrow.clockwise")
                                }
                            }
                            Button {
                                chatState.showReactionPickerFor = message.id
                            } label: {
                                Label("Add Reaction", systemImage: "face.smiling")
                            }
                            Button {
                                UIPasteboard.general.string = message.content
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }

                    // ── Thinking Bubble ────────────────────────────────────
                    // Shows during the gap between "generation started" and
                    // "first token appears." This is the satisfying animation.
                    if chatState.isThinking || !chatState.thinkingText.isEmpty {
                        ThinkingBubbleView(
                            phase: chatState.thinkingText.isEmpty
                                ? thinkingTracker.phase
                                : .reasoning,
                            elapsedSeconds: thinkingTracker.elapsedSeconds,
                            reasoningText: chatState.thinkingText.isEmpty
                                ? nil
                                : chatState.thinkingText,
                            isGenerating: chatState.isGenerating
                        )
                        .id("thinking")
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .onChange(of: chatState.isThinking) { _, isThinking in
                            if isThinking {
                                thinkingTracker.start()
                            } else {
                                thinkingTracker.stop()
                            }
                        }
                        .onChange(of: chatState.thinkingText) { _, newText in
                            if !newText.isEmpty {
                                thinkingTracker.setReasoning(true)
                            }
                        }
                        .onAppear {
                            if chatState.isThinking {
                                thinkingTracker.start()
                            }
                        }
                    }

                    // ── Streaming message ──────────────────────────────────
                    // The actual generated text. Appears after thinking completes.
                    if !chatState.streamingText.isEmpty {
                        StreamingBubbleView(text: chatState.streamingText)
                            .id("streaming")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .accessibilityLabel("Assistant is typing: \(chatState.streamingText.prefix(200))")
                            .accessibilityValue("Streaming response")
                    }

                    // Anchor for auto-scroll
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chatState.streamingText) { _, _ in
                // Debounced scroll during streaming: scroll at most once per 80ms
                // instead of on every token (which would be 42 times/sec)
                scheduleDebouncedScroll(proxy: proxy)
            }
            .onChange(of: chatState.isThinking) { _, isThinking in
                if isThinking {
                    // Scroll to show the thinking bubble when it appears
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatState.conversation.messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onAppear {
                scrollProxy = proxy
            }
        }
    }

    // MARK: - Debounced Auto-Scroll

    /// Schedule a debounced scroll to bottom. During streaming at 42 tok/s,
    /// we don't want to trigger 42 animated scrolls per second. Instead,
    /// we coalesce them into a scroll every ~80ms (12.5 scrolls/sec),
    /// which is smooth enough for the eye but doesn't overwhelm the UI.
    private func scheduleDebouncedScroll(proxy: ScrollViewProxy) {
        // Cancel any pending scroll
        scrollDebounceTask?.cancel()

        scrollDebounceTask = Task { @MainActor in
            // Wait 80ms before scrolling
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy: proxy, animated: false)
        }
    }

    /// Scroll to the bottom of the message list.
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                if !chatState.streamingText.isEmpty {
                    proxy.scrollTo("streaming", anchor: .bottom)
                } else {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        } else {
            if !chatState.streamingText.isEmpty {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Error Banner

    /// Frutiger Aero: frosted glass with colored left border accent.
    private var errorBanner: some View {
        HStack(spacing: 8) {
            // Left accent border
            RoundedRectangle(cornerRadius: 2)
                .fill(.red)
                .frame(width: 3)

            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(chatState.lastError?.errorDescription ?? "Unknown error")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer()

            Button("Dismiss") {
                FrutigerAeroTheme.shared.lightHaptic()
                chatState.lastError = nil
            }
            .font(.system(.caption, design: .rounded))
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 4, x: 0, y: 2)
        .padding(.horizontal, 12)
    }

    // MARK: - Input Bar

    /// Frutiger Aero: frosted glass background with glossy send button.
    private var inputBar: some View {
        VStack(spacing: 0) {
            // Phase 6.1: Image attachments bar
            AttachedImagesBar(
                attachments: chatState.pendingImageAttachments,
                onRemove: { id in
                    chatState.removeImageAttachment(id: id)
                }
            )

            HStack(alignment: .bottom, spacing: 8) {
                // Phase 6.1: Image picker button — Frutiger Aero: glassy circle
                if chatState.isReady {
                    ImagePickerButton { attachment in
                        chatState.addImageAttachment(attachment)
                    }
                }

                // Phase 6.4: Microphone button — Frutiger Aero: glassy circle
                if chatState.isReady {
                    MicButton(
                        speechManager: chatState.speechManager,
                        onTranscriptionComplete: { text in
                            inputText = text
                        }
                    )
                }

                // Text field
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                // Phase 6.4: TTS read-aloud button
                if chatState.speechManager.isSpeaking {
                    Button {
                        FrutigerAeroTheme.shared.lightHaptic()
                        chatState.speechManager.stopSpeaking()
                    } label: {
                        Image(systemName: "speaker.slash.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                    }
                } else if let lastAssistant = chatState.conversation.conversationalMessages.last(where: { $0.role == .assistant }) {
                    Button {
                        FrutigerAeroTheme.shared.lightHaptic()
                        chatState.speechManager.speak(lastAssistant.content)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Read last response aloud")
                }

                // Send / Stop button — Frutiger Aero: glossy circular button
                if chatState.isGenerating {
                    Button {
                        FrutigerAeroTheme.shared.lightHaptic()
                        chatState.stopGeneration()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.red.opacity(0.8), .red.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                Circle()
                                    .fill(FrutigerAeroTheme.shared.subtleGloss)
                            )
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(color: .red.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .scaleEffect(stopPressed ? 0.96 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: stopPressed)
                    .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                        stopPressed = pressing
                    }, perform: {})
                    .accessibilityLabel("Stop generation")
                } else {
                    let canSend = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !chatState.pendingImageAttachments.isEmpty

                    Button {
                        FrutigerAeroTheme.shared.lightHaptic()
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(
                                        canSend
                                            ? FrutigerAeroTheme.shared.buttonGradient
                                            : LinearGradient(
                                                colors: [.gray.opacity(0.4), .gray.opacity(0.3)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                    )
                            )
                            .overlay(
                                Circle()
                                    .fill(FrutigerAeroTheme.shared.subtleGloss)
                            )
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.3), lineWidth: 0.5)
                            )
                            .shadow(
                                color: canSend
                                    ? FrutigerAeroTheme.shared.neonBlue.opacity(0.3)
                                    : Color.clear,
                                radius: canSend ? 6 : 0, x: 0, y: 3
                            )
                    }
                    .scaleEffect(sendPressed ? 0.96 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: sendPressed)
                    .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                        sendPressed = pressing
                    }, perform: {})
                    .disabled(!canSend)
                    .disabled(!chatState.isReady)
                    .accessibilityLabel("Send message")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // Frutiger Aero: frosted glass background
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(
                        FrutigerAeroTheme.shared.glossHighlight
                            .opacity(0.15)
                    )
                    .frame(height: 1),
                alignment: .top
            )
        }
    }

    @State private var inputText = ""

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !chatState.pendingImageAttachments.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        chatState.sendMessage(text)
    }

    // MARK: - Toolbar Buttons

    private var modelStatusButton: some View {
        Button {
            FrutigerAeroTheme.shared.lightHaptic()
            selectedTab = .models
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(engineStateColor)
                    .frame(width: 8, height: 8)

                Text(engineStateLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Frutiger Aero: use theme colors for engine state indicator.
    private var engineStateColor: Color {
        switch chatState.engineState {
        case .idle:       return .gray
        case .loading:    return FrutigerAeroTheme.shared.goldAccent
        case .ready:      return FrutigerAeroTheme.shared.softTeal
        case .generating: return FrutigerAeroTheme.shared.neonBlue
        case .error:      return .red
        case .unloading:  return .gray
        }
    }

    private var engineStateLabel: String {
        switch chatState.engineState {
        case .idle:       return NSLocalizedString("No Model", comment: "Engine state: no model loaded")
        case .loading:    return NSLocalizedString("Loading...", comment: "Engine state: loading model")
        case .ready:      return NSLocalizedString("Ready", comment: "Engine state: ready")
        case .generating: return NSLocalizedString("Generating...", comment: "Engine state: generating")
        case .error:      return NSLocalizedString("Error", comment: "Engine state: error")
        case .unloading:  return NSLocalizedString("Unloading", comment: "Engine state: unloading")
        }
    }

    private var clearButton: some View {
        Button {
            FrutigerAeroTheme.shared.lightHaptic()
            chatState.clearConversation()
        } label: {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
        }
        .scaleEffect(clearPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: clearPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            clearPressed = pressing
        }, perform: {})
        .disabled(chatState.isGenerating)
        .accessibilityLabel("Clear conversation")
        .accessibilityHint("Clear all messages and start a new conversation")
    }

    // MARK: - Phase 7: Export Button

    private var exportButton: some View {
        Button {
            FrutigerAeroTheme.shared.lightHaptic()
            showExportSheet = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundStyle(.secondary)
        }
        .scaleEffect(exportPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: exportPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            exportPressed = pressing
        }, perform: {})
        .disabled(chatState.conversation.conversationalMessages.isEmpty)
        .accessibilityLabel("Export conversation")
    }
}

// MARK: - Frutiger Aero Button Style

/// A custom button style that applies Frutiger Aero glossy gradient + scale on press.
struct FrutigerAeroButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(FrutigerAeroTheme.shared.buttonGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .fill(FrutigerAeroTheme.shared.subtleGloss)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(
                color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3),
                radius: 6, x: 0, y: 3
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - System Message Bubble

/// A centered system message with distinct visual treatment.
/// Frutiger Aero: frosted glass with orange tint.
struct SystemMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 40)

            Text(message.content)
                .font(.system(.caption, design: .rounded))
                .italic()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.06))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
                .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 4, x: 0, y: 2)

            Spacer(minLength: 40)
        }
    }
}

// MARK: - Message Bubble View

/// A single message bubble in the chat interface.
///
/// Frutiger Aero styling:
/// - User bubble: frosted glass (ultraThinMaterial), gloss highlight, blue-tinted glass
/// - Assistant bubble: frosted glass (regularMaterial), gloss highlight, white-tinted glass
/// - Both have soft drop shadows and the BubbleShape tail preserved.
struct MessageBubbleView: View {
    let message: ChatMessage
    let style: MessageBubbleStyle
    let showRegenerate: Bool
    let onRegenerate: () -> Void

    init(
        message: ChatMessage,
        style: MessageBubbleStyle,
        showRegenerate: Bool = false,
        onRegenerate: @escaping () -> Void = {}
    ) {
        self.message = message
        self.style = style
        self.showRegenerate = showRegenerate
        self.onRegenerate = onRegenerate
    }

    var body: some View {
        HStack {
            if style.alignment == .trailing {
                Spacer(minLength: 40)
            }

            VStack(alignment: style.alignment == .trailing ? .trailing : .leading, spacing: 4) {
                // Role label
                Text(roleLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                // Phase 6.1: Image attachments (user messages)
                if let images = message.imageAttachments, !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(images) { attachment in
                                MessageImageView(attachment: attachment)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }

                // Phase 6.2: Function call records (assistant messages)
                if let functionCalls = message.functionCalls, !functionCalls.isEmpty {
                    FunctionCallIndicator(functionCalls: functionCalls)
                        .padding(.horizontal, 12)
                }

                // Phase 6.3: RAG source citations (assistant messages)
                if let ragSources = message.ragSources, !ragSources.isEmpty {
                    RAGSourcesIndicator(sources: ragSources)
                        .padding(.horizontal, 12)
                }

                // Message content — Frutiger Aero: frosted glass bubble
                Group {
                    switch style {
                    case .assistant:
                        // Rendered markdown for finalized assistant messages
                        MarkdownRenderer.renderedText(message.content)
                            .textSelection(.enabled)
                    default:
                        Text(message.content)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(style.foregroundColor)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                // Frutiger Aero: frosted glass background + tint overlay
                .background(
                    // Material layer
                    style == .user ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial)
                )
                .overlay(
                    // Tint overlay — translucent color on top of the material
                    BubbleShape(isUser: style == .user)
                        .fill(style.backgroundColor)
                )
                .clipShape(BubbleShape(isUser: style == .user))
                // Gloss highlight overlay
                .overlay(
                    BubbleShape(isUser: style == .user)
                        .fill(FrutigerAeroTheme.shared.glossHighlight)
                        .opacity(0.25)
                )
                // Border
                .overlay(
                    BubbleShape(isUser: style == .user)
                        .stroke(.white.opacity(0.25), lineWidth: 0.5)
                )
                // Soft drop shadow
                .shadow(
                    color: style == .user
                        ? FrutigerAeroTheme.shared.neonBlue.opacity(0.15)
                        : FrutigerAeroTheme.shared.buttonShadow,
                    radius: 6, x: 0, y: 3
                )
                .frame(maxWidth: 300, alignment: .leading)

                // Generation metadata + regenerate (for assistant messages)
                if style == .assistant {
                    HStack(spacing: 6) {
                        if let metadata = message.generationMetadata {
                            Text(String(format: "%.1f tok/s", metadata.tokensPerSecond))
                            Text("\u{00B7}")  // Middle dot
                            Text("\(metadata.tokensGenerated) tokens")
                            if metadata.stopReason == .cancelled {
                                Text("\u{00B7}")
                                Text("Stopped")
                                    .foregroundStyle(.orange)
                            }
                        }

                        if showRegenerate {
                            if message.generationMetadata != nil {
                                Text("\u{00B7}")
                            }
                            Button {
                                FrutigerAeroTheme.shared.lightHaptic()
                                onRegenerate()
                            } label: {
                                Label("Regenerate", systemImage: "arrow.clockwise")
                                    .font(.system(.caption2, design: .rounded))
                            }
                            .foregroundStyle(FrutigerAeroTheme.shared.neonBlue)
                        }
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                }

                // Phase 7.3: Message reactions
                // Reactions are displayed here if the parent ChatView passes them in
            }

            if style.alignment == .leading {
                Spacer(minLength: 40)
            }
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .system:    return NSLocalizedString("System", comment: "Role label: system")
        case .user:      return NSLocalizedString("You", comment: "Role label: user")
        case .assistant: return NSLocalizedString("Assistant", comment: "Role label: assistant")
        }
    }
}

// MARK: - Streaming Bubble View

/// A special bubble for the currently streaming message.
///
/// Frutiger Aero: similar to assistant but slightly more transparent material,
/// white-tinted glass with gloss highlight.
struct StreamingBubbleView: View {
    let text: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Assistant")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                MarkdownRenderer.streamText(text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    // Frutiger Aero: lighter material for streaming
                    .background(.regularMaterial)
                    .overlay(
                        BubbleShape(isUser: false)
                            .fill(MessageBubbleStyle.streaming.backgroundColor)
                    )
                    .clipShape(BubbleShape(isUser: false))
                    // Gloss highlight
                    .overlay(
                        BubbleShape(isUser: false)
                            .fill(FrutigerAeroTheme.shared.glossHighlight)
                            .opacity(0.2)
                    )
                    .overlay(
                        BubbleShape(isUser: false)
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: FrutigerAeroTheme.shared.buttonShadow, radius: 4, x: 0, y: 2)
                    .frame(maxWidth: 300, alignment: .leading)
            }

            Spacer(minLength: 40)
        }
    }
}

// MARK: - Bubble Shape

/// A custom shape for message bubbles with a "tail" on one side.
///
/// User bubbles have the tail on the bottom-right, assistant on the left.
/// The tail gives the classic chat bubble appearance.
/// Preserved from original — no shape changes, only fill/styling changes.
struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> SwiftUI.Path {
        let cornerRadius: CGFloat = 16
        let tailWidth: CGFloat = 8
        let tailHeight: CGFloat = 14

        var path = SwiftUI.Path()

        if isUser {
            // User bubble: rounded rect with a small tail on bottom-right
            let bubbleRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width - tailWidth,
                height: rect.height - tailHeight
            )

            // Rounded rectangle with asymmetric corners (sharper on tail side)
            path.move(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY))
            path.addLine(to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.minY))
            path.addQuadCurve(
                to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY + cornerRadius),
                control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY)
            )
            path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.maxY),
                control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY)
            )
            // Tail
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: bubbleRect.maxX - cornerRadius * 1.5, y: rect.maxY - tailHeight * 0.3))
            path.addLine(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY - cornerRadius),
                control: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY)
            )
            path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY + cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY),
                control: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY)
            )
        } else {
            // Assistant bubble: rounded rect with a small tail on bottom-left
            let bubbleRect = CGRect(
                x: rect.minX + tailWidth,
                y: rect.minY,
                width: rect.width - tailWidth,
                height: rect.height - tailHeight
            )

            // Top-left corner (sharper to match tail area)
            path.move(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY))
            path.addLine(to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.minY))
            path.addQuadCurve(
                to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY + cornerRadius),
                control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY)
            )
            path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: bubbleRect.maxX - cornerRadius, y: bubbleRect.maxY),
                control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY)
            )
            path.addLine(to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY - cornerRadius),
                control: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY)
            )
            // Tail
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: bubbleRect.minX + cornerRadius * 1.5, y: rect.maxY - tailHeight * 0.3))
            path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY + cornerRadius))
            path.addQuadCurve(
                to: CGPoint(x: bubbleRect.minX + cornerRadius, y: bubbleRect.minY),
                control: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY)
            )
        }

        return path
    }
}

// MARK: - Model Loader Sheet

/// A sheet for loading a GGUF model file.
struct ModelLoaderSheet: View {
    let chatState: ChatState

    @Environment(\.dismiss) private var dismiss
    @State private var modelPath = ""
    @State private var selectedFormat: ChatTemplateFormat = .llama3

    var body: some View {
        NavigationStack {
            Form {
                Section("Model File") {
                    HStack {
                        TextField("Path to .gguf file", text: $modelPath)
                            .font(.system(.body, design: .monospaced))

                        Button("Browse") {
                            // In a full implementation, this would use
                            // UIDocumentPickerViewController to select a file.
                            // For sideloaded apps, files are typically placed
                            // in the Documents directory via Finder/SSHDisk.
                        }
                    }

                    if modelPath.isEmpty {
                        Text("Place your .gguf model in the app's Documents directory, or enter the full path above.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Chat Template Format") {
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ChatTemplateFormat.allCases, id: \.self) { format in
                            Text(format.description).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button("Load Model") {
                        loadModel()
                    }
                    .disabled(modelPath.isEmpty)
                    .disabled(isLoading)
                }
            }
            .navigationTitle("Load Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(id: "main") {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                let documentsDir = NSSearchPathForDirectoriesInDomains(
                    .documentDirectory, .userDomainMask, true
                ).first ?? ""
                modelPath = (documentsDir as NSString).appendingPathComponent("model.gguf")
            }
        }
    }

    private var isLoading: Bool {
        if case .loading = chatState.engineState { return true }
        return false
    }

    private func loadModel() {
        let url = URL(fileURLWithPath: modelPath)
        chatState.setTemplateFormat(selectedFormat)
        chatState.loadModel(from: url)
        dismiss()
    }
}

// MARK: - Phase 6: Mic Button

/// A button that toggles speech recognition for voice input.
/// Frutiger Aero: glassy circle with frosted background.
struct MicButton: View {
    let speechManager: SpeechManager
    let onTranscriptionComplete: (String) -> Void

    @State private var isListening = false
    @State private var isPressed = false

    var body: some View {
        Button {
            FrutigerAeroTheme.shared.lightHaptic()
            if isListening {
                speechManager.stopListening()
                isListening = false
                if let text = speechManager.consumeRecognizedText() {
                    onTranscriptionComplete(text)
                }
            } else {
                speechManager.startListening()
                isListening = true

                // Auto-stop after transcription completes
                Task {
                    // Monitor for completion
                    while speechManager.recognitionState.isListening && !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                    if let text = speechManager.consumeRecognizedText() {
                        onTranscriptionComplete(text)
                    }
                    isListening = false
                }
            }
        } label: {
            Image(systemName: isListening ? "waveform.circle.fill" : "mic.circle.fill")
                .font(.title3)
                .foregroundStyle(isListening ? .white : FrutigerAeroTheme.shared.neonBlue)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Circle()
                        .fill(
                            isListening
                                ? Color.red.opacity(0.15)
                                : FrutigerAeroTheme.shared.neonBlue.opacity(0.1)
                        )
                )
                .overlay(
                    Circle()
                        .fill(FrutigerAeroTheme.shared.subtleGloss)
                )
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(
                    color: isListening
                        ? .red.opacity(0.2)
                        : FrutigerAeroTheme.shared.neonBlue.opacity(0.15),
                    radius: 4, x: 0, y: 2
                )
        }
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityLabel(isListening ? "Stop listening" : "Start voice input")
        .symbolEffect(.variableColor.iterative, isActive: isListening)
    }
}

// MARK: - Phase 6.2: Function Call Indicator

/// Shows a compact indicator when the assistant used tools during generation.
/// Frutiger Aero: frosted glass capsules.
struct FunctionCallIndicator: View {
    let functionCalls: [FunctionCallRecord]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(functionCalls) { call in
                    HStack(spacing: 4) {
                        Image(systemName: call.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(call.isSuccess ? .green : .red)
                        Text(call.toolName)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(call.isSuccess ? Color.green.opacity(0.06) : Color.red.opacity(0.06))
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Phase 6.3: RAG Sources Indicator

/// Shows a compact indicator of the document sources consulted for a response.
/// Frutiger Aero: frosted glass capsules.
struct RAGSourcesIndicator: View {
    let sources: [RAGSourceCitation]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(FrutigerAeroTheme.shared.neonBlue)

                ForEach(sources) { source in
                    HStack(spacing: 2) {
                        Text(source.documentName)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(1)
                        Text(String(format: "%.0f%%", source.similarity * 100))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(FrutigerAeroTheme.shared.neonBlue.opacity(0.06))
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    )
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    ChatView(chatState: {
        let state = ChatState()
        // Pre-populate with sample messages for preview
        state.conversation.append(.userMessage("What is the capital of France?"))
        state.conversation.append(.assistantMessage(
            "The capital of France is **Paris**. It is the largest city in France and one of the most important cultural and economic centers in Europe.\n\nSome key facts:\n- Population: ~2.2 million (city), ~12 million (metro)\n- Known as the \"City of Light\"\n- Home to the Eiffel Tower, Louvre Museum, and Notre-Dame",
            tokenInfo: MessageTokenInfo(promptTokenCount: 8, generationTokenCount: 45),
            metadata: GenerationMetadata(
                tokensGenerated: 45,
                durationSeconds: 1.2,
                promptProcessingSeconds: 0.3,
                peakMemoryBytes: 1_200_000_000,
                stopReason: .endOfGenerationToken
            )
        ))
        return state
    }())
}
