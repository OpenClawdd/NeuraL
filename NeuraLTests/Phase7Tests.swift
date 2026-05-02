//
//  Phase7Tests.swift
//  NeuraLTests
//
//  Phase 7 — Unit Tests for User Experience & Personalization
//
//  Tests:
//  1. ThemeManager — theme persistence, defaults, color scheme conversion
//  2. AppTheme — Codable round-trip, equality
//  3. AccentColorOption — all cases, color access
//  4. ChatBubbleStyle — corner radii, descriptions
//  5. FontScaling — scale factors
//  6. PromptLibrary — CRUD, built-in templates, persistence
//  7. SavedPrompt — creation, categories
//  8. BranchManager — create/switch/delete branches, reactions, edits
//  9. ConversationExporter — text/markdown/JSON export
//  10. ConversationArchive — archive/unarchive lifecycle
//

import XCTest
@testable import NeuraL

final class Phase7Tests: XCTestCase {

    // MARK: - Theme Tests

    /// Test AppTheme default values.
    func testAppThemeDefaults() {
        let theme = AppTheme.default
        XCTAssertEqual(theme.colorScheme, .system)
        XCTAssertEqual(theme.accentColor, .blue)
        XCTAssertEqual(theme.bubbleStyle, .rounded)
        XCTAssertEqual(theme.fontScaling, .normal)
        XCTAssertTrue(theme.showTimestamps)
        XCTAssertTrue(theme.showTokenCounts)
        XCTAssertFalse(theme.compactMode)
    }

    /// Test AppTheme Codable round-trip.
    func testAppThemeCodable() throws {
        let theme = AppTheme(
            colorScheme: .dark,
            accentColor: .purple,
            bubbleStyle: .minimal,
            fontScaling: .large,
            showTimestamps: false,
            showTokenCounts: true,
            compactMode: true
        )

        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(AppTheme.self, from: data)

        XCTAssertEqual(decoded, theme, "Decoded theme should equal original")
    }

    /// Test AppTheme equality.
    func testAppThemeEquality() {
        let theme1 = AppTheme.default
        let theme2 = AppTheme.default
        XCTAssertEqual(theme1, theme2)

        var theme3 = AppTheme.default
        theme3.colorScheme = .dark
        XCTAssertNotEqual(theme1, theme3)
    }

    /// Test ColorSchemePreference conversion.
    func testColorSchemeConversion() {
        XCTAssertNil(ColorSchemePreference.system.colorScheme, "System should return nil")
        XCTAssertNotNil(ColorSchemePreference.light.colorScheme)
        XCTAssertNotNil(ColorSchemePreference.dark.colorScheme)
    }

    /// Test AccentColorOption has all cases.
    func testAccentColorOptionCases() {
        XCTAssertEqual(AccentColorOption.allCases.count, 8)
        for option in AccentColorOption.allCases {
            XCTAssertFalse(option.description.isEmpty)
            // Color should be accessible
            _ = option.color
            _ = option.lightColor
            _ = option.gradient
        }
    }

    /// Test ChatBubbleStyle corner radii.
    func testChatBubbleStyleCornerRadius() {
        XCTAssertEqual(ChatBubbleStyle.rounded.cornerRadius, 16)
        XCTAssertEqual(ChatBubbleStyle.minimal.cornerRadius, 8)
        XCTAssertEqual(ChatBubbleStyle.classic.cornerRadius, 12)
    }

    /// Test FontScaling scale factors.
    func testFontScalingScaleFactors() {
        XCTAssertEqual(FontScaling.small.scaleFactor, 0.85, accuracy: 0.01)
        XCTAssertEqual(FontScaling.normal.scaleFactor, 1.0, accuracy: 0.01)
        XCTAssertEqual(FontScaling.large.scaleFactor, 1.2, accuracy: 0.01)
        XCTAssertEqual(FontScaling.extraLarge.scaleFactor, 1.4, accuracy: 0.01)
    }

    /// Test ThemeManager defaults on fresh instance.
    func testThemeManagerDefaults() {
        let manager = ThemeManager()
        XCTAssertEqual(manager.theme.colorScheme, .system)
        XCTAssertEqual(manager.theme.accentColor, .blue)
    }

    /// Test ThemeManager convenience accessors.
    func testThemeManagerConvenienceAccessors() {
        let manager = ThemeManager()
        manager.accentColor = .green
        XCTAssertEqual(manager.accentColorValue, .green)

        manager.fontScaling = .large
        XCTAssertEqual(manager.fontScaleFactor, 1.2, accuracy: 0.01)
    }

    // MARK: - Prompt Library Tests

    /// Test PromptLibrary has built-in templates.
    func testPromptLibraryHasBuiltIns() {
        let library = PromptLibrary()
        XCTAssertFalse(library.builtInPrompts.isEmpty, "Should have built-in templates")
        XCTAssertTrue(library.builtInPrompts.count >= 6, "Should have at least 6 built-in templates")
    }

