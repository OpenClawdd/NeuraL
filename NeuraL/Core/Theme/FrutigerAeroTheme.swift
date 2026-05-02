//
//  FrutigerAeroTheme.swift
//  NeuraL
//
//  Frutiger Aero Theme — Glassy, Glossy, Vibrant, Translucent
//
//  This theme provides the visual foundation for the Frutiger Aero aesthetic:
//  - Soft blues, cyan, teal, white, translucent overlays
//  - Glassy frosted materials using system .ultraThinMaterial
//  - Gloss highlights via LinearGradient overlays
//  - Subtle gold accents
//  - GPU-safe: all decorative animations respect engineState to free
//    the GPU for AI inference
//
//  Design principles:
//  - System materials (.regularMaterial, .ultraThinMaterial) are highly
//    optimised by iOS and NOT GPU-heavy
//  - No large continuous animations; use static gradients + subtle glow
//  - Skeuomorphic elements (glossy buttons, reflections) via simple
//    LinearGradient overlays and shadow
//  - All blurs pause during inference (observe engineState)
//

import SwiftUI
import Observation

// MARK: - Frutiger Aero Theme

/// The Frutiger Aero visual theme. Provides colors, gradients, and
/// GPU-aware animation helpers for the entire app.
///
/// Injected as an @Observable into the SwiftUI environment so any view
/// can read theme values and the GPU budget state.
@Observable
@MainActor
final class FrutigerAeroTheme {

    // MARK: - Singleton

    static let shared = FrutigerAeroTheme()

    // MARK: - GPU Budget

    /// Whether the GPU should be considered "busy" with inference.
    /// When true, decorative animations are paused to free GPU resources.
    var isGPUBusy: Bool = false

    // MARK: - Color Palette

    /// Primary neon blue accent.
    let neonBlue = Color(red: 0/255, green: 180/255, blue: 216/255)

    /// Vibrant cyan for highlights.
    let vibrantCyan = Color(red: 0/255, green: 229/255, blue: 255/255)

    /// Soft teal for secondary accents.
    let softTeal = Color(red: 0/255, green: 188/255, blue: 212/255)

    /// Gold accent for premium/special elements.
    let goldAccent = Color(red: 255/255, green: 215/255, blue: 0/255)

    /// Light background blue.
    let lightBlue = Color(red: 224/255, green: 247/255, blue: 250/255)

    /// Medium background blue.
    let mediumBlue = Color(red: 178/255, green: 235/255, blue: 242/255)

    /// Deep ocean blue for contrast areas.
    let deepOcean = Color(red: 0/255, green: 105/255, blue: 148/255)

    // MARK: - Gradients

