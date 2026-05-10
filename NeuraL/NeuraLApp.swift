import SwiftUI

@main
struct NeuraLApp: App {
    @StateObject private var chatState = ChatState()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: AppTab = .chat

    var body: some Scene {
        WindowGroup {
            Group {
                if sizeClass == .regular {
                    NavigationSplitView {
                        List(selection: $selectedTab) {
                            ForEach(AppTab.allCases) { tab in
                                NavigationLink(value: tab) {
                                    Label(tab.title, systemImage: tab.icon)
                                }
                                .tag(tab)
                            }
                        }
                        .navigationTitle("NeuraL")
                    } detail: {
                        detailView(for: selectedTab)
                    }
                } else {
                    TabView(selection: $selectedTab) {
                        ChatView(chatState: chatState)
                            .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                            .tag(AppTab.chat)

                        ModelsView(chatState: chatState)
                            .tabItem { Label("Models", systemImage: "cube") }
                            .tag(AppTab.models)

                        DocumentsView(chatState: chatState)
                            .tabItem { Label("Knowledge", systemImage: "doc.text.magnifyingglass") }
                            .tag(AppTab.knowledge)

                        NeuralLabView(chatState: chatState)
                            .tabItem { Label("Lab", systemImage: "sparkles") }
                            .tag(AppTab.lab)

                        SystemStatusView(chatState: chatState)
                            .tabItem { Label("System", systemImage: "cpu") }
                            .tag(AppTab.system)
                    }
                }
            }
            .tint(.blue)
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .background:
                    chatState.runShadowSynthesis()
                    BackgroundSynthesisScheduler.shared.schedule()
                case .active:
                    chatState.runShadowSynthesis()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    @ViewBuilder
    private func detailView(for tab: AppTab) -> some View {
        switch tab {
        case .chat:
            ChatView(chatState: chatState)
        case .models:
            ModelsView(chatState: chatState)
        case .knowledge:
            DocumentsView(chatState: chatState)
        case .lab:
            NeuralLabView(chatState: chatState)
        case .system:
            SystemStatusView(chatState: chatState)
        }
    }
}



// p.s. code is looking clean bro, keep cooking 🔥
