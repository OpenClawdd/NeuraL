//
//  VisionEncoder.swift
//  NeuraL
//
//  Phase 6.1 — Vision Model Loader & Image Encoder
//
//  This actor manages the multimodal projector (.mmproj) model and provides
//  image encoding capabilities for vision-language models (e.g., llava,
//  Llama-3.2-Vision). It wraps llama.cpp CLIP/llava C API into a safe,
//  actor-isolated Swift interface.
//

import Foundation
import CoreGraphics
import UIKit
import os

// MARK: - Image Attachment

/// Represents an image attached to a chat message. Stored as compressed
/// JPEG data at two resolutions: a small thumbnail for UI display, and
/// a full-resolution version for model encoding.
struct ImageAttachment: Sendable, Identifiable, Codable {
    let id: UUID
    let name: String
    let thumbnailData: Data
    let fullImageData: Data
    let originalWidth: Int
    let originalHeight: Int
    let estimatedTokens: Int

    static func from(_ image: UIImage, name: String = "Image") -> ImageAttachment? {
        let originalWidth = Int(image.size.width * image.scale)
        let originalHeight = Int(image.size.height * image.scale)

        guard let thumbnail = image.resizedToFit(maxSize: CGSize(width: 200, height: 200)),
              let thumbData = thumbnail.jpegData(compressionQuality: 0.6) else {
            return nil
        }

        guard let fullImage = image.resizedToFit(maxSize: CGSize(width: 1024, height: 1024)),
              let fullData = fullImage.jpegData(compressionQuality: 0.85) else {
            return nil
        }

        let estimatedTokens = 576

        return ImageAttachment(
            id: UUID(),
            name: name,
            thumbnailData: thumbData,
            fullImageData: fullData,
            originalWidth: originalWidth,
            originalHeight: originalHeight,
            estimatedTokens: estimatedTokens
        )
    }

    static func from(data: Data, name: String = "Image") -> ImageAttachment? {
        guard let image = UIImage(data: data) else { return nil }
        return from(image, name: name)
    }

    var thumbnailImage: UIImage? {
        UIImage(data: thumbnailData)
    }
}

// MARK: - Image Embedding

/// Encoded image representation ready for insertion into the LLM KV cache.
struct ImageEmbedding: Sendable {
    let embeddings: [Float]
    let patchCount: Int
    let embeddingDimension: Int
    let estimatedTokens: Int
}

// MARK: - Vision Encoder Configuration

struct VisionEncoderConfiguration: Sendable {
    let projectorPath: String
    let threadCount: Int
    let imageSize: Int
    let usesLlavaImageToken: Bool
    let imageTokenString: String

    static let `default` = VisionEncoderConfiguration(
        projectorPath: "",
        threadCount: 2,
        imageSize: 336,
        usesLlavaImageToken: true,
        imageTokenString: "<image>"
    )

    /// Configuration for Llama-3.2-Vision style models using pipe-delimited tokens.
    static let llamaVision = VisionEncoderConfiguration(
        projectorPath: "",
        threadCount: 2,
        imageSize: 448,
        usesLlavaImageToken: false,
        imageTokenString: "|image|"
    )
}

// MARK: - Vision Encoder State

enum VisionEncoderState: Sendable, Equatable, CustomStringConvertible {
    case idle
    case loading
    case ready
    case encoding
    case error(String)

