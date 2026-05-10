import SwiftUI

@main
struct NeuraLApp: App {
    @StateObject private var chatState = ChatState()
    var body: some Scene {
        WindowGroup {
            ContentView(chatState: chatState)
        }
    }
}

struct ContentView: View {
    @ObservedObject var chatState: ChatState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: AppTab? = .chat

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List(AppTab.allCases, selection: $selectedTab) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.title, systemImage: tab.icon)
                        }
                    }
                    .navigationTitle("NeuraL")
                } detail: {
                    detailView(for: selectedTab)
                }
            } else {
                TabView(selection: Binding(get: { selectedTab ?? .chat }, set: { selectedTab = $0 })) {
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

    @ViewBuilder
    private func detailView(for tab: AppTab?) -> some View {
        switch tab ?? .chat {
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
