//
//  ThemeManager.swift
//  NeuraL
//
//  Phase 7.1 — Theme Management & Personalization
//
//  Provides a centralized theme system that controls:
//  - Color scheme: light, dark, or follow system
//  - Accent color: user-selectable from a curated palette
//  - Chat bubble style: rounded, minimal, classic
//  - Font scaling: accessibility-friendly text sizing
//  - Custom wallpaper/background for the chat view
//
//  Architecture:
//  - ThemeManager is @Observable + @MainActor for direct SwiftUI binding
//  - Theme preferences are persisted to UserDefaults
//  - The manager publishes the current theme, and views apply it
//    through the @Environment or direct observation
//

import SwiftUI
import Observation

// MARK: - Color Scheme Preference

/// The user's preferred color scheme.
enum ColorSchemePreference: String, CaseIterable, Codable, CustomStringConvertible {
    case system
    case light
    case dark

    var description: String {
        switch self {
        case .system: return NSLocalizedString("System", comment: "Color scheme: follow system")
        case .light:  return NSLocalizedString("Light", comment: "Color scheme: light mode")
        case .dark:   return NSLocalizedString("Dark", comment: "Color scheme: dark mode")
        }
    }

    /// Convert to SwiftUI ColorScheme?. Returns nil for .system (use default).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }
}

// MARK: - Accent Color

/// Predefined accent colors that users can choose from.
/// Each has a name, a primary color, and a lighter variant for backgrounds.
enum AccentColorOption: String, CaseIterable, Codable, Identifiable, CustomStringConvertible {
    case blue
    case purple
    case teal
    case green
    case orange
    case pink
    case red
    case indigo

    var id: String { rawValue }

    var description: String {
        switch self {
        case .blue:   return NSLocalizedString("Blue", comment: "Accent color blue")
        case .purple: return NSLocalizedString("Purple", comment: "Accent color purple")
        case .teal:   return NSLocalizedString("Teal", comment: "Accent color teal")
        case .green:  return NSLocalizedString("Green", comment: "Accent color green")
        case .orange: return NSLocalizedString("Orange", comment: "Accent color orange")
        case .pink:   return NSLocalizedString("Pink", comment: "Accent color pink")
        case .red:    return NSLocalizedString("Red", comment: "Accent color red")
        case .indigo: return NSLocalizedString("Indigo", comment: "Accent color indigo")
        }
    }

    /// The primary accent color.
    var color: Color {
        switch self {
        case .blue:   return .blue
        case .purple: return .purple
        case .teal:   return .teal
        case .green:  return .green
        case .orange: return .orange
        case .pink:   return .pink
        case .red:    return .red
        case .indigo: return .indigo
        }
    }

    /// A lighter version for backgrounds and subtle highlights.
    var lightColor: Color {
        color.opacity(0.15)
    }

    /// A gradient from the color to a lighter version.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.6)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Chat Bubble Style

/// The visual style for chat message bubbles.
enum ChatBubbleStyle: String, CaseIterable, Codable, CustomStringConvertible {
    case rounded
    case minimal
    case classic

    var description: String {
        switch self {
        case .rounded:  return NSLocalizedString("Rounded", comment: "Bubble style: rounded")
        case .minimal:  return NSLocalizedString("Minimal", comment: "Bubble style: minimal")
        case .classic:  return NSLocalizedString("Classic", comment: "Bubble style: classic")
        }
    }

    var systemImage: String {
        switch self {
        case .rounded:  return "bubble.left.and.bubble.right.fill"
        case .minimal:  return "line.3.horizontal"
        case .classic:  return "ellipsis.bubble.fill"
        }
    }

    /// Corner radius for this bubble style.
    var cornerRadius: CGFloat {
        switch self {
        case .rounded:  return 16
        case .minimal:  return 8
        case .classic:  return 12
        }
    }
}

// MARK: - Font Scaling

/// Font scaling option for accessibility.
enum FontScaling: String, CaseIterable, Codable, CustomStringConvertible {
    case small
    case normal
    case large
    case extraLarge

