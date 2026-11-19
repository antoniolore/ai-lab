# Protocol: bitnet.cpp on CPU — "100B on a single CPU", "up to 6.17x on x86"

- **Written:** 2026-11-18, after the triage ([`TRIAGE.md`](TRIAGE.md)) and before any measurement. Changes after the first run go in the changelog at the bottom.
- **Source claim:** `@byteonai` on X, 2026-11-17 — <https://x.com/byteonai/status/2122717876054310952> (claim card `claims/inbox/2026-11-18.md` § C-20261118-01). Numbers from the README of `microsoft/BitNet` and arXiv 2410.16144.
- **Tags:** **[V]** verified by us · **[D]** declared by Microsoft / the authors · **[I]** our hypothesis.
- **Lab:** `$LAB/` on desktop (sources, builds, models, raw logs); on the MacBook `$LAB/`. Consolidated results land here in `results/`.

## 1. Claims under test

| ID | Claim | Source | How we test it |
|----|-------|--------|----------------|
| C1 | "It can run a 100B-parameter BitNet model on a single CPU" at "speeds comparable to human reading (5-7 tokens per second)" | Post; README; 2410.16144 Table 4 (100B dummy: 6.58 tok/s M2 Ultra, 1.70 tok/s i7-13700H) [D] | Documentary (no 100B model exists, TRIAGE §1). Optional timing of a random-weight 100B with the paper's layout (§3.4) |
| C2 | "Up to 6.17x faster on x86 CPUs" | 2410.16144 Table 4: 13B dummy, decode, vs llama.cpp FP16 [D] | Same ratio on the one real model (2B4T), i7-8700K: bitnet.cpp I2_S vs stock llama.cpp F16 (**faithful**) and vs stock llama.cpp TQ2_0 / Q4_0 / a comparable Q4_K_M model (**honest**) |
| C3 | "Up to 82.2 % less energy" | 2410.16144 Table 6: 7B dummy vs FP16 [D] | Only if measurable: RAPL package energy on desktop (§4); else "not measured" |
| C4 (implicit) | The speed comes from bitnet.cpp | Post wording | Decompose: ternary-vs-FP16 weights (llama.cpp F16 → TQ2_0) vs engine (llama.cpp TQ2_0 → bitnet.cpp I2_S) |
| C5 (implicit) | ARM range 1.37–5.07x | README [D] | Same configurations on the M4 Max CPU |

Hypotheses written before measuring [I]:

