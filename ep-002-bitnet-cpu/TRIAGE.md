# Triage — bitnet.cpp, "a 100B model on a single CPU", "up to 6.17x" (C-20261118-01)

- **Author:** the bench author (R&D), 2026-11-18, read-only. Ordered by Antonio via the editor (proposal A/12 `bitnet-100b-single-cpu`, go-ahead 2026-11-18).
- **Tags:** **[V]** verified by us at the source on the date given · **[D]** declared by Microsoft / the authors, not verified · **[derived]** our arithmetic from [V]/[D] data · **[I]** our hypothesis.
- Local copies of the sources (not in git): `$LAB/src/BitNet/` (clone) and `docs/*.pdf|txt` (arXiv PDFs).

## Sources read (2026-11-18)

| Source | Version read |
|--------|--------------|
| `github.com/microsoft/BitNet` README, `LICENSE`, `utils/generate-dummy-bitnet-model.py`, `utils/codegen_tl1.py`, `utils/codegen_tl2.py`, `utils/e2e_benchmark.py`, `setup_env.py` | commit `0b341e582afbf9e1011f24744b554c96a3477eb5` (2026-07-27, "Add VibeASR.cpp release to News (#596)"); submodule `3rdparty/llama.cpp` at `390c307752ab78fd8189f359d6954c9ba1be74af` (branch `release-bitnet-embedding-0.6b-270m`) |
| arXiv 2410.16144, "1-bit AI Infra: Part 1.1, Fast and Lossless BitNet b1.58 Inference on CPUs" (Wang, Zhou, Song et al., Microsoft Research) — the "technical report" the README links for the numbers | v2, 2024-10-23 (v1 2024-10-21) |
| arXiv 2502.11880, "Bitnet.cpp: Efficient Edge Inference for Ternary LLMs" (system paper) | v1, submitted 2025-02-17 |
| arXiv 2504.12285, "BitNet b1.58 2B4T Technical Report" | PDF downloaded 2026-11-18 (latest version) |
| Hugging Face API + model cards (`microsoft/bitnet-b1.58-2B-4T` and siblings, community models in the README table) | revisions listed in §3 |
| Microsoft HF collection `microsoft/bitnet-67fddfe39a03686367734550` and HF model search `author=microsoft, search=bitnet` | 2026-11-18 |

## 1. Is there a public 100B BitNet b1.58 model?

**No.** The 100B is a **dummy model with random weights**, built only to time the kernels.

- README (commit above) [V]: "bitnet.cpp can run a 100B BitNet b1.58 model on a single CPU, achieving speeds comparable to human reading (5-7 tokens per second) … Please refer to the technical report". It does not link or name a 100B model.
- Technical report 2410.16144 v2, §3.1 and **Appendix A** [V]: "Comprehensive tests were conducted on models with various parameter sizes, ranging from 125M to 100B"; "**The tested models are dummy setups used in a research context to demonstrate the inference performance of bitnet.cpp.**" 100B config: `hidden_size 8192, intermediate_size 45568, num_hidden_layers 72, num_attention_heads 64`.
- Same config in the repo's `utils/generate-dummy-bitnet-model.py` (`model_config["100B"]`) [V]; the script fills every tensor with `torch.randn` (random numbers), then ternarises it. A model like this produces no meaningful text; its only use is timing.
- Parameter count of that config [derived]: per layer 4·8192² (attention, no GQA in the dummy) + 3·8192·45568 (MLP) = 1.388 B; × 72 = 99.96 B; + 32,002 × 8,192 embeddings ≈ **100.2 B**. So "100B" is the right size for the layout; it just was never trained.
- Microsoft's BitNet collection on HF lists only `bitnet-b1.58-2B-4T` (+ `-bf16`, `-gguf`) and the 2B4T report; the HF search `author=microsoft, bitnet` adds only the two embedding models and `VibeVoice-ASR-BitNet` [V, 2026-11-18]. The README table lists nothing larger than 10B (Falcon3 1.58-bit family, community) [V].
- The README itself says [V]: "We use existing 1-bit LLMs available on Hugging Face to demonstrate the inference capabilities of bitnet.cpp. We hope the release of bitnet.cpp will inspire the development of 1-bit LLMs in large-scale settings".
- Memory needed for the dummy [derived]: ~100 B × 2 bit (I2_S) / 8 ≈ 25 GB; TL2 (1.67 bpw) ≈ 21 GB. "In RAM it fits" holds; "you can download and run a 100B BitNet model" does not.

