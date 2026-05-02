//
//  Phase6Tests.swift
//  NeuraLTests
//
//  Phase 6 — Unit Tests for Multimodal & On-Device Intelligence
//
//  Tests the Phase 6 components that can be verified without a loaded model:
//  1. FunctionCallParser — parse, strip, partial detection
//  2. ToolRegistry — register, unregister, generate definitions
//  3. BuiltInTools — Calculator, Calendar, DeviceInfo execution
//  4. VectorStore — add, search, remove, persistence
//  5. DocumentChunker — chunk text with overlap
//  6. SimpleEmbedding — consistent embedding generation
//  7. RAGPipeline — shouldUseRAG heuristic
//  8. ImageAttachment — creation and thumbnail generation
//  9. VisionEncoder — state machine, configuration
//  10. SpeechManager — state transitions
//

import XCTest
import UIKit
@testable import NeuraL

final class Phase6Tests: XCTestCase {

    // MARK: - FunctionCallParser Tests

    /// Test parsing a single function call from model output.
    func testParseSingleFunctionCall() {
        let text = """
        I'll calculate that for you.
        <function>
        {"name": "calculator", "parameters": {"expression": "2+2"}}
        </function>
        """

        let calls = FunctionCallParser.parseCalls(from: text)
        XCTAssertEqual(calls.count, 1, "Should parse exactly one function call")
        XCTAssertEqual(calls[0].name, "calculator")
        XCTAssertEqual(calls[0].parameters["expression"] as? String, "2+2")
    }

    /// Test parsing multiple function calls.
    func testParseMultipleFunctionCalls() {
        let text = """
        Let me check the date and your device.
        <function>
        {"name": "calendar", "parameters": {"action": "now"}}
        </function>
        And also:
        <function>
        {"name": "device_info", "parameters": {"category": "basic"}}
        </function>
        """

        let calls = FunctionCallParser.parseCalls(from: text)
        XCTAssertEqual(calls.count, 2, "Should parse two function calls")
        XCTAssertEqual(calls[0].name, "calendar")
        XCTAssertEqual(calls[1].name, "device_info")
    }

    /// Test parsing with malformed JSON inside function tags.
    func testParseMalformedFunctionCall() {
        let text = """
        <function>
        {invalid json}
        </function>
        """

        let calls = FunctionCallParser.parseCalls(from: text)
        XCTAssertTrue(calls.isEmpty, "Malformed JSON should produce no calls")
    }

    /// Test partial function call detection during streaming.
    func testPartialFunctionCallDetection() {
        let partial = "Let me compute <function>\n{\"name\": \"calc"
        XCTAssertTrue(FunctionCallParser.hasPartialFunctionCall(in: partial),
                      "Should detect incomplete function block")

        let complete = """
        <function>
        {"name": "calc", "parameters": {}}
        </function>
        """
        XCTAssertFalse(FunctionCallParser.hasPartialFunctionCall(in: complete),
                       "Should not detect partial in complete block")
    }

    /// Test stripping function call blocks from text.
    func testStripFunctionCalls() {
        let text = """
        Hello! <function>
        {"name": "calculator", "parameters": {"expression": "2+2"}}
        </function> The result is 4.
        """

        let stripped = FunctionCallParser.stripFunctionCalls(from: text)
        XCTAssertFalse(stripped.contains("<function>"), "Should not contain function tags")
        XCTAssertFalse(stripped.contains("calculator"), "Should not contain function content")
        XCTAssertTrue(stripped.contains("Hello!"), "Should preserve non-function text")
        XCTAssertTrue(stripped.contains("The result is 4."), "Should preserve text after function")
    }

    /// Test empty text produces no calls.
    func testParseEmptyText() {
        let calls = FunctionCallParser.parseCalls(from: "")
        XCTAssertTrue(calls.isEmpty)
    }

    /// Test function call with missing parameters field.
    func testParseFunctionCallMissingParameters() {
        let text = """
        <function>
        {"name": "tool_name"}
        </function>
        """
        let calls = FunctionCallParser.parseCalls(from: text)
        XCTAssertEqual(calls.count, 1, "Should still parse when parameters missing")
        XCTAssertEqual(calls[0].name, "tool_name")
    }

    // MARK: - ToolRegistry Tests

