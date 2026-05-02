# NeuraL — Build Guide

## Prerequisites

- **Xcode 15.4+** (required for Swift 5.10 concurrency features)
- **Apple Developer Account** (paid, for the extended-virtual-addressing entitlement)
- **iOS 17.0+** target device (iPhone 15 Pro recommended; iPad Pro M1+ also works)
- **Physical device** — Metal GPU offloading does not work on the simulator

## Project Setup

### 1. Create the Xcode Project

```
1. Open Xcode → File → New → Project
2. Select iOS → App
3. Product Name: NeuraL
4. Interface: SwiftUI
5. Language: Swift
6. Minimum Deployments: iOS 17.0
7. Save to a directory of your choice
```

### 2. Add Source Files

Copy the following files from this archive into your Xcode project:

```
NeuraL/
├── NeuraLApp.swift              → Replace the auto-generated one
├── Core/
│   ├── InferenceEngine.swift        → Add to project
│   ├── MemoryManager.swift          → Add to project
│   ├── LlamaCppBridge.swift         → Add to project
│   ├── TokenStreamer.swift          → Add to project
│   ├── ModelLoader.swift            → Add to project
│   ├── InferenceOrchestrator.swift  → Add to project
│   ├── Theme/
│   │   └── FrutigerAeroTheme.swift  → Add to project (Frutiger Aero theme)
│   └── System/
│       └── SystemInfo.swift          → Add to project (device capabilities)
├── Intelligence/
│   ├── BuiltInTools.swift           → Add to project
│   ├── DocumentImporter.swift       → Add to project
│   ├── RAGPipeline.swift            → Add to project
│   ├── ToolRegistry.swift           → Add to project
│   └── VectorStore.swift            → Add to project
├── Models/
│   ├── ChatMessage.swift            → Add to project
│   ├── ChatTemplateEngine.swift     → Add to project
│   └── ModelCatalog.swift           → Add to project
├── Multimodal/
│   ├── ImagePickerView.swift        → Add to project
│   └── VisionEncoder.swift          → Add to project
├── Personalization/
│   ├── ConversationBranching.swift  → Add to project
│   ├── ConversationExporter.swift   → Add to project
│   ├── PromptLibrary.swift          → Add to project
│   └── ThemeManager.swift           → Add to project
├── Speech/
│   └── SpeechManager.swift          → Add to project
├── State/
│   ├── ChatState.swift              → Add to project
│   └── SmartContextEvictor.swift    → Add to project
├── Views/
│   ├── AppIconView.swift            → Add to project (glossy N+L logo)
│   ├── ChatView.swift               → Add to project
│   ├── ConversationsView.swift      → Add to project
│   ├── DocumentsView.swift          → Add to project
│   ├── MarkdownRenderer.swift       → Add to project
│   ├── ModelsView.swift             → Add to project
│   ├── SystemStatusView.swift       → Add to project
│   └── ThinkingBubbleView.swift    → Add to project
├── Assets.xcassets/
│   └── AppIcon.appiconset/          → Add to project (icon catalog)
Bridging/
│   ├── BridgingHeader.h             → Add to project
│   ├── llama_c_interop.h            → Add to project
│   └── llama.modulemap              → Add to project (reference only)
Entitlements/
│   └── NeuraL.entitlements       → Add to project
```

### 3. Build llama.cpp for iOS arm64

This is the most critical step. llama.cpp must be compiled as a static library
for the iOS device architecture.

#### Option A: CMake (Recommended)

```bash
# Clone llama.cpp
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp
git checkout b4155  # Use a stable release tag; adjust as needed

# Create a build directory for iOS
mkdir build-ios && cd build-ios

# Configure with CMake for iOS
cmake .. \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DBUILD_SHARED_LIBS=OFF

# Build
cmake --build . --config Release -j$(sysctl -n hw.ncpu)

# The output will be in:
#   build-ios/src/libllama.a
#   build-ios/ggml/src/libggml.a
#   build-ios/ggml/src/libggml-metal.a (if Metal is enabled)
```

#### Option B: Direct Xcode Integration

Alternatively, add the llama.cpp source files directly to your Xcode project:

