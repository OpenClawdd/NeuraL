# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NeuraL is an iOS app (SwiftUI, iOS 17.0+) that runs local LLM inference on-device via llama.cpp with Metal GPU acceleration. It features a "Frutiger Aero" glassy/translucent visual design. The project uses XcodeGen (`project.yml`) to generate the Xcode project.

## Build System

- **Generate Xcode project:** `xcodegen generate` (requires `brew install xcodegen`)
- **Build for device:** `xcodebuild -project NeuraL.xcodeproj -scheme NeuraL -destination 'generic/platform=iOS' build`
- **Build unsigned archive:** `xcodebuild -project NeuraL.xcodeproj -scheme NeuraL -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -derivedDataPath ./DerivedData archive -archivePath ./NeuraL.xcarchive`
- **llama.cpp setup:** Must be cloned as a git submodule (`git submodule update --init --recursive`), then compiled as a static library for iOS arm64 with `-DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON` (see BUILD_GUIDE.md for full CMake instructions).
- **CI:** GitHub Actions workflow at `.github/workflows/build.yml` produces an unsigned IPA artifact.

## Architecture

### App entry and tab structure
`NeuraL/NeuraLApp.swift` — 5 tabs: Chat, Models, Knowledge (DocumentsView), Lab (NeuralLabView), System (SystemStatusView). State flows through `ChatState`, an `@MainActor ObservableObject` that holds conversation messages, orchestration, and DreamState.

### Core inference layer (`NeuraL/Core/`)
- **InferenceEngine.swift** — Protocol definitions (`InferenceEngine`, `InferenceEngineDiagnostics`), error types (`InferenceError`), and config structs (`MemoryBudget`, `ModelMetadata`, `ModelLoadConfiguration`, `GenerationParameters`). Two preset configs: `.default` (2048 ctx, GPU on) and `.conservative` (1024 ctx, CPU-only).
- **LlamaCppBridge.swift** — `actor` wrapping raw llama.cpp C API calls. Loads models via `llama_model_load_from_file`, manages context/sampler lifecycle, produces `AsyncThrowingStream<EmittedToken, Error>` for generation. Uses `llama_sampler_chain_*` APIs for temperature/top-p/top-k sampling.
- **InferenceOrchestrator.swift** — Main engine `actor` implementing `InferenceEngine`. Currently a stub that streams placeholder text; production builds connect it to `LlamaCppBridge`.
- **TokenStreamer.swift** — `UTF8TokenAccumulator` handles the fact that LLM tokens can split multi-byte UTF-8 sequences. Buffers partial bytes and only emits complete characters.
- **ThinkTagParser.swift** — Parses `<think>...</think>` reasoning trace tags from model output, separating trace from visible answer. Supports partial (unclosed) traces during streaming. Truncates traces at 12KB.
- **ModelLoader.swift** — Thin `actor` wrapper around `LlamaCppBridge` for model loading.

### State layer (`NeuraL/State/`)
- **ChatState.swift** — Central `@MainActor ObservableObject`. Owns the `InferenceOrchestrator`, `DreamSynthesizer`, and conversation messages. On message send, creates a user message, streams tokens from the orchestrator, parses them via `ThinkTagParser`, then auto-synthesizes a `DreamCard`.
- **SmartContextEvictor.swift** — Message-boundary-aware context eviction. Always preserves the system prompt intact. Evicts complete (user, assistant) turn pairs from oldest first. Re-processes the prompt to rebuild the KV cache rather than shifting positions (avoids RoPE positional encoding issues).

### Intelligence layer (`NeuraL/Intelligence/`)
- **ToolRegistry.swift** — Function-calling system using ReAct pattern. Tools conform to `NeuraLTool` (name, description, JSON parameter schema, `execute`). `ToolRegistry` is a shared `actor` that generates tool definition prompts and resolves tool names. `FunctionCallParser` extracts `<function>...</function>` JSON blocks from model output.
- **RAGPipeline.swift** — Retrieval-augmented generation pipeline: embed query → search `VectorStore` → construct augmented prompt → generate.
- **VectorStore.swift** — On-device vector storage for document embeddings.
- **DocumentImporter.swift** — PDF/TXT import for the RAG pipeline.
- **BuiltInTools.swift** — Calculator, Calendar, DeviceInfo tools.

