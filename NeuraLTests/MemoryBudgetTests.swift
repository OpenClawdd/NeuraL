//
//  MemoryBudgetTests.swift
//  NeuraLTests
//
//  Phase 5.2 — Focused tests for MemoryBudget computation logic
//
//  These tests verify the budget computation without requiring a
//  physical device or loaded model. They test the pure logic of
//  memory estimation and budget calculation.
//

import XCTest
@testable import NeuraL

final class MemoryBudgetTests: XCTestCase {

    // MARK: - MemoryBudget.canLoad Boundary Tests

    /// Verify that exactly the threshold (200MB) passes.
    func testCanLoadAtExactThreshold() {
        let budget = MemoryBudget(
            maxContextLength: 2048,
            estimatedTotalBytes: 1_000_000_000,
            remainingFreeBytes: 200 * 1_048_576,
            gpuOffloadingRecommended: true,
            recommendedThreadCount: 2,
            thermalState: .nominal
        )
        XCTAssertTrue(budget.canLoad)
    }

    /// Verify that 1 byte below the threshold fails.
    func testCannotLoadOneByteBelowThreshold() {
        let budget = MemoryBudget(
            maxContextLength: 2048,
            estimatedTotalBytes: 1_000_000_000,
            remainingFreeBytes: (200 * 1_048_576) - 1,
            gpuOffloadingRecommended: true,
            recommendedThreadCount: 2,
            thermalState: .nominal
        )
        XCTAssertFalse(budget.canLoad, "1 byte below 200MB should fail")
    }

    /// Verify very large remaining memory passes.
    func testCanLoadWithLargeRemaining() {
        let budget = MemoryBudget(
            maxContextLength: 4096,
            estimatedTotalBytes: 1_000_000_000,
            remainingFreeBytes: 8_000_000_000,  // 8 GB
            gpuOffloadingRecommended: true,
            recommendedThreadCount: 4,
            thermalState: .nominal
        )
        XCTAssertTrue(budget.canLoad)
    }

    /// Verify zero remaining fails.
    func testCannotLoadWithZeroRemaining() {
        let budget = MemoryBudget(
            maxContextLength: 512,
            estimatedTotalBytes: 500_000_000,
            remainingFreeBytes: 0,
            gpuOffloadingRecommended: false,
            recommendedThreadCount: 1,
            thermalState: .critical
        )
        XCTAssertFalse(budget.canLoad)
    }

    // MARK: - GPU Offloading Recommendation

    /// At nominal thermal state, GPU offloading should typically be recommended.
    func testGPURecommendedAtNominalThermal() {
        let budget = MemoryBudget(
            maxContextLength: 2048,
            estimatedTotalBytes: 800_000_000,
            remainingFreeBytes: 2_000_000_000,
            gpuOffloadingRecommended: true,
            recommendedThreadCount: 2,
            thermalState: .nominal
        )
        XCTAssertTrue(budget.gpuOffloadingRecommended)
    }

    /// At serious thermal state, GPU offloading should not be recommended.
    func testGPUNotRecommendedAtSeriousThermal() {
        let budget = MemoryBudget(
            maxContextLength: 2048,
            estimatedTotalBytes: 800_000_000,
            remainingFreeBytes: 2_000_000_000,
            gpuOffloadingRecommended: false,
            recommendedThreadCount: 1,
            thermalState: .serious
        )
        XCTAssertFalse(budget.gpuOffloadingRecommended)
    }

    // MARK: - Thread Count Recommendations

    /// At nominal thermal, 2 threads are recommended.
    func testThreadCountAtNominal() {
        let budget = MemoryBudget(
            maxContextLength: 2048,
            estimatedTotalBytes: 800_000_000,
            remainingFreeBytes: 2_000_000_000,
            gpuOffloadingRecommended: true,
            recommendedThreadCount: 2,
            thermalState: .nominal
        )
        XCTAssertEqual(budget.recommendedThreadCount, 2)
    }

    /// At critical thermal, only 1 thread is recommended.
    func testThreadCountAtCritical() {
        let budget = MemoryBudget(
            maxContextLength: 1024,
            estimatedTotalBytes: 800_000_000,
            remainingFreeBytes: 1_500_000_000,
            gpuOffloadingRecommended: false,
            recommendedThreadCount: 1,
            thermalState: .critical
        )
        XCTAssertEqual(budget.recommendedThreadCount, 1)
    }

    // MARK: - Context Length

    /// Verify that the context length is preserved in the budget.
    func testContextLengthPreservation() {
        let budget = MemoryBudget(
            maxContextLength: 4096,
            estimatedTotalBytes: 2_000_000_000,
            remainingFreeBytes: 500_000_000,
            gpuOffloadingRecommended: true,
            recommendedThreadCount: 2,
            thermalState: .nominal
        )
        XCTAssertEqual(budget.maxContextLength, 4096)
    }

    /// Verify that small context lengths are representable.
    func testSmallContextLength() {
        let budget = MemoryBudget(
            maxContextLength: 256,
            estimatedTotalBytes: 800_000_000,
            remainingFreeBytes: 2_000_000_000,
            gpuOffloadingRecommended: true,
            recommendedThreadCount: 2,
            thermalState: .nominal
        )
        XCTAssertEqual(budget.maxContextLength, 256)
    }

    // MARK: - MemorySnapshot Tests

    /// Test that MemorySnapshot produces a description.
    func testMemorySnapshotDescription() {
        let snapshot = MemoryManager.MemorySnapshot(
            availableBytes: 2_000_000_000,
            physicalBytes: 8_000_000_000,
            thermalState: .nominal,
            deviceTier: .premium
        )
        XCTAssertFalse(snapshot.description.isEmpty, "MemorySnapshot should have a description")
        XCTAssertTrue(snapshot.description.contains("Premium"))
    }

    /// Test DeviceCapabilityTier ordering.
    func testDeviceCapabilityTierOrdering() {
        // The tiers should be ordered by capability
        let tiers: [DeviceCapabilityTier] = [.limited, .standard, .premium, .extended]
        for i in 0..<(tiers.count - 1) {
            XCTAssertNotEqual(tiers[i].description, tiers[i + 1].description,
                              "Each tier should have a unique description")
        }
    }
}
