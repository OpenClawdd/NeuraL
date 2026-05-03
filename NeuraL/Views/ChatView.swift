import SwiftUI
struct ChatView: View {
    @StateObject private var chatState = ChatState()
    @State private var inputText = ""
    var body: some View {
        VStack {
            ScrollView { LazyVStack { ForEach(chatState.messages) { msg in
                HStack {
                    if msg.role == .user { Spacer() }
                    Text(msg.content).padding().background(msg.role == .user ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2)).cornerRadius(12)
                    if msg.role == .assistant { Spacer() }
                }
            } } }
            HStack {
                TextField("Message", text: $inputText).textFieldStyle(.roundedBorder)
                Button("Send") { chatState.sendMessage(inputText); inputText = "" }
            }.padding()
        }
    }
}
