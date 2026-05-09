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

    // MARK: - Fallback synthesis (empty / whitespace-only answer)

    func testSynthesizerFallbackOnEmptyAnswer() {
        let synth = DreamSynthesizer()
        let sourceID = UUID()
        let card = synth.synthesize(
            latestUserPrompt: "What is consciousness?",
            assistantAnswer: "",
            reasoningTrace: "<think>deep thoughts</think>",
            selectedNeuralMode: "Focus",
            pinnedMessages: [],
            importedDocumentNames: ["PhilDoc"],
            sourceMessageID: sourceID
        )
        XCTAssertEqual(card.title, "Reflection", "Fallback card should use sentinel title 'Reflection'")
        XCTAssertEqual(card.confidence, 0.0, "Fallback card confidence must be 0.0")
        XCTAssertEqual(card.sourceMessageID, sourceID, "Fallback card must preserve the source message ID")
        XCTAssertEqual(card.rememberedTheme, "PhilDoc", "Fallback card should still carry the first imported document name")
        XCTAssertTrue(card.tags.isEmpty, "Fallback card should have no tags")
    }

    func testSynthesizerFallbackOnWhitespaceOnlyAnswer() {
        let synth = DreamSynthesizer()
        let card = synth.synthesize(
            latestUserPrompt: "Hello",
            assistantAnswer: "   \n\t  ",
            reasoningTrace: nil,
            selectedNeuralMode: "Chat",
            pinnedMessages: [],
            importedDocumentNames: [],
            sourceMessageID: UUID()
        )
        XCTAssertEqual(card.title, "Reflection", "Whitespace-only answer should trigger fallback")
        XCTAssertEqual(card.confidence, 0.0)
    }

    // MARK: - Cold-launch retention enforcement

    func testStoreEnforcesRetentionOnColdLaunch() {
        // Build a store, stuff it with cards beyond the .fifty limit, then re-init
        // with .fifty and confirm the cap is applied immediately on load.
        let store = DreamStore(retention: .unlimited)
        for i in 0..<70 {
            let card = DreamCard(
                title: "Card \(i)",
                summary: "summary",
                nextAction: "action",
                rememberedTheme: nil,
                sourceMessageID: UUID(),
                confidence: 0.5,
                tags: []
            )
            store.append(card, retention: .unlimited)
        }
        XCTAssertEqual(store.cards.count, 70, "Precondition: unlimited store should hold all 70 cards")

        // Cold-launch with .fifty — retention must fire during init
        let coldStore = DreamStore(retention: .fifty)
        XCTAssertLessThanOrEqual(coldStore.cards.count, 50, "Cold-launch with .fifty retention should cap cards at 50")
    }

    func testStoreRetentionUnlimitedDoesNotTruncate() {
        let store = DreamStore(retention: .unlimited)
        for i in 0..<60 {
            let card = DreamCard(
                title: "Card \(i)",
                summary: "s",
                nextAction: "n",
                rememberedTheme: nil,
                sourceMessageID: UUID(),
                confidence: 0.5,
                tags: []
            )
            store.append(card, retention: .unlimited)
        }
        let coldStore = DreamStore(retention: .unlimited)
        XCTAssertEqual(coldStore.cards.count, 60, "Unlimited retention should not truncate on cold launch")
    }
}
