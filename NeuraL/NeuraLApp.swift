import SwiftUI

@main
struct NeuraLApp: App {
    @StateObject private var chatState = ChatState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundSynthesisScheduler.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                ChatView(chatState: chatState)
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

                ModelsView(chatState: chatState)
                    .tabItem { Label("Models", systemImage: "cube") }

                DocumentsView(chatState: chatState)
                    .tabItem { Label("Knowledge", systemImage: "doc.text.magnifyingglass") }

                NeuralLabView(chatState: chatState)
                    .tabItem { Label("Lab", systemImage: "sparkles") }

                SystemStatusView(chatState: chatState)
                    .tabItem { Label("System", systemImage: "cpu") }
            }
            .tint(.blue)
            .onChange(of: scenePhase) {
                switch scenePhase {
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
}

// p.s. i love you noah <3

// p.s. i love you noah <3