**Can the 100B dummy be regenerated from the public repo?** Only partly, and not out of the box [V, code read at the commit above]:

- `generate-dummy-bitnet-model.py` writes only `f32`, `f16`, `tl1`, `tl2` (no `i2_s`). A 100B in f16 would be ~200 GB to write and then quantise: not feasible here.
- The **TL2 (x86)** path has the block constants hard-wired for the 0.7B "large" layout (`KEMD = 1536`, `KGQA = 4096`) and raises `NotImplementedError` for any other matrix width, so a 100B TL2 dummy cannot be generated without patching.
- The **TL1 (ARM)** path reads the widths from `model_config`, so a 100B TL1 file can be generated [I: not yet run], but bitnet.cpp must then be compiled with TL1 kernels for the 100B matrix shapes, and `codegen_tl1.py` / `codegen_tl2.py` only know three models (`bitnet_b1_58-large`, `bitnet_b1_58-3B`, `Llama3-8B-1.58-100B-tokens`). The block sizes Microsoft used for 100B are not published.
- Consequence for the bench: the 100B row is reproducible only with our own patch (new shapes in the codegen dictionary, block sizes chosen by us), declared as a deviation. See `PROTOCOL.md` §3.4.

## 2. Which CPU, which baseline, how many tokens/s; what "up to 6.17x" means

### Hardware [D, 2410.16144 §3.1]

- **x86:** Surface Laptop Studio 2, **Intel Core i7-13700H** (14 cores, 20 threads), 64 GB.
- **ARM:** Mac Studio, **Apple M2 Ultra**, 64 GB.
- Two settings per device: unlimited threads ("reporting the optimal inference speed") and 2 threads.

### Baseline [D]

- **llama.cpp in Float16.** Figure 1 caption of 2410.16144: "llama.cpp(fp16) versus bitnet.cpp (ternary kernels)"; 2502.11880 §4.1.2: "we chose llama.cpp Float16 as the baseline". The llama.cpp version/commit used is **not stated** in either paper (da verificare: not found).
- Speeds are **token generation (decode)** [D, 2502.11880 §4.1.3 "token generation speed"; Table 7 caption "average results from 10 tests"]. Prompt length and prefill are not reported. The repo's `utils/e2e_benchmark.py` runs `llama-bench -p 512 -n 128 -b 1 -r 5` [V, code], i.e. prompt processed with batch size 1.

### Where each headline number comes from [D, 2410.16144 Tables 4–6]

| README / post number | Table | Device | Model (dummy) | llama.cpp fp16 | bitnet.cpp |
|---|---|---|---|---|---|
| **6.17x** (x86 upper bound) | 4, unlimited threads | i7-13700H | **13B** | 1.78 tok/s | 10.99 tok/s |
| 2.37x (x86 lower bound) | 4 | i7-13700H | 125M | 164.04 | 389.08 |
| 5.07x (ARM upper bound) | 4 | M2 Ultra | 70B | 1.71 | 8.67 |
| 1.37x (ARM lower bound) | 4 | M2 Ultra | 125M | 434.40 | 593.43 |
| **"100B at 5–7 tok/s, human reading speed"** | 4 | **M2 Ultra** | 100B | N/A (fp16 does not fit) | **6.58** |
| same 100B on **x86** | 4 | i7-13700H | 100B | N/A | **1.70** |
| **82.2 %** less energy | 6 (J/token) | i7-13700H | 7B | 11.305 | 2.017 |
| 71.9 % | 6 | i7-13700H | 700M | 1.367 | 0.384 |

