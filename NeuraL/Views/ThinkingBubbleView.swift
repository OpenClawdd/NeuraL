//
//  ThinkingBubbleView.swift
//  NeuraL
//
//  Phase 3+ — The Satisfying Thinking Animation
//  Frutiger Aero Edition — Glassy, Glossy, Vibrant, Translucent
//
//  This is the visual bridge between "user sends message" and "first token appears."
//  During prompt processing (0.3–2.0s), there's a gap where the model is:
//    1. Tokenizing the prompt
//    2. Processing prompt tokens through the transformer (llama_decode batches)
//    3. Preparing the first autoregressive token
//
//  Instead of showing nothing (boring) or a spinner (generic), we show:
//    - A pulsing "neural activity" animation with spring-bouncing dots
//    - A shimmer effect on the border that rotates like a loading ring
//    - Phase-aware labels ("Tokenizing...", "Processing...", "Thinking...")
//    - An optional reasoning text stream for <think/> block models
//    - A satisfying collapse transition when the first real token arrives
//    - A shimmer sweep across the reasoning text as it streams in
//    - Floating particles (GPU-safe: disabled during inference)
//    - Frosted glass backgrounds with gloss highlights
//
//  The animation is designed to feel alive and intentional, not like a loading
//  spinner. The dots bounce with spring physics, the colors shift through the
//  Frutiger Aero palette, the border shimmers, and the label changes to reflect
//  what the engine is actually doing.
//
//  For models that output reasoning tokens (e.g., DeepSeek-R1 with <think/>
//  blocks), the thinking bubble expands to show the reasoning text as it
//  streams in, with a collapsible summary after generation completes.
//
//  GPU Optimization:
//    The floating particle system (Canvas + TimelineView) is automatically
//    disabled when `isGenerating == true` to free GPU resources for inference.
//    Spring-bounce dots remain lightweight and always animate.
//

import SwiftUI
import Observation

// MARK: - Thinking Phase

/// The current phase of the thinking/prompt-processing lifecycle.
/// Each phase maps to a different visual treatment and label.
enum ThinkingPhase: Sendable {
    /// The prompt is being tokenized (usually <50ms).
    case tokenizing
    /// Prompt tokens are being processed through the transformer (the slow part).
    case processing
    /// The model is "thinking" — prompt processing complete, first token imminent.
    case thinking
    /// The model is producing reasoning/thinking tokens (e.g., <think/> blocks).
    case reasoning

    var label: String {
        switch self {
        case .tokenizing:  return "Thinking…"
        case .processing:  return "Thinking…"
        case .thinking:    return "Thinking…"
        case .reasoning:   return "Reasoning…"
        }
    }

    /// A more descriptive sublabel for the current phase.
    var sublabel: String? {
        switch self {
        case .tokenizing:  return "Tokenizing prompt"
        case .processing:  return "Processing tokens"
        case .thinking:    return "Preparing response"
        case .reasoning:   return nil
        }
    }

    var systemImage: String {
        switch self {
        case .tokenizing:  return "text.format"
        case .processing:  return "gearshape.2"
        case .thinking:    return "brain"
        case .reasoning:   return "brain.head.profile"
        }
    }

    /// The primary accent color for this phase — Frutiger Aero palette.
    var accentColor: Color {
        let theme = FrutigerAeroTheme.shared
        switch self {
        case .tokenizing:  return theme.neonBlue
        case .processing:  return theme.softTeal
        case .thinking:    return theme.vibrantCyan
        case .reasoning:   return theme.goldAccent
        }
    }

    /// Gradient colors for the shimmer border — Frutiger Aero phase palette.
    var gradientColors: [Color] {
        let theme = FrutigerAeroTheme.shared
        switch self {
        case .tokenizing:
            return [
                theme.neonBlue.opacity(0.0),
                theme.neonBlue.opacity(0.3),
                theme.neonBlue.opacity(0.0),
                theme.vibrantCyan.opacity(0.2),
                theme.neonBlue.opacity(0.0)
            ]
        case .processing:
            return [
                theme.softTeal.opacity(0.0),
                theme.neonBlue.opacity(0.3),
                theme.softTeal.opacity(0.0),
                theme.vibrantCyan.opacity(0.2),
                theme.softTeal.opacity(0.0)
            ]
        case .thinking:
            return [
                theme.vibrantCyan.opacity(0.0),
                theme.neonBlue.opacity(0.3),
                theme.softTeal.opacity(0.0),
                theme.vibrantCyan.opacity(0.2),
                theme.vibrantCyan.opacity(0.0)
            ]
        case .reasoning:
            return [
                theme.goldAccent.opacity(0.0),
                theme.goldAccent.opacity(0.3),
                theme.goldAccent.opacity(0.0),
                theme.neonBlue.opacity(0.2),
                theme.goldAccent.opacity(0.0)
            ]
        }
    }
}

