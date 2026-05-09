//
//  DocumentImporter.swift
//  NeuraL
//
//  Phase 6.3 â€” Document Import & Chunking for RAG
//
//  Handles importing documents (PDF, TXT, MD) from the user's device,
//  extracting text, splitting into chunks, generating embeddings, and
//  storing in the VectorStore for retrieval-augmented generation.
//
//  Chunking strategy:
//  - Documents are split into overlapping chunks of ~500 tokens
//  - Overlap of ~50 tokens between chunks preserves context at boundaries
//  - Metadata (source, position) is preserved for citation
//
//  Embedding strategy:
//  - Primary: Use the LLM's embedding layer (if the loaded model supports it)
//  - Fallback: Hash-based embedding using DJB2 + random projection
//    (lightweight but less accurate; good enough for basic RAG)
//

import Foundation
import UniformTypeIdentifiers
import PDFKit

// MARK: - Document Import Error

enum DocumentImportError: LocalizedError {
    case fileNotFound(path: String)
    case unsupportedFormat(ext: String)
    case extractionFailed(detail: String)
    case chunkingFailed(detail: String)
    case embeddingFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .unsupportedFormat(let ext): return "Unsupported format: .\(ext). Supported: .txt, .md, .pdf"
        case .extractionFailed(let detail): return "Text extraction failed: \(detail)"
        case .chunkingFailed(let detail): return "Chunking failed: \(detail)"
        case .embeddingFailed(let detail): return "Embedding generation failed: \(detail)"
        }
    }
}

// MARK: - Document Chunker

/// Splits text into overlapping chunks suitable for embedding and retrieval.
enum DocumentChunker {

    /// Target chunk size in characters (~500 tokens at ~3.8 chars/token).
    static let chunkSize = 1900

    /// Overlap between chunks in characters (~50 tokens).
    static let chunkOverlap = 190

    /// Split text into overlapping chunks.
    ///
    /// The chunker attempts to split on paragraph boundaries when possible,
    /// falling back to sentence boundaries, and ultimately to word boundaries.
    static func chunk(text: String, sourceName: String, documentId: UUID) -> [DocumentChunk] {
        guard !text.isEmpty else { return [] }

        var chunks: [DocumentChunk] = []
        let totalLength = text.count
        var startIndex = text.startIndex
        var chunkIndex = 0

        while startIndex < text.endIndex {
            let endIndex = text.index(startIndex, offsetBy: min(chunkSize, text.distance(from: startIndex, to: text.endIndex)))

            // Try to find a natural break point near the end
            let searchRange = text.index(endIndex, offsetBy: min(-200, -text.distance(from: startIndex, to: endIndex)))..<endIndex
            let breakSearch = String(text[searchRange])

            var actualEnd = endIndex
            // Prefer paragraph break
            if let paraBreak = breakSearch.lastIndex(of: "\n\n") {
                let adjustedOffset = text.distance(from: searchRange.lowerBound, to: paraBreak)
                actualEnd = text.index(searchRange.lowerBound, offsetBy: adjustedOffset)
            }
            // Fallback: sentence break
            else if let sentBreak = breakSearch.lastIndex(of: ". ") {
                let adjustedOffset = text.distance(from: searchRange.lowerBound, to: sentBreak) + 1
                actualEnd = text.index(searchRange.lowerBound, offsetBy: adjustedOffset)
            }
            // Fallback: newline
            else if let lineBreak = breakSearch.lastIndex(of: "\n") {
                let adjustedOffset = text.distance(from: searchRange.lowerBound, to: lineBreak)
                actualEnd = text.index(searchRange.lowerBound, offsetBy: adjustedOffset)
            }

            let chunkText = String(text[startIndex..<actualEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

            if !chunkText.isEmpty {
                let rangeStart = text.distance(from: text.startIndex, to: startIndex)
                let estimatedTokens = max(1, Int(Double(chunkText.utf8.count) / 3.8))

                let embedding = SimpleEmbedding.embed(chunkText)

                chunks.append(DocumentChunk(
                    id: UUID(),
                    documentId: documentId,
                    documentName: sourceName,
                    text: chunkText,
                    chunkIndex: chunkIndex,
                    embedding: embedding,
                    rangeStart: rangeStart,
                    estimatedTokens: estimatedTokens
                ))
                chunkIndex += 1
            }

            // Move start with overlap
            let nextStart = text.index(actualEnd, offsetBy: -min(chunkOverlap, text.distance(from: startIndex, to: actualEnd)))
            if nextStart <= startIndex {
                startIndex = text.index(after: actualEnd)
            } else {
                startIndex = nextStart
            }
        }

        return chunks
    }
}

// MARK: - Simple Embedding

/// A lightweight embedding generator that uses hash-based random projection.
/// This is a fallback when the LLM's embedding layer is not available.
///
/// The approach:
/// 1. Split text into n-grams (unigrams and bigrams)
/// 2. Hash each n-gram to a seed for a pseudo-random vector
/// 3. Accumulate the random vectors, weighted by n-gram frequency
/// 4. Normalize the result
///
/// This produces reasonable embeddings for keyword-based similarity
/// without requiring any neural network inference.
enum SimpleEmbedding {

    /// Embedding dimension (must match the LLM's embedding dim for direct comparison,
    /// but for our keyword search fallback, any reasonable dimension works).
    static let dimension = 512

    /// Generate an embedding vector for a text string.
    static func embed(_ text: String) -> [Float] {
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract unigrams and bigrams
        let words = normalized.split(separator: " ").map(String.init)
        var ngramFreqs: [String: Float] = [:]

        // Unigrams
        for word in words where word.count > 2 {
            ngramFreqs[word, default: 0] += 1.0
        }

        // Bigrams
        for i in 0..<(words.count - 1) {
            let bigram = "\(words[i]) \(words[i + 1])"
            ngramFreqs[bigram, default: 0] += 1.5
        }

        // Generate embedding using random projection
        var embedding = [Float](repeating: 0, count: dimension)

        for (ngram, weight) in ngramFreqs {
            let seed = djb2Hash(ngram)
            var rng = SeededRNG(seed: seed)

            for i in 0..<dimension {
                let projection = rng.nextNormal() * weight
                embedding[i] += projection
            }
        }

        // Normalize to unit length
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            for i in 0..<dimension {
                embedding[i] /= norm
            }
        }

        return embedding
    }

    /// DJB2 hash function for strings.
    private static func djb2Hash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }
}

