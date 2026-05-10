import SwiftUI

struct OnboardingView: View {
    @ObservedObject var chatState: ChatState
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    private let pages = [
        OnboardingPage(
            title: "Private Cognition",
            description: "NeuraL is local-first. Your thoughts, data, and models stay on your device. No cloud, no tracking, no accounts required.",
            icon: "lock.shield.fill",
            color: .blue
        ),
        OnboardingPage(
            title: "Bring Your Own Model",
            description: "To begin, you'll need to import a GGUF model file. NeuraL runs these directly on your hardware for total control.",
            icon: "cpu.fill",
            color: .purple
        ),
        OnboardingPage(
            title: "Grounded Knowledge",
            description: "Import your local documents (PDF, Text, Markdown) to give the model context. Knowledge remains private and secure.",
            icon: "doc.text.magnifyingglass",
            color: .teal
        ),
        OnboardingPage(
            title: "Ready to Explore",
            description: "Configure your workspace in the Lab, load a model in the Models tab, and start your first private conversation.",
            icon: "sparkles",
            color: .orange
        )
    ]

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button("Skip") {
                        complete()
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                }

                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        pageView(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                VStack(spacing: 16) {
                    Button(action: next) {
                        Text(currentPage == pages.count - 1 ? "Get Started" : "Next")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(pages[currentPage].color.gradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Image(systemName: page.icon)
                .font(.system(size: 100))
                .foregroundStyle(page.color.gradient)
                .shadow(color: page.color.opacity(0.3), radius: 20, x: 0, y: 10)
                .padding(.bottom, 20)

            Text(page.title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .padding(.top, 60)
    }

    private func next() {
        if currentPage < pages.count - 1 {
            withAnimation { currentPage += 1 }
        } else {
            complete()
        }
    }

    private func complete() {
        chatState.hasCompletedOnboarding = true
        dismiss()
    }
}

struct OnboardingPage {
    let title: String
    let description: String
    let icon: String
    let color: Color
}

#Preview {
    OnboardingView(chatState: ChatState())
}