    var description: String {
        switch self {
        case .idle: return "Idle"
        case .loading: return "Loading projector..."
        case .ready: return "Ready"
        case .encoding: return "Encoding image..."
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - Vision Encoder

/// Actor that manages the multimodal projector and encodes images for
/// vision-language model inference.
actor VisionEncoder {

    private var state: VisionEncoderState = .idle
    private var clipContext: OpaquePointer?
    private var configuration: VisionEncoderConfiguration?
    private let logger = Logger(subsystem: "com.neural.vision", category: "VisionEncoder")

    var currentState: VisionEncoderState { state }
    var isReady: Bool { state.isReady }

    // MARK: - Projector Loading

    /// Load a multimodal projector (.mmproj) file.
    func loadProjector(at url: URL, config: VisionEncoderConfiguration = .default) throws {
        switch state {
        case .idle, .error:
            break
        case .loading:
            throw VisionError.invalidState("Cannot load projector while in \(state) state.")
        case .ready:
            return  // already loaded
        case .encoding:
            throw VisionError.invalidState("Cannot load projector while in \(state) state.")
        }

        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw VisionError.projectorNotFound(path: path)
        }

        state = .loading
        logger.info("Loading multimodal projector: \(path)")

        let updatedConfig = VisionEncoderConfiguration(
            projectorPath: path,
            threadCount: config.threadCount,
            imageSize: config.imageSize,
            usesLlavaImageToken: config.usesLlavaImageToken,
            imageTokenString: config.imageTokenString
        )
        self.configuration = updatedConfig

        let ctx = path.withCString { pathPtr in
            clip_model_load(pathPtr, 1)
        }

        guard let ctx else {
            state = .error("Failed to load projector.")
            throw VisionError.projectorLoadFailed(
                path: path,
                detail: "clip_model_load returned NULL. Ensure the file is a valid .mmproj GGUF."
            )
        }

        self.clipContext = ctx
        state = .ready

        let nPatches = clip_n_patches(ctx)
        logger.info("Projector loaded. Image patches: \(nPatches)")
    }

    // MARK: - Image Encoding

    /// Encode an image into embeddings suitable for the LLM KV cache.
    func encodeImage(_ image: UIImage) throws -> ImageEmbedding {
        guard state.isReady else {
            throw VisionError.invalidState("Encoder not ready. Current state: \(state)")
        }
        guard let clipCtx = clipContext else {
            throw VisionError.invalidState("No CLIP context available.")
        }

        state = .encoding
        defer {
            if case .encoding = state {
                state = .ready
            }
        }

        let config = configuration ?? .default

        let targetSize = CGSize(width: config.imageSize, height: config.imageSize)
        guard let resizedImage = image.resizedToFit(maxSize: targetSize),
              let imageData = resizedImage.jpegData(compressionQuality: 0.9) else {
            throw VisionError.imageProcessingFailed("Failed to resize or compress image.")
        }

        let embed = imageData.withUnsafeBytes { dataPtr in
            guard let baseAddress = dataPtr.baseAddress else { return OpaquePointer(bitPattern: 0) }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            let result = llava_image_embed_make_with_clip_ctx(
                clipCtx,
                Int32(config.threadCount),
                bytes,
                Int32(imageData.count),
                Int32(config.imageSize),
                Int32(config.imageSize)
            )
            return OpaquePointer(result)
        }

        guard let embed else {
            throw VisionError.encodingFailed("Image encoding returned NULL.")
        }

        defer {
            llava_image_embed_free(embed)
        }

        let nImagePos = embed.pointee.n_image_pos
        guard nImagePos > 0 else {
            throw VisionError.encodingFailed("Image encoding produced zero positions.")
        }

        let embeddingDim = 4096
        let totalFloats = Int(nImagePos) * embeddingDim

        var embeddingData = [Float](repeating: 0, count: totalFloats)
        if let embedPtr = embed.pointee.embed {
            for i in 0..<totalFloats {
                embeddingData[i] = embedPtr[i]
            }
        }

        return ImageEmbedding(
            embeddings: embeddingData,
            patchCount: Int(nImagePos),
            embeddingDimension: embeddingDim,
            estimatedTokens: Int(nImagePos)
        )
    }

    /// Encode an image from raw data.
    func encodeImageData(_ data: Data) throws -> ImageEmbedding {
        guard let image = UIImage(data: data) else {
            throw VisionError.imageProcessingFailed("Could not create UIImage from data.")
        }
        return try encodeImage(image)
    }

    // MARK: - Projector Unloading

    func unloadProjector() {
        if let ctx = clipContext {
            clip_free(ctx)
            clipContext = nil
        }
        configuration = nil
        state = .idle
        logger.info("Projector unloaded.")
    }

    // MARK: - Token Helpers

    func imageTokenString() -> String {
        configuration?.imageTokenString ?? "<image>"
    }

    func imagePatchCount() -> Int {
        guard let ctx = clipContext else { return 0 }
        return Int(clip_n_patches(ctx))
    }

    deinit {
        if let ctx = clipContext {
            clip_free(ctx)
        }
    }
}

// MARK: - Vision Errors

enum VisionError: LocalizedError, CustomStringConvertible {
    case projectorNotFound(path: String)
    case projectorLoadFailed(path: String, detail: String)
    case invalidState(String)
    case imageProcessingFailed(String)
    case encodingFailed(String)
    case unsupportedFormat(String)

    var description: String {
        switch self {
        case .projectorNotFound(let path):
            return "Projector file not found: \(path)"
        case .projectorLoadFailed(let path, let detail):
            return "Projector load failed (\(detail)): \(path)"
        case .invalidState(let detail):
            return "Vision encoder invalid state: \(detail)"
        case .imageProcessingFailed(let detail):
            return "Image processing failed: \(detail)"
        case .encodingFailed(let detail):
            return "Image encoding failed: \(detail)"
        case .unsupportedFormat(let detail):
            return "Unsupported format: \(detail)"
        }
    }

    var errorDescription: String? { description }
}

// MARK: - UIImage Extension

extension UIImage {
    /// Resize the image to fit within the given size while maintaining aspect ratio.
    func resizedToFit(maxSize: CGSize) -> UIImage? {
        let aspect = size.width / size.height
        let targetSize: CGSize
        if aspect > 1 {
            targetSize = CGSize(width: maxSize.width, height: maxSize.width / aspect)
        } else {
            targetSize = CGSize(width: maxSize.height * aspect, height: maxSize.height)
        }

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
