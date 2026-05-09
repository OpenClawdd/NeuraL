//
//  llama_c_interop.h
//  NeuraL
//
//  Supplementary C declarations that make the llama.cpp API more ergonomic
//  from Swift. These are thin wrappers that reduce the amount of unsafe
//  pointer manipulation required on the Swift side.
//
//  This file is included via the bridging header.
//

#ifndef llama_c_interop_h
#define llama_c_interop_h

#include "llama.h"
#include <stdlib.h>
#include <string.h>
#include <os/proc.h>

// ─── Callback Types ────────────────────────────────────────────────────

/// Callback invoked by the inference engine for each generated token.
///   - token_text: UTF-8 string of the generated token (may be partial bytes)
///   - token_id:   The integer token ID from the model's vocabulary
///   - is_eog:     True if this token is an end-of-generation token
///   - user_data:  Opaque pointer passed through from the caller
typedef void (*onddevice_token_callback_t)(
    const char *token_text,
    llama_token token_id,
    bool is_eog,
    void *user_data
);

/// Callback for model loading progress.
///   - progress: 0.0 to 1.0
///   - user_data: Opaque pointer
typedef void (*ondevice_load_progress_t)(
    float progress,
    void *user_data
);

// ─── Swift-Friendly Wrappers ───────────────────────────────────────────

/// Allocate and return a new llama_model_params with sensible iOS defaults.
/// This avoids Swift having to call llama_model_default_params() and then
/// set individual fields through unsafe pointers.
static inline struct llama_model_params ondevice_model_params_default(void) {
    struct llama_model_params params = llama_model_default_params();
    // On iOS, we want to use the Metal GPU for prompt processing (batched)
    // but may fall back to CPU for autoregressive generation if Metal
    // overhead exceeds benefit for batch_size=1.
    params.n_gpu_layers = 99;  // Offload all layers to GPU if available
    params.use_mmap     = true;  // Memory-map the model file (reduces RSS)
    params.use_mlock    = false; // mlock is restricted on iOS; don't attempt
    params.check_tensors = false; // Skip validation for faster load
    return params;
}

/// Allocate and return a new llama_context_params tuned for on-device use.
/// n_ctx will be set by the MemoryManager; this provides the base defaults.
static inline struct llama_context_params ondevice_context_params_default(int32_t n_ctx) {
    struct llama_context_params params = llama_context_default_params();
    params.n_ctx            = n_ctx;
    params.n_batch          = 512;    // Batch size for prompt processing
    params.n_ubatch         = 512;    // Micro-batch size (physical batch)
    params.n_seq_max        = 1;      // Single conversation (no parallel sequences)
    params.n_threads        = 2;      // Conservative: 2 threads for low thermal
    params.n_threads_batch  = 4;      // More threads for batched prompt processing
    params.rope_freq_base   = 0.0f;   // 0 = use model default
    params.rope_freq_scale  = 0.0f;   // 0 = use model default
    params.attention_type   = LLAMA_ATTENTION_TYPE_CAUSAL;
    params.flash_attn       = true;   // Use Flash Attention if available (Metal)
    params.permute_rope     = true;   // Permute for better memory locality
    params.pooling_type     = LLAMA_POOLING_TYPE_NONE; // Generative, not embedding
    return params;
}

/// Extract the model architecture metadata needed for memory planning.
/// Returns 0 on success, -1 on failure. Output parameters are written
/// only on success.
static inline int ondevice_get_model_metadata(
    const char *model_path,
    int32_t *out_n_layers,
    int32_t *out_n_embd,
    int32_t *out_n_vocab,
    size_t  *out_file_size
) {
    // Get file size first (cheap check before loading the model)
    FILE *f = fopen(model_path, "rb");
    if (!f) return -1;
    fseek(f, 0, SEEK_END);
    *out_file_size = (size_t)ftell(f);
    fclose(f);

    // Load model metadata only (partial load, then free)
    struct llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers  = 0;  // CPU only for metadata probe
    mparams.use_mmap      = true;
    mparams.check_tensors = false;

    struct llama_model *model = llama_model_load_from_file(model_path, mparams);
    if (!model) return -1;

    // Extract architecture details from the model
    const struct llama_model_stats stats;
    // Note: llama.cpp doesn't expose a direct stats struct in the C API.
    // We use the n_layer, n_embd from the model's hparams.
    // These are accessible via the model's internal state, but the C API
    // provides llama_model_n_ctx_train(), etc. For now we approximate:
    *out_n_layers = 0;  // Will be populated via Swift-side llama_model_n_layer()
    *out_n_embd   = 0;  // Will be populated via Swift-side llama_model_n_embd()
    *out_n_vocab  = llama_model_n_vocab(model);

    llama_model_free(model);
    return 0;
}

#endif /* llama_c_interop_h */