- H1: decode on CPU is memory-bandwidth bound, so the speed-up over F16 tracks bytes per weight: 2B4T F16 (~4.8 GB) vs I2_S (~1.2 GB, incl. embeddings) → **~2.5–4x** in decode at this size, below 6.17x because the 2B model is small and embeddings/attention weigh more (the paper's own ratio at 2.5B is 4.19x on x86).
- H2: stock llama.cpp **TQ2_0** decodes within **±20 %** of bitnet.cpp I2_S on both machines (2502.11880 Table 7: within ~5 % on x86).
- H3: against what a user without BitNet would run (Qwen2.5-1.5B-Instruct Q4_K_M, which Microsoft's own card places at similar average quality), bitnet.cpp is **≤ 1.5x** faster in decode.
- H4: prefill (pp512) gains are smaller than decode gains, because prefill is compute-bound and both engines use int8 activations for ternary types [I].
- H5: on the M4 Max (≈ 500 GB/s class memory vs ~40 GB/s dual-channel DDR4-class on the 8700K [I]) every configuration is several times faster, and ratios shrink.

## 2. Software and models (pinned)

| Item | Value | Status |
|------|-------|--------|
| bitnet.cpp | `microsoft/BitNet` commit `0b341e582afbf9e1011f24744b554c96a3477eb5` (2026-07-27), submodule llama.cpp fork `390c307752ab78fd8189f359d6954c9ba1be74af`. Built from source with the README's I2_S path: codegen as `setup_env.py` does for `BitNet-b1.58-2B-4T`, then `cmake -DBITNET_X86_TL2=OFF` (x86) / `-DBITNET_ARM_TL1=OFF` (ARM), clang, Release. `include/gemm-config.h` left at defaults | [V] commit |
| Compilers | desktop: Ubuntu 24.04 container, clang 18 (README requires ≥ 18); Mac: Apple clang 21.0.0 | to log in `env/` |
| llama.cpp (stock) | release **b12503**, commit `4577932fab595eaa8b27ad71734d5de1f3c07d8c` (2026-11-18), official prebuilt CPU binaries: `llama-b12503-bin-ubuntu-x64.tar.gz` sha256 `0d585f8a…6a9d`, `llama-b12503-bin-macos-arm64.tar.gz` sha256 `e88d7e91…2214` (GitHub release digests) | [V] digests |
| BitNet 2B4T, I2_S | `microsoft/bitnet-b1.58-2B-4T-gguf` rev `a1f2f1c7…`, `ggml-model-i2_s.gguf`, 1,187,801,280 bytes, MIT | [V] API; sha256 at download |
| BitNet 2B4T, BF16 | `microsoft/bitnet-b1.58-2B-4T-bf16` rev `27668139…`, 4,825,679,400 bytes, MIT. Converted with stock `convert_hf_to_gguf.py` (b12503) to **F16**, then `llama-quantize` (b12503) to **TQ2_0**, **TQ1_0**, **Q4_0** | [V] API |
| Baseline model | `Qwen/Qwen2.5-1.5B-Instruct-GGUF` rev `91cad511…`, `qwen2.5-1.5b-instruct-q4_k_m.gguf` 1,117,320,736 bytes, sha256 `6a1a2eb6…407e`, Apache-2.0 | [V] API |

Total download ≈ 7.2 GB (no file above 30 GB). Third-party code: on desktop only inside a throwaway container (`--network none` for build/convert/bench after dependencies are installed, read-only source mount, no env, no QL `.env`, no credentials); on the Mac as the user from `$LAB/` with a `uv` venv (no system install).

Why Qwen2.5-1.5B-Instruct: it is the model Microsoft's 2B4T card puts next to BitNet (average 55.23 vs 54.19 on its table) [D], it ships an official Q4_K_M GGUF, and Q4_K_M is what a llama.cpp user would download. Quality is **not** re-measured here (outside the claim), and the piece says so.

## 3. Configurations

Tool: `llama-bench` of each engine (bitnet.cpp builds its own from the fork), CPU only.
Common flags: `-p 512 -n 128 -r 5 -o json` (plus `-ngl 0` everywhere; on the Mac stock binary also `-dev none` so Metal is not used).
Threads: the paper reports a 2-thread and an "unlimited" setting; we run **`-t 2`** and **`-t <physical cores>`**, plus `-t <logical>` on desktop:

| Machine | `-t` values |
|---------|-------------|
| desktop, i7-8700K (6C/12T, AVX2) | 2, 6, 12 |
| MacBook Pro M4 Max (12P + 4E) | 2, 12 |

### 3.1 Rows (each machine)

| Row | Engine | Model / type | Role |
|-----|--------|--------------|------|
| `bn-i2s` | bitnet.cpp | 2B4T I2_S (official GGUF) | The claim's setup |
| `ll-f16` | stock llama.cpp | 2B4T F16 | **Faithful baseline** (the paper's "llama.cpp fp16") |
| `ll-tq2` | stock llama.cpp | 2B4T TQ2_0 | Same weights, stock engine, ternary type |
| `ll-tq1` | stock llama.cpp | 2B4T TQ1_0 | Same, 1.69 bpw |
| `ll-q40` | stock llama.cpp | 2B4T Q4_0 | The 2502.11880 quantised baseline |
| `ll-qwen-q4km` | stock llama.cpp | Qwen2.5-1.5B-Instruct Q4_K_M | "What you would run without BitNet" |
| `bn-e2e` | bitnet.cpp | 2B4T I2_S, `utils/e2e_benchmark.py` flags (`-p 512 -n 128 -b 1 -r 5`, same `-t`) | Repo's own benchmark command, for the record |

If stock llama.cpp loads the I2_S GGUF, that is noted; we do not expect it to (TRIAGE §3).

### 3.2 Repetitions and the number we report

Each row × thread value runs as **3 separate invocations** of `llama-bench -r 5`, with a cool-down between invocations (≥ 30 s and 1-min load below a threshold measured at idle before the session). Reported: **median of the three invocation means** for pp512 and tg128, plus min/max of the three; per-run samples (`samples_ts`) kept in the raw JSON when the engine emits them.

### 3.3 Quality sanity check (not a quality benchmark)

Only to show the engines run the *same* model correctly, not to rate it:
1. Greedy completion, `--temp 0 --seed 42 -n 128`, raw prompt, same two prompts (`prompts/`), for `bn-i2s`, `ll-f16`, `ll-tq2`. Outputs saved and diffed.
2. `llama-perplexity -c 512 --chunks 16` on a text written today (this protocol + TRIAGE, cannot be in the training data) for the same three rows. Reported as is; any row diverging by > 2 % from F16 is investigated before the speed numbers are used.

### 3.4 Optional: 100B dummy (paper layout) — desktop night and Mac, only after 3.1

Goal: answer "does a 100B ternary model decode at 5–7 tok/s on *these* CPUs?", knowing the weights are random (as in the paper).
- Layout from 2410.16144 Appendix A / `generate-dummy-bitnet-model.py` (`hidden 8192, intermediate 45568, 72 layers, 64 heads`, no GQA, vocab 32,002) ≈ 100.2 B parameters.
- The repo's generator cannot produce it for x86 (TL2 hard-wired to the 0.7B layout) nor in I2_S (TRIAGE §1). We therefore write **our own generator** (lab only) that emits the same layout with random ternary payloads directly in **TQ2_0** (stock llama.cpp, ≈ 25.8 GB) and, if the I2_S tensor layout of the fork can be confirmed from its source, in **I2_S** (bitnet.cpp, ≈ 25 GB). Declared as a deviation in the results; Microsoft's TL1/TL2 100B kernels (block sizes unpublished) are not reproduced.
- Rows: `ll-tq2-100b`, `bn-i2s-100b`; `-p 64 -n 32 -r 3` (time budget), `-t` best from 3.1. One invocation per row if a single run exceeds 10 min.
- Memory: desktop needs the local inference server stopped (≈ 26 GB model + OS; today ~34 GB available with services up). Mac: 48 GB unified, run only with swap = 0 throughout (watchdog as in the pilot).

## 4. Metrics

- pp512 and tg128 (t/s) from llama-bench JSON.
- Peak memory per invocation: Linux `/usr/bin/time -v` max RSS (container-internal); macOS `/usr/bin/time -l` max RSS and peak memory footprint. Model files are memory-mapped (default), so RSS includes touched model pages: stated with the numbers.
- Energy (C3): desktop only, RAPL package counter (`/sys/class/powercap/intel-rapl:0/energy_uj`, read with `sudo -n` before/after each tg-only invocation `-p 0 -n 128`), idle power measured for 60 s before the session and subtracted, reported as J/token **with the caveat** that the package counter includes every other process on the host. Mac: not measured (needs `powermetrics` as root; not used).
- Environment per invocation: load average, free memory, swap; Mac also memory-pressure level and thermal warnings (`pmset -g therm`), as in the pilot.

## 5. Thresholds for the verdict

- Reading speed: as in the pilot (Brysbaert 2019, ≈ 238 words/min ≈ 5–6 tok/s) — the README itself cites 5–7 tok/s.
- C2 "6.17x on x86" — **faithful** ratio `bn-i2s / ll-f16` tg on the i7-8700K at best `-t`; **honest** ratios `bn-i2s / ll-tq2`, `bn-i2s / ll-q40`, `bn-i2s / ll-qwen-q4km`. If the honest ratios are ≤ 1.5x while the faithful one is ≥ 3x, the "6.17x" is a baseline effect (Misleading). If `bn-i2s / ll-tq2` ≥ 2x on both machines, the engine itself is a real win (speed part "True with asterisks").
- C1 is decided on the documentary evidence (TRIAGE); §3.4, if run, only adds what a 100B ternary layout does on our CPUs.

Verdict scale (project BRIEF): Confirmed · True with asterisks · Misleading · Not reproducible · False.

## 6. Schedule and machines

| Part | Machine | When |
|------|---------|------|
| Downloads, GGUF conversion (container, `--network none` after deps), bitnet.cpp x86 build | desktop | 2026-11-18 daytime (short CPU use) |
| §3.1–3.3 | Mac (CPU only) | 2026-11-18 daytime (always available) |
| §3.1–3.3 + energy, then §3.4 | desktop CPU | Night 2026-11-18, unit starts 22:01 (order t6 → 100B → t12 → t2 → energy, see changelog). Night window **22:00–05:00**, with the local inference server stopped and restarted afterwards (the operator, BRIEF § Test bench). Reason: clean CPU (the OCR llama.cpp servers and other services share the 12 threads) and RAM for §3.4 |
| §3.4 100B dummy | desktop (night) and Mac | After §3.1 on each machine |

## 7. Noise and limits

- One x86 CPU (2017 desktop, AVX2, no AVX-512, DDR4) and one ARM laptop chip; the paper used an i7-13700H laptop and an M2 Ultra. Absolute numbers will differ; ratios between rows on the same machine are the comparable quantity.
- Only one real BitNet LLM (2.4B). The paper's ratios grow with model size; ours cover the small end. Larger sizes only as random-weight layouts (§3.4).
- Mac: Antonio's daily machine; apps are not closed unless he authorises a clean session as in the pilot. Load is logged.
- desktop: other containers keep running at night (except the local inference server); logged.

## Changelog

- 2026-11-18: first version.
- 2026-11-18 (after build and smoke tests, before any reported measurement). Findings that change §2–§3; smoke-test numbers are not results:
  - **bitnet.cpp at HEAD (`0b341e5`) on ARM is unusable.** The July 2026 submodule (`390c307`, branch `release-bitnet-embedding-0.6b-270m`) implements `ggml_vec_dot_i2_i8_s` only for AVX2; on ARM it falls back to a scalar loop, and `src/ggml-bitnet-mad.cpp` (the NEON kernels) is no longer compiled (`src/CMakeLists.txt` sets `GGML_SOURCES_BITNET` twice, the second overwrites the first). It also does not compile on the M4 without a one-line patch (`src1_cont` undeclared when `__ARM_FEATURE_MATMUL_INT8` disables `GGML_USE_LLAMAFILE`; patch `$LAB_ROOT/.../patches/01-i2s-src1_cont.patch`). Smoke test: ~9 tok/s decode and garbage output ("@@@@") with the official GGUF. HEAD's `llama-quantize` no longer accepts `I2_S`, so the README's "Convert from .safetensors" path fails at the last step.
  - **bitnet.cpp `01eb415` (2026-03-10, last commit before the July rework, kernels from `112f853` 2025-11-19 / `1876a3e` 2026-01-27) on ARM is partly broken:** with prompts of up to 7 tokens (BOS included) the output is garbage ("!!!!"), from 8 tokens on it is coherent (QC greedy prompts OK), and `llama-perplexity` (`-c 512`) dies with SIGBUS. Same behaviour with the official GGUF and with an I2_S quantised on the Mac. Its speed rows are kept as secondary (`bn-i2s-01eb415-INVALID` on the Mac), not used for the verdict.
  - **bitnet.cpp `404980e` (2025-06-03, last commit before the November 2025 kernel rewrite) on ARM gives correct output** with the official GGUF and with a local I2_S. It becomes the **bitnet.cpp reference on the Mac**. On x86, HEAD and `01eb415` both give coherent output; x86 runs HEAD (claim's "current" setup), `01eb415` and `404980e`.
  - `01eb415` on x86 needs a one-line const fix with clang 18 (`patches/02-01eb415-x86-const.patch`). Mac builds: `-DGGML_METAL=OFF -DGGML_BLAS=OFF` (CPU only), static libs for HEAD (shared-lib link error on macOS).
  - **Stock llama.cpp cannot run BitNet-b1.58-2B-4T correctly.** Its `bitnet` architecture is the 1bitLLM layout: SiLU FFN, while 2B4T uses ReLU² (`hidden_act: relu2`), and the converter does not map 2B4T's `attn_sub_norm`/`ffn_sub_norm` names nor its BPE tokenizer. With a 3-line converter patch (`patches/03-mainline-convert-2b4t-proxy.patch`, conversion only, engine untouched) the model loads and runs with the same tensor shapes and types but degenerate output. Rows `ll-*` on 2B4T are therefore a **speed proxy** (same bytes moved and same matmuls; the activation differs on a 6,912-wide vector per layer, negligible cost [I]), never a quality comparison.
  - **Added a second, correct same-model pair:** `1bitLLM/bitnet_b1_58-large` (0.7B, MIT, rev `85d04719…`, `model.safetensors` sha256 `100062646f1f…4b52`), the model Microsoft used for the 2410.16144 accuracy test; supported natively by both engines (greedy output identical in stock llama.cpp F16 and TQ2_0). Rows `bn-large-i2s`, `ll-large-f16`, `ll-large-tq2`, `ll-large-tq1`, `ll-large-q40`.
  - **Embedding confound:** the official I2_S GGUF keeps `token_embd` (tied output, 128,256 × 2,560) in F16 (~657 MB read per decoded token), stock `llama-quantize` puts it in Q6_K (~269 MB). Added `ll-tq2-embf16` (TQ2_0 with `--token-embedding-type f16`) so the engine comparison is like for like.
  - Mac I2_S GGUFs are quantised on the Mac from the same F32 GGUF (made with the `01eb415` converter scripts from the BF16 weights), because the I2_S block size is architecture-specific in the November 2025+ kernels (`QK_I2_S` 128 on x86, 64 on ARM).
  - HEAD on the Mac: one invocation `-r 3` at `-t 12`, recorded as "as shipped, invalid output"; not used for ratios.
- 2026-11-18 (afternoon, before the desktop night): **order of the desktop night changed by Antonio's decision**: **t6 → 100B layouts (TQ2_0 and I2_S, §3.4) → t12 → t2 → energy** (was t6 → t12 → t2 → energy → 100B). Reason: the operator's estimate for the whole night is 5–6 h against 6 h 14 min available (22:01–04:15), so with the 100B last they risked being cut by the soft deadline. t6 stays first because it is the core x86 data for the "6.17x" part of the verdict; the 100B are documentary (C1 is decided on the triage) and still start around 01:30 [I]. Unchanged: the ≥ 32 GiB MemAvailable gate for the 100B, deadlines (no new run after 04:15, kill at 04:30), the local inference server restore, the operator's corrections D1–D6 (container memory cap, bounded restore, `.failed` files, key on stdin, sha re-check). Script reviewed and scheduled by the operator (user unit `debunking-ai-bitnet-night`, 22:01); copy in `scripts/`.
