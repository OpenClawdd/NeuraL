//
//  DeviceCapabilityTier.swift
//  NeuraL
//
//  Device memory capability tier used by SystemInfo to classify the
//  device and gate features like extended virtual addressing.
//

import Foundation

// MARK: - DeviceCapabilityTier

/// Classifies a device by available RAM into capability tiers.
///
/// Tiers are assigned at launch based on `ProcessInfo.physicalMemory`:
/// - `.limited`  — < 4 GB
/// - `.standard` — 4 GB to < 8 GB
/// - `.premium`  — 8 GB to < 16 GB
/// - `.extended` — 16 GB+
enum DeviceCapabilityTier: String, CaseIterable, Equatable, Codable, Sendable, CustomStringConvertible {
    case limited
    case standard
    case premium
    case extended

    var description: String {
        switch self {
        case .limited:  return "Limited (< 4 GB)"
        case .standard: return "Standard (4 GB)"
        case .premium:  return "Premium (8 GB)"
        case .extended: return "Extended (16 GB+)"
        }
    }
}
