//
//  AppIconView.swift
//  NeuraL
//
//  Frutiger Aero — Glossy Interlocking "NL" Logo
//
//  A SwiftUI view rendering the NeuraL app icon: two glossy
//  interlocking "N" and "L" letters on a frosted glass circle
//  with a neon-cyan-to-gold gradient. Designed for the welcome /
//  empty state screen and any other internal branding placement.
//
//  GPU-safe: the shimmer animation automatically pauses when
//  isGenerating is true (observed via FrutigerAeroTheme.isGPUBusy).
//

import SwiftUI

// MARK: - App Icon View

struct AppIconView: View {
    /// Size of the icon (default 120 pt).
    var size: CGFloat = 120

    /// When true the shimmer animation is suppressed to save GPU cycles.
    var isGenerating: Bool = false

    @Environment(FrutigerAeroTheme.self) private var theme

    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // ── Frosted glass circle backdrop ──────────────────────
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    theme.vibrantCyan.opacity(0.6),
                                    theme.goldAccent.opacity(0.4),
                                    theme.vibrantCyan.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: theme.neonBlue.opacity(0.35), radius: 12, x: 0, y: 4)
                .shadow(color: theme.goldAccent.opacity(0.15), radius: 20, x: 0, y: 8)

            // ── Interlocking N and L letters ───────────────────────
            // The "N" leans left in cyan, the "L" leans right in gold,
            // their vertical strokes overlapping to create a neural
            // synapse / circuit-board motif.
            ZStack {
                // N — cyan, slightly rotated left
                NLetterPath()
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.vibrantCyan,
                                theme.neonBlue,
                                theme.vibrantCyan.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.34, height: size * 0.48)
                    .rotationEffect(.degrees(-10))
                    .offset(x: -size * 0.1, y: 0)

                // L — gold, slightly rotated right
                LLetterPath()
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.goldAccent.opacity(0.9),
                                theme.goldAccent,
                                Color.white.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.34, height: size * 0.48)
                    .rotationEffect(.degrees(10))
                    .offset(x: size * 0.1, y: 0)
            }

            // ── Gloss highlight ────────────────────────────────────
            Circle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.45), location: 0.0),
                            .init(color: .white.opacity(0.08), location: 0.45),
                            .init(color: .clear, location: 0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: UnitPoint(x: 0.5, y: 0.6)
                    )
                )
                .frame(width: size, height: size)

            // ── Shimmer sweep (paused when generating) ─────────────
            if !isGenerating {
                Circle()
                    .fill(.clear)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .white.opacity(0.18), location: 0.5),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: size, height: size)
                            .rotationEffect(.degrees(Double(shimmerPhase)))
                    )
                    .clipped()
                    .onAppear {
                        withAnimation(
                            .linear(duration: 3.0).repeatForever(autoreverses: false)
                        ) {
                            shimmerPhase = 360
                        }
                    }
            }
        }
    }
}

// MARK: - N Letter Shape

/// A custom `Shape` that draws a bold, modern capital "N".
/// Two vertical strokes connected by a diagonal, with rounded joins
/// for a friendly Frutiger Aero feel.
struct NLetterPath: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let stroke = w * 0.24
        let r = stroke * 0.4

        var path = Path()

        // Left vertical (bottom to top)
        path.move(to: CGPoint(x: r, y: h))
        path.addLine(to: CGPoint(x: 0, y: h - r))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
        path.addLine(to: CGPoint(x: stroke - r, y: 0))
        path.addArc(tangent1End: CGPoint(x: stroke, y: 0), tangent2End: CGPoint(x: stroke, y: r), radius: r)

        // Diagonal (top-left down to bottom-right)
        path.addLine(to: CGPoint(x: stroke, y: h - r * 2.5))
        path.addLine(to: CGPoint(x: w - stroke - r * 0.5, y: r * 2.5))

        // Right vertical (top to bottom)
        path.addLine(to: CGPoint(x: w - stroke, y: r))
        path.addArc(tangent1End: CGPoint(x: w - stroke, y: 0), tangent2End: CGPoint(x: w - stroke + r, y: 0), radius: r)
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: r), radius: r)
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - r, y: h), radius: r)
        path.addLine(to: CGPoint(x: w - stroke + r, y: h))
        path.addArc(tangent1End: CGPoint(x: w - stroke, y: h), tangent2End: CGPoint(x: w - stroke, y: h - r), radius: r)

        // Diagonal back (bottom-right up to top-left)
        path.addLine(to: CGPoint(x: w - stroke, y: r * 2.5))
        path.addLine(to: CGPoint(x: stroke + r * 0.5, y: h - r * 2.5))

        // Close left vertical bottom
        path.addLine(to: CGPoint(x: stroke, y: h - r))
        path.addArc(tangent1End: CGPoint(x: stroke, y: h), tangent2End: CGPoint(x: r, y: h), radius: r)

        path.closeSubpath()
        return path
    }
}

// MARK: - L Letter Shape

/// A custom `Shape` that draws a bold, modern capital "L".
/// A vertical stroke on the left with a horizontal base,
/// rounded joins for the Frutiger Aero feel.
struct LLetterPath: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let stroke = w * 0.24
        let r = stroke * 0.4

        var path = Path()

        // Start at bottom-left, go up
        path.move(to: CGPoint(x: r, y: h))
        path.addLine(to: CGPoint(x: 0, y: h - r))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
        path.addLine(to: CGPoint(x: stroke - r, y: 0))
        path.addArc(tangent1End: CGPoint(x: stroke, y: 0), tangent2End: CGPoint(x: stroke, y: r), radius: r)

        // Down the vertical stroke
        path.addLine(to: CGPoint(x: stroke, y: h - stroke + r))

        // Horizontal base: right
        path.addArc(tangent1End: CGPoint(x: stroke, y: h - stroke), tangent2End: CGPoint(x: stroke + r, y: h - stroke), radius: r)
        path.addLine(to: CGPoint(x: w - r, y: h - stroke))
        path.addArc(tangent1End: CGPoint(x: w, y: h - stroke), tangent2End: CGPoint(x: w, y: h - stroke + r), radius: r)
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - r, y: h), radius: r)

        // Horizontal base: left (bottom edge)
        path.addLine(to: CGPoint(x: r, y: h))
        path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - r), radius: r)

        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        AppIconView(size: 120, isGenerating: false)
        AppIconView(size: 80, isGenerating: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
        LinearGradient(
            colors: [Color(hex: "#E0F7FA"), Color(hex: "#B2EBF2")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .environment(FrutigerAeroTheme.shared)
}
