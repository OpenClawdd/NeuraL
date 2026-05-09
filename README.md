# NeuraL

On-device LLM inference for iOS that treats reasoning as a first-class feature.

## DreamState

Most local LLM apps pipe tokens straight to the screen. Reasoning models that emit `&lt;think&gt;` traces get those traces either stripped silently or dumped inline as garbled markup.

NeuraL captures every `&lt;think&gt;` block, parses it out of the visible response, and distills it into a persistent **Dream Card** — a structured reflection record with a summary, confidence estimate, next-action suggestion, and the raw reasoning trace preserved for later inspection.

The pipeline is four pieces:

- **ThinkTagParser** — parses `&lt;think&gt;...&lt;/think&gt;` blocks from the token stream in real time. Handles partial (unclosed) blocks during streaming so the UI never flashes raw markup. Traces are truncated at 12KB to bound memory, with a token estimate stored for the UI.
- **DreamSynthesizer** — extracts a title, summary, next action, tags, and confidence score from every assistant response. Runs locally with no cloud dependency.
- **DreamStore** — persists Dream Cards to `Application Support/DreamState/dreamcards.json` with configurable retention (50 / 100 / unlimited). Oldest cards evict first.
- **DreamboardView** — renders Dream Cards inline in the chat interface. Each card exposes "Use as prompt" and "Pin memory" actions.

DreamState settings are user-configurable: reasoning trace visibility (always / collapsed / never), raw trace access, auto-creation toggle, and retention cap.

## Competitive landscape

- **Off Grid** (Mohammed Ali Chherawalla) — runs local models on iOS but strips reasoning tokens during generation. No trace preservation, no reflection layer.
- **Locally** — similar local-inference approach. Discards `&lt;think&gt;` output without processing or storing it.

Both treat reasoning traces as noise. NeuraL treats them as signal. If you're running a reasoning-capable model locally, losing the trace means losing visibility into the model's chain of thought — which is often more instructive than the final answer.

## Model compatibility

NeuraL does not ship a model or download one for you. It loads any text-generation GGUF file that emits `&lt;think&gt;` tags. Compatible families include:

| Family | Trace quality | Notes |
|--------|--------------|-------|
| DeepSeek-R1-distilled Qwen (1.5B–7B) | High | Cleanest traces; the default recommendation |
| QwQ (Qwen-with-Questions) | High | Verbose but well-structured reasoning |
| DeepSeek-R1-distilled Llama (8B) | High | Needs larger device; 8B Q4 fits 8GB devices |
| Phi-4-reasoning | Medium | Traces exist but can be terse or formulaic |
| Gemma 3 thinking variants | Medium | Uses `&lt;think&gt;` but trace format less consistent |
| DeepSeek-V2-lite / V3-lite | High | Good traces, heavier models |

Any fine-tune that preserves the `&lt;think&gt;` / `&lt;/think&gt;` output convention works. See [SUPPORTED_MODELS.md](SUPPORTED_MODELS.md) for detailed per-model recommendations including quantization levels for Apple A18 (8GB LPDDR5X).

## Architecture

```
NeuraL/
  Core/           InferenceEngine protocol, LlamaCppBridge (C interop actor),
                  TokenStreamer (UTF-8 safe accumulation), ThinkTagParser,
                  ModelLoader, MemoryManager, FrutigerAeroTheme
  State/          ChatState (@MainActor ObservableObject), SmartContextEvictor,
                  BackgroundSynthesisScheduler
  DreamState/     DreamCard, DreamStore, DreamSynthesizer
  Intelligence/   ToolRegistry (function calling), RAGPipeline, VectorStore,
                  DocumentImporter, BuiltInTools
  Models/         ChatMessage, ChatTemplateEngine (Llama-3 / Gemma / ChatML),
                  ModelCatalog
  Views/          ChatView, ConversationsView, DreamboardView, NeuralLabView,
                  MarkdownRenderer (two-phase: streaming + rich final),
                  ModelsView, DocumentsView, SystemStatusView, ThinkingBubbleView
  Personalization/ ConversationBranching, ConversationExporter, PromptLibrary,
                   ThemeManager
  Multimodal/     ImagePickerView, VisionEncoder (CLIP/LLaVA)
  Speech/         SpeechManager (recognition + TTS)
Bridging/         BridgingHeader.h, llama_c_interop.h (llama.cpp C API → Swift)
Entitlements/     extended-virtual-addressing entitlement
```

Key technical details:

- **Context eviction** — `SmartContextEvictor` preserves the system prompt intact when the context window fills. Evicts complete user/assistant turn pairs from oldest first, then re-processes the prompt to rebuild the KV cache rather than shifting positions (avoids RoPE positional encoding drift).
- **Chat templates** — `ChatTemplateEngine` supports Llama-3, Gemma, ChatML, and raw passthrough. Auto-detects format from model architecture name.
- **Tool use** — `ToolRegistry` implements the ReAct pattern. Tools expose JSON Schema parameters and the model invokes them via `&lt;function&gt;...&lt;/function&gt;` blocks parsed from the token stream.
- **RAG** — On-device vector store with document import (PDF/TXT), embedding, and similarity search. Results are injected into the system prompt with source citations.
- **Multimodal** — CLIP/LLaVA vision encoder integration via the bridging header. Supports image input for vision-language models with `.mmproj` projector files.

## Build and install

Prerequisites: macOS with Xcode 15.4+, Apple Developer account (paid, for the extended-virtual-addressing entitlement), iOS 17.0+ device. The simulator does not support Metal GPU offloading.

```bash
git clone https://github.com/OpenClawdd/NeuraL.git
cd NeuraL
git submodule update --init --recursive
xcodegen generate
open NeuraL.xcodeproj
```

Select your device, set your development team in Signing & Capabilities, and run.

**Without local Xcode:** use the [GitHub Actions + KSign workflow](NO_XCODE_KSIGN_GUIDE.md).

Full build instructions including llama.cpp CMake configuration, Metal shader setup, and troubleshooting: [BUILD_GUIDE.md](BUILD_GUIDE.md).

## Loading a model

1. Obtain a GGUF from a compatible model family (see [SUPPORTED_MODELS.md](SUPPORTED_MODELS.md)).
2. Transfer the `.gguf` file to your iPhone via AirDrop, iCloud Drive, or Finder. Place it in **Files > On My iPhone**.
3. Open NeuraL, tap the **Models** tab, and tap **Load GGUF Model**.
4. Select the file from the Files picker. Wait for the Model Status card to show architecture, quantization, and context length.
5. Switch to the **Chat** tab and send a message.

Detailed GGUF loading guide: [PHONE_GGUF_GUIDE.md](PHONE_GGUF_GUIDE.md).
