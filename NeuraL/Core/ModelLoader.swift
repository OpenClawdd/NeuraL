//
//  ModelLoader.swift
//  NeuraL
//
//  Phase 1 — GGUF Model Validation, Pre-Flight Checks, and Loading Orchestration
//
//  The ModelLoader is responsible for everything that happens BEFORE the
//  model is loaded into the llama.cpp context:
//
//  1. File validation: Does the file exist? Is it a valid GGUF file?
//  2. Metadata extraction: What's the architecture, size, quantization?
//  3. Memory budgeting: Can this device actually run this model?
//  4. Configuration synthesis: Given the model and the device, what
//     configuration should we use for loading?
//
//  The ModelLoader is an actor because it coordinates between the
//  MemoryManager (actor) and the LlamaCppBridge (actor), and it
//  ensures that pre-flight checks are atomic — no other operation
//  can interfere while we're deciding whether a model can be loaded.
//

import Foundation

// MARK: - GGUF File Validator

/// Validates GGUF file integrity before attempting to load it into llama.cpp.
///
/// GGUF file format (simplified):
///   - Magic: "GGUF" (4 bytes)
///   - Version: uint32 (current: 3)
///   - Tensor count: uint64
///   - Metadata KV count: uint64
///   - Metadata KV pairs (variable length)
///   - Tensor info array
///   - Padding to alignment
///   - Tensor data
///
/// We validate the magic number and version as a quick sanity check.
/// Full validation happens inside llama.cpp when the model is loaded.
enum GGUFValidator {

    /// GGUF magic number as byte sequence.
    private static let ggufMagic: [UInt8] = [0x47, 0x47, 0x55, 0x46]  // "GGUF"

    /// Supported GGUF version range.
    private static let supportedVersionRange: ClosedRange<UInt32> = 2...3

    /// Validate a GGUF file at the given URL.
    ///
    /// - Parameter url: File URL to the .gguf file.
    /// - Returns: Validation result with file size if valid.
    static func validate(url: URL) -> Result<GGUFFileInfo, GGUFValidationError> {
        let path = url.path

        // Check 1: File exists
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(.fileNotFound(path: path))
        }

        // Check 2: File is readable
        guard FileManager.default.isReadableFile(atPath: path) else {
            return .failure(.fileNotReadable(path: path))
        }

        // Check 3: Get file size
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? UInt64 else {
            return .failure(.cannotReadAttributes(path: path))
        }

        // Check 4: Minimum file size (a valid GGUF must have at least the header)
        let minimumSize = UInt64(4 + 4 + 8 + 8)  // magic + version + tensor_count + kv_count
        guard fileSize >= minimumSize else {
            return .failure(.fileTooSmall(size: fileSize, minimum: minimumSize))
        }

        // Check 5: Read and validate the GGUF header
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return .failure(.cannotOpenFile(path: path))
        }
        defer { try? handle.close() }

        // Read the magic number (4 bytes)
        guard let magicData = try? handle.read(upToCount: 4),
              magicData.count == 4 else {
            return .failure(.cannotReadHeader(field: "magic"))
        }

        let magic = [UInt8](magicData)
        guard magic == ggufMagic else {
            return .failure(.invalidMagic(actual: magic, expected: ggufMagic))
        }

        // Read the version (4 bytes, little-endian)
        guard let versionData = try? handle.read(upToCount: 4),
              versionData.count == 4 else {
            return .failure(.cannotReadHeader(field: "version"))
        }

        let version = versionData.withUnsafeBytes { pointer -> UInt32 in
            pointer.load(as: UInt32.self)
        }

        guard supportedVersionRange.contains(version) else {
            return .failure(.unsupportedVersion(version: version, supported: supportedVersionRange))
        }

        return .success(GGUFFileInfo(
            url: url,
            fileSize: fileSize,
            ggufVersion: Int(version)
        ))
    }
}

/// Information extracted from a GGUF file header.
struct GGUFFileInfo: Sendable {
    let url: URL
    let fileSize: UInt64
    let ggufVersion: Int
}

/// Errors that can occur during GGUF file validation.
enum GGUFValidationError: LocalizedError, CustomStringConvertible {
    case fileNotFound(path: String)
    case fileNotReadable(path: String)
    case cannotReadAttributes(path: String)
    case fileTooSmall(size: UInt64, minimum: UInt64)
    case cannotOpenFile(path: String)
    case cannotReadHeader(field: String)
    case invalidMagic(actual: [UInt8], expected: [UInt8])
    case unsupportedVersion(version: UInt32, supported: ClosedRange<UInt32>)