```
1. In Xcode, right-click the project → Add Files to "NeuraL"
2. Navigate to the llama.cpp source directory
3. Add these directories (with "Create groups" selected):
   - src/ (all .c and .cpp files)
   - ggml/src/ (all .c and .cpp files)
   - ggml/src/ggml-metal/ (ggml-metal.m and ggml-metal.metal)
4. Add header search paths:
   - llama.cpp/include
   - llama.cpp/ggml/include
   - llama.cpp/src
   - llama.cpp/ggml/src
5. Add compiler flags:
   - C++ files: -std=c++17
   - Add to "Other C Flags": -DGGML_USE_METAL
```

**⚠️ Important**: If you use the Xcode integration method, you must also add
the `ggml-metal.metal` file to the "Copy Files" build phase with
"Destination: Resources" so the Metal shaders are included in the app bundle.

### 4. Configure Xcode Build Settings

In your Xcode project's Build Settings:

| Setting | Value |
|---------|-------|
| Objective-C Bridging Header | `$(SRCROOT)/Bridging/BridgingHeader.h` |
| Header Search Paths | `$(SRCROOT)/Bridging` + llama.cpp include paths |
| Library Search Paths | Path to `libllama.a` and `libggml.a` |
| Other Linker Flags | `-lllama -lggml -lggml-metal -framework Metal -framework Foundation -lc++` |
| Swift Compiler - Custom Flags | (none needed) |
| Enable Bitcode | No (llama.cpp doesn't support bitcode) |
| Other C Flags | `-DGGML_USE_METAL` |
| Other C++ Flags | `-DGGML_USE_METAL -std=c++17` |
| SWIFT_INCLUDE_PATHS | `$(SRCROOT)/Bridging` (if using modulemap approach) |

### 5. Configure Entitlements

```
1. Select the project target → Signing & Capabilities
2. Under "Code Signing Entitlements", set: NeuraL/Entitlements/NeuraL.entitlements
3. Ensure your paid Apple Developer team is selected
4. The com.apple.developer.kernel.extended-virtual-addressing entitlement
   requires a paid certificate — it will NOT work with free provisioning
```

### 6. Add the GGUF Model File

For testing, you'll need a quantized GGUF model. Recommended models:

| Model | Quantization | File Size | RAM Needed | Source |
|-------|-------------|-----------|------------|--------|
| Phi-2 2.7B | Q4_K_M | ~1.7 GB | ~4 GB | HuggingFace |
| Llama-3.2-1B | Q4_K_M | ~0.8 GB | ~2 GB | HuggingFace |
| Llama-3.2-3B | Q4_K_M | ~2.0 GB | ~5 GB | HuggingFace |
| TinyLlama 1.1B | Q4_K_M | ~0.7 GB | ~2 GB | HuggingFace |
| Qwen2.5-1.5B | Q4_K_M | ~1.0 GB | ~3 GB | HuggingFace |

**To add the model to the app:**

1. **During development (Xcode):** Add the .gguf file to the project's
   "Copy Files" build phase with "Destination: Resources". Then access it via:
   ```swift
   let modelURL = Bundle.main.url(forResource: "model", withExtension: "gguf")!
   ```

2. **At runtime (production):** Copy the model to the app's Documents directory
   via AirDrop, Files app, or a download mechanism. Access via:
   ```swift
   let documentsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
   let modelPath = (documentsDir as NSString).appendingPathComponent("model.gguf")
   let modelURL = URL(fileURLWithPath: modelPath)
   ```

### 7. Build and Run

```
1. Connect your physical iOS device
2. Select the device as the run destination
3. Build and run (Cmd+R)
4. Observe the output in the Xcode console
```

## Troubleshooting

### "Undefined symbol" linker errors
- Ensure `libllama.a` and `libggml.a` are linked in the target's
  "Link Binary With Libraries" build phase
- Verify the architectures match (both should be arm64 for iOS device)
- Check that "Other Linker Flags" includes `-lllama -lggml`

### "Cannot find 'llama_xxx' in scope"
- Verify the bridging header path is correct in Build Settings
- Clean the build folder (Cmd+Shift+K) and rebuild
- Ensure `llama.h` is in the header search paths

### App crashes immediately on launch
- Check the entitlements file is correctly referenced
- Verify the provisioning profile includes the extended-virtual-addressing entitlement
- On devices with <6GB RAM, even a 1.5B Q4 model may be too large

### "Model loaded but metadata extraction returned nil"
- This can happen if llama.cpp's C API version doesn't match the headers
- Ensure the llama.cpp source version matches the headers in your project

### Thermal throttling
- If the device gets hot and generation slows dramatically, the MemoryManager
  will automatically reduce thread count and skip GPU offloading
- Consider using `ModelLoadConfiguration.conservative` for sustained use

### Memory warnings / jetsam kills
- The MemoryManager should prevent this, but if it happens:
  1. Use a smaller model (1.5B instead of 3B)
  2. Reduce context length (1024 instead of 2048)
  3. Disable GPU offloading (set gpuLayerCount to 0)
  4. Close other apps before running

## File Structure Summary

```
NeuraL/
├── NeuraL.xcodeproj
├── NeuraL/
│   ├── NeuraLApp.swift            # App entry + 5 tabs (Chat, Models, Docs, System, Settings)
│   ├── Core/
│   │   ├── InferenceEngine.swift     # Protocol, errors, config types
│   │   ├── MemoryManager.swift       # RAM probing, thermal, budgeting
│   │   ├── LlamaCppBridge.swift      # llama.cpp C interop (actor)
│   │   ├── TokenStreamer.swift       # UTF-8 safe token accumulation
│   │   ├── ModelLoader.swift         # GGUF validation, pre-flight checks
│   │   ├── InferenceOrchestrator.swift # Main engine (implements protocol)
│   │   ├── Theme/
│   │   │   └── FrutigerAeroTheme.swift # Frutiger Aero theme, colors, materials
│   │   └── System/
│   │       └── SystemInfo.swift       # Device capabilities, JIT, memory detection
│   ├── Intelligence/
│   │   ├── BuiltInTools.swift        # Calculator, Calendar, DeviceInfo tools
│   │   ├── DocumentImporter.swift     # PDF/TXT import for RAG
│   │   ├── RAGPipeline.swift          # Retrieval-augmented generation
│   │   ├── ToolRegistry.swift         # Tool registration & execution
│   │   └── VectorStore.swift          # On-device vector storage
│   ├── Models/
│   │   ├── ChatMessage.swift         # Conversation data models
│   │   ├── ChatTemplateEngine.swift  # Llama-3, Gemma, ChatML templates
│   │   └── ModelCatalog.swift        # Curated model catalog + downloads
│   ├── Multimodal/
│   │   ├── ImagePickerView.swift     # Camera & photo library picker
│   │   └── VisionEncoder.swift       # LLaVA vision projector
│   ├── Personalization/
│   │   ├── ConversationBranching.swift # Branch & edit messages
│   │   ├── ConversationExporter.swift  # Export (TXT/MD/PDF/JSON) + Settings
│   │   ├── PromptLibrary.swift         # System prompt templates
│   │   └── ThemeManager.swift          # Color scheme & accent colors
│   ├── Speech/
│   │   └── SpeechManager.swift         # Speech recognition & TTS
│   ├── State/
│   │   ├── ChatState.swift           # @Observable state bridge
│   │   └── SmartContextEvictor.swift  # Context eviction with system prompt
│   ├── Assets.xcassets/
│   │   └── AppIcon.appiconset/     # App icon catalog (add PNGs after rendering)
│   └── Views/
│       ├── AppIconView.swift          # Glossy interlocking N+L logo (Frutiger Aero)
│       ├── ChatView.swift            # Primary chat interface (Frutiger Aero)
│       ├── ConversationsView.swift   # Conversation sidebar (Frutiger Aero)
│       ├── DocumentsView.swift       # RAG document management
│       ├── MarkdownRenderer.swift    # Two-phase markdown rendering
│       ├── ModelsView.swift          # Models tab (Frutiger Aero)
│       ├── SystemStatusView.swift    # Device capabilities tab (Frutiger Aero)
│       └── ThinkingBubbleView.swift  # Neural dots animation (Frutiger Aero)
├── Bridging/
│   ├── BridgingHeader.h              # Exposes llama.cpp C API to Swift
│   ├── llama_c_interop.h             # Swift-friendly C wrappers
│   └── llama.modulemap               # Alternative: module-based import
├── Entitlements/
│   └── NeuraL.entitlements        # extended-virtual-addressing
├── NeuraLTests/                    # Unit tests
└── NeuraLUITests/                  # UI tests
```

## Next Steps (Phase 5)

Phase 5 continues with:
- Unit tests for MemoryBudget, UTF8TokenAccumulator, SmartContextEvictor
- UI tests for empty state, model loading, eviction banner
- Address Sanitizer verification
- App Store & TestFlight preparation
