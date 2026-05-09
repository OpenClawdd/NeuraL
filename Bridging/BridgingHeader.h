//
//  BridgingHeader.h
//  NeuraL
//
//  Phase 1 — C Bridging Header for llama.cpp
//
//  This header exposes the llama.cpp C API to Swift. All llama.cpp functions
//  are already declared with extern "C" linkage in llama.h, so Swift can
//  call them directly once this bridging header is registered in the Xcode
//  target's Build Settings > Objective-C Bridging Header.
//
//  IMPORTANT: llama.cpp must be compiled as a static library (libllama.a)
//  for the iOS arm64 target. See the CMake instructions in BUILD_GUIDE.md.
//

#ifndef BridgingHeader_h
#define BridgingHeader_h

// ─── llama.cpp Core API ────────────────────────────────────────────────
// We include the consolidated header which pulls in ggml.h internally.
// Ensure the llama.cpp source directory is in the header search paths.
#include "llama.h"

// ─── Supplementary Declarations ────────────────────────────────────────
// llama.cpp's C API is comprehensive, but we expose a few helper
// declarations that make Swift interop cleaner.

/// Returns the build timestamp of the linked llama.cpp library.
/// This is useful for version-gating features at runtime.
static inline const char * ondevice_llama_build_target(void) {
    return "iOS";
}

/// Convenience: compute the number of bytes required for a KV cache
/// given model parameters and context length. This is used by the
/// MemoryManager to validate that the device can hold the model before
/// attempting to load it.
///
/// Formula (approximation, conservative):
///   n_layers * 2 * n_embd * n_ctx * sizeof(float16)
/// The factor of 2 accounts for key + value tensors per layer.
/// We use float16 because llama.cpp stores KV cache in FP16 by default.
static inline size_t ondevice_kv_cache_bytes(int n_layers, int n_embd, int n_ctx) {
    return (size_t)n_layers * 2 * (size_t)n_embd * (size_t)n_ctx * sizeof(uint16_t);
}

/// Wrapper around os_proc_available_memory() for Swift access.
/// This is available on iOS 11+. Returns 0 on older versions.
/// We declare it here because the os/proc.h header isn't directly
/// accessible from Swift without this bridging.
#include <os/proc.h>

static inline size_t ondevice_available_memory(void) {
    return os_proc_available_memory();
}

// ─── Phase 6.1: CLIP/llava Multimodal API ─────────────────────────────
// These declarations enable vision-language model support by wrapping
// the CLIP image encoder and llava multimodal projector. These functions
// are defined in llama.cpp's llava component (llava.cpp / clip.cpp).
//
// IMPORTANT: The llama.cpp build must include llava support. Add
// -DLLAMA_BUILD_LLAVA=ON to the CMake configuration.

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque type for the CLIP vision encoder context.
typedef struct clip_ctx clip_ctx;

/// Opaque type for llava image embeddings.
struct llava_image_embed {
    float * embed;
    int n_image_pos;
};

/// Load a CLIP model from a GGUF file.
/// Returns NULL on failure.
/// @param fname  Path to the .mmproj GGUF file
/// @param verbosity  0 = silent, 1 = info, 2 = debug
clip_ctx * clip_model_load(const char * fname, int32_t verbosity);

/// Free a CLIP context.
void clip_free(clip_ctx * ctx);

/// Get the number of image patches the CLIP model produces.
int32_t clip_n_patches(const clip_ctx * ctx);

/// Create image embeddings from raw image bytes using a CLIP context.
/// The image is decoded and resized internally.
/// @param ctx  CLIP context (must be loaded)
/// @param n_threads  Number of threads for encoding
/// @param image_bytes  Raw image data (JPEG/PNG)
/// @param image_bytes_length  Length of image data
/// @param image_width  Desired image width
/// @param image_height  Desired image height
/// Returns NULL on failure.
struct llava_image_embed * llava_image_embed_make_with_clip_ctx(
    clip_ctx * ctx,
    int n_threads,
    const unsigned char * image_bytes,
    int image_bytes_length,
    int image_width,
    int image_height
);

/// Free image embeddings.
void llava_image_embed_free(struct llava_image_embed * embed);

/// Evaluate image embeddings into the LLM's KV cache.
/// @param ctx_llama  LLM context
/// @param embed  Image embeddings to evaluate
/// @param n_batch  Batch size for processing
/// @param n_past  Pointer to the current position (updated on return)
/// Returns true on success.
bool llava_eval_image_embed(
    struct llama_context * ctx_llama,
    const struct llava_image_embed * embed,
    int n_batch,
    llama_pos * n_past
);

#ifdef __cplusplus
}
#endif

#endif /* BridgingHeader_h */
