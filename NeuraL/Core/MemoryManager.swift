import Foundation
actor MemoryManager {
    static let shared = MemoryManager()
    var currentThermalState: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }
    var availableMemory: UInt64 { UInt64(os_proc_available_memory()) }
    func canLoadModel(fileSize: UInt64) -> Bool { true }
    func computeBudget(modelFileSize: UInt64, layerCount: Int, embeddingDimension: Int, desiredContextLength: Int) -> (maxContext: Int, remaining: UInt64, gpuOffload: Bool) {
        (desiredContextLength, 0, true)
    }
}