    /// The primary background gradient — soft blue to light cyan.
    let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 224/255, green: 247/255, blue: 250/255),
            Color(red: 178/255, green: 235/255, blue: 242/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// A darker variant of the background for dark mode.
    let backgroundGradientDark = LinearGradient(
        colors: [
            Color(red: 10/255, green: 25/255, blue: 49/255),
            Color(red: 20/255, green: 40/255, blue: 70/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Gloss highlight overlay — white-to-transparent, top to center.
    let glossHighlight = LinearGradient(
        colors: [.white.opacity(0.6), .white.opacity(0.0)],
        startPoint: .top,
        endPoint: .center
    )

    /// Subtle gloss for smaller elements (buttons, chips).
    let subtleGloss = LinearGradient(
        colors: [.white.opacity(0.35), .white.opacity(0.0)],
        startPoint: .top,
        endPoint: .center
    )

    /// Button gradient fill — neon blue to teal.
    let buttonGradient = LinearGradient(
        colors: [
            Color(red: 0/255, green: 180/255, blue: 216/255),
            Color(red: 0/255, green: 188/255, blue: 212/255)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Shimmer gradient for loading states.
    let shimmerGradient = LinearGradient(
        colors: [
            .white.opacity(0.0),
            .white.opacity(0.3),
            .white.opacity(0.0)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    // MARK: - Materials

    /// Glassy background for cards and bubbles.
    var glassBackground: Color { .white.opacity(0.25) }

    /// Button shadow color.
    let buttonShadow = Color.black.opacity(0.15)

    // MARK: - Haptics

    /// Trigger a light impact haptic (button taps, selections).
    func lightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Trigger a selection haptic (toggle changes, picker selections).
    func selectionHaptic() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: - Initialization

    private init() {}
}

// MARK: - Environment Key

/// Environment key for injecting FrutigerAeroTheme into the SwiftUI environment.
struct FrutigerAeroThemeKey: EnvironmentKey {
    static let defaultValue = FrutigerAeroTheme.shared
}

extension EnvironmentValues {
    /// Access the Frutiger Aero theme from any view.
    var aeroTheme: FrutigerAeroTheme {
        get { self[FrutigerAeroThemeKey.self] }
        set { self[FrutigerAeroThemeKey.self] = newValue }
    }
}

// MARK: - View Modifiers

extension View {

    /// Apply the Frutiger Aero glass card style: frosted material + gloss + shadow.
    func aeroGlassCard(
        cornerRadius: CGFloat = 16,
        glowOnHover: Bool = false
    ) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(FrutigerAeroTheme.shared.glossHighlight)
                    .opacity(0.4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(
                color: FrutigerAeroTheme.shared.buttonShadow,
                radius: 8, x: 0, y: 4
            )
    }

    /// Apply the glossy button style: gradient fill + inner gloss + scale on press.
    func aeroGlossyButton(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(FrutigerAeroTheme.shared.buttonGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(FrutigerAeroTheme.shared.subtleGloss)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(
                color: FrutigerAeroTheme.shared.neonBlue.opacity(0.3),
                radius: 6, x: 0, y: 3
            )
    }

    /// Apply Frutiger Aero background gradient.
    func aeroBackground() -> some View {
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

    /// Conditionally hide decorative content during GPU inference.
    /// Use this to wrap any purely decorative animations.
    @ViewBuilder
    func aeroGPUSafe<Content: View>(
        isGenerating: Bool,
        @ViewBuilder fallback: () -> Content = { EmptyView() }
    ) -> some View {
        if isGenerating {
            fallback()
        } else {
            self
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    /// Create a Color from a hex string (e.g., "#00B4D8" or "00B4D8").
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Frutiger Aero Toggle Style

/// A custom toggle style with glossy track and cyan thumb.
struct AeroToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label

            Spacer()

            ZStack {
                // Track
                RoundedRectangle(cornerRadius: 14)
                    .fill(configuration.isOn
                        ? FrutigerAeroTheme.shared.neonBlue.opacity(0.3)
                        : Color(.systemGray5))
                    .frame(width: 48, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                configuration.isOn
                                    ? FrutigerAeroTheme.shared.neonBlue.opacity(0.5)
                                    : Color(.systemGray4),
                                lineWidth: 1
                            )
                    )

                // Thumb
                Circle()
                    .fill(configuration.isOn
                        ? FrutigerAeroTheme.shared.vibrantCyan
                        : Color(.systemGray2))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                    )
                    .offset(x: configuration.isOn ? 10 : -10)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
            }
            .onTapGesture {
                configuration.isOn.toggle()
                FrutigerAeroTheme.shared.selectionHaptic()
            }
        }
    }
}

// MARK: - Frutiger Aero Progress Style

/// A glossy progress bar style for downloads.
struct AeroProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? 0

        return ZStack(alignment: .leading) {
            // Track
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(height: 6)

            // Filled portion with shimmer
            RoundedRectangle(cornerRadius: 4)
                .fill(FrutigerAeroTheme.shared.buttonGradient)
                .frame(width: max(0, CGFloat(fractionCompleted) * 200), height: 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(FrutigerAeroTheme.shared.shimmerGradient)
                        .offset(x: CGFloat(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 2)) * 100)
                )
        }
    }
}