Reading of the table [derived]:

- "Up to 6.17x faster on x86" = **one cell**: a randomly-initialised 13B model, decode only, against **unquantised FP16** llama.cpp, on a 14-core laptop chip. For x86 the 30B–100B rows have no ratio because the FP16 baseline does not fit in 64 GB.
- In the 2-thread table (Table 5) the x86 peak is even higher (**6.46x**, 7B); the README quotes the unlimited-thread range.
- **"100B on a single CPU at reading speed" was measured on the Apple M2 Ultra (ARM, Mac Studio), not on x86.** On the x86 laptop the same 100B decodes at **1.70 tok/s**, below the 5–7 tok/s the README cites as reading speed. The post puts "100B on a single CPU" next to "up to 6.17x faster on x86 CPUs": the two numbers come from different CPUs and different model sizes, and neither has a baseline for 100B.
- No energy figure exists for 100B; the 82.2 % is the 7B row.

### Against a *quantised* baseline — the authors' own numbers [D, 2502.11880 Appendix E, Table 7, i7-13700H, unlimited threads, tok/s]

| Model (dummy) | Float16 | **Q4_0** (llama.cpp) | **TQ2_0** (llama.cpp ternary) | TQ1_0 | I2_S (bitnet.cpp) | TL2_0 (bitnet.cpp) |
|---|---|---|---|---|---|---|
| 7B | 3.30 | 9.09 | 19.92 | 17.96 | 20.62 | 20.72 |
| 13B | 1.78 | 5.04 | 11.21 | 10.55 | 10.62 | 11.41 |
| 100B | N/A | 0.67 | 1.61 | 1.48 | 1.65 | 1.69 |

Derived ratios: at 13B, I2_S vs Q4_0 ≈ **2.1x** (not 6.17x); I2_S vs llama.cpp's own ternary type TQ2_0 ≈ **0.95x**, TL2_0 vs TQ2_0 ≈ 1.02x. At 100B, TL2_0 vs TQ2_0 ≈ 1.05x. In other words, by Microsoft's own later paper, most of the "6x" is **ternary weights vs FP16 weights** (about 8x fewer bytes of weights to read per token [derived: 16 vs ~2 bits per weight]), not bitnet.cpp vs llama.cpp: stock llama.cpp with its TQ2_0 type is within ~5 % on x86. Ternary weights need a model trained ternary (BitNet b1.58); you cannot get them by converting an existing FP16 model without quality loss [I, to be explained in primer I-07, not tested here].

Note: the 2502.11880 numbers for 13B (I2_S 10.62) are not identical to 2410.16144 ("bitnet.cpp" 10.99); the second paper does not say which kernel the first one reported. Declared as is.

## 3. 1.58-bit models you can actually run today

Hugging Face API, read 2026-11-18 (`license` = HF tag; sizes in bytes from the API).

