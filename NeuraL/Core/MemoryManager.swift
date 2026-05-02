//
//  MemoryManager.swift
//  NeuraL
//
//  Phase 1 — Memory Probing, Thermal Monitoring, and Context Window Sizing
//  Phase 4 — Memory Pressure Monitoring & Graceful Shutdown
//
//  This module is the gatekeeper for model loading. Before any model is loaded,
//  the MemoryManager answers the question: "Can this device actually run this
//  model without getting jetsam-killed?"
//
//  Key responsibilities:
//  1. Probe available physical/virtual memory via os_proc_available_memory()
//  2. Estimate the total memory footprint of a model (weights + KV cache + overhead)
//  3. Compute the maximum safe context window length
//  4. Monitor thermal state and recommend throttling
//  5. Provide a memory budget that the InferenceOrchestrator must respect
//  6. Monitor OS memory pressure via DispatchSource and trigger graceful shutdown
//     when iOS signals imminent jetsam, saving partial work as a draft
//

import Foundation
import os

// MARK: - Memory Budget

/// A computed memory budget that constrains how a model is loaded.
///
/// The MemoryManager produces this after analyzing the model's metadata
/// and the device's current memory/thermal situation. The InferenceEngine
/// MUST respect these limits — exceeding them risks jetsam termination.
struct MemoryBudget: Sendable {
    /// The maximum context window length the device can support for this model.
    /// This may be smaller than the model's training context length.
    let maxContextLength: Int

    /// Estimated total memory usage if the model is loaded with the
    /// computed maxContextLength.
    let estimatedTotalBytes: UInt64

    /// The amount of memory that will remain free after loading.
    let remainingFreeBytes: UInt64

    /// Whether GPU (Metal) offloading is recommended given the thermal state.
    let gpuOffloadingRecommended: Bool

    /// Recommended thread count for autoregressive generation.
    let recommendedThreadCount: Int

    /// The thermal state at the time this budget was computed.
    let thermalState: ProcessInfo.ThermalState

    /// Whether this budget allows the model to be loaded at all.
    var canLoad: Bool {
        // We require at least 200MB of headroom after loading to avoid
        // jetsam killing us during KV cache growth or OS memory pressure spikes.
        remainingFreeBytes >= 200 * 1_048_576
    }
}

// MARK: - Device Capability Tier

/// A coarse classification of the device's capability for on-device LLM inference.
/// Used to select sensible defaults without requiring per-device configuration.
enum DeviceCapabilityTier: Sendable, CustomStringConvertible {
    /// Older devices with ≤4GB RAM (iPhone 12 and earlier, most iPads).
    /// Can only run 1.5B Q4_0 models with short context.
    case limited
    /// Mid-range devices with 6-8GB RAM (iPhone 13 Pro through 14 Pro).
    /// Can run 1.5B Q4_K_M with 2048 context, or 3B with 1024 context.
    case standard
    /// High-end devices with ≥8GB RAM (iPhone 15 Pro+, iPad Pro M1+ 16GB).
    /// Can run 3B Q4_K_M with 2048 context comfortably.
    case premium
    /// Devices with ≥16GB RAM (iPad Pro M2/M4 16GB, Mac with Apple Silicon).
    /// Can run 3B models with large context or potentially larger models.
    case extended

    var description: String {
        switch self {
        case .limited:   return "Limited (≤4GB)"
        case .standard:  return "Standard (6-8GB)"
        case .premium:   return "Premium (8-16GB)"
        case .extended:  return "Extended (16GB+)"
        }
    }
}

// MARK: - MemoryManager

