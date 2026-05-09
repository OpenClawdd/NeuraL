//
//  VectorStore.swift
//  NeuraL
//
//  Phase 6.3 — On-Device Vector Store for RAG
//
//  A lightweight, in-memory vector store that supports cosine similarity
//  search over document chunks. Designed for on-device RAG (Retrieval
//  Augmented Generation) without requiring any external services.
//
//  Architecture:
//  - Documents are imported, chunked, and embedded using the LLM's
//    embedding layer (or a hash-based fallback for models without
//    embedding output).
//  - Chunks are stored with their embedding vectors and metadata.
//  - At query time, the query is embedded and the top-K most similar
//    chunks are retrieved and injected into the conversation context.
//
//  Memory considerations:
//  - Each chunk stores its embedding vector (typically 2048-4096 floats).
//  - For 1000 chunks with 2048-dim embeddings: ~8 MB (Float32).
//  - The store is persisted as JSON to Documents/VectorStore/.
//

import Foundation
import os

// MARK: - Document Chunk

/// A chunk of text from a document, with its embedding vector and metadata.
struct DocumentChunk: Sendable, Identifiable, Codable {
    let id: UUID
    /// The source document's identifier.
    let documentId: UUID
    /// The source document's filename.
    let documentName: String
    /// The chunk's text content.
    let text: String
    /// The chunk's index within the document (0-based).
    let chunkIndex: Int
    /// The embedding vector for this chunk.
    let embedding: [Float]
    /// The character range of this chunk in the original document.
    let rangeStart: Int
    /// Token count estimate for this chunk.
    let estimatedTokens: Int

    /// Compute cosine similarity between this chunk's embedding and a query embedding.
    func cosineSimilarity(to queryEmbedding: [Float]) -> Float {
        guard embedding.count == queryEmbedding.count, !embedding.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<embedding.count {
            dotProduct += embedding[i] * queryEmbedding[i]
            normA += embedding[i] * embedding[i]
            normB += queryEmbedding[i] * queryEmbedding[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dotProduct / denominator
    }
}

// MARK: - Imported Document

/// Metadata for an imported document.
struct ImportedDocument: Sendable, Identifiable, Codable {
    let id: UUID
    let filename: String
    let fileType: String // "pdf", "txt", "md"
    let fileSize: UInt64
    let importDate: Date
    let chunkCount: Int
    let totalEstimatedTokens: Int
}

// MARK: - Search Result

/// A search result from the vector store.
struct SearchResult: Sendable {
    let chunk: DocumentChunk
    let similarity: Float
}

// MARK: - Vector Store

/// In-memory vector store with persistence. Supports adding documents,
/// searching by cosine similarity, and managing the store.
actor VectorStore {

    static let shared = VectorStore()

    private var chunks: [DocumentChunk] = []
    private var documents: [UUID: ImportedDocument] = [:]
    private let logger = Logger(subsystem: "com.neural.rag", category: "VectorStore")

    // MARK: - Persistence

    private static var storeDirectory: URL {
        let documentsDir = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        let dir = documentsDir.appendingPathComponent("VectorStore", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    nonisolated private var chunksFileURL: URL {
        Self.storeDirectory.appendingPathComponent("chunks.json")
    }

    nonisolated private var documentsFileURL: URL {
        Self.storeDirectory.appendingPathComponent("documents.json")
    }

    // MARK: - Initialization

    init() {
        // Load persisted data
        if let data = try? Data(contentsOf: chunksFileURL),
           let decoded = try? JSONDecoder().decode([DocumentChunk].self, from: data) {
            chunks = decoded
        }

        if let data = try? Data(contentsOf: documentsFileURL),
           let decoded = try? JSONDecoder().decode([ImportedDocument].self, from: data) {
            for doc in decoded {
                documents[doc.id] = doc
            }
        }
    }

    // MARK: - Adding Documents

    /// Add chunks from an imported document.
    func addChunks(_ newChunks: [DocumentChunk], document: ImportedDocument) {
        chunks.append(contentsOf: newChunks)
        documents[document.id] = document
        persist()
        logger.info("Added \(newChunks.count) chunks from '\(document.filename)'. Total chunks: \(self.chunks.count)")
    }

    // MARK: - Searching

    /// Search for the top-K most similar chunks to a query embedding.
    func search(queryEmbedding: [Float], topK: Int = 5, minimumSimilarity: Float = 0.3) -> [SearchResult] {
        let scored = chunks.map { chunk in
            SearchResult(chunk: chunk, similarity: chunk.cosineSimilarity(to: queryEmbedding))
        }
        .filter { $0.similarity >= minimumSimilarity }
        .sorted { $0.similarity > $1.similarity }

        return Array(scored.prefix(topK))
    }

    /// Search for chunks related to a text query using simple keyword matching
    /// as a fallback when embeddings are not available.
    func keywordSearch(query: String, topK: Int = 5) -> [SearchResult] {
        let queryLower = query.lowercased()
        let queryWords = queryLower.split(separator: " ").map(String.init)

        let scored = chunks.map { chunk -> SearchResult in
            let textLower = chunk.text.lowercased()
            var score: Float = 0
            for word in queryWords where word.count > 2 {
                if textLower.contains(word) {
                    score += 1.0
                }
            }
            // Boost for exact phrase match
            if textLower.contains(queryLower) {
                score += 3.0
            }
            return SearchResult(chunk: chunk, similarity: score)
        }
        .filter { $0.similarity > 0 }
        .sorted { $0.similarity > $1.similarity }

        return Array(scored.prefix(topK))
    }

    // MARK: - Document Management

    /// Remove a document and all its chunks.
    func removeDocument(id: UUID) {
        chunks.removeAll { $0.documentId == id }
        documents.removeValue(forKey: id)
        persist()
        logger.info("Removed document \(id). Remaining chunks: \(self.chunks.count)")
    }

    /// Get all imported documents.
    func allDocuments() -> [ImportedDocument] {
        Array(documents.values).sorted { $0.importDate > $1.importDate }
    }

    /// Get chunk count.
    var totalChunks: Int { self.chunks.count }

    /// Get total estimated tokens across all chunks.
    var totalEstimatedTokens: Int {
        chunks.reduce(0) { $0 + $1.estimatedTokens }
    }

    /// Clear the entire store.
    func clearAll() {
        chunks = []
        documents = [:]
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(chunks) {
            try? data.write(to: chunksFileURL, options: .atomic)
        }
        let docArray = Array(documents.values)
        if let data = try? JSONEncoder().encode(docArray) {
            try? data.write(to: documentsFileURL, options: .atomic)
        }
    }
}