    /// Test adding a user prompt.
    func testPromptLibraryAddUserPrompt() {
        let library = PromptLibrary()
        let prompt = SavedPrompt.create(name: "Test Prompt", content: "You are a test assistant.")
        library.addPrompt(prompt)

        XCTAssertFalse(library.userPrompts.isEmpty, "Should have user prompts after adding")
        XCTAssertEqual(library.userPrompts.first?.name, "Test Prompt")
    }

    /// Test deleting a user prompt.
    func testPromptLibraryDeleteUserPrompt() {
        let library = PromptLibrary()
        let prompt = SavedPrompt.create(name: "To Delete", content: "Delete me.")
        library.addPrompt(prompt)

        library.deletePrompt(id: prompt.id)
        XCTAssertNil(library.prompt(withId: prompt.id), "Deleted prompt should not be found")
    }

    /// Test deleting a built-in prompt is not allowed.
    func testPromptLibraryCannotDeleteBuiltIn() {
        let library = PromptLibrary()
        let builtIn = library.builtInPrompts.first!
        library.deletePrompt(id: builtIn.id)

        XCTAssertNotNil(library.prompt(withId: builtIn.id), "Built-in prompt should survive deletion")
    }

    /// Test updating a prompt.
    func testPromptLibraryUpdatePrompt() {
        let library = PromptLibrary()
        var prompt = SavedPrompt.create(name: "Original", content: "Original content")
        library.addPrompt(prompt)

        prompt.name = "Updated"
        prompt.content = "Updated content"
        library.updatePrompt(prompt)

        let found = library.prompt(withId: prompt.id)
        XCTAssertEqual(found?.name, "Updated")
    }

    /// Test PromptCategory properties.
    func testPromptCategoryProperties() {
        for category in PromptCategory.allCases {
            XCTAssertFalse(category.description.isEmpty)
            XCTAssertFalse(category.systemImage.isEmpty)
        }
    }

    /// Test SavedPrompt creation.
    func testSavedPromptCreation() {
        let prompt = SavedPrompt.create(name: "Helper", content: "Be helpful.", category: .general)
        XCTAssertEqual(prompt.name, "Helper")
        XCTAssertEqual(prompt.content, "Be helpful.")
        XCTAssertFalse(prompt.isBuiltIn)
        XCTAssertEqual(prompt.category, .general)
    }

    /// Test SavedPrompt built-in creation.
    func testSavedPromptBuiltIn() {
        let prompt = SavedPrompt.builtIn(name: "Template", content: "Template content", category: .creative)
        XCTAssertTrue(prompt.isBuiltIn)
        XCTAssertEqual(prompt.category, .creative)
    }

    // MARK: - Branch Manager Tests

    /// Test creating a branch.
    func testBranchManagerCreateBranch() {
        let manager = BranchManager()
        let messageId = UUID()

        let branchId = manager.createBranch(divergingFrom: messageId)
        XCTAssertNotNil(manager.activeBranchId)
        XCTAssertEqual(manager.activeBranchId, branchId)
        XCTAssertTrue(manager.hasBranches)
    }

    /// Test switching branches.
    func testBranchManagerSwitchBranches() {
        let manager = BranchManager()
        let messageId = UUID()

        let branch1 = manager.createBranch(divergingFrom: messageId, label: "Branch 1")
        manager.switchToTrunk()
        XCTAssertNil(manager.activeBranchId)

        manager.switchToBranch(branch1)
        XCTAssertEqual(manager.activeBranchId, branch1)
    }

    /// Test deleting a branch.
    func testBranchManagerDeleteBranch() {
        let manager = BranchManager()
        let messageId = UUID()

        let branchId = manager.createBranch(divergingFrom: messageId)
        manager.deleteBranch(branchId)
        XCTAssertFalse(manager.hasBranches)
        XCTAssertNil(manager.activeBranchId)
    }

    /// Test branch label.
    func testBranchManagerBranchLabel() {
        let manager = BranchManager()
        let messageId = UUID()

        let _ = manager.createBranch(divergingFrom: messageId, label: "My Branch")
        XCTAssertEqual(manager.activeBranchLabel, "My Branch")

        manager.switchToTrunk()
        XCTAssertNil(manager.activeBranchLabel)
    }

    /// Test adding and retrieving reactions.
    func testBranchManagerReactions() {
        let manager = BranchManager()
        let messageId = UUID()

        XCTAssertTrue(manager.reactionsFor(messageId: messageId).isEmpty)

        manager.addReaction(emoji: "👍", to: messageId)
        XCTAssertEqual(manager.reactionsFor(messageId: messageId).count, 1)
        XCTAssertEqual(manager.reactionsFor(messageId: messageId).first?.emoji, "👍")

        manager.addReaction(emoji: "❤️", to: messageId)
        XCTAssertEqual(manager.reactionsFor(messageId: messageId).count, 2)
    }

    /// Test removing a reaction.
    func testBranchManagerRemoveReaction() {
        let manager = BranchManager()
        let messageId = UUID()

        manager.addReaction(emoji: "👍", to: messageId)
        let reactionId = manager.reactionsFor(messageId: messageId).first!.id
        manager.removeReaction(reactionId: reactionId, from: messageId)
        XCTAssertTrue(manager.reactionsFor(messageId: messageId).isEmpty)
    }