/// Singleton actor that manages memory budgeting for on-device inference.
///
/// Usage:
/// ```swift
/// let budget = await MemoryManager.shared.computeBudget(
///     modelFileSize: 1_100_000_000,
///     layerCount: 28,
///     embeddingDimension: 2048,
///     desiredContextLength: 2048
/// )
/// if !budget.canLoad {
///     // Don't load the model
/// }
/// ```
actor MemoryManager {

    static let shared = MemoryManager()

    // MARK: - Constants

    /// Safety margin: we require this much free memory AFTER loading the model.
    /// iOS jetsam is aggressive; 200MB headroom is the minimum safe buffer.
    private let safetyMarginBytes: UInt64 = 200 * 1_048_576

    /// Overhead multiplier: model weights on disk don't account for:
    /// - llama.cpp internal buffers (temp tensors for computation)
    /// - tokenizer allocations
    /// - Swift runtime overhead
    /// We apply a 1.25x multiplier to the model file size to estimate
    /// the actual memory consumed by the loaded model.
    private let modelOverheadMultiplier: Double = 1.25

    /// Bytes per KV cache entry per layer: 2 * n_embd * sizeof(float16)
    /// (key and value tensors, each with n_embd elements in FP16 = 2 bytes each)
    private let bytesPerKVEntryPerLayer: Int = 2 * 2048 * 2  // Default, overridden by actual n_embd

    // MARK: - Thermal Monitoring

    /// Current thermal state of the device.
    var currentThermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }

    /// Whether the device is in a thermally constrained state where
    /// generation should throttle or switch to CPU-only mode.
    var isThermallyConstrained: Bool {
        currentThermalState >= .serious
    }

    // MARK: - Memory Probing

    /// Returns the amount of memory currently available to this process,
    /// as reported by os_proc_available_memory().
    ///
    /// This value accounts for other apps and system processes using memory.
    /// It can fluctuate rapidly, so always re-probe before critical operations.
    var availableMemory: UInt64 {
        // os_proc_available_memory() is bridged through our C header.
        let available = ondevice_available_memory()
        // On simulator or older OS, this may return 0. Fall back to a
        // conservative estimate based on device tier.
        if available == 0 {
            return fallbackAvailableMemory
        }
        return UInt64(available)
    }

    /// Physical memory of the device (total RAM).
    var physicalMemory: UInt64 {
        UInt64(ProcessInfo.processInfo.physicalMemory)
    }

    /// Device capability tier based on total physical memory.
    var deviceTier: DeviceCapabilityTier {
        let totalGB = Double(physicalMemory) / 1_073_741_824
        switch totalGB {
        case ..<4:   return .limited
        case ..<8:   return .standard
        case ..<16:  return .premium
        default:     return .extended
        }
    }

    /// Fallback memory estimate when os_proc_available_memory() returns 0
    /// (e.g., on the simulator). Uses conservative percentages of physical RAM.
    private var fallbackAvailableMemory: UInt64 {
        let total = physicalMemory
        switch deviceTier {
        case .limited:  return total / 4       // 25% for very constrained devices
        case .standard: return total * 2 / 5   // 40%
        case .premium:  return total / 2       // 50%
        case .extended: return total * 3 / 5   // 60%
        }
    }

    // MARK: - Budget Computation

    /// Compute a memory budget for loading a model with the given characteristics.
    ///
    /// This is the primary decision function. Call it before attempting to load
    /// any model. It answers: "Given this model's size and the device's current
    /// state, what is the maximum context length I can safely use?"
    ///
    /// - Parameters:
    ///   - modelFileSize: Size of the .gguf file in bytes.
    ///   - layerCount: Number of transformer layers in the model.
    ///   - embeddingDimension: Embedding dimension (d_model) per layer.
    ///   - desiredContextLength: The context length the caller would LIKE to use.
    ///         The returned budget may specify a smaller value.
    /// - Returns: A MemoryBudget with the computed constraints.
    func computeBudget(
        modelFileSize: UInt64,
        layerCount: Int,
        embeddingDimension: Int,
        desiredContextLength: Int
    ) -> MemoryBudget {
        let available = availableMemory
        let thermal = currentThermalState

        // Step 1: Estimate model weights memory footprint
        let weightsBytes = UInt64(Double(modelFileSize) * modelOverheadMultiplier)

        // Step 2: Calculate KV cache bytes per token of context
        // Formula: n_layers * 2 * n_embd * sizeof(float16) * n_ctx
        let bytesPerContextToken = UInt64(layerCount) * 2 * UInt64(embeddingDimension) * 2

        // Step 3: Compute maximum context length that fits in available memory
        let memoryForKV = available > (weightsBytes + safetyMarginBytes)
            ? available - weightsBytes - safetyMarginBytes
            : 0

        let maxPossibleContext = memoryForKV / max(bytesPerContextToken, 1)

        // Step 4: Cap at the desired context length (user's requested maximum)
        let computedContext = min(Int(maxPossibleContext), desiredContextLength)

        // Step 5: Ensure context is at least 256 (below this, the model is unusable)
        let safeContext = max(computedContext, 256)

        // Step 6: Compute actual KV cache size for the safe context length
        let kvCacheBytes = bytesPerContextToken * UInt64(safeContext)

        // Step 7: Total estimated footprint
        let totalBytes = weightsBytes + kvCacheBytes

        // Step 8: Remaining free memory
        let remaining = available > totalBytes ? available - totalBytes : 0

        // Step 9: GPU offloading recommendation
        // On .serious or .critical thermal state, GPU offloading may cause
        // thermal throttling that actually SLOWS generation. In that case,
        // CPU-only with fewer threads is faster overall.
        let gpuRecommended = thermal < .serious

        // Step 10: Thread count recommendation based on thermal state
        let threads: Int
        switch thermal {
        case .nominal:   threads = 2
        case .fair:      threads = 2
        case .serious:   threads = 1
        case .critical:  threads = 1
        @unknown default: threads = 1
        }

        return MemoryBudget(
            maxContextLength: safeContext,
            estimatedTotalBytes: totalBytes,
            remainingFreeBytes: remaining,
            gpuOffloadingRecommended: gpuRecommended,
            recommendedThreadCount: threads,
            thermalState: thermal
        )
    }

    /// Quick check: can a model of the given file size be loaded at all?
    ///
    /// This is a fast pre-check that doesn't compute the full budget.
    /// Useful for filtering models in a UI before the user selects one.
    func canLoadModel(fileSize: UInt64) -> Bool {
        let estimatedFootprint = UInt64(Double(fileSize) * modelOverheadMultiplier)
        return availableMemory > estimatedFootprint + safetyMarginBytes
    }

    // MARK: - Runtime Memory Monitoring

    /// Snapshot of current memory usage for diagnostics.
    struct MemorySnapshot: Sendable, CustomStringConvertible {
        let availableBytes: UInt64
        let physicalBytes: UInt64
        let thermalState: ProcessInfo.ThermalState
        let deviceTier: DeviceCapabilityTier

        var description: String {
            let availMB = Double(availableBytes) / 1_048_576
            let physGB = Double(physicalBytes) / 1_073_741_824
            return String(format: """
                Memory: %.0f MB available / %.1f GB total | Thermal: %@ | Tier: %@
                """, availMB, physGB, thermalStateDescription, deviceTier)
        }

        private var thermalStateDescription: String {
            switch thermalState {
            case .nominal:  return "Nominal"
            case .fair:     return "Fair"
            case .serious:  return "Serious"
            case .critical: return "Critical"
            @unknown default: return "Unknown"
            }
        }
    }

    /// Capture a memory snapshot for logging or UI display.
    func snapshot() -> MemorySnapshot {
        MemorySnapshot(
            availableBytes: availableMemory,
            physicalBytes: physicalMemory,
            thermalState: currentThermalState,
            deviceTier: deviceTier
        )
    }

    // MARK: - Thermal Yield

    /// If the device is thermally constrained, sleep for a short duration
    /// to allow the system to cool. Call this periodically during generation.
    ///
    /// Returns the actual duration slept (0 if no sleep was needed).
    @discardableResult
    func yieldForThermalIfNecessary() async -> Duration {
        guard isThermallyConstrained else { return .zero }

        // At .serious, yield 10ms per call; at .critical, yield 50ms.
        let yieldMs: UInt64
        switch currentThermalState {
        case .serious:  yieldMs = 10
        case .critical: yieldMs = 50
        default:        return .zero
        }

        try? await Task.sleep(for: .milliseconds(yieldMs))
        return .milliseconds(yieldMs)
    }

    // MARK: - Dynamic Token Rate Cap

    /// Compute the maximum tokens-per-second the engine should target
    /// based on the current thermal state. This prevents the device from
    /// entering deeper throttling by voluntarily slowing generation.
    ///
    /// - Returns: Maximum tokens per second, or nil for no cap.
    func dynamicTokenRateCap() -> Double? {
        switch currentThermalState {
        case .nominal, .fair:
            return nil  // No cap needed
        case .serious:
            return 10.0  // Cap at 10 tok/s
        case .critical:
            return 3.0   // Cap at 3 tok/s (near-stall to let device cool)
        @unknown default:
            return 5.0
        }
    }

    /// Compute the delay between tokens (in milliseconds) needed to enforce
    /// the dynamic token rate cap. Returns 0 if no cap is needed.
    ///
    /// This is used by the generation loop to insert artificial delays
    /// between tokens, preventing thermal runaway.
    ///
    /// - Parameter currentTokPerSec: The current observed generation rate.
    func interTokenDelayMs(currentTokPerSec: Double) -> UInt64 {
        guard let cap = dynamicTokenRateCap(), currentTokPerSec > cap else {
            return 0
        }
        // If generating faster than the cap, compute the delay needed
        // to bring the rate down to the cap.
        // Target interval = 1000ms / capTokPerSec
        // Current interval = 1000ms / currentTokPerSec
        // Extra delay = target - current
        let targetIntervalMs = 1000.0 / cap
        let currentIntervalMs = 1000.0 / currentTokPerSec
        let delay = max(0, targetIntervalMs - currentIntervalMs)
        return UInt64(delay)
    }

    /// Whether GPU offloading should be disabled due to thermal state.
    /// At .critical, GPU offloading generates too much heat and should be
    /// dropped in favor of CPU-only inference (which is slower but cooler).
    var shouldDisableGPUForThermal: Bool {
        currentThermalState >= .critical
    }

    // MARK: - Memory Pressure Monitoring

    /// Callback type for memory pressure events. The handler receives
    /// the dispatch source memory pressure level and should take
    /// immediate action to reduce memory usage.
    typealias MemoryPressureHandler = @Sendable (DispatchSource.MemoryPressureEvent) -> Void

    /// The currently registered memory pressure handler.
    private var memoryPressureHandler: MemoryPressureHandler?

    /// The DispatchSource monitoring memory pressure.
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// Register a handler to be called when the OS signals memory pressure.
    ///
    /// This uses `DispatchSource.makeMemoryPressureSource()` which monitors
    /// the same signals that iOS uses before jetsam-killing processes.
    ///
    /// The handler is called on an arbitrary dispatch queue, so it must
    /// be thread-safe. The typical response is:
    /// 1. Cancel the active generation
    /// 2. Save partially generated text as a draft
    /// 3. Evict unnecessary KV cache data
    /// 4. Display a user-visible warning
    ///
    /// - Parameter handler: The closure to call when memory pressure changes.
    func registerMemoryPressureHandler(_ handler: @escaping MemoryPressureHandler) {
        // Remove any existing source
        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        self.memoryPressureHandler = handler

        // Create a memory pressure source that monitors .warning and .critical
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let event = source.memoryPressure
            self.logger.warning("Memory pressure event: \(event == .critical ? "CRITICAL" : "WARNING")")

            // Capture the current available memory for diagnostics
            let availableNow = self.availableMemory
            self.logger.warning("Available memory at pressure event: \(availableNow / 1_048_576) MB")

            // Call the registered handler
            self.memoryPressureHandler?(event)
        }

        source.resume()
        self.memoryPressureSource = source
        logger.info("Memory pressure monitor registered.")
    }

    /// Unregister the memory pressure handler and stop monitoring.
    func unregisterMemoryPressureHandler() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        memoryPressureHandler = nil
        logger.info("Memory pressure monitor unregistered.")
    }

    /// Logger instance for memory pressure events.
    private let logger = Logger(subsystem: "com.neural.engine", category: "MemoryManager")

    /// Whether we're currently in a memory pressure state (warning or critical).
    /// This is set by the memory pressure handler and checked by the generation loop.
    private var isUnderMemoryPressure: Bool = false

    /// Mark that the app is under memory pressure (called by the handler).
    func setUnderMemoryPressure(_ underPressure: Bool) {
        isUnderMemoryPressure = underPressure
    }

    /// Check whether the app is currently under memory pressure.
    var underMemoryPressure: Bool {
        isUnderMemoryPressure
    }
}
