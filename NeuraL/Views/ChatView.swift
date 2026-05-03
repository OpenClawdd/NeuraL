import SwiftUI

struct ChatView: View {
    @StateObject private var chatState = ChatState()
    @State private var inputText = ""
    @State private var particles: [Particle] = []
    @State private var backgroundAngle: Double = 0
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Animated gradient background
            AngularGradient(colors: [.blue, .purple, .pink, .cyan, .blue], center: .center)
                .hueRotation(.degrees(backgroundAngle))
                .ignoresSafeArea()

            // Floating particle field (disabled when generating to save GPU)
            if !chatState.isGenerating {
                Canvas { context, size in
                    for p in particles {
                        let pos = CGPoint(x: p.x * size.width, y: p.y * size.height)
                        context.fill(Path(ellipseIn: CGRect(x: pos.x-2, y: pos.y-2, width: 4, height: 4)), with: .color(.white.opacity(0.2)))
                    }
                }
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Chat messages
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
                                        .scaleEffect(msg.role == .user ? 1.0 : 1.02)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: msg.id)
                                    if msg.role == .assistant { Spacer() }
                                }
                            }
                            if chatState.isGenerating {
                                HStack {
                                    Spacer()
                                    ThreeDotsTyping()
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: chatState.messages.count) { _ in
                        withAnimation { proxy.scrollTo(chatState.messages.last?.id, anchor: .bottom) }
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
            if !chatState.isGenerating {
                backgroundAngle += 0.2
                if particles.count < 50 {
                    particles.append(Particle())
                } else {
                    particles = particles.filter { $0.life > 0 }
                    for i in particles.indices { particles[i].move() }
                }
            }
        }
    }
}

struct Particle {
    var x: Double = Double.random(in: 0...1)
    var y: Double = Double.random(in: 0...1)
    var life: Double = Double.random(in: 0.5...1.5)
    mutating func move() {
        y -= 0.002
        life -= 0.002
        if y < 0 { y = 1; life = Double.random(in: 0.5...1.5) }
    }
}

struct ThreeDotsTyping: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 4) {
            Circle().frame(width: 8, height: 8).opacity(dotCount >= 1 ? 1 : 0.3)
            Circle().frame(width: 8, height: 8).opacity(dotCount >= 2 ? 1 : 0.3)
            Circle().frame(width: 8, height: 8).opacity(dotCount >= 3 ? 1 : 0.3)
        }
        .foregroundColor(.blue)
        .onReceive(timer) { _ in
            withAnimation { dotCount = (dotCount + 1) % 4 }
        }
    }
}
