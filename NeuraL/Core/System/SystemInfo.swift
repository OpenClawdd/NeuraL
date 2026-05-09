//
//  SystemInfo.swift
//  NeuraL
//
//  System Capability Detection & Status (Sideload Focus)
//
//  Detects and exposes:
//  - Device model, CPU cores, RAM total/free
//  - Memory tier (Standard, Premium, Extended)
//  - JIT availability (debugger-attached check)
//  - Extended virtual addressing entitlement status
//  - Thermal state and token rate cap
//  - Metal GPU status
//  - Helper app detection (GetMoreRAM, Jitterbug) via URL schemes
//
//  All checks are lightweight and safe. No private APIs are used
//  for detection — only sysctl, proc_info, and public URL scheme queries.
//

import SwiftUI
import Observation
import MachO
import os

// MARK: - System Info

/// Observable model for system capability detection.
/// Instantiated in NeuraLApp and placed in the environment.
@Observable
@MainActor
final class SystemInfo {

    // MARK: - Device Info

    /// Device model identifier (e.g., "iPhone15,2").
    let deviceModel: String

    /// User-friendly device name (e.g., "iPhone 14 Pro").
    let deviceName: String

    /// Number of CPU cores.
    let cpuCoreCount: Int

    /// Total physical RAM in bytes.
    let totalRAM: UInt64

    /// Available memory in bytes.
    var availableMemory: UInt64

    // MARK: - Tier Info

    /// Device memory tier.
    let memoryTier: DeviceCapabilityTier

    // MARK: - JIT Status

    /// Whether JIT compilation is available.
    /// Detected by checking if a debugger is attached, which is
    /// the standard sideloading JIT mechanism.
    var isJITAvailable: Bool = false

    /// Explanation of JIT status for the UI.
    var jitStatusDescription: String = ""

    // MARK: - Extended Memory

    /// Whether extended virtual addressing is enabled via entitlement.
    /// We know the entitlement is present in our build, so this is
    /// determined by checking the device tier.
    var isExtendedMemoryEnabled: Bool = false

    /// Description of extended memory status.
    var extendedMemoryDescription: String = ""

    // MARK: - Thermal

    /// Current thermal state.
    var thermalState: ProcessInfo.ThermalState = .nominal

    /// Current token rate cap based on thermal state.
    var tokenRateCap: String = "Unlimited"

    // MARK: - Metal

    /// Whether Metal GPU is available and active.
    var isMetalAvailable: Bool = false

    // MARK: - Helper Apps

    /// Whether GetMoreRAM helper is installed.
    var isGetMoreRAMInstalled: Bool = false

    /// Whether Jitterbug helper is installed.
    var isJitterbugInstalled: Bool = false

    // MARK: - Initialization

    init() {
        // Device model
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        self.deviceModel = String(cString: machine)

        // Device name
        self.deviceName = Self.mapModelToName(self.deviceModel)

        // CPU cores
        self.cpuCoreCount = ProcessInfo.processInfo.processorCount

        // Total RAM
        self.totalRAM = UInt64(ProcessInfo.processInfo.physicalMemory)

        // Memory tier
        let totalGB = Double(totalRAM) / 1_073_741_824
        switch totalGB {
        case ..<4:   self.memoryTier = DeviceCapabilityTier.limited
        case ..<8:   self.memoryTier = DeviceCapabilityTier.standard
        case ..<16:  self.memoryTier = DeviceCapabilityTier.premium
        default:     self.memoryTier = DeviceCapabilityTier.extended
        }

        // Available memory (initial)
        let available = ondevice_available_memory()
        self.availableMemory = available > 0 ? UInt64(available) : totalRAM / 2

        // Extended memory — we have the entitlement in our build
        self.isExtendedMemoryEnabled = memoryTier == DeviceCapabilityTier.extended || memoryTier == DeviceCapabilityTier.premium
        self.extendedMemoryDescription = isExtendedMemoryEnabled
            ? NSLocalizedString("Enabled — Extended virtual addressing entitlement is active", comment: "")
            : NSLocalizedString("Not available — Device has limited memory for model context", comment: "")

        // Metal availability
        self.isMetalAvailable = Self.checkMetalAvailability()
    }

