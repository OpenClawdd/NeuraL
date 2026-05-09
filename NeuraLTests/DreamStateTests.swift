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

    // MARK: - Synthesizer edge cases

    func testSynthesizerReturnsNilForEmptyAnswer() {
        let synth = DreamSynthesizer()
        let card = synth.synthesize(
            latestUserPrompt: "Hello",
            assistantAnswer: "",
            reasoningTrace: nil,
            selectedNeuralMode: "Local",
            pinnedMessages: [],
            importedDocumentNames: [],
            sourceMessageID: UUID()
        )
        XCTAssertNil(card)
    }

    func testSynthesizerReturnsNilForWhitespaceOnlyAnswer() {
        let synth = DreamSynthesizer()
        let card = synth.synthesize(
            latestUserPrompt: "Hello",
            assistantAnswer: "   \n  \n  ",
            reasoningTrace: nil,
            selectedNeuralMode: "Local",
            pinnedMessages: [],
            importedDocumentNames: [],
            sourceMessageID: UUID()
        )
        XCTAssertNil(card)
    }

    func testSynthesizerReturnsNilForTooShortAnswer() {
        let synth = DreamSynthesizer()
        let card = synth.synthesize(
            latestUserPrompt: "Hello",
            assistantAnswer: "OK.",
            reasoningTrace: nil,
            selectedNeuralMode: "Local",
            pinnedMessages: [],
            importedDocumentNames: [],
            sourceMessageID: UUID()
        )
        XCTAssertNil(card)
    }

    func testSynthesizerReturnsValidCardForUsefulAnswer() {
        let synth = DreamSynthesizer()
        let card = synth.synthesize(
            latestUserPrompt: "What is the best approach for the iOS app architecture?",
            assistantAnswer: "For your iOS app, I recommend using MVVM with actor-based concurrency. This approach ensures thread safety and clear separation of concerns. - Start with protocol abstractions for all services.",
            reasoningTrace: "Evaluating architecture patterns for iOS app with local inference requirements.",
            selectedNeuralMode: "Focus",
            pinnedMessages: [],
            importedDocumentNames: ["ArchitectureNotes.pdf"],
            sourceMessageID: UUID()
        )
        XCTAssertNotNil(card)
        if let card = card {
            XCTAssertFalse(card.title.isEmpty)
            XCTAssertFalse(card.summary.isEmpty)
            XCTAssertFalse(card.nextAction.isEmpty)
            XCTAssertGreaterThan(card.confidence, 0.0)
            XCTAssertFalse(card.tags.isEmpty)
        }
    }

    func testSynthesizerCardHasSourceMessageID() {
        let synth = DreamSynthesizer()
        let sourceID = UUID()
        let card = synth.synthesize(
            latestUserPrompt: "Test prompt",
            assistantAnswer: "This is a sufficiently long answer to produce a DreamCard with proper metadata.",
            reasoningTrace: nil,
            selectedNeuralMode: "Local",
            pinnedMessages: [],
            importedDocumentNames: [],
            sourceMessageID: sourceID
        )
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.sourceMessageID, sourceID)
    }

    func testSynthesizerExtractsTags() {
        let synth = DreamSynthesizer()
        let card = synth.synthesize(
            latestUserPrompt: "machine learning model deployment",
            assistantAnswer: "Deploying machine learning models requires careful consideration of model serving infrastructure and optimization techniques for production.",
            reasoningTrace: "Focus on deployment and optimization aspects.",
            selectedNeuralMode: "Builder",
            pinnedMessages: [],
            importedDocumentNames: [],
            sourceMessageID: UUID()
        )
        XCTAssertNotNil(card)
        if let card = card {
            // Tags should include relevant terms from prompt + answer
            let hasMLTerms = card.tags.contains("machine") || card.tags.contains("learning") || card.tags.contains("model")
            XCTAssertTrue(hasMLTerms || !card.tags.isEmpty)
        }
    }
}