// MARK: - Thinking Bubble View

/// The main thinking animation view. Appears during the gap between
/// "user sends message" and "first token appears in streamingText."
///
/// Two modes:
/// 1. **Compact** (no reasoning text): Animated dots + phase label + elapsed time + shimmer border
/// 2. **Expanded** (with reasoning text): Same header + scrollable reasoning text with shimmer sweep
///
/// GPU Optimization:
/// When `isGenerating` is true, the floating particle system is disabled
/// to conserve GPU resources for inference.
struct ThinkingBubbleView: View {
    /// The current thinking phase.
    let phase: ThinkingPhase

    /// Elapsed seconds since thinking started.
    let elapsedSeconds: Double

    /// Optional reasoning text being streamed (for <think/> block models).
    /// When nil or empty, shows compact mode.
    let reasoningText: String?

    /// Whether the model is currently generating tokens.
    /// When true, the floating particle system is disabled to save GPU.
    var isGenerating: Bool = false

    /// Whether the reasoning section is expanded (for the collapsible UI).
    @State private var isReasoningExpanded: Bool = true

    /// Animation state for the neural dots.
    @State private var dotPhase: Double = 0

    /// Whether the thinking has just started (for entrance animation).
    @State private var hasAppeared: Bool = false

    /// Shimmer rotation angle for the border.
    @State private var shimmerAngle: Double = 0

    /// Shimmer sweep position for reasoning text.
    @State private var shimmerPosition: CGFloat = -200

    /// Pulse animation for the "glow" behind the header.
    @State private var glowPulse: Bool = false

    /// Phase label tracking for smooth text transitions
    @State private var displayedLabel: String = "Thinking…"

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                // -- Header: Phase indicator + elapsed time with glow
                thinkingHeader