| Model | Params | Origin | License (HF tag) | Files | Revision |
|---|---|---|---|---|---|
| `microsoft/bitnet-b1.58-2B-4T-gguf` | 2.4B (README) / "~2 Billion" (card) | **Official**, native ternary, 4T tokens | MIT [V tag + card §License] | `ggml-model-i2_s.gguf` 1,187,801,280 (1.19 GB) | `a1f2f1c765812aa8af3f6eda4a313707064bba15` |
| `microsoft/bitnet-b1.58-2B-4T-bf16` | same | Official, BF16 master weights (for conversion / training) | MIT [V tag] | `model.safetensors` 4,825,679,400 (4.83 GB) | `276681394656abdadb8e80e5b2c3db5e5d7fcaff` |
| `microsoft/bitnet-b1.58-2B-4T` | same | Official, packed 1.58-bit for `transformers` (no speed gain there, per card) | MIT [V] | `model.safetensors` 1,178,623,988 | `04c3b9ad9361b824064a1f25ea60a8be9599b127` |
| `1bitLLM/bitnet_b1_58-large` | 0.7B | Community (reproduction of the 2024 paper) | da verificare | — | — |
| `1bitLLM/bitnet_b1_58-3B` | 3.3B | Community | MIT [V tag] | 3 safetensors, 13.3 GB total (FP32) | `af89e318…` |
| `HF1BitLLM/Llama3-8B-1.58-100B-tokens` | 8.0B | Community: Llama 3 8B fine-tuned to 1.58 bit on **100B tokens** (the "100B" in the name = training tokens) | **no license tag** (da verificare; Llama 3 base license likely applies [I]) | `model.safetensors` 3,846,768,552 | `5c35ae1f…` |
| `tiiuae/Falcon3-*-1.58bit` (1B–10B) | up to 10B | Community (TII) | `license:other` (Falcon license, da verificare) | 10B: 3,986,209,008 | — |
| `tiiuae/Falcon-E-*` (1B–3B) | up to 3B | Community (TII) | `license:other` (da verificare) | — | — |

- Largest 1.58-bit model in the README's support table: **10B** (Falcon3-10B-Instruct-1.58bit). Largest **official native** BitNet LLM: **2.4B**.
- The 2B4T model card [D] says it is for "research and development purposes" and does not recommend commercial or real-world use without further testing. It also claims quality comparable to full-precision models of similar size: average 54.19 on its benchmark table vs **Qwen2.5 1.5B 55.23**, Llama 3.2 1B 44.90, SmolLM2 1.7B 48.70 — and "Latency (CPU decoding)" 29 ms vs 41–124 ms, measured on an **i7-13800H, 8 threads, 128 tokens**, BitNet in bitnet.cpp and the others in llama.cpp with **quantisation not stated** (2504.12285 appendix, da verificare which format).
- **Stock llama.cpp** (release `b12503`, commit `4577932fab595eaa8b27ad71734d5de1f3c07d8c`, 2026-11-18) [V, code read]: has the `bitnet` architecture (`src/models/bitnet.cpp`), a converter that registers `BitNetForCausalLM` with `microsoft/bitnet-b1.58-2B-4T` as its example (`conversion/bitnet.py`), and the ternary types `TQ1_0` (1.69 bpw) and `TQ2_0` (2.06 bpw) in `llama-quantize`. It cannot read bitnet.cpp's `I2_S` GGUF [I: `I2_S` is not a ggml type in mainline; to confirm by loading it]. So the same 2B4T model can be timed in both engines, starting from the BF16 weights.

## 4. Provisional verdict [I, before any measurement]

- **"It can run a 100B-parameter BitNet model on a single CPU"** — the measurement exists, but on a **random-weight dummy**, and the "reading speed" figure is from an **Apple M2 Ultra**, not from an x86 CPU (x86: 1.70 tok/s). No 100B BitNet model exists to download, so nobody reading the post can run one. As written in the post: **Misleading**.
- **"Up to 6.17x faster on x86"** — a real number in the paper, but the single best cell (13B dummy, decode) against **FP16** llama.cpp, a baseline nobody uses on a CPU. Against llama.cpp Q4_0 the authors' own table gives ~2x; against llama.cpp's ternary type ~1x. **Misleading** (true number, missing baseline).
- **"Up to 82.2 % less energy"** — 7B dummy vs FP16, same caveat; we cannot verify energy on our bench unless RAPL works (`PROTOCOL.md`).
- **News framing** — bitnet.cpp 1.0 is from 2024-10-17 (README); the 2B4T model from 2025-04-14. Nothing new in the post except the date. The repo is active (latest commit 2026-07-27).
- Overall expected verdict: **Misleading**, pending the bench. The bench can still move it: if bitnet.cpp on our i7-8700K beats stock llama.cpp TQ2_0/Q4_K_M by a wide margin on the real 2B4T, the speed part becomes "True with asterisks".