### Models (`NeuraL/Models/`)
- **ChatMessage.swift** — `ChatMessage` (role, content, reasoningTrace, etc.) and `Conversation` (array of messages).
- **ChatTemplateEngine.swift** — Formats conversations into model-specific prompt strings. Supports Llama-3 (default, also used by Qwen2.5), Gemma/Phi, ChatML (Mistral), and raw passthrough. Auto-detects format from architecture name. Ends prompts with an assistant header so the model continues generating.
- **ModelCatalog.swift** — Curated model catalog.

### DreamState (`NeuraL/DreamState/`)
Local cognition layer that auto-synthesizes "DreamCards" from conversation turns — captures title, summary, next action, tags, and confidence from each assistant response. Controlled by user-configurable `DreamStateSettings` (trace visibility, retention, auto-create toggle).

### Views (`NeuraL/Views/`)
All views use Frutiger Aero styling (glass morphism, blue gradients, `.ultraThinMaterial` backgrounds from `FrutigerAeroTheme`). Key views: `ChatView`, `ConversationsView` (sidebar), `MarkdownRenderer` (two-phase: simplified streaming + rich final), `ThinkingBubbleView`, `NeuralLabView`, `DreamboardView`, `ModelsView`, `DocumentsView`, `SystemStatusView`.

### Bridging (`Bridging/`)
- **BridgingHeader.h** — Exposes llama.cpp C API (`llama.h`) and helper inline functions (`ondevice_kv_cache_bytes`, `ondevice_available_memory`) to Swift. Also declares CLIP/llava multimodal API wrappers.
- **llama_c_interop.h** — Additional Swift-friendly C wrappers.

### Entitlements
`com.apple.developer.kernel.extended-virtual-addressing` — required for loading 1.5B+ param quantized models on 8GB+ RAM devices. Requires paid Apple Developer certificate.

## Testing

Tests live in `NeuraLTests/` and use `@testable import NeuraL` with XCTest. Test files:
- `InferenceEngineTests.swift` — MemoryBudget, ChatTemplateEngine formatting, Conversation management, config defaults, EngineState
- `MemoryBudgetTests.swift` — Detailed memory budget boundary tests
- `ContextEvictionTests.swift` — SmartContextEvictor with simulated conversations
- `ThinkTagParserTests.swift` — `<think>` tag parsing edge cases
- `DreamStateTests.swift` — DreamState models
- `Phase6Tests.swift` — Tool registry, function call parsing, RAG
- `Phase7Tests.swift` — PromptLibrary, exports

Run tests via Xcode (Cmd+U) or: `xcodebuild test -project NeuraL.xcodeproj -scheme NeuraL -destination 'platform=iOS Simulator,name=iPhone 16'`

**Important:** Tests cannot run on the simulator if they need actual Metal GPU offloading — many core inference tests avoid loading real models and test logic/types only.

## Key design patterns

- **Actor-based concurrency** for all inference state (`LlamaCppBridge`, `InferenceOrchestrator`, `ModelLoader`, `ToolRegistry`, `ToolExecutor`)
- **`@MainActor ObservableObject`** for UI-facing state (`ChatState`)
- **Protocol abstraction** — `InferenceEngine` protocol allows swapping real and mock implementations
- **Streaming via `AsyncThrowingStream`** — tokens stream from bridge → state → SwiftUI views
- **Two-phase rendering** — markdown is rendered lightweight during streaming (hiding unclosed delimiters), then fully parsed with `AttributedString(markdown:)` when complete
- **Preset configs as static lets** — `ModelLoadConfiguration.default` / `.conservative`, `GenerationParameters.chat` / `.deterministic`
- **All types are `Sendable`** and most are `Equatable` to support safe actor boundaries
