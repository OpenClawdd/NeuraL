import XCTest
@testable import NeuraL

@MainActor
final class DreamStateTests: XCTestCase {
    func testSynthesizerCreatesCard() {
        let synth = DreamSynthesizer()
        let card = synth.synthesize(latestUserPrompt: "Plan launch", assistantAnswer: "1. Draft launch brief", reasoningTrace: "step-by-step", selectedNeuralMode: "Focus", pinnedMessages: [], importedDocumentNames: ["Spec"], sourceMessageID: UUID())
        XCTAssertFalse(card.title.isEmpty)
        XCTAssertFalse(card.nextAction.isEmpty)
    }

    func testStoreSavesReloads() {
        let store = DreamStore()
        let card = DreamCard(title: "t", summary: "s", nextAction: "n", rememberedTheme: nil, sourceMessageID: UUID(), confidence: 0.5, tags: [])
        store.append(card, retention: .unlimited)
        let store2 = DreamStore()
        XCTAssertTrue(store2.cards.contains { $0.id == card.id })
    }
}