                // -- Reasoning text (if present)
                if let reasoning = reasoningText, !reasoning.isEmpty {
                    reasoningSection(reasoning)
                }
            }

            Spacer(minLength: 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                hasAppeared = true
            }
            // Start the shimmer rotation
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                shimmerAngle = 360
            }
            // Start the glow pulse
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            // Start shimmer sweep for reasoning text
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                shimmerPosition = 400
            }
        }
        .onChange(of: phase) { _, newPhase in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                displayedLabel = newPhase.label
            }
        }
    }

    // MARK: - Header

    private var thinkingHeader: some View {
        HStack(spacing: 10) {
            // Animated neural dots with spring bounce
            NeuralDotsView(phase: phase, dotPhase: dotPhase)
                .frame(width: 32, height: 18)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        dotPhase = 1.0
                    }
                }

            // Phase label with icon — animates smoothly between states
            HStack(spacing: 5) {
                Image(systemName: phase.systemImage)
                    .font(.caption2)
                    .foregroundStyle(phase.accentColor.opacity(0.8))
                    .contentTransition(.symbolEffect(.replace))

                Text(displayedLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: displayedLabel)
            }

            // Sublabel for the current phase (shows detail)
            if let sublabel = phase.sublabel {
                Text(sublabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.quaternary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Elapsed time (shows after 0.5s to avoid flash)
            if elapsedSeconds > 0.5 {
                Text(String(format: "%.1fs", elapsedSeconds))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Frosted glass base — replaces Color(.systemGray6)
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)

                // Subtle blue glow — Frutiger Aero signature
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [
                                FrutigerAeroTheme.shared.neonBlue.opacity(glowPulse ? 0.08 : 0.02),
                                .clear
                            ],
                            center: .leading,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )

                // Phase-aware glow behind the header
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [
                                phase.accentColor.opacity(glowPulse ? 0.06 : 0.01),
                                .clear
                            ],
                            center: .leading,
                            startRadius: 0,
                            endRadius: 140
                        )
                    )

                // Gloss highlight overlay — Frutiger Aero signature
                RoundedRectangle(cornerRadius: 16)
                    .fill(FrutigerAeroTheme.shared.glossHighlight)
                    .opacity(0.35)

                // Shimmer border — rotates continuously
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        AngularGradient(
                            colors: phase.gradientColors, center: .center,
                            angle: .degrees(shimmerAngle)
                        ),
                        lineWidth: 1.5
                    )

                // Floating particles — GPU-safe: disabled during inference
                if !isGenerating {
                    FloatingParticlesView(accentColor: phase.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .allowsHitTesting(false)
                }
            }
        )
        .opacity(hasAppeared ? 1.0 : 0.0)
        .offset(y: hasAppeared ? 0 : 8)
        .shadow(
            color: FrutigerAeroTheme.shared.neonBlue.opacity(glowPulse ? 0.12 : 0.0),
            radius: 8,
            y: 2
        )
        .shadow(
            color: phase.accentColor.opacity(glowPulse ? 0.08 : 0.0),
            radius: 6,
            y: 1
        )
    }

    // MARK: - Reasoning Section

    /// Collapsible reasoning text area for <think/> block output.
    /// Features a shimmer sweep across the text as it streams in.
    /// Frosted glass background with gloss overlay — Frutiger Aero.
    private func reasoningSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Expand/collapse toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isReasoningExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isReasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(phase.accentColor.opacity(0.6))

                    Text("Reasoning")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(phase.accentColor.opacity(0.7))

                    if !isReasoningExpanded {
                        Text("\(text.prefix(60))...")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }

                    // Live indicator dot when still generating
                    if phase == .reasoning {
                        Circle()
                            .fill(phase.accentColor)
                            .frame(width: 5, height: 5)
                            .opacity(glowPulse ? 1.0 : 0.3)
                    }
                }
            }
            .buttonStyle(.plain)

            // Reasoning text content with shimmer — frosted glass + gloss
            if isReasoningExpanded {
                ZStack(alignment: .topLeading) {
                    ScrollView {
                        Text(text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .padding(10)

                    // Shimmer sweep overlay — a bright line that sweeps
                    // across the text while streaming, giving the feeling
                    // of "live thought processing"
                    if phase == .reasoning {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        phase.accentColor.opacity(0.06),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 80)
                            .offset(x: shimmerPosition)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    ZStack {
                        // Frosted glass background
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.ultraThinMaterial)

                        // Gloss overlay
                        RoundedRectangle(cornerRadius: 10)
                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                            .opacity(0.3)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(phase.accentColor.opacity(0.1), lineWidth: 0.5)
                )
            }
        }
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Neural Dots View

/// Three animated dots that bounce with spring physics, evoking "neural activity."
///
/// The dots use a staggered animation with interpolatingSpring bounce:
/// - Dot 1: bounces first (slightly ahead)
/// - Dot 2: bounces second
/// - Dot 3: bounces third (slightly behind)
///
/// The color shifts through the Frutiger Aero palette to add visual interest.
/// The overall effect is organic and alive — a spring-based bounce rather
/// than a simple pulse, giving the dots a satisfying physicality.
struct NeuralDotsView: View {
    let phase: ThinkingPhase
    let dotPhase: Double

    @State private var isAnimating = false

    /// Spring bounce offset per dot — driven by interpolatingSpring
    @State private var bounceOffsets: [CGFloat] = [0, 0, 0]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dotColor(index: index))
                    .frame(width: 7, height: 7)
                    .scaleEffect(scaleForDot(index: index))
                    .opacity(opacityForDot(index: index))
                    .offset(y: bounceOffsets[index])
                    .shadow(
                        color: dotColor(index: index).opacity(0.4),
                        radius: scaleForDot(index: index) > 0.9 ? 3 : 0
                    )
            }
        }
        .onAppear {
            isAnimating = true
            startSpringBounce()
        }
    }

    /// Staggered scale: each dot scales at a slightly different time.
    private func scaleForDot(index: Int) -> CGFloat {
        guard isAnimating else { return 0.7 }
        let base: CGFloat = 0.7
        let pulse: CGFloat = 0.5
        let stagger = Double(index) * 0.2
        let t = (dotPhase + stagger).truncatingRemainder(dividingBy: 1.0)
        let wave = sin(t * .pi * 2) * 0.5 + 0.5  // 0.0 → 1.0 → 0.0
        return base + pulse * CGFloat(wave)
    }

    /// Staggered opacity: dots brighten as they "bounce."
    private func opacityForDot(index: Int) -> Double {
        guard isAnimating else { return 0.4 }
        let stagger = Double(index) * 0.2
        let t = (dotPhase + stagger).truncatingRemainder(dividingBy: 1.0)
        let wave = sin(t * .pi * 2) * 0.5 + 0.5
        return 0.3 + 0.7 * wave
    }

    /// Phase-aware color: different phases tint the dots differently — Frutiger Aero palette.
    private func dotColor(index: Int) -> Color {
        let theme = FrutigerAeroTheme.shared
        switch phase {
        case .tokenizing:
            return [theme.neonBlue, theme.vibrantCyan, theme.neonBlue][index]
        case .processing:
            return [theme.softTeal, theme.neonBlue, theme.softTeal][index]
        case .thinking:
            return [theme.vibrantCyan, theme.neonBlue, theme.softTeal][index]
        case .reasoning:
            return [theme.goldAccent, theme.neonBlue, theme.goldAccent][index]
        }
    }

    /// Drive a repeating spring-based bounce on each dot, staggered.
    /// Uses `.interpolatingSpring` for a physical, bouncy feel.
    private func startSpringBounce() {
        // Staggered bounce loop: each dot bounces with a delay
        for index in 0..<3 {
            bounceDot(index: index)
        }
    }

    /// Animate a single dot with a spring bounce, then repeat.
    private func bounceDot(index: Int) {
        let delay = Double(index) * 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            repeatBounce(index: index)
        }
    }

    /// Repeating spring bounce cycle for one dot.
    private func repeatBounce(index: Int) {
        withAnimation(.interpolatingSpring(stiffness: 200, damping: 12)) {
            bounceOffsets[index] = -4
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.interpolatingSpring(stiffness: 120, damping: 10)) {
                bounceOffsets[index] = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2 + Double(index) * 0.15) {
            repeatBounce(index: index)
        }
    }
}