// MARK: - Seeded RNG

/// A simple seeded pseudo-random number generator for reproducible random projections.
private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed &+ 1 // Avoid all-zero state
    }

    /// Generate a normally-distributed random number using Box-Muller.
    mutating func nextNormal() -> Float {
        let u1 = Float(nextUniform())
        let u2 = Float(nextUniform())
        guard u1 > 0 else { return 0 }

        let r = sqrt(-2.0 * log(u1))
        let theta = 2.0 * Float.pi * u2
        return r * cos(theta) * 0.1 // Scale down for stability
    }

    /// Generate a uniform random number in [0, 1).
    private mutating func nextUniform() -> Double {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state) / Double(UInt64.max)
    }
}

// MARK: - Document Importer

/// Orchestrates the document import pipeline: extract text, chunk, embed, store.
actor DocumentImporter {

    private let vectorStore: VectorStore

    init(vectorStore: VectorStore = .shared) {
        self.vectorStore = vectorStore
    }

    /// Import a document from a file URL.
    ///
    /// Supports:
    /// - .txt: Plain text (UTF-8)
    /// - .md: Markdown (treated as plain text)
    /// - .pdf: PDF (text extraction via CGPDFDocument)
    func importDocument(at url: URL) async throws -> ImportedDocument {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw DocumentImportError.fileNotFound(path: path)
        }

        let ext = url.pathExtension.lowercased()
        guard ["txt", "md", "pdf"].contains(ext) else {
            throw DocumentImportError.unsupportedFormat(ext: ext)
        }

        // Step 1: Extract text
        let text: String
        switch ext {
        case "txt", "md":
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                throw DocumentImportError.extractionFailed(detail: "Could not read file as UTF-8 text.")
            }
            text = content

        case "pdf":
            text = extractPDFText(from: url)

        default:
            throw DocumentImportError.unsupportedFormat(ext: ext)
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentImportError.extractionFailed(detail: "No text content found in the document.")
        }

        // Step 2: Create document metadata
        let documentId = UUID()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0

        let document = ImportedDocument(
            id: documentId,
            filename: url.lastPathComponent,
            fileType: ext,
            fileSize: fileSize,
            importDate: Date(),
            chunkCount: 0,
            totalEstimatedTokens: 0
        )

        // Step 3: Chunk the text
        let chunks = DocumentChunker.chunk(
            text: text,
            sourceName: url.lastPathComponent,
            documentId: documentId
        )

        guard !chunks.isEmpty else {
            throw DocumentImportError.chunkingFailed(detail: "Document produced zero chunks.")
        }

        // Step 4: Store in vector store
        let totalTokens = chunks.reduce(0) { $0 + $1.estimatedTokens }
        let finalDocument = ImportedDocument(
            id: documentId,
            filename: url.lastPathComponent,
            fileType: ext,
            fileSize: fileSize,
            importDate: Date(),
            chunkCount: chunks.count,
            totalEstimatedTokens: totalTokens
        )

        await vectorStore.addChunks(chunks, document: finalDocument)

        return finalDocument
    }

    /// Extract text from a PDF document using PDFKit.
    private func extractPDFText(from url: URL) -> String {
        guard let pdf = PDFDocument(url: url) else { return "" }
        return pdf.string ?? ""
    }
}