    // MARK: - Refresh

    /// Refresh all dynamic values (thermal, memory, JIT, helpers).
    func refresh() {
        // Available memory
        let available = ondevice_available_memory()
        self.availableMemory = available > 0 ? UInt64(available) : totalRAM / 2

        // Thermal state
        self.thermalState = ProcessInfo.processInfo.thermalState
        switch thermalState {
        case .nominal:  self.tokenRateCap = NSLocalizedString("Unlimited", comment: "")
        case .fair:     self.tokenRateCap = NSLocalizedString("Full speed", comment: "")
        case .serious:  self.tokenRateCap = NSLocalizedString("10 tok/s cap", comment: "")
        case .critical: self.tokenRateCap = NSLocalizedString("3 tok/s cap", comment: "")
        @unknown default: self.tokenRateCap = NSLocalizedString("5 tok/s cap", comment: "")
        }

        // JIT detection — check if debugger is attached
        self.isJITAvailable = Self.isDebuggerAttached()
        self.jitStatusDescription = isJITAvailable
            ? NSLocalizedString("Available — Debugger attached, JIT compilation enabled", comment: "")
            : NSLocalizedString("Unavailable — No debugger detected. Use a JIT enabler to enable.", comment: "")

        // Helper app detection
        self.isGetMoreRAMInstalled = Self.canOpenURLScheme("getmoreram://")
        self.isJitterbugInstalled = Self.canOpenURLScheme("jitterbug://")
    }

    // MARK: - Formatted Values

    /// Total RAM formatted as human-readable string.
    var totalRAMFormatted: String {
        let gb = Double(totalRAM) / 1_073_741_824
        return String(format: "%.1f GB", gb)
    }

    /// Available memory formatted as human-readable string.
    var availableMemoryFormatted: String {
        let mb = Double(availableMemory) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    /// Memory tier formatted.
    var memoryTierFormatted: String {
        memoryTier.description
    }

    /// Thermal state formatted.
    var thermalStateFormatted: String {
        switch thermalState {
        case .nominal:  return NSLocalizedString("Nominal", comment: "")
        case .fair:     return NSLocalizedString("Fair", comment: "")
        case .serious:  return NSLocalizedString("Serious", comment: "")
        case .critical: return NSLocalizedString("Critical", comment: "")
        @unknown default: return NSLocalizedString("Unknown", comment: "")
        }
    }

    // MARK: - Private Helpers

    /// Check if a debugger is attached using sysctl.
    /// This is the standard technique for JIT detection on sideloaded apps.
    private static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }

        // P_TRACED flag indicates a debugger is attached
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    /// Check if a URL scheme can be opened (helper app detection).
    private static func canOpenURLScheme(_ scheme: String) -> Bool {
        guard let url = URL(string: scheme) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Check Metal availability.
    private static func checkMetalAvailability() -> Bool {
        let device = MTLCreateSystemDefaultDevice()
        return device != nil
    }

    /// Map device model identifier to a user-friendly name.
    private static func mapModelToName(_ model: String) -> String {
        // iPhone mappings
        let iphoneMap: [String: String] = [
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
        ]
        if let name = iphoneMap[model] { return name }
        if model.hasPrefix("iPhone") { return "iPhone" }
        if model.hasPrefix("iPad") { return "iPad" }
        if model.hasPrefix("x86_64") || model.hasPrefix("arm64") { return "Simulator" }
        return model
    }
}

// MARK: - P_TRACED constant

/// The P_TRACED flag from sysctl for debugger detection.
/// This is a public constant defined in BSD sysctl headers.
private let P_TRACED: Int32 = 0x00000800