// MARK: - Floating Particles View

/// Tiny floating particles that rise slowly — Frutiger Aero ambient effect.
/// Uses Canvas + TimelineView for efficient rendering.
///
/// GPU Safety: This view is only rendered when `isGenerating` is false
/// in the parent ThinkingBubbleView. The parent controls visibility.
struct FloatingParticlesView: View {
    let accentColor: Color

    /// Pre-generated particle data so we don't recreate on each frame.
    private let particles: [Particle]

    init(accentColor: Color) {
        self.accentColor = accentColor
        // Generate a set of particles with deterministic positions
        var generated: [Particle] = []
        for i in 0..<8 {
            generated.append(Particle(
                id: i,
                x: CGFloat(i) / 8.0 + CGFloat.random(in: -0.05...0.05),
                baseY: CGFloat.random(in: 0.5...1.0),
                speed: CGFloat.random(in: 0.02...0.06),
                size: CGFloat.random(in: 1.5...3.0),
                opacity: Double.random(in: 0.15...0.4)
            ))
        }
        self.particles = generated
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let date = timeline.date.timeIntervalSinceReferenceDate

                for particle in particles {
                    // Particle rises slowly and wraps around
                    let yOffset = CGFloat(date) * particle.speed * 30
                    let wrappedY = particle.baseY * size.height - yOffset.truncatingRemainder(dividingBy: size.height)
                    let finalY = wrappedY < 0 ? wrappedY + size.height : wrappedY
                    let x = particle.x * size.width

                    // Subtle horizontal sway
                    let sway = sin(date * 0.5 + Double(particle.id) * 1.3) * 3.0

                    let point = CGPoint(x: x + sway, y: finalY)
                    let rect = CGRect(
                        x: point.x - particle.size / 2,
                        y: point.y - particle.size / 2,
                        width: particle.size,
                        height: particle.size
                    )

                    context.opacity = particle.opacity
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(accentColor)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// Data model for a single floating particle.
private struct Particle {
    let id: Int
    /// Horizontal position as a fraction of width (0–1).
    let x: CGFloat
    /// Starting vertical position as a fraction of height (0–1).
    let baseY: CGFloat
    /// Rise speed multiplier.
    let speed: CGFloat
    /// Particle diameter.
    let size: CGFloat
    /// Base opacity.
    let opacity: Double
}

// MARK: - Thinking Bubble (Finalized)

/// A collapsed, finalized thinking summary that appears on assistant messages
/// that contained reasoning. Shows the reasoning duration and a "Show reasoning"
/// button that expands to reveal the thinking text.
///
/// This is the Phase B version of ThinkingBubbleView — it appears AFTER
/// generation completes, attached to the assistant message bubble.
///
/// Frutiger Aero: frosted glass card style with gloss overlay.
struct ThinkingSummaryView: View {
    let reasoningText: String
    let durationSeconds: Double

    @State private var isExpanded = false

    /// Animation for the spring collapse effect
    @State private var isCollapsed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header — frosted glass card
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .contentTransition(.symbolEffect(.replace))

                    Image(systemName: "brain.head.profile")
                        .font(.caption2)
                        .foregroundStyle(FrutigerAeroTheme.shared.softTeal.opacity(0.7))

                    Text("Thought for \(String(format: "%.1f", durationSeconds))s")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !isExpanded {
                        Text("\(reasoningText.prefix(80))...")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        // Frosted glass card
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)

                        // Gloss overlay
                        RoundedRectangle(cornerRadius: 8)
                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                            .opacity(0.3)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(FrutigerAeroTheme.shared.neonBlue.opacity(0.12), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            // Expanded reasoning text with spring animation — frosted glass
            if isExpanded {
                ScrollView {
                    Text(reasoningText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(10)
                .background(
                    ZStack {
                        // Frosted glass background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)

                        // Gloss overlay
                        RoundedRectangle(cornerRadius: 8)
                            .fill(FrutigerAeroTheme.shared.subtleGloss)
                            .opacity(0.25)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(FrutigerAeroTheme.shared.neonBlue.opacity(0.1), lineWidth: 0.5)
                )
                .padding(.top, 4)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)).animation(.spring(response: 0.35, dampingFraction: 0.82)),
                        removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)).animation(.spring(response: 0.25, dampingFraction: 0.9))
                    )
                )
            }
        }
    }
}

