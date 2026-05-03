import SwiftUI

struct ChatView: View {
    @StateObject private var chatState = ChatState()
    @State private var inputText = ""
    @State private var backgroundAngle: Double = 0
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AngularGradient(colors: [.blue, .purple, .pink, .cyan, .blue], center: .center)
                .hueRotation(.degrees(backgroundAngle))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(chatState.messages) { msg in
                                HStack {
                                    if msg.role == .user { Spacer() }
                                    Text(msg.content)
                                        .padding(12)
                                        .background(msg.role == .user ? Color.blue.opacity(0.8) : Color.white.opacity(0.25))
                                        .foregroundColor(msg.role == .user ? .white : .primary)
                                        .cornerRadius(20)
                                        .shadow(radius: 3)
                                    if msg.role == .assistant { Spacer() }
                                }
                            }
                            if chatState.isGenerating {
                                HStack {
                                    Spacer()
                                    Text(chatState.streamingTokens.joined())
                                        .padding(12)
                                        .background(Color.white.opacity(0.25))
                                        .cornerRadius(20)
                                        + Text("|").foregroundColor(.blue)
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chatState.messages.count) {
                        withAnimation { proxy.scrollTo(chatState.messages.last?.id, anchor: .bottom) }
                    }
                }

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
            if !chatState.isGenerating { backgroundAngle += 0.2 }
        }
    }
}