    var description: String {
        switch self {
        case .small:      return NSLocalizedString("Small", comment: "Font size: small")
        case .normal:     return NSLocalizedString("Normal", comment: "Font size: normal")
        case .large:      return NSLocalizedString("Large", comment: "Font size: large")
        case .extraLarge: return NSLocalizedString("Extra Large", comment: "Font size: extra large")
        }
    }

    /// Scale factor relative to default.
    var scaleFactor: CGFloat {
        switch self {
        case .small:      return 0.85
        case .normal:     return 1.0
        case .large:      return 1.2
        case .extraLarge: return 1.4
        }
    }
}

// MARK: - App Theme

/// The complete theme configuration for the app.
struct AppTheme: Codable, Equatable {
    var colorScheme: ColorSchemePreference
    var accentColor: AccentColorOption
    var bubbleStyle: ChatBubbleStyle
    var fontScaling: FontScaling
    var showTimestamps: Bool
    var showTokenCounts: Bool
    var compactMode: Bool

    static let `default` = AppTheme(
        colorScheme: .system,
        accentColor: .blue,
        bubbleStyle: .rounded,
        fontScaling: .normal,
        showTimestamps: true,
        showTokenCounts: true,
        compactMode: false
    )
}

// MARK: - Theme Manager

/// Centralized theme management. @Observable for direct SwiftUI binding.
/// Persists theme preferences to UserDefaults.
@Observable
@MainActor
final class ThemeManager {

    static let shared = ThemeManager()

    /// The current theme configuration.
    var theme: AppTheme {
        didSet {
            saveTheme()
        }
    }

    // MARK: - Convenience Accessors

    var colorSchemePreference: ColorSchemePreference {
        get { theme.colorScheme }
        set { theme.colorScheme = newValue }
    }

    var accentColor: AccentColorOption {
        get { theme.accentColor }
        set { theme.accentColor = newValue }
    }

    var bubbleStyle: ChatBubbleStyle {
        get { theme.bubbleStyle }
        set { theme.bubbleStyle = newValue }
    }

    var fontScaling: FontScaling {
        get { theme.fontScaling }
        set { theme.fontScaling = newValue }
    }

    /// The SwiftUI ColorScheme to apply (nil = follow system).
    var preferredColorScheme: ColorScheme? {
        theme.colorScheme.colorScheme
    }

    /// The primary accent color.
    var accentColorValue: Color {
        theme.accentColor.color
    }

    /// Font size multiplier.
    var fontScaleFactor: CGFloat {
        theme.fontScaling.scaleFactor
    }

    // MARK: - Initialization

    private init() {
        self.theme = Self.loadTheme()
    }

    // MARK: - Persistence

    private static let themeKey = "neural.theme"

    private func saveTheme() {
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: Self.themeKey)
        }
    }

    private static func loadTheme() -> AppTheme {
        guard let data = UserDefaults.standard.data(forKey: themeKey),
              let theme = try? JSONDecoder().decode(AppTheme.self, from: data) else {
            return .default
        }
        return theme
    }

    /// Reset theme to defaults.
    func resetToDefaults() {
        theme = .default
    }
}

// MARK: - Scaled Font Modifier

/// A SwiftUI modifier that applies font scaling from ThemeManager.
struct ScaledFont: ViewModifier {
    let size: CGFloat
    let design: Font.Design
    let weight: Font.Weight?

    @State private var scaleFactor: CGFloat = 1.0

    init(size: CGFloat, design: Font.Design = .default, weight: Font.Weight? = nil) {
        self.size = size
        self.design = design
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(font)
            .onAppear {
                scaleFactor = ThemeManager.shared.fontScaleFactor
            }
            .onChange(of: ThemeManager.shared.fontScaling) { _, _ in
                scaleFactor = ThemeManager.shared.fontScaleFactor
            }
    }

    private var font: Font {
        let scaledSize = size * scaleFactor
        var f = Font.system(size: scaledSize, design: design)
        if let weight = weight {
            f = f.weight(weight)
        }
        return f
    }
}

extension View {
    /// Apply a scaled font based on the user's font scaling preference.
    func scaledFont(size: CGFloat, design: Font.Design = .default, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFont(size: size, design: design, weight: weight))
    }

    /// Apply the accent color from ThemeManager.
    func themedAccentColor() -> some View {
        self.tint(ThemeManager.shared.accentColorValue)
    }
}
