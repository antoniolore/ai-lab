# Results — desktop, Intel Core i7-8700K, CPU only (night 2026-11-18 → 19)

Protocol: [`../../PROTOCOL.md`](../../PROTOCOL.md) (§3, changelog 2026-11-18, order t6 → 100B → t12 → t2 → energy by Antonio's decision). Runner `scripts/desktop-night.sh` (reviewed by the operator, corrections D1–D6), user unit `debunking-ai-bitnet-night`, start 22:01. Raw data in `2026-11-18/`: `raw/` (llama-bench JSON), `time/` (GNU time), `energy/rapl.txt`, `night.log`, `env.txt`, `summary.md` (from `scripts/summarize.py`).

| Item | Value |
|------|-------|
| Machine | i7-8700K (6C/12T, AVX2, max 4.7 GHz, L3 12 MiB), 62 GB DDR4, Linux 7.2 (Linux) |
| Isolation | Container `lab-bitnet:2026-11-18`, `--network none`, `--cpuset-cpus 0-11`, memory cap = MemAvailable − 3 GiB, no swap |
| Host | the local inference server stopped 22:01 → restored 02:27 (`RESTORE_STATUS` OK, the inference gateway `main` answered). The other containers (other services, including two OCR llama.cpp servers) kept running; 1-min load before each run 0.4–2.5 (`night.log`; corrected 2026-11-19, was "0.6–2.5") |
| bitnet.cpp | HEAD `0b341e5` (the claim's current repo), `01eb415`, `404980e`; clang 18 + libomp, `-DBITNET_X86_TL2=OFF` (I2_S) |
| stock llama.cpp | b12503 `4577932`, official `ubuntu-x64` CPU binary |
| Outcome | exit 0, DONE, **134 runs OK, 0 failed**, night done 02:26 |
| Settings | `-p 512 -n 128 -r 5`, 3 invocations per row; 30 s cool-down + wait for load < 2.5 |

## Decode (tg128, tokens/s) — median of 3 invocations

| Row | what | `-t 6` | `-t 12` | `-t 2` |
|-----|------|------:|-------:|------:|
| `bn-i2s-head` | bitnet.cpp HEAD, 2B4T I2_S (official GGUF) | **24.8** | 20.5 | 17.9 |
| `bn-i2s-v0` | bitnet.cpp `404980e` | 24.4 | 19.9 | 19.5 |
| `bn-i2s-01eb415` | bitnet.cpp `01eb415` | 24.0 | 19.8 | 20.2 |
| `ll-f16` | stock, 2B4T F16 (proxy) — the paper's baseline type | 6.8 | 5.4 | 5.2 |
| `ll-tq2-embf16` | stock, 2B4T TQ2_0, F16 embeddings (like the official I2_S) | 24.5 | 18.5 | 18.7 |
| `ll-tq2` | stock, 2B4T TQ2_0 default (Q6_K embeddings) | 33.3 | 26.3 | 24.7 |
| `ll-tq1` | stock, 2B4T TQ1_0 | 34.6 | 27.8 | 17.8 |
| `ll-q40` | stock, 2B4T Q4_0 | 20.3 | 16.6 | 15.6 |
| `ll-qwen-q4km` | stock, Qwen2.5-1.5B-Instruct Q4_K_M | **30.3** | 24.4 | 23.1 |
| `bn-large-i2s-head` | bitnet.cpp HEAD, bitnet_b1_58-large (0.7B) | 96.2 | 73.6 | 70.7 |
| `ll-large-f16` | stock, large F16 | 22.4 | 17.0 | 18.3 |
| `ll-large-tq2` | stock, large TQ2_0 | 90.6 | 75.2 | 77.7 |
| `ll-large-tq1` | stock, large TQ1_0 | 100.3 | 76.7 | 55.4 |
| `ll-large-q40` | stock, large Q4_0 | 66.8 | 53.2 | 50.7 |

`-t 6` (physical cores) is the fastest decode setting for every row; `-t 12` (hyper-threads) is slower. Spread across invocations is ≤ 2 % for almost all rows (min–max in `summary.md`).

## Ratios (decode, `-t 6`; the other thread counts in `summary.md`)

| Comparison | ratio |
|------------|------:|
| bitnet.cpp HEAD vs stock **F16**, 2B4T proxy (faithful to the paper) | **3.65x** (3.46–3.81x over 2/6/12 threads) |
| bitnet.cpp HEAD vs stock **F16**, large (real same model) | 4.29x (3.86–4.32x) |
| stock TQ2_0 (emb F16) vs stock F16 — same engine, only the weights change | 3.60x |
| bitnet.cpp HEAD vs stock **TQ2_0, F16 embeddings** (engine only, like for like) | **1.01x** (0.96–1.10x) |
| bitnet.cpp HEAD vs stock **TQ2_0** default | 0.74x (0.72–0.78x) |
| bitnet.cpp HEAD vs stock TQ2_0, large | 1.06x (0.91–1.06x) |
| bitnet.cpp HEAD vs stock **Q4_0**, 2B4T | 1.22x (1.14–1.23x) |
| bitnet.cpp HEAD 2B4T vs **Qwen2.5-1.5B Q4_K_M** | **0.82x** (0.77–0.84x) |

Reading [measured; interpretation I]:
- Faithful reproduction: bitnet.cpp is **3.5–3.8x faster than FP16** at decode on this x86 CPU (4.3x on the 0.7B). The paper's x86 figures are 4.19x for a 2.5B and 3.88x for a 700M dummy (Table 4, i7-13700H): same order, so the paper's ratio is reproducible against its own baseline.
- **The engine adds nothing measurable at decode:** stock llama.cpp with TQ2_0 gets the same 3.6x over F16 by itself, and with like-for-like embeddings it is within ±10 % of bitnet.cpp. With its default (Q6_K) embeddings stock llama.cpp is **34 % faster** than the official bitnet.cpp GGUF (bitnet.cpp at 0.74x), because a 2B model's 128k-token tied embedding is a large share of the bytes read per token (F16 657 MB vs Q6_K 269 MB).
- Against what a llama.cpp user would actually run (Qwen2.5-1.5B Q4_K_M), bitnet.cpp 2B4T is **18 % slower** at decode.
- Against Q4_0 of the same weights, bitnet.cpp is 1.2x (paper's later table: ~2.1x at 13B; the gap grows with size [D]).

## Prefill (pp512, tokens/s, `-t 6`)

bitnet.cpp HEAD 174.7 · `404980e` 142.4 · `01eb415` 186.7 · stock F16 46.8 · TQ2_0 153.9 · TQ1_0 77.5 · Q4_0 105.9 · Qwen Q4_K_M 200.8. On x86 bitnet.cpp HEAD's prefill is 1.14x stock TQ2_0 and 3.7x F16; Qwen Q4_K_M is still faster. (No BLAS backend on this binary, unlike the Mac.)

## 100B random-weight layout (§3.4; 1 invocation, `-p 64 -n 32 -r 3`)

| Row | `-t 6` pp64 / tg32 | `-t 12` pp64 / tg32 | peak RSS |
|-----|------|------|------|
| stock llama.cpp, TQ2_0 (26.3 GB file) | 3.75 / **1.15** | 3.96 / 1.00 | 25.1 GiB |
| bitnet.cpp HEAD, I2_S (25.5 GB file) | 4.39 / **1.15** | 4.44 / 0.99 | 24.4 GiB |

- A 100B ternary layout **does run** in 62 GB on a 2017 desktop CPU, at **~1.15 tokens/s**: about a fifth of the 5–7 tok/s the README calls reading speed. The paper's own x86 figure for its 100B dummy is 1.70 tok/s on a newer laptop chip (i7-13700H) [D]; ours is lower, same order.
- bitnet.cpp and stock llama.cpp are **identical** at decode here (1.153 vs 1.154 t/s), as expected for a purely memory-bound case where both read ~2 bits per weight. Samples per run differ by < 0.5 %.
- Weights are random (as in the paper): nothing about quality can be said, and no such model exists to download (TRIAGE §1). Generator: `scripts/gen_dummy_bitnet.py`, validated on the 0.7B layout against the real model (±15 %, daytime smoke test).

## Energy (RAPL package counter, `-t 6`, tg-only `-p 0 -n 256 -r 3` = 768 tokens, 1 invocation each)

Idle package power measured just before: **20.1 W** (60 s, other containers running).

| Row | decode t/s | avg package W | J/token gross | J/token net of idle |
|-----|-----:|-----:|-----:|-----:|
| bitnet.cpp HEAD, 2B4T I2_S | 24.4 | 57.2 | 2.46 | **1.60** |
| stock F16 (2B4T proxy) | 6.8 | 56.3 | 8.43 | 5.43 |
| stock TQ2_0, F16 embeddings | 20.3 | 62.6 | 3.18 | 2.16 |
| stock Qwen2.5-1.5B Q4_K_M | 30.1 | 58.3 | 2.05 | 1.35 |

- bitnet.cpp vs F16: **−71 %** energy per token (−70.8 % gross, −70.5 % net): just under the low end of the declared 71.9–82.2 % [D] (the low end is the paper's smallest model, 700M). Correction 2026-11-19: an earlier version said "inside the README's x86 range", which was wrong by 1.1–1.4 points.
- vs stock TQ2_0 (same weights, F16 embeddings): −23 % gross / −26 % net. vs Qwen Q4_K_M: **+20 % gross / +18 % net** (bitnet.cpp uses more energy per token).
- Caveats: the package counter includes every process on the host; intervals are the run's START–END in `night.log` (includes ~1–2 s of container start and model mapping); one invocation per row; the F16 run wrapped the 32-bit counter once (corrected with `max_energy_range_uj` = 262,143,328,850 µJ). Treat differences below ~10 % as noise.

## Anomalies

- None in the run: 0 failures, restore OK. The first daytime smoke tests (2026-11-18) showed up to 2x noise from the services; the night numbers are stable (≤ 2 % spread).
- HEAD vs `01eb415` vs `404980e` on x86 are within ~3 % at decode at `-t 6` and `-t 12`, up to 13 % apart at `-t 2` (17.9 / 19.5 / 20.2; corrected 2026-11-19, was "within ±3 %"); prefill differs (HEAD 175, `01eb415` 187, `404980e` 142 at `-t 6`).
