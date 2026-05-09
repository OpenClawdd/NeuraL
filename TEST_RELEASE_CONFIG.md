# NeuraL — Test & Release Configuration

## Phase 5.4 — Address Sanitizer & Memory Checks

### Enabling Sanitizers in Xcode

1. **Open the scheme editor**: Product → Scheme → Edit Scheme…
2. **Select "Run" → "Diagnostics"**
3. **Enable the following:**
   - ✅ Address Sanitizer (detects buffer overflows, use-after-free, stack corruption)
   - ✅ Zombie Objects (detects messages sent to deallocated objects)
   - ✅ Thread Sanitizer (detects data races — important for our actor-based architecture)
   - ✅ Undefined Behavior Sanitizer (detects integer overflow, null dereference)

### Manual Memory Stress Test Procedure

Run the following stress test on a physical device (iPhone 15 Pro recommended):

```
1. Build with Release configuration + Address Sanitizer
2. Launch the app
3. Load the Llama-3.2-1B Q4_K_M model (~762MB)
4. Perform the following 20 times:
   a. Send a message ("Tell me about quantum physics")
   b. Wait for generation to complete
   c. Unload the model (tap Unload)
   d. Immediately reload the model
   e. Verify the engine state returns to .ready
5. Check Xcode console for:
   - No "Address Sanitizer" warnings
   - No "Zombie" messages
   - No jetsam termination in device logs
6. Check Memory Graph:
   - Product → Debug → View Memory Graph
   - Verify no retain cycles between ChatState and InferenceOrchestrator
   - Verify LlamaModel/LlamaContext/LlamaSamplerChain are freed after unload
```

### Expected Behavior During Stress Test

| Metric | Expected Value |
|--------|---------------|
| Memory after load | ~1.2-1.5 GB (model + KV cache + overhead) |
| Memory after unload | ~50-100 MB (base app + Swift runtime) |
| Memory after 20 cycles | Same as first load (no leak) |
| Generation rate | 40-45 tok/s on iPhone 15 Pro |
| Thermal state after 5 min | .fair to .serious (expected) |
| No crashes | Zero crashes in 20 cycles |

### Key Leak Points to Verify

1. **LlamaCppBridge deinit**: All `llama_model_free()`, `llama_free()`, `llama_sampler_free()` must be called
2. **TokenStreamController**: continuation must be `.finish()`ed and set to nil
3. **ChatState**: generationTask must be `.cancel()`ed before deinit
4. **MemoryManager**: DispatchSourceMemoryPressure must be `.cancel()`ed

---

## Phase 5.5 — App Store & TestFlight Prep

### App Privacy Details

NeuraL collects **NO user data**. All processing happens on-device.

| Data Type | Collected | Purpose |
|-----------|-----------|---------|
| Conversations | No | Stored locally only |
| Model files | No | Downloaded from public HuggingFace repos |
| Usage analytics | No | None whatsoever |
| Device info | No | Not transmitted |
| Location | No | Not used |
| Contacts | No | Not used |
| Photos | No | Not used (future vision support will be opt-in) |

### TestFlight Description

```
NeuraL — Private, On-Device AI

Run powerful language models directly on your iPhone or iPad — 
no internet required, no data leaves your device.

FEATURES:
• Run Llama 3.2, Gemma 2, Phi-3, and Qwen 2.5 models locally
• Stream responses in real-time with thinking animations
• Smart context management — conversations continue even when 
  the context window fills up
• Resumable model downloads — pause and continue later
• Import your own GGUF model files
• Full markdown rendering in responses
• Dark mode support
• VoiceOver accessible

REQUIREMENTS:
• iPhone with 6GB+ RAM (iPhone 13 Pro or later recommended)
• iPhone 15 Pro for best performance (~42 tok/s with Llama 3.2 1B)
• iPad Pro with M1 or later
• iOS 17.0 or later

MODELS:
• Llama 3.2 1B Instruct — Fast & lightweight (~762 MB)
• Llama 3.2 3B Instruct — Best quality that fits on iPhone (~2 GB)
• Gemma 2 2B IT — Google's efficient model (~1.4 GB)
• Phi-3 Mini 4K — Microsoft's reasoning model (~2.3 GB)
• Qwen 2.5 1.5B — Multilingual champion (~990 MB)
• Qwen 2.5 3B — Larger multilingual model (~1.9 GB)

All models run 100% on-device using Apple Silicon GPU acceleration.
No server, no API key, no subscription.
```

### Screenshots Needed

| Screen | Content | Device |
|--------|---------|--------|
| Chat empty state | "NeuraL" title, "Go to Models" CTA | iPhone 15 Pro |
| Chat with messages | User + assistant bubbles, markdown | iPhone 15 Pro |
| Thinking animation | Neural dots, "Thinking…" label | iPhone 15 Pro |
| Models tab | Catalog cards, active model badge | iPhone 15 Pro |
| Download progress | Circular progress on model card | iPhone 15 Pro |
| Conversations sidebar | Conversation list, bookmarks | iPhone 15 Pro |

### Extended Virtual Addressing Entitlement Request

When requesting the `com.apple.developer.kernel.extended-virtual-addressing` entitlement from Apple, use the following explanation:

```
App: NeuraL
Entitlement: com.apple.developer.kernel.extended-virtual-addressing

Explanation:
NeuraL runs large language models (1-3 billion parameters) entirely 
on-device using the llama.cpp inference engine. These models require 
significant memory mapping to load efficiently:

- Model weights: 0.8-2.5 GB (memory-mapped from disk)
- KV cache: 0.5-2.0 GB (GPU and CPU memory for context)
- Total process memory: 2-5 GB

Without extended virtual addressing, iOS limits the process address space 
to approximately 3 GB on devices with 8+ GB of physical RAM. This makes 
it impossible to load and run 3B-parameter models that our users expect, 
even though the physical RAM is available.

The extended virtual Addressing entitlement lifts this limit to match the 
device's actual physical RAM, allowing NeuraL to:
1. Load 3B-parameter quantized models (Llama 3.2 3B, Phi-3 Mini)
2. Maintain conversation context with larger KV caches (2048+ tokens)
3. Use Metal GPU acceleration for both prompt processing and generation

No data is transmitted off-device. All inference happens locally using 
Apple Silicon's Neural Engine and GPU.

This entitlement is essential for the app's core functionality. Without it, 
NeuraL can only support 1B-parameter models, severely limiting the 
quality of on-device AI responses.
```

### Archive & Upload Checklist

- [ ] Bump version to 1.0.0 (or 0.1.0 for TestFlight beta)
- [ ] Set build number to current timestamp or incrementing integer
- [ ] Verify entitlements are included in the build
- [ ] Archive: Product → Archive
- [ ] Upload to App Store Connect via Organizer
- [ ] Wait for processing (typically 5-15 minutes)
- [ ] Add TestFlight description
- [ ] Add screenshots
- [ ] Enable automatic updates for TestFlight testers
- [ ] Distribute to internal testers first
- [ ] After internal validation, distribute to external testers