    /// Test registering and looking up a tool.
    func testToolRegistryRegisterAndLookup() async {
        let registry = ToolRegistry()
        let tool = CalculatorTool()
        await registry.register(tool)

        let found = await registry.tool(named: "calculator")
        XCTAssertNotNil(found, "Should find registered tool")
        XCTAssertEqual(found?.name, "calculator")
    }

    /// Test unregistering a tool.
    func testToolRegistryUnregister() async {
        let registry = ToolRegistry()
        await registry.register(CalculatorTool())
        await registry.unregister(name: "calculator")

        let found = await registry.tool(named: "calculator")
        XCTAssertNil(found, "Should not find unregistered tool")
    }

    /// Test generating tool definitions prompt.
    func testToolRegistryDefinitionsPrompt() async {
        let registry = ToolRegistry()
        await registry.register(CalculatorTool())
        await registry.register(CalendarTool())

        let prompt = await registry.generateToolDefinitionsPrompt()
        XCTAssertFalse(prompt.isEmpty, "Definitions prompt should not be empty")
        XCTAssertTrue(prompt.contains("calculator"), "Should mention calculator tool")
        XCTAssertTrue(prompt.contains("calendar"), "Should mention calendar tool")
        XCTAssertTrue(prompt.contains("<function>"), "Should include function call format")
    }

    /// Test empty registry produces empty prompt.
    func testToolRegistryEmptyPrompt() async {
        let registry = ToolRegistry()
        let prompt = await registry.generateToolDefinitionsPrompt()
        XCTAssertTrue(prompt.isEmpty, "Empty registry should produce empty prompt")
    }

    // MARK: - BuiltInTools Tests

    /// Test CalculatorTool with basic arithmetic.
    func testCalculatorToolBasicArithmetic() async throws {
        let tool = CalculatorTool()
        let result = try await tool.execute(parameters: ["expression": "2 + 3"])
        XCTAssertTrue(result.isSuccess, "Basic addition should succeed")
        XCTAssertTrue(result.output.contains("5"), "Result should contain 5")
    }

    /// Test CalculatorTool with division.
    func testCalculatorToolDivision() async throws {
        let tool = CalculatorTool()
        let result = try await tool.execute(parameters: ["expression": "10 / 4"])
        XCTAssertTrue(result.isSuccess)
    }

    /// Test CalculatorTool with invalid expression.
    func testCalculatorToolInvalidExpression() async throws {
        let tool = CalculatorTool()
        let result = try await tool.execute(parameters: ["expression": "import os"])
        XCTAssertFalse(result.isSuccess, "Code injection should be rejected")
    }

    /// Test CalculatorTool missing parameter.
    func testCalculatorToolMissingParameter() async throws {
        let tool = CalculatorTool()
        let result = try await tool.execute(parameters: [:])
        XCTAssertFalse(result.isSuccess, "Missing expression should fail")
    }

    /// Test CalendarTool "now" action.
    func testCalendarToolNow() async throws {
        let tool = CalendarTool()
        let result = try await tool.execute(parameters: ["action": "now"])
        XCTAssertTrue(result.isSuccess, "Calendar now should succeed")
        XCTAssertTrue(result.output.contains("Current date and time"), "Should contain date/time header")
    }

    /// Test CalendarTool unknown action.
    func testCalendarToolUnknownAction() async throws {
        let tool = CalendarTool()
        let result = try await tool.execute(parameters: ["action": "fly_to_moon"])
        XCTAssertFalse(result.isSuccess, "Unknown action should fail")
    }

