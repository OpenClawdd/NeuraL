import SwiftUI
@main
struct NeuraLApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ChatView().tabItem { Label("Chat", systemImage: "bubble.left") }
                ModelsView().tabItem { Label("Models", systemImage: "cube") }
            }
        }
    }
}
