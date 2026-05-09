# Supported Models

NeuraL's DreamState captures `&lt;think&gt;` reasoning traces from any text-generation GGUF that emits them. Every model listed below has been checked for trace compatibility with `ThinkTagParser`. Recommendations assume an iPhone 16 Pro / 16 Pro Max (Apple A18, 8GB LPDDR5X).

## Recommended

### DeepSeek-R1-Distill-Qwen-1.5B

The best model for typical iPhone hardware. Fits entirely in RAM at Q4_K_M with room for a 2048-token context window. &lt;think&gt; traces are cleanly structured, with consistent open/close tags and coherent chain-of-thought.

| Quantization | File size | RAM at 2048 ctx | Tokens/sec (A18) | Verdict |
|---|---|---|---|---|
| Q4_K_M | ~1.0 GB | ~2.2 GB | 18–25 | **Recommended** |
| Q5_K_M | ~1.2 GB | ~2.5 GB | 15–22 | Good, slightly slower |
| Q8_0 | ~1.7 GB | ~3.5 GB | 10–15 | Only if context &lt; 1024 |
| Q2_K | ~0.6 GB | ~1.5 GB | 22–30 | Fast but degraded quality |

### DeepSeek-R1-Distill-Qwen-7B

Barely fits 8GB devices at Q4_K_M with a modest context window. Excellent reasoning quality. A18 Pro / 12GB+ devices handle this comfortably; on 8GB, expect the model to use most available RAM.

| Quantization | File size | RAM at 1024 ctx | Tokens/sec (A18) | Verdict |
|---|---|---|---|---|
| Q4_K_M | ~4.2 GB | ~6.5 GB | 6–10 | **Tight fit, works** |
| Q2_K | ~2.5 GB | ~3.5 GB | 10–14 | Significantly degraded |
| Q3_K_M | ~3.0 GB | ~4.2 GB | 8–12 | Usable tradeoff |
| Q5_K_M+ | ~5.5 GB | ~8.0 GB | 3–6 | Too large for 8GB |

### QwQ-32B (Qwen-with-Questions)

Verbose reasoning traces — QwQ thinks out loud extensively before answering. Traces are well-structured but long; the ThinkTagParser's 12KB truncation may cut off deep reasoning chains. Best on 12GB+ devices at Q4_K_M.

A18 suitability: requires IQ3_XXS or Q2_K to fit at usable context. Trace truncation is expected.

## Compatible

### DeepSeek-R1-Distill-Llama-8B

Produces clean &lt;think&gt; traces. Format matches Llama-3 tokenizer conventions, so the ChatTemplateEngine auto-detects the correct template. Traces are concise compared to QwQ.

| Quantization | File size | RAM at 1024 ctx | Tokens/sec (A18) | Verdict |
|---|---|---|---|---|
| Q4_K_M | ~4.9 GB | ~7.0 GB | 5–8 | **Tight, works** |
| Q2_K | ~3.0 GB | ~4.0 GB | 9–13 | Degraded but runs |
| Q3_K_M | ~3.5 GB | ~4.8 GB | 7–10 | Usable tradeoff |

### Phi-4-Reasoning (14B)

Microsoft's reasoning model. Emits &lt;think&gt; tags but traces are often formulaic — shorter and less exploratory than DeepSeek-distilled variants. Tag format is standard and parses correctly.

A18 requires aggressive quantization (IQ2_XXS or Q2_K) and short context. Trace quality under aggressive quantization degrades further.

### Gemma 3 Thinking Variants (1B, 4B)

Google's Gemma 3 models in their "thinking" configuration output &lt;think&gt; blocks. Trace structure is inconsistent — Gemma 3 sometimes nests thinking blocks or uses non-standard delimiters in early fine-tune checkpoints. ThinkTagParser handles the standard format but may produce messy traces on older checkpoints.

| Model | Quantization | File size | Tokens/sec (A18) | Verdict |
|---|---|---|---|---|
| Gemma-3-1B-IT-Thinking | Q4_K_M | ~0.8 GB | 22–30 | Light, traces inconsistent |
| Gemma-3-4B-IT-Thinking | Q4_K_M | ~2.5 GB | 12–18 | Moderate fit, trace quality varies |

## Flagged

These models either fail to produce parseable &lt;think&gt; tags or produce output that confuses the parser.

### Phi-3-Mini / Phi-3.5-Mini (non-reasoning)

These are instruction models, not reasoning models. They do not emit `&lt;think&gt;` tags natively. Occasionally produce the literal text `&lt;think&gt;` in responses when prompted to "think step by step," which the parser will misinterpret as a reasoning trace block.

### Command R / Command R+

Cohere's models use a different reasoning convention (internal CoT tokens that are not exposed in the output stream). No `&lt;think&gt;` tags appear. DreamState will not capture traces from these models.

### Llama-3.1 / Llama-3.2 / Llama-3.3 (base instruct, non-reasoning)

Standard instruction-tuned Llama models. No reasoning traces. DreamState still synthesizes Dream Cards from the visible answer content, but there is no chain-of-thought to capture.

### Qwen2.5 (base instruct, non-reasoning)

Same as Llama-3.x — instruction-tuned, no &lt;think&gt; tags. The ChatTemplateEngine supports these models for generation, but DreamState will not find reasoning traces to preserve.

## Quantization notes for A18 (8GB LPDDR5X)

General rules for Apple Silicon:

- **Q4_K_M** is the sweet spot for most models. Balanced quality/size ratio, fits 1.5B–3B comfortably, 7B tightly.
- **Q5_K_M** offers marginal quality improvement but ~20% larger files and ~15% lower throughput. Worth it for 1.5B models; avoid for &ge;3B on 8GB devices.
- **Q3_K_M** and **IQ3_XXS** are viable for 7B–8B models that won't fit at Q4. The IQ quants (importance-aware) generally outperform Q3 at the same file size.
- **Q2_K** is a last resort. Significant quality degradation, especially on reasoning tasks where precision matters.
- **Q8_0** and **F16** are not practical on 8GB devices for models &ge;3B.
- **Context window** consumes ~0.5MB per token per billion parameters at FP16 KV cache. A 2048-token context on a 7B model adds roughly 200MB. Budget for it.
- **iOS jetsam** kills apps that exceed available RAM. The MemoryManager probes `os_proc_available_memory()` before loading, but iOS can reclaim memory at any time during inference. Close other apps, use conservative context windows, and prefer Q4_K_M or smaller.