## 4b. Verdict after the bench (2026-11-19) — **Misleading** (internal, not published)

Measured on the i7-8700K (night 2026-11-18, [`results/desktop/RESULTS-desktop.md`](results/desktop/RESULTS-desktop.md)) and on the M4 Max CPU (clean session 2026-11-19, [`results/mac/RESULTS-mac.md`](results/mac/RESULTS-mac.md)). Decode, median of 3 invocations.

| Claim piece | What we measured | Verdict on the piece |
|---|---|---|
| "Up to 6.17x faster on x86" | Against **FP16** (the paper's baseline) bitnet.cpp is **3.65x** faster on x86 with the 2B4T proxy (4.29x on the real 0.7B) and 2.74x on the M4 Max: the paper's ratio is reproducible in kind. Against **stock llama.cpp's own ternary type TQ2_0** with the same embeddings: **1.01x** x86, **1.00x** Mac — stock llama.cpp gets the same speed-up by itself; with its default Q6_K embeddings it is 34 % (x86) / 21 % (Mac) **faster** than the official bitnet.cpp GGUF. Against **Qwen2.5-1.5B Q4_K_M** (similar quality per Microsoft's card): bitnet.cpp is **slower**, 0.82x x86, 0.79x Mac (0.61x at 2 threads) | True number, misleading comparison: the gain is ternary weights vs 16-bit weights, not bitnet.cpp vs a normal local setup |
| "Up to 82.2 % less energy" | RAPL on x86: **−71 %** J/token vs FP16 (−70.5 % net, −70.8 % gross: just under the low end of the declared 71.9–82.2 %; correction 2026-11-19, an earlier version said "inside the range"), **−26 %** vs stock TQ2_0, **+18 %** vs Qwen Q4_K_M (net of idle; one run each, host counter) | Same pattern as speed |
| "Can run a 100B-parameter BitNet model on a single CPU" | No such model exists (§1). A random-weight 100B layout runs: **1.15 t/s** on the i7-8700K (both engines identical), **6.7 t/s** bitnet.cpp / **6.1 t/s** stock llama.cpp on the M4 Max CPU | Misleading: there is nothing to run; "reading speed" holds only on a high-bandwidth Apple chip, and stock llama.cpp gets there too |
| Implicit: "it runs, today" | bitnet.cpp at the current commit gives **garbage output on Apple Silicon** (scalar fallback, ~12 t/s); the last commit that works on the M4 is from 2025-06-03. On x86 the current commit works | Adds to the "not what the post implies" side; to be told precisely (version, date, CPU), not as a general "it's broken" |
| News framing | bitnet.cpp 1.0 is from 2024-10-17 | Old news re-posted |

Overall: **Misleading** (confirmed by the bench; scale in the project BRIEF). What holds: ternary models do decode 2.7–3.7x faster than FP16 on CPU and use ~70 % less energy per token; a 100B ternary layout would fit in RAM and read-speed decode is possible on an M4 Max-class CPU. What the post hides: no 100B model exists, the baseline is FP16, and stock llama.cpp — or simply a 4-bit model of a similar-quality conventional LLM — is as fast or faster.

## 5. Open points (da verificare)

- llama.cpp version used as baseline in 2410.16144 / 2502.11880.
- Licence of `HF1BitLLM/Llama3-8B-1.58-100B-tokens`, `1bitLLM/bitnet_b1_58-large`, Falcon 1.58-bit (not needed for the bench).
- Format of the competitors in the 2B4T card latency row.
- Whether mainline llama.cpp really rejects the `I2_S` GGUF (to be observed in the bench).
- Exact `@byteonai` text: still the scout's screenshot transcription.