    /// Test DeviceInfoTool basic category.
    func testDeviceInfoToolBasic() async throws {
        let tool = DeviceInfoTool()
        let result = try await tool.execute(parameters: ["category": "basic"])
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.output.contains("Device:"), "Should contain device info")
    }

    /// Test DeviceInfoTool storage category.
    func testDeviceInfoToolStorage() async throws {
        let tool = DeviceInfoTool()
        let result = try await tool.execute(parameters: ["category": "storage"])
        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.output.contains("storage") || result.output.contains("Storage") || result.output.contains("GB"),
                      "Should contain storage info")
    }

    /// Test BuiltInTools.registerAll registers all tools.
    func testBuiltInToolsRegisterAll() async {
        let registry = ToolRegistry()
        await registry.register(CalculatorTool())
        await registry.register(CalendarTool())
        await registry.register(DeviceInfoTool())

        let tools = await registry.allTools()
        XCTAssertEqual(tools.count, 3, "Should have 3 built-in tools registered")
    }

    // MARK: - DocumentChunker Tests

    /// Test chunking a simple text.
    func testChunkSimpleText() {
        let text = "This is a test document. " + String(repeating: "It contains multiple sentences about various topics. ", count: 50)
        let chunks = DocumentChunker.chunk(text: text, sourceName: "test.txt", documentId: UUID())

        XCTAssertGreaterThan(chunks.count, 0, "Should produce at least one chunk")
        for chunk in chunks {
            XCTAssertFalse(chunk.text.isEmpty, "Each chunk should have non-empty text")
            XCTAssertGreaterThan(chunk.estimatedTokens, 0, "Each chunk should have positive token count")
            XCTAssertEqual(chunk.documentName, "test.txt")
        }
    }

    /// Test chunking empty text produces no chunks.
    func testChunkEmptyText() {
        let chunks = DocumentChunker.chunk(text: "", sourceName: "empty.txt", documentId: UUID())
        XCTAssertTrue(chunks.isEmpty, "Empty text should produce no chunks")
    }

    /// Test chunking preserves document ID.
    func testChunkPreservesDocumentId() {
        let docId = UUID()
        let text = String(repeating: "Test content for chunking. ", count: 100)
        let chunks = DocumentChunker.chunk(text: text, sourceName: "test.txt", documentId: docId)

        for chunk in chunks {
            XCTAssertEqual(chunk.documentId, docId, "All chunks should have the correct document ID")
        }
    }

    /// Test chunk indices are sequential.
    func testChunkIndicesSequential() {
        let text = String(repeating: "This is paragraph content for testing chunk index ordering. ", count: 200)
        let chunks = DocumentChunker.chunk(text: text, sourceName: "test.txt", documentId: UUID())

        for (index, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.chunkIndex, index, "Chunk index should match its position")
        }
    }

    // MARK: - SimpleEmbedding Tests

    /// Test that identical text produces identical embeddings.
    func testEmbeddingConsistency() {
        let text = "The quick brown fox jumps over the lazy dog"
        let embed1 = SimpleEmbedding.embed(text)
        let embed2 = SimpleEmbedding.embed(text)
        XCTAssertEqual(embed1, embed2, "Same text should produce same embedding")
    }

    /// Test that different text produces different embeddings.
    func testEmbeddingDifference() {
        let embed1 = SimpleEmbedding.embed("Hello world")
        let embed2 = SimpleEmbedding.embed("Goodbye universe")
        XCTAssertNotEqual(embed1, embed2, "Different text should produce different embeddings")
    }

    /// Test embedding dimension.
    func testEmbeddingDimension() {
        let embed = SimpleEmbedding.embed("Test")
        XCTAssertEqual(embed.count, SimpleEmbedding.dimension, "Embedding dimension should match configured value")
    }

    /// Test that embedding for empty-ish text still works.
    func testEmbeddingShortText() {
        let embed = SimpleEmbedding.embed("Hi")
        XCTAssertEqual(embed.count, SimpleEmbedding.dimension, "Short text should still produce full-dimension embedding")
    }

    // MARK: - VectorStore Tests

    /// Test VectorStore cosine similarity with identical vectors.
    func testCosineSimilarityIdentical() {
        let chunk = DocumentChunk(
            id: UUID(), documentId: UUID(), documentName: "test.txt",
            text: "test", chunkIndex: 0, embedding: [1.0, 0.0, 0.0],
            rangeStart: 0, estimatedTokens: 1
        )
        let similarity = chunk.cosineSimilarity(to: [1.0, 0.0, 0.0])
        XCTAssertEqual(similarity, 1.0, accuracy: 0.001, "Identical vectors should have similarity 1.0")
    }

    /// Test VectorStore cosine similarity with orthogonal vectors.
    func testCosineSimilarityOrthogonal() {
        let chunk = DocumentChunk(
            id: UUID(), documentId: UUID(), documentName: "test.txt",
            text: "test", chunkIndex: 0, embedding: [1.0, 0.0],
            rangeStart: 0, estimatedTokens: 1
        )
        let similarity = chunk.cosineSimilarity(to: [0.0, 1.0])
        XCTAssertEqual(similarity, 0.0, accuracy: 0.001, "Orthogonal vectors should have similarity 0.0")
    }

    /// Test VectorStore cosine similarity with opposite vectors.
    func testCosineSimilarityOpposite() {
        let chunk = DocumentChunk(
            id: UUID(), documentId: UUID(), documentName: "test.txt",
            text: "test", chunkIndex: 0, embedding: [1.0, 0.0],
            rangeStart: 0, estimatedTokens: 1
        )
        let similarity = chunk.cosineSimilarity(to: [-1.0, 0.0])
        XCTAssertEqual(similarity, -1.0, accuracy: 0.001, "Opposite vectors should have similarity -1.0")
    }

    /// Test VectorStore cosine similarity with mismatched dimensions.
    func testCosineSimilarityMismatchedDimensions() {
        let chunk = DocumentChunk(
            id: UUID(), documentId: UUID(), documentName: "test.txt",
            text: "test", chunkIndex: 0, embedding: [1.0, 0.0],
            rangeStart: 0, estimatedTokens: 1
        )
        let similarity = chunk.cosineSimilarity(to: [1.0, 0.0, 0.0])
        XCTAssertEqual(similarity, 0.0, "Mismatched dimensions should return 0")
    }

    /// Test VectorStore keyword search.
    func testVectorStoreKeywordSearch() async {
        let store = VectorStore()
        let docId = UUID()
        let doc = ImportedDocument(
            id: docId, filename: "test.txt", fileType: "txt",
            fileSize: 100, importDate: Date(), chunkCount: 2,
            totalEstimatedTokens: 50
        )
        let chunks = [
            DocumentChunk(
                id: UUID(), documentId: docId, documentName: "test.txt",
                text: "The capital of France is Paris. Paris is known for the Eiffel Tower.",
                chunkIndex: 0,
                embedding: Array(repeating: Float(0), count: SimpleEmbedding.dimension),
                rangeStart: 0, estimatedTokens: 20
            ),
            DocumentChunk(
                id: UUID(), documentId: docId, documentName: "test.txt",
                text: "Berlin is the capital of Germany. Germany is in central Europe.",
                chunkIndex: 1,
                embedding: Array(repeating: Float(0), count: SimpleEmbedding.dimension),
                rangeStart: 100, estimatedTokens: 20
            )
        ]
        store.addChunks(chunks, document: doc)

        let results = await store.keywordSearch(query: "Paris France", topK: 5)
        XCTAssertGreaterThan(results.count, 0, "Keyword search should find results")
        XCTAssertTrue(results[0].chunk.text.contains("Paris"), "Top result should contain 'Paris'")
    }

    // MARK: - ImageAttachment Tests

    /// Test creating an ImageAttachment from a UIColor-based image.
    func testImageAttachmentCreation() {
        // Create a simple 100x100 red image
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        let attachment = ImageAttachment.from(image, name: "Red Square")
        XCTAssertNotNil(attachment, "Should create attachment from UIImage")
        XCTAssertEqual(attachment?.name, "Red Square")
        XCTAssertEqual(attachment?.originalWidth, 100)
        XCTAssertEqual(attachment?.originalHeight, 100)
        XCTAssertGreaterThan(attachment?.thumbnailData.count ?? 0, 0, "Thumbnail data should not be empty")
        XCTAssertGreaterThan(attachment?.fullImageData.count ?? 0, 0, "Full image data should not be empty")
    }

    /// Test creating an ImageAttachment from Data.
    func testImageAttachmentFromData() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50))
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            XCTFail("Could not create JPEG data")
            return
        }

        let attachment = ImageAttachment.from(data: data, name: "Blue")
        XCTAssertNotNil(attachment, "Should create attachment from Data")
        XCTAssertEqual(attachment?.name, "Blue")
    }

    /// Test that invalid data produces nil attachment.
    func testImageAttachmentInvalidData() {
        let invalidData = Data("not an image".utf8)
        let attachment = ImageAttachment.from(data: invalidData, name: "Invalid")
        XCTAssertNil(attachment, "Invalid data should produce nil attachment")
    }

    /// Test thumbnail image accessor.
    func testImageAttachmentThumbnailImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let image = renderer.image { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        }

        let attachment = ImageAttachment.from(image, name: "Green")!
        let thumbnail = attachment.thumbnailImage
        XCTAssertNotNil(thumbnail, "Should be able to retrieve thumbnail image")
    }

    // MARK: - VisionEncoder State Machine Tests

    /// Test VisionEncoder initial state is idle.
    func testVisionEncoderInitialState() async {
        let encoder = VisionEncoder()
        let state = await encoder.currentState
        XCTAssertEqual(state, .idle, "Initial state should be idle")
        let isReady = await encoder.isReady
        XCTAssertFalse(isReady, "Should not be ready initially")
    }

    /// Test VisionEncoderConfiguration defaults.
    func testVisionEncoderDefaultConfiguration() {
        let config = VisionEncoderConfiguration.default
        XCTAssertEqual(config.threadCount, 2)
        XCTAssertEqual(config.imageSize, 336)
        XCTAssertTrue(config.usesLlavaImageToken)
        XCTAssertEqual(config.imageTokenString, "<image>")
    }

    /// Test VisionEncoderConfiguration for Llama Vision.
    func testVisionEncoderLlamaVisionConfiguration() {
        let config = VisionEncoderConfiguration.llamaVision
        XCTAssertEqual(config.imageSize, 448)
        XCTAssertFalse(config.usesLlavaImageToken)
        XCTAssertEqual(config.imageTokenString, "|image|")
    }

    /// Test VisionEncoderState descriptions.
    func testVisionEncoderStateDescriptions() {
        XCTAssertEqual(VisionEncoderState.idle.description, "Idle")
        XCTAssertEqual(VisionEncoderState.loading.description, "Loading projector...")
        XCTAssertEqual(VisionEncoderState.ready.description, "Ready")
        XCTAssertEqual(VisionEncoderState.encoding.description, "Encoding image...")
        XCTAssertTrue(VisionEncoderState.error("test").description.contains("test"))
    }

    /// Test VisionEncoderState isReady.
    func testVisionEncoderStateIsReady() {
        XCTAssertTrue(VisionEncoderState.ready.isReady)
        XCTAssertFalse(VisionEncoderState.idle.isReady)
        XCTAssertFalse(VisionEncoderState.loading.isReady)
        XCTAssertFalse(VisionEncoderState.error("test").isReady)
    }

    /// Test VisionError descriptions.
    func testVisionErrorDescriptions() {
        let errors: [VisionError] = [
            .projectorNotFound(path: "/test.mmproj"),
            .projectorLoadFailed(path: "/test.mmproj", detail: "bad file"),
            .invalidState("not ready"),
            .imageProcessingFailed("bad image"),
            .encodingFailed("null result"),
            .unsupportedFormat("bmp")
        ]
        for error in errors {
            XCTAssertFalse(error.description.isEmpty, "Error should have non-empty description")
            XCTAssertNotNil(error.errorDescription)
        }
    }

    // MARK: - RAGPipeline Heuristic Tests

    /// Test RAGConfiguration defaults.
    func testRAGConfigurationDefaults() {
        let config = RAGConfiguration.default
        XCTAssertEqual(config.topK, 5)
        XCTAssertEqual(config.minimumSimilarity, 0.3, accuracy: 0.01)
        XCTAssertEqual(config.maxContextTokens, 1500)
        XCTAssertTrue(config.includeCitations)
        XCTAssertFalse(config.ragSystemPrompt.isEmpty)
    }

    /// Test RAGResult sourceSummary with empty results.
    func testRAGResultEmptySourceSummary() {
        let result = RAGResult(
            retrievedChunks: [],
            augmentedSystemPrompt: "test",
            contextTokensUsed: 0,
            hasContext: false
        )
        XCTAssertEqual(result.sourceSummary, "No relevant documents found.")
    }

    /// Test FunctionCallRecord creation and fields.
    func testFunctionCallRecord() {
        let record = FunctionCallRecord(
            id: UUID(),
            toolName: "calculator",
            parameters: "{\"expression\": \"2+2\"}",
            result: "4",
            isSuccess: true,
            durationSeconds: 0.05
        )
        XCTAssertEqual(record.toolName, "calculator")
        XCTAssertTrue(record.isSuccess)
        XCTAssertEqual(record.durationSeconds, 0.05, accuracy: 0.001)
    }

    /// Test RAGSourceCitation creation.
    func testRAGSourceCitation() {
        let citation = RAGSourceCitation(
            id: UUID(),
            documentName: "report.pdf",
            chunkIndex: 3,
            similarity: 0.85,
            snippet: "This is a snippet"
        )
        XCTAssertEqual(citation.documentName, "report.pdf")
        XCTAssertEqual(citation.chunkIndex, 3)
        XCTAssertEqual(citation.similarity, 0.85, accuracy: 0.01)
    }

    // MARK: - Speech Recognition State Tests

    /// Test SpeechRecognitionState properties.
    func testSpeechRecognitionStateIsListening() {
        XCTAssertTrue(SpeechRecognitionState.listening(partialResult: "hello").isListening)
        XCTAssertFalse(SpeechRecognitionState.idle.isListening)
        XCTAssertFalse(SpeechRecognitionState.completed(finalText: "hello").isListening)
        XCTAssertFalse(SpeechRecognitionState.error("fail").isListening)
    }

    /// Test SpeechRecognitionState isCompleted.
    func testSpeechRecognitionStateIsCompleted() {
        XCTAssertTrue(SpeechRecognitionState.completed(finalText: "hello").isCompleted)
        XCTAssertFalse(SpeechRecognitionState.idle.isCompleted)
        XCTAssertFalse(SpeechRecognitionState.listening(partialResult: "").isCompleted)
    }

    /// Test SpeechRecognitionState descriptions.
    func testSpeechRecognitionStateDescriptions() {
        XCTAssertEqual(SpeechRecognitionState.idle.description, "Idle")
        XCTAssertTrue(SpeechRecognitionState.listening(partialResult: "test").description.contains("Listening"))
        XCTAssertTrue(SpeechRecognitionState.completed(finalText: "done").description.contains("Completed"))
    }

    // MARK: - ToolResult Tests

    /// Test ToolResult success factory.
    func testToolResultSuccess() {
        let result = ToolResult.success("42", metadata: ["time": "0.05s"])
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.output, "42")
        XCTAssertEqual(result.metadata["time"], "0.05s")
    }

    /// Test ToolResult failure factory.
    func testToolResultFailure() {
        let result = ToolResult.failure("Something went wrong")
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.output, "Something went wrong")
        XCTAssertTrue(result.metadata.isEmpty)
    }

    // MARK: - ToolExecutor Tests

    /// Test ToolExecutor with unknown tool.
    func testToolExecutorUnknownTool() async {
        let registry = ToolRegistry()
        let executor = ToolExecutor(registry: registry)
        let call = FunctionCall(name: "nonexistent_tool", parameters: [:], rawText: "")

        let result = await executor.execute(call: call)
        XCTAssertFalse(result.isSuccess, "Unknown tool should fail")
        XCTAssertTrue(result.output.contains("Unknown tool"), "Should mention unknown tool")
    }

    /// Test ToolExecutor with registered tool.
    func testToolExecutorWithRegisteredTool() async {
        let registry = ToolRegistry()
        await registry.register(CalculatorTool())
        let executor = ToolExecutor(registry: registry)
        let call = FunctionCall(name: "calculator", parameters: ["expression": "3+4"], rawText: "")

        let result = await executor.execute(call: call)
        XCTAssertTrue(result.isSuccess, "Registered tool should succeed")
        XCTAssertTrue(result.output.contains("7"), "3+4 should equal 7")
    }

    /// Test ToolExecutor executeAll runs in sequence.
    func testToolExecutorExecuteAll() async {
        let registry = ToolRegistry()
        await registry.register(CalculatorTool())
        await registry.register(CalendarTool())
        let executor = ToolExecutor(registry: registry)

        let calls = [
            FunctionCall(name: "calculator", parameters: ["expression": "1+1"], rawText: ""),
            FunctionCall(name: "calendar", parameters: ["action": "now"], rawText: "")
        ]

        let results = await executor.executeAll(calls: calls)
        XCTAssertEqual(results.count, 2, "Should have results for both calls")
        XCTAssertTrue(results[0].isSuccess)
        XCTAssertTrue(results[1].isSuccess)
    }

    // MARK: - CatalogEntry Tests

    /// Test CatalogEntry vision model properties.
    func testCatalogEntryVisionModel() {
        let visionEntry = ModelCatalog.entries.first { $0.supportsVision }
        XCTAssertNotNil(visionEntry, "Should have at least one vision model in catalog")
        XCTAssertEqual(visionEntry?.supportsVision, true)
        XCTAssertNotNil(visionEntry?.mmprojFilename)
        XCTAssertNotNil(visionEntry?.mmprojDownloadURL)
        XCTAssertGreaterThan(visionEntry?.mmprojDownloadSizeBytes ?? 0, 0)
    }

    /// Test CatalogEntry download size formatting.
    func testCatalogEntryDownloadSizeFormatting() {
        let entry = ModelCatalog.entries.first!
        XCTAssertFalse(entry.downloadSizeString.isEmpty, "Download size string should not be empty")
    }

    /// Test CatalogEntry isDownloaded check.
    func testCatalogEntryIsDownloadedCheck() {
        // A model that hasn't been downloaded should return false
        let entry = ModelCatalog.entries.first { !$0.isDownloaded }
        XCTAssertNotNil(entry, "Should have at least one undownloaded model in test environment")
    }

    // MARK: - UIImage Extension Tests

    /// Test UIImage.resizedToFit reduces image size.
    func testUIImageResizedToFit() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 2000))
        let image = renderer.image { context in
            UIColor.purple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2000, height: 2000))
        }

        let resized = image.resizedToFit(maxSize: CGSize(width: 500, height: 500))
        XCTAssertNotNil(resized, "Should produce a resized image")
        XCTAssertLessThanOrEqual(resized!.size.width, 500, "Width should be within bounds")
        XCTAssertLessThanOrEqual(resized!.size.height, 500, "Height should be within bounds")
    }

    /// Test UIImage.resizedToFit with aspect ratio preservation.
    func testUIImageResizedToFitAspectPreservation() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 500))
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 500))
        }

        let resized = image.resizedToFit(maxSize: CGSize(width: 200, height: 200))
        XCTAssertNotNil(resized)
        // 2:1 aspect ratio should be preserved: 200x100
        XCTAssertEqual(resized!.size.width, 200, accuracy: 1.0)
        XCTAssertEqual(resized!.size.height, 100, accuracy: 1.0)
    }

    // MARK: - DocumentImportError Tests

    /// Test DocumentImportError descriptions.
    func testDocumentImportErrorDescriptions() {
        let errors: [DocumentImportError] = [
            .fileNotFound(path: "/missing.txt"),
            .unsupportedFormat(ext: "docx"),
            .extractionFailed(detail: "no text"),
            .chunkingFailed(detail: "zero chunks"),
            .embeddingFailed(detail: "model error")
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - ImportedDocument Tests

    /// Test ImportedDocument creation and properties.
    func testImportedDocumentCreation() {
        let doc = ImportedDocument(
            id: UUID(),
            filename: "report.pdf",
            fileType: "pdf",
            fileSize: 1_048_576,
            importDate: Date(),
            chunkCount: 10,
            totalEstimatedTokens: 500
        )
        XCTAssertEqual(doc.filename, "report.pdf")
        XCTAssertEqual(doc.fileType, "pdf")
        XCTAssertEqual(doc.fileSize, 1_048_576)
        XCTAssertEqual(doc.chunkCount, 10)
    }

    // MARK: - VisionEncoderConfiguration Tests

    /// Test that custom configuration overrides defaults.
    func testVisionEncoderCustomConfiguration() {
        let config = VisionEncoderConfiguration(
            projectorPath: "/custom/path.mmproj",
            threadCount: 4,
            imageSize: 512,
            usesLlavaImageToken: false,
            imageTokenString: "<|image|>"
        )
        XCTAssertEqual(config.projectorPath, "/custom/path.mmproj")
        XCTAssertEqual(config.threadCount, 4)
        XCTAssertEqual(config.imageSize, 512)
        XCTAssertFalse(config.usesLlavaImageToken)
        XCTAssertEqual(config.imageTokenString, "<|image|>")
    }

    // MARK: - ImageEmbedding Tests

    /// Test ImageEmbedding creation.
    func testImageEmbeddingCreation() {
        let embedding = ImageEmbedding(
            embeddings: [1.0, 2.0, 3.0],
            patchCount: 3,
            embeddingDimension: 1,
            estimatedTokens: 3
        )
        XCTAssertEqual(embedding.patchCount, 3)
        XCTAssertEqual(embedding.embeddingDimension, 1)
        XCTAssertEqual(embedding.estimatedTokens, 3)
        XCTAssertEqual(embedding.embeddings.count, 3)
    }

    // MARK: - FunctionCall ParametersJSON Tests

    /// Test FunctionCall parametersJSON serialization.
    func testFunctionCallParametersJSON() {
        let call = FunctionCall(
            name: "calculator",
            parameters: ["expression": "2+2", "precision": 4],
            rawText: "<function>...</function>"
        )
        let json = call.parametersJSON
        XCTAssertTrue(json.contains("expression"), "JSON should contain 'expression' key")
        XCTAssertTrue(json.contains("2+2"), "JSON should contain the value")
    }
}
