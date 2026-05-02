//
//  SystemStatusView.swift
//  NeuraL
//
//  System Status Tab — Frutiger Aero Styled
//
//  Displays device capability information with a focus on
//  sideloaded-app features: JIT detection, extended memory,
//  helper app availability, thermal state, and Metal status.
//
//  All cards use the Frutiger Aero glass style with frosted
//  materials, gloss highlights, and soft shadows.
//

import SwiftUI

// MARK: - System Status View

struct SystemStatusView: View {
    let chatState: ChatState
    @State private var systemInfo = SystemInfo()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // ── Device Overview Card ─────────────────────────────
                    deviceOverviewCard

                    // ── Memory & Tier Card ──────────────────────────────
                    memoryCard

                    // ── JIT & Capabilities Card ─────────────────────────
                    jitCapabilitiesCard

                    // ── Thermal & Performance Card ──────────────────────
                    thermalPerformanceCard

                    // ── Metal & GPU Card ────────────────────────────────
                    metalGPUCard

                    // ── Helper Apps Card ────────────────────────────────
                    helperAppsCard

                    // ── Model Status Card ───────────────────────────────
                    modelStatusCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(aeroBackgroundGradient)
            .navigationTitle(NSLocalizedString("System", comment: "System tab title"))
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            systemInfo.refresh()
        }
    }

    // MARK: - Background

    private var aeroBackgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 224/255, green: 247/255, blue: 250/255),
                    Color(red: 178/255, green: 235/255, blue: 242/255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Device Overview Card

    private var deviceOverviewCard: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(FrutigerAeroTheme.shared.neonBlue.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: "iphone.gen3")
                    .font(.title)
                    .foregroundStyle(FrutigerAeroTheme.shared.neonBlue)
            }

            Text(systemInfo.deviceName)
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Text(systemInfo.deviceModel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                infoPill(icon: "cpu.fill", label: "\(systemInfo.cpuCoreCount) cores", color: FrutigerAeroTheme.shared.neonBlue)
                infoPill(icon: "memorychip.fill", label: systemInfo.totalRAMFormatted, color: FrutigerAeroTheme.shared.softTeal)
                infoPill(icon: "circle.fill", label: systemInfo.memoryTierFormatted, color: FrutigerAeroTheme.shared.goldAccent)
            }
        }
        .padding(20)
        .aeroGlassCard()
    }

    // MARK: - Memory Card

    private var memoryCard: some View {
        VStack(spacing: 10) {
            cardHeader("Memory & Storage", icon: "memorychip.fill", color: FrutigerAeroTheme.shared.softTeal)

            Divider().opacity(0.3)

            infoRow("Total RAM", value: systemInfo.totalRAMFormatted)
            infoRow("Available", value: systemInfo.availableMemoryFormatted)

            // Memory usage bar
            let usedFraction = 1.0 - (Double(systemInfo.availableMemory) / Double(systemInfo.totalRAM))
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Memory Usage", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(FrutigerAeroTheme.shared.buttonGradient)
                            .frame(width: geo.size.width * min(1.0, CGFloat(usedFraction)))
                    }
                }
                .frame(height: 8)
            }

            infoRow("Memory Tier", value: systemInfo.memoryTierFormatted)
            infoRow("Extended Addressing", value: systemInfo.isExtendedMemoryEnabled ? "Enabled" : "Not Available",
                    valueColor: systemInfo.isExtendedMemoryEnabled ? .green : .secondary)
        }
        .padding(16)
        .aeroGlassCard()
    }

    // MARK: - JIT & Capabilities Card

    private var jitCapabilitiesCard: some View {
        VStack(spacing: 10) {
            cardHeader("JIT & Capabilities", icon: "bolt.fill", color: FrutigerAeroTheme.shared.goldAccent)

            Divider().opacity(0.3)

            HStack {
                Image(systemName: systemInfo.isJITAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(systemInfo.isJITAvailable ? .green : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("JIT Compilation")
                        .font(.subheadline.bold())
                    Text(systemInfo.jitStatusDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // JIT info
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("JIT can improve model compilation speed for custom backends")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } icon: {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Label {
                    Text("Not required for normal inference — models run fine without JIT")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } icon: {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .aeroGlassCard()
    }

    // MARK: - Thermal & Performance Card

    private var thermalPerformanceCard: some View {
        VStack(spacing: 10) {
            cardHeader("Thermal & Performance", icon: "thermometer.medium", color: thermalColor)

            Divider().opacity(0.3)

            infoRow("Thermal State", value: systemInfo.thermalStateFormatted,
                    valueColor: thermalColor)
            infoRow("Token Rate Cap", value: systemInfo.tokenRateCap)

            // Thermal indicator
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(thermalBarColor(for: level))
                        .frame(height: 8)
                }
            }
        }
        .padding(16)
        .aeroGlassCard()
    }

    private var thermalColor: Color {
        switch systemInfo.thermalState {
        case .nominal:  return .green
        case .fair:     return .yellow
        case .serious:  return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }

    private func thermalBarColor(for level: Int) -> Color {
        let stateLevel: Int
        switch systemInfo.thermalState {
        case .nominal:  stateLevel = 0
        case .fair:     stateLevel = 1
        case .serious:  stateLevel = 2
        case .critical: stateLevel = 3
        @unknown default: stateLevel = 4
        }
        return level <= stateLevel ? thermalColor : Color(.systemGray5)
    }

    // MARK: - Metal & GPU Card

    private var metalGPUCard: some View {
        VStack(spacing: 10) {
            cardHeader("Metal & GPU", icon: "gpu", color: FrutigerAeroTheme.shared.neonBlue)

            Divider().opacity(0.3)

            HStack {
                Image(systemName: systemInfo.isMetalAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(systemInfo.isMetalAvailable ? .green : .red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Metal GPU Acceleration")
                        .font(.subheadline.bold())
                    Text(systemInfo.isMetalAvailable
                        ? "Available — GPU offloading active for model layers"
                        : "Not available — CPU-only inference")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(16)
        .aeroGlassCard()
    }

    // MARK: - Helper Apps Card

    private var helperAppsCard: some View {
        VStack(spacing: 10) {
            cardHeader("Helper Apps", icon: "app.badge.fill", color: FrutigerAeroTheme.shared.vibrantCyan)

            Divider().opacity(0.3)

            helperRow(
                name: "GetMoreRAM",
                icon: "memorychip",
                isInstalled: systemInfo.isGetMoreRAMInstalled,
                urlScheme: "getmoreram://"
            )

            helperRow(
                name: "Jitterbug",
                icon: "bolt.fill",
                isInstalled: systemInfo.isJitterbugInstalled,
                urlScheme: "jitterbug://"
            )

            // Info
            Label {
                Text("Helper apps can enable JIT compilation and extended memory for sideloaded apps. Install them separately.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } icon: {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .aeroGlassCard()
    }

    // MARK: - Model Status Card

    private var modelStatusCard: some View {
        VStack(spacing: 10) {
            cardHeader("Active Model", icon: "cpu.fill", color: FrutigerAeroTheme.shared.neonBlue)

            Divider().opacity(0.3)

            if let metadata = chatState.modelMetadata {
                infoRow("Architecture", value: metadata.architecture.prefix(1).uppercased() + metadata.architecture.dropFirst())
                infoRow("Quantization", value: metadata.quantization)
                infoRow("Model Size", value: String(format: "%.1f GB", Double(metadata.fileSize) / 1_073_741_824))
                infoRow("Context Used", value: "\(chatState.contextTokensUsed) / \(chatState.maxContextTokens) tokens")
                infoRow("Engine State", value: engineStateLabel, valueColor: engineStateColor)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No model loaded")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .aeroGlassCard()
    }

    // MARK: - Helper Views

    private func cardHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)

            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)

            Spacer()
        }
    }

    private func infoRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }

    private func infoPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2.bold())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func helperRow(name: String, icon: String, isInstalled: Bool, urlScheme: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isInstalled ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.bold())
                Text(isInstalled
                    ? NSLocalizedString("Installed", comment: "")
                    : NSLocalizedString("Not installed", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    if let url = URL(string: urlScheme) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(NSLocalizedString("Open", comment: ""))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(FrutigerAeroTheme.shared.neonBlue)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Engine State

    private var engineStateLabel: String {
        switch chatState.engineState {
        case .idle:       return "Idle"
        case .loading:    return "Loading..."
        case .ready:      return "Ready"
        case .generating: return "Generating..."
        case .error:      return "Error"
        case .unloading:  return "Unloading"
        }
    }

    private var engineStateColor: Color {
        switch chatState.engineState {
        case .idle:       return .gray
        case .loading:    return .yellow
        case .ready:      return .green
        case .generating: return FrutigerAeroTheme.shared.neonBlue
        case .error:      return .red
        case .unloading:  return .gray
        }
    }
}