// MARK: - Phase Tracker

/// Tracks the thinking phase over time, transitioning through phases
/// based on elapsed duration. This gives the user a sense of progress
/// even though we can't know the exact internal state of the engine.
///
/// Phase transitions:
///   0.0–0.3s:  "Tokenizing"  (prompt tokenization is fast)
///   0.3–1.5s:  "Processing"  (llama_decode batches being processed)
///   1.5s+:     "Thinking"    (first token is imminent)
///
/// If reasoningText is non-empty, transitions to "Reasoning" immediately.
@MainActor
@Observable
class ThinkingPhaseTracker {
    var phase: ThinkingPhase = .tokenizing
    var elapsedSeconds: Double = 0

    private var startTime: ContinuousClock.Instant?
    private var updateTask: Task<Void, Never>?

    func start() {
        startTime = ContinuousClock.now
        phase = .tokenizing
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                self.update()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
    }

    func setReasoning(_ hasReasoning: Bool) {
        if hasReasoning {
            phase = .reasoning
        }
    }

    private func update() {
        guard let startTime = startTime else { return }
        let elapsed = ContinuousClock.now - startTime
        let seconds = Double(elapsed.components.seconds) +
                      Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        elapsedSeconds = seconds

        // Phase transitions (only upgrade, never downgrade)
        if phase != .reasoning {
            if seconds < 0.3 {
                phase = .tokenizing
            } else if seconds < 1.5 {
                phase = .processing
            } else {
                phase = .thinking
            }
        }
    }
}

// MARK: - Preview

#Preview("Thinking Bubble - Compact") {
    VStack(spacing: 20) {
        ThinkingBubbleView(phase: .tokenizing, elapsedSeconds: 0.1, reasoningText: nil, isGenerating: false)
        ThinkingBubbleView(phase: .processing, elapsedSeconds: 0.8, reasoningText: nil, isGenerating: false)
        ThinkingBubbleView(phase: .thinking, elapsedSeconds: 2.1, reasoningText: nil, isGenerating: false)
        ThinkingBubbleView(phase: .reasoning, elapsedSeconds: 3.5, reasoningText: "Let me analyze this step by step.\n\nFirst, I need to consider the constraints of the problem. The user is asking about...", isGenerating: true)
    }
    .padding()
}

#Preview("Thinking Summary") {
    ThinkingSummaryView(
        reasoningText: "Let me think about this carefully.\n\nThe user is asking about the capital of France. This is a straightforward factual question. I should provide a clear, confident answer with some supporting context.",
        durationSeconds: 1.8
    )
    .padding()
}
