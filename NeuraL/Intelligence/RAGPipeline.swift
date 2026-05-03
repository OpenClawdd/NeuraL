//
//  RAGPipeline.swift
//  NeuraL
//
//  Phase 6.3 — Retrieval-Augmented Generation Pipeline
//
//  Orchestrates the RAG workflow:
//  1. Receive a user query
//  2. Embed the query (using SimpleEmbedding or LLM embeddings)
//  3. Search the VectorStore for relevant chunks
//  4. Construct an augmented prompt with retrieved context
//  5. Pass to the inference engine for generation
//
//  The RAG pipeline is designed to be transparent: the user can see
//  which sources were consulted, and citations are included in responses.
//

import Foundation

// MARK: - RAG Configuration

/// Configuration for the RAG pipeline.
struct RAGConfiguration: Sendable {
    /// Maximum number of chunks to retrieve per query.
    let topK: Int
    /// Minimum similarity score for a chunk to be included.
    let minimumSimilarity: Float
    /// Maximum total tokens from retrieved context (to avoid context overflow).
    let maxContextTokens: Int
    /// Whether to include source citations in the augmented prompt.
    let includeCitations: Bool
    /// The system prompt addition that instructs the model to use RAG context.
    let ragSystemPrompt: String

    static let `default` = RAGConfiguration(
        topK: 5,
        minimumSimilarity: 0.3,
        maxContextTokens: 1500,
        includeCitations: true,
        ragSystemPrompt: """
        You have been provided with relevant context from the user's documents. \
        Use this context to answer the user's question. If the context doesn't contain \
        enough information to answer the question, say so. Always cite the source document \
        when using information from the provided context.
        """
    )
}

// MARK: - RAG Result

/// The result of a RAG retrieval operation.
struct RAGResult: Sendable {
    /// The retrieved chunks with their similarity scores.
    let retrievedChunks: [SearchResult]
    /// The augmented system prompt with context injected.
    let augmentedSystemPrompt: String
    /// The total tokens used by the retrieved context.
    let contextTokensUsed: Int
    /// Whether any relevant context was found.
    let hasContext: Bool

    /// A human-readable summary of the sources consulted.
    var sourceSummary: String {
        if retrievedChunks.isEmpty {
            return "No relevant documents found."
        }

        let sources = Dictionary(grouping: retrievedChunks) { $0.chunk.documentName }
        return sources.map { name, results in
            "\(name) (\(results.count) chunk\(results.count > 1 ? "s" : ""))"
        }.joined(separator: ", ")
    }
}

// MARK: - RAG Pipeline

/// Orchestrates retrieval-augmented generation for on-device document Q&A.
actor RAGPipeline {

    private let vectorStore: VectorStore
    private let configuration: RAGConfiguration

    init(
        vectorStore: VectorStore = .shared,
        configuration: RAGConfiguration = .default
    ) {
        self.vectorStore = vectorStore
        self.configuration = configuration
    }

    /// Retrieve relevant context for a user query.
    ///
    /// This is the main entry point for RAG. Given a user's message,
    /// it embeds the query, searches the vector store, and constructs
    /// an augmented system prompt with the retrieved context.
    func retrieve(for query: String) async -> RAGResult {
        // Step 1: Embed the query
        let queryEmbedding = SimpleEmbedding.embed(query)

        // Step 2: Search the vector store
        let results = await vectorStore.search(
            queryEmbedding: queryEmbedding,
            topK: configuration.topK,
            minimumSimilarity: configuration.minimumSimilarity
        )

        // If vector search found nothing, try keyword search as fallback
        let searchResults: [SearchResult]
        if results.isEmpty {
            searchResults = await vectorStore.keywordSearch(
                query: query,
                topK: configuration.topK
            )
        } else {
            searchResults = results
        }

        // Step 3: Select chunks within token budget
        var selectedChunks: [SearchResult] = []
        var tokensUsed = 0

        for result in searchResults {
            let chunkTokens = result.chunk.estimatedTokens
            if tokensUsed + chunkTokens <= configuration.maxContextTokens {
                selectedChunks.append(result)
                tokensUsed += chunkTokens
            } else {
                break
            }
        }

        // Step 4: Construct augmented prompt
        let augmentedPrompt: String
        if selectedChunks.isEmpty {
            augmentedPrompt = configuration.ragSystemPrompt
        } else {
            var contextParts: [String] = []
            contextParts.append(configuration.ragSystemPrompt)
            contextParts.append("")
            contextParts.append("---")
            contextParts.append("Retrieved Context:")
            contextParts.append("")

            for (index, result) in selectedChunks.enumerated() {
                if configuration.includeCitations {
                    contextParts.append("[Source \(index + 1): \(result.chunk.documentName), chunk \(result.chunk.chunkIndex + 1), similarity: \(String(format: "%.2f", result.similarity))]")
                }
                contextParts.append(result.chunk.text)
                contextParts.append("")
            }

            contextParts.append("---")
            contextParts.append("Answer the user's question using the context above. Cite sources by number (e.g., [1]).")

            augmentedPrompt = contextParts.joined(separator: "\n")
        }

        return RAGResult(
            retrievedChunks: selectedChunks,
            augmentedSystemPrompt: augmentedPrompt,
            contextTokensUsed: tokensUsed,
            hasContext: !selectedChunks.isEmpty
        )
    }

    /// Quick check: does the query likely benefit from RAG?
    ///
    /// Simple heuristic: questions and document-related queries benefit from RAG;
    /// creative/generative tasks do not.
    func shouldUseRAG(for query: String) async -> Bool {
        let queryLower = query.lowercased()
        let questionIndicators = ["what", "who", "when", "where", "how", "why", "which", "explain", "describe", "tell me about", "summarize", "define", "find", "search", "look up", "document", "file", "notes", "pdf", "article"]
        let creativeIndicators = ["write", "create", "generate", "compose", "imagine", "story", "poem", "code", "program"]

        let isQuestion = questionIndicators.contains { queryLower.hasPrefix($0) || queryLower.contains(" \($0) ") }
        let isCreative = creativeIndicators.contains { queryLower.hasPrefix($0) }

        // Check if vector store has any documents
        let chunkCount = await self.vectorStore.totalChunks

        return chunkCount > 0 && (isQuestion || !isCreative)
    }
}