    /// Test message editing.
    func testBranchManagerMessageEditing() {
        let manager = BranchManager()
        let messageId = UUID()

        let message = ChatMessage.userMessage("Original text")
        XCTAssertEqual(manager.displayContent(for: message), "Original text")
        XCTAssertFalse(manager.isEdited(messageId: messageId))

        manager.editMessage(id: messageId, newContent: "Edited text")
        XCTAssertTrue(manager.isEdited(messageId: messageId))
        XCTAssertEqual(manager.displayContent(for: message), "Edited text")
    }

    /// Test reverting an edit.
    func testBranchManagerRevertEdit() {
        let manager = BranchManager()
        let messageId = UUID()

        manager.editMessage(id: messageId, newContent: "Edited")
        manager.revertEdit(messageId: messageId)
        XCTAssertFalse(manager.isEdited(messageId: messageId))
    }

    /// Test resetting the branch manager.
    func testBranchManagerReset() {
        let manager = BranchManager()
        let messageId = UUID()

        let _ = manager.createBranch(divergingFrom: messageId)
        manager.addReaction(emoji: "👍", to: messageId)
        manager.editMessage(id: messageId, newContent: "Edited")

        manager.reset()

        XCTAssertFalse(manager.hasBranches)
        XCTAssertNil(manager.activeBranchId)
        XCTAssertTrue(manager.reactions.isEmpty)
        XCTAssertTrue(manager.editedContents.isEmpty)
    }

    // MARK: - MessageReaction Tests

    /// Test MessageReaction creation.
    func testMessageReactionCreation() {
        let reaction = MessageReaction.create("🔥")
        XCTAssertEqual(reaction.emoji, "🔥")
    }

    // MARK: - BranchInfo Tests

    /// Test BranchInfo creation.
    func testBranchInfoCreation() {
        let branch = BranchInfo(
            id: UUID(),
            divergeFromMessageId: UUID(),
            label: "Test Branch",
            createdAt: Date(),
            parentBranchId: nil
        )
        XCTAssertEqual(branch.label, "Test Branch")
        XCTAssertNil(branch.parentBranchId)
    }

    // MARK: - Export Tests

    /// Test text export produces non-empty data.
    func testTextExport() {
        var conv = Conversation(systemPrompt: "You are helpful.")
        conv.append(.userMessage("Hello"))
        conv.append(.assistantMessage("Hi there!", tokenInfo: MessageTokenInfo(promptTokenCount: 4, generationTokenCount: 5), metadata: nil))

        let data = ConversationExporter.export(conversation: conv, format: .text)
        XCTAssertNotNil(data, "Text export should produce data")
        XCTAssertGreaterThan(data?.count ?? 0, 0)

        let text = String(data: data!, encoding: .utf8)
        XCTAssertTrue(text?.contains("Hello") ?? false, "Text export should contain user message")
        XCTAssertTrue(text?.contains("Hi there!") ?? false, "Text export should contain assistant message")
    }

    /// Test markdown export produces non-empty data.
    func testMarkdownExport() {
        var conv = Conversation(systemPrompt: "Be concise.")
        conv.append(.userMessage("What is AI?"))
        conv.append(.assistantMessage("AI is...", tokenInfo: MessageTokenInfo(promptTokenCount: 4, generationTokenCount: 5), metadata: nil))

        let data = ConversationExporter.export(conversation: conv, format: .markdown)
        XCTAssertNotNil(data)

        let md = String(data: data!, encoding: .utf8)
        XCTAssertTrue(md?.contains("#") ?? false, "Markdown should have headers")
        XCTAssertTrue(md?.contains("What is AI?") ?? false)
    }

    /// Test JSON export produces valid Codable data.
    func testJSONExport() throws {
        var conv = Conversation(systemPrompt: "Test")
        conv.append(.userMessage("Hello"))

        let data = ConversationExporter.export(conversation: conv, format: .json)
        XCTAssertNotNil(data)

        let decoded = try JSONDecoder().decode(Conversation.self, from: data!)
        XCTAssertEqual(decoded.messages.count, conv.messages.count)
    }

    /// Test export filename generation.
    func testExportFilename() {
        var conv = Conversation(systemPrompt: "Test")
        conv.append(.userMessage("This is a test conversation"))

        let filename = ConversationExporter.filename(for: conv, format: .markdown)
        XCTAssertTrue(filename.hasSuffix(".md"))
        XCTAssertFalse(filename.isEmpty)
    }

    // MARK: - ExportFormat Tests

    /// Test ExportFormat properties.
    func testExportFormatProperties() {
        XCTAssertEqual(ExportFormat.text.fileExtension, "txt")
        XCTAssertEqual(ExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(ExportFormat.pdf.fileExtension, "pdf")
        XCTAssertEqual(ExportFormat.json.fileExtension, "json")

        for format in ExportFormat.allCases {
            XCTAssertFalse(format.description.isEmpty)
            XCTAssertFalse(format.systemImage.isEmpty)
        }
    }
}