    var description: String {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileNotReadable(let path):
            return "File not readable: \(path)"
        case .cannotReadAttributes(let path):
            return "Cannot read file attributes: \(path)"
        case .fileTooSmall(let size, let minimum):
            return String(format: "File too small (%llu bytes, minimum %llu)", size, minimum)
        case .cannotOpenFile(let path):
            return "Cannot open file: \(path)"
        case .cannotReadHeader(let field):
            return "Cannot read GGUF header field: \(field)"
        case .invalidMagic(let actual, _):
            let actualStr = actual.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "Invalid GGUF magic number: \(actualStr) (expected GGUF)"
        case .unsupportedVersion(let version, let supported):
            return "Unsupported GGUF version: \(version) (supported: \(supported))"
        }
    }

    var errorDescription: String? { description }
}

// MARK: - Model Loading Orchestration

/// Orchestrates the model loading sequence:
///   1. Validate the GGUF file
///   2. Probe the model metadata (lightweight, doesn't fully load the model)
///   3. Compute a memory budget via MemoryManager
///   4. Synthesize the loading configuration
///   5. Load the model via LlamaCppBridge
///
/// This actor serializes the loading process to prevent race conditions
/// where two concurrent loads could both pass the memory check but
/// together exceed available memory.
actor ModelLoader {

    // MARK: - Loading Result

    /// Result of a successful model loading operation.
    struct LoadResult: Sendable {
        let metadata: ModelMetadata
        let configuration: LlamaBridgeConfiguration
        let budget: MemoryBudget
    }

    // MARK: - Pre-Flight Check

    /// Perform a pre-flight check on a model file without loading it.
    ///
    /// This validates the file, estimates memory requirements, and computes
    /// a budget. It does NOT load the model or allocate any significant memory.
    ///
    /// - Parameters:
    ///   - modelURL: File URL to the .gguf file.
    ///   - desiredConfiguration: The loading configuration the caller would like to use.
    /// - Returns: A PreFlightResult indicating whether the model can be loaded
    ///           and with what constraints.
    func preFlightCheck(
        modelURL: URL,
        desiredConfiguration: ModelLoadConfiguration
    ) -> PreFlightResult {
        // Step 1: Validate the GGUF file
        let validationResult = GGUFValidator.validate(url: modelURL)
        switch validationResult {
        case .success(let fileInfo):
            break
        case .failure(let error):
            return .invalidFile(error)
        }

        guard case .success(let fileInfo) = validationResult else {
            fatalError("Unreachable")  // Swift doesn't know the switch is exhaustive here
        }

        // Step 2: Quick memory check — can we even fit the file in memory?
        let memoryManager = MemoryManager.shared
        let canLoad = memoryManager.canLoadModel(fileSize: fileInfo.fileSize)

        if !canLoad {
            let snapshot = memoryManager.snapshot()
            return .insufficientMemory(
                fileSize: fileInfo.fileSize,
                availableBytes: snapshot.availableBytes
            )
        }

        // Step 3: We can't extract exact model metadata without loading the model
        // (llama.cpp doesn't expose a lightweight metadata-only API in the C interface).
        // Instead, we estimate based on typical model sizes:
        //   - 1.5B Q4_K_M ≈ 1.0GB file → ~28 layers, ~2048 embd
        //   - 3B Q4_K_M ≈ 2.0GB file → ~32 layers, ~2560 embd
        //   - 1.5B Q4_0 ≈ 0.8GB file → ~28 layers, ~2048 embd
        //
        // These estimates are conservative (they assume a larger model than
        // might be the case, which means we're more likely to refuse a load
        // that would fail than to allow one that would crash).
        let estimatedLayerCount: Int
        let estimatedEmbeddingDim: Int
        let fileSizeGB = Double(fileInfo.fileSize) / 1_073_741_824

        if fileSizeGB < 1.0 {
            // Likely a 1.5B Q4_0 or smaller model
            estimatedLayerCount = 28
            estimatedEmbeddingDim = 2048
        } else if fileSizeGB < 1.5 {
            // Likely a 1.5B Q4_K_M or similar
            estimatedLayerCount = 28
            estimatedEmbeddingDim = 2048
        } else if fileSizeGB < 2.5 {
            // Likely a 3B model
            estimatedLayerCount = 32
            estimatedEmbeddingDim = 2560
        } else {
            // Larger model — use conservative estimates
            estimatedLayerCount = 40
            estimatedEmbeddingDim = 3072
        }

        // Step 4: Compute the memory budget
        let budget = memoryManager.computeBudget(
            modelFileSize: fileInfo.fileSize,
            layerCount: estimatedLayerCount,
            embeddingDimension: estimatedEmbeddingDim,
            desiredContextLength: desiredConfiguration.maxContextLength
        )

        if !budget.canLoad {
            return .budgetExceeded(budget: budget, fileSize: fileInfo.fileSize)
        }

        // Step 5: Synthesize the bridge configuration
        let bridgeConfig = LlamaBridgeConfiguration(
            contextLength: budget.maxContextLength,
            gpuLayerCount: budget.gpuOffloadingRecommended ? desiredConfiguration.gpuLayerCount : 0,
            generationThreadCount: budget.recommendedThreadCount,
            batchThreadCount: desiredConfiguration.batchThreadCount,
            batchSize: desiredConfiguration.batchSize,
            useMemoryMapping: desiredConfiguration.useMemoryMapping
        )

        return .canLoad(
            fileInfo: fileInfo,
            budget: budget,
            bridgeConfiguration: bridgeConfig
        )
    }

    // MARK: - Full Load

    /// Load a model into the given bridge after performing pre-flight checks.
    ///
    /// This is the complete loading sequence:
    ///   1. Pre-flight validation and budgeting
    ///   2. Load the model into the LlamaCppBridge
    ///   3. Extract actual metadata from the loaded model
    ///   4. Return the result with accurate metadata
    ///
    /// - Parameters:
    ///   - modelURL: File URL to the .gguf file.
    ///   - configuration: Desired loading configuration.
    ///   - bridge: The LlamaCppBridge to load the model into.
    /// - Returns: LoadResult with metadata and configuration.
    /// - Throws: InferenceError on any failure.
    func load(
        modelURL: URL,
        configuration: ModelLoadConfiguration,
        into bridge: LlamaCppBridge
    ) async throws -> LoadResult {
        // Step 1: Pre-flight check
        let preFlight = preFlightCheck(modelURL: modelURL, desiredConfiguration: configuration)

        switch preFlight {
        case .canLoad(_, let budget, let bridgeConfig):
            // Step 2: Load the model into the bridge
            let filePath = modelURL.path
            try await bridge.loadModel(filePath: filePath, config: bridgeConfig)

            // Step 3: Extract actual metadata from the loaded model
            let metadata = await bridge.getModelMetadata()

            guard let metadata = metadata else {
                throw InferenceError.backendInitializationFailed(
                    detail: "Model loaded but metadata extraction returned nil."
                )
            }

            // Step 4: Return with the actual metadata
            var finalMetadata = metadata
            // Update the file size from the actual file
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? UInt64 {
                finalMetadata = ModelMetadata(
                    architecture: metadata.architecture,
                    layerCount: metadata.layerCount,
                    embeddingDimension: metadata.embeddingDimension,
                    vocabularySize: metadata.vocabularySize,
                    trainingContextLength: metadata.trainingContextLength,
                    fileSize: size,
                    quantization: metadata.quantization,
                    estimatedMemoryFootprint: metadata.estimatedMemoryFootprint
                )
            }

            return LoadResult(
                metadata: finalMetadata,
                configuration: bridgeConfig,
                budget: budget
            )

        case .invalidFile(let error):
            throw InferenceError.modelCorrupt(path: modelURL.path, detail: error.description)

        case .insufficientMemory(let fileSize, let availableBytes):
            let estimatedFootprint = UInt64(Double(fileSize) * 1.25)
            throw InferenceError.insufficientMemory(
                requiredBytes: estimatedFootprint,
                availableBytes: availableBytes
            )

        case .budgetExceeded(let budget, _):
            throw InferenceError.insufficientMemory(
                requiredBytes: budget.estimatedTotalBytes,
                availableBytes: budget.remainingFreeBytes + budget.estimatedTotalBytes
            )
        }
    }
}

// MARK: - Pre-Flight Result

/// Result of a pre-flight model check.
enum PreFlightResult: Sendable {
    /// The model can be loaded with the given configuration.
    case canLoad(
        fileInfo: GGUFFileInfo,
        budget: MemoryBudget,
        bridgeConfiguration: LlamaBridgeConfiguration
    )
    /// The GGUF file is invalid or corrupt.
    case invalidFile(GGUFValidationError)
    /// The device doesn't have enough memory to even consider loading this model.
    case insufficientMemory(fileSize: UInt64, availableBytes: UInt64)
    /// The model could fit in memory, but the budget computation shows
    /// insufficient headroom (not enough free memory after loading).
    case budgetExceeded(budget: MemoryBudget, fileSize: UInt64)

    /// Whether the model can be loaded.
    var canLoad: Bool {
        if case .canLoad = self { return true }
        return false
    }
}
