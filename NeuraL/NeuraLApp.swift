//
//  NeuraLApp.swift
//  NeuraL
//
//  Phase 3 — Application Entry Point
//  Phase 4 — Auto-save conversations on background
//  Phase 6 — Multimodal & Intelligence (Vision, Tools, RAG, Speech)
//  Phase 7 — User Experience & Personalization (Theme, Prompts, Export)
//  Frutiger Aero — Glassy, Glossy, Vibrant, Translucent
//
//  The app now uses a tab-based navigation with:
//  - Chat tab: Full ChatView interface with streaming, thinking bubbles, etc.
//  - Models tab: Browse, download, and import GGUF models
//  - Documents tab: Import and manage documents for RAG (Phase 6.3)
//  - System tab: Device capabilities, JIT, extended memory, thermal status
//  - Settings tab: Theme, prompt library, export, archive (Phase 7)
//
//  The ChatState is shared between tabs so the Models tab can load a model
//  and the Chat tab immediately reflects the change.
//
//  Frutiger Aero Integration:
//  - FrutigerAeroTheme injected as environment object
//  - SystemInfo injected as environment object
//  - GPU state observed: decorative animations pause during inference
//

import SwiftUI

@main
struct NeuraLApp: App {
    @State private var chatState = ChatState()
    @State private var selectedTab: AppTab = .chat
    @State private var aeroTheme = FrutigerAeroTheme.shared
    @State private var systemInfo = SystemInfo()

    init() {
        // Initialize built-in tools on app launch (Phase 6.2)
        // This is done synchronously in init to ensure tools are available
        // before any generation request
        Task {
            await BuiltInTools.registerAll()
        }
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                // ── Chat Tab ────────────────────────────────────────────
                ChatView(chatState: chatState, selectedTab: $selectedTab)
                    .tag(AppTab.chat)
                    .tabItem {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                    }

                // ── Models Tab ──────────────────────────────────────────
                ModelsView(chatState: chatState)
                    .tag(AppTab.models)
                    .tabItem {
                        Label("Models", systemImage: "cube.box.fill")
                    }

                // ── Documents Tab (Phase 6.3 RAG) ───────────────────────
                NavigationStack {
                    DocumentsView(chatState: chatState)
                }
                .tag(AppTab.documents)
                .tabItem {
                    Label("Docs", systemImage: "doc.text.magnifyingglass")
                }

                // ── System Tab (JIT, Memory, Capabilities) ──────────────
                SystemStatusView(chatState: chatState)
                    .tag(AppTab.system)
                    .tabItem {
                        Label("System", systemImage: "cpu")
                    }

                // ── Settings Tab (Phase 7) ──────────────────────────────
                NavigationStack {
                    SettingsView(chatState: chatState)
                }
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            .preferredColorScheme(ThemeManager.shared.preferredColorScheme)
            .tint(ThemeManager.shared.accentColorValue)
            .environment(aeroTheme)
            .environment(systemInfo)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                // Auto-save the conversation when the app enters background
                saveConversationOnBackground()
            }
            .onChange(of: chatState.isGenerating) { _, isGenerating in
                // Sync GPU busy state to the Frutiger Aero theme
                // so decorative animations pause during inference
                aeroTheme.isGPUBusy = isGenerating
            }
        }
    }

    /// Save the current conversation when the app goes to background.
    private func saveConversationOnBackground() {
        let conv = chatState.conversation
        let hasMessages = conv.messages.contains { $0.role != .system }
        if hasMessages {
            try? ConversationStore.save(conv)
        }
    }
}

// MARK: - Tab Identifier

/// Identifiers for the app's tabs, used for programmatic tab switching.
enum AppTab: Hashable {
    case chat
    case models
    case documents
    case system
    case settings
}
