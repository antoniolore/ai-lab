# Pilot protocol: llama.cpp MoE expert offload (`--n-cpu-moe`)

- **Written:** 2026-11-02, before any measurement. Changes after the first run are listed in the changelog at the bottom.
- **Source claim:** Abhinav Raj, "I changed one llama.cpp flag, and my 8GB laptop GPU now runs a 35B model faster than I can read", XDA Developers, 2026-10-22.
  <https://www.xda-developers.com/i-stopped-thinking-my-8gb-gpu-was-too-small-after-learning-to-offload-moe-llm-layers-to-ram/>
- **Tags:** **[V]** verified by us · **[D]** declared by the author / a third party · **[I]** our hypothesis, to be confirmed or refuted by the data.

## 1. Claims under test

What the article reports [D] (re-read at the source on 2026-11-02):

- Laptop: Lenovo Legion 5, RTX 3070 Mobile 8 GB, Windows 11. CPU, system RAM and llama.cpp build not stated.
- Command: `llama-bench -m Qwen3.6-27B-IQ4_XS.gguf -m Qwen3.6-35B-A3B-UD-IQ4_XS.gguf -ngl 99 -ncmoe 0,28 -p 512 -n 128 -r 3 -ctk q8_0 -ctv q8_0`

| Model | `-ncmoe` | pp512 (t/s) | tg128 (t/s) |
|-------|----------|-------------|-------------|
| Qwen3.6-27B dense IQ4_XS (14.37 GiB) | n/a | 38.83 | 0.75 |
| Qwen3.6-35B-A3B UD-IQ4_XS (16.50 GiB) | 0 | 109.66 | 4.02 |
| Qwen3.6-35B-A3B UD-IQ4_XS (16.50 GiB) | 28 | 341.37 | 32.82 |

Testable claims:

| ID | Claim | How we test it |
|----|-------|----------------|
| C1 | One flag (`-ncmoe 28`) makes a 35B MoE run on an 8 GB GPU "faster than I can read" | tg on an 8 GB VRAM budget (desktop, VRAM ballast) against a reading-speed threshold (§5) |
| C2 | The flag gives ~8× generation (4.02 → 32.82 t/s) and ~3× prompt processing (109.66 → 341.37) | Same command on our hardware, **plus honest baselines** (§3) |
| C3 | The dense 27B is unusable on that GPU (0.75 t/s), the MoE is the way | Same dense model, same budget |
| C4 (implicit) | The flag only moves weights; output quality is unchanged | Greedy output + perplexity across placements (§6) |
| C5 (missing) | How much system RAM it needs is not stated | Peak RSS / footprint per run |

Hypotheses written before measuring [I]:

- H1: the `-ncmoe 0` baseline is pathological. On Windows the driver spills to shared system memory over PCIe (sysmem fallback); on Linux the CUDA allocation fails outright. The 8× is mostly "fixing a broken baseline", not the flag's gain over a sane setup.
- H2: against an honest baseline (`-ngl` partial, i.e. classic layer offload that fits in VRAM) the flag still wins on tg for MoE models, because attention + shared tensors stay on GPU and only small expert slices are read from RAM per token. Expected gain 1.5–3×, not 8×.
- H3: recent llama.cpp auto-fit (`-fitt`) places tensors by itself; a user on a current build may get similar numbers with **no** manual flag.
- H4 (Mac, unified memory): `-ncmoe` makes things **slower**, because it moves expert compute from the GPU to the CPU while the memory is the same pool. The flag is a fix for split memory, not a general speed-up.
- H5: outputs and perplexity are unchanged by placement (tiny float differences across backends only).

## 2. Software and models (pinned)

| Item | Value | Status |
|------|-------|--------|
| llama.cpp | release **b12034**, commit `1c5ed702c9e540ac14cc8c78100ea3984bc0e227` (2026-11-02), official prebuilt binaries, sha256 checked against the GitHub release digest | [V] |
| Mac binary | `llama-b12034-bin-macos-arm64.tar.gz`, sha256 `ce1893ad…1d9b` | [V] |
| Linux binary | `llama-b12034-bin-ubuntu-cuda-12.8-x64.tar.gz` + `cudart-llama-b12034-bin-ubuntu-cuda-12.8-x64.tar.gz`, run in an `ubuntu:24.04` container with the NVIDIA runtime | [V] digests in `env/` |
| MoE model | `unsloth/Qwen3.6-35B-A3B-GGUF` rev `a483e9e6cbd595906af30beda3187c2663a1118c`, file `Qwen3.6-35B-A3B-UD-IQ4_XS.gguf`, 17,730,509,792 bytes (= 16.51 GiB, matches the article's 16.50 GiB), sha256 `649d7508…bb3`. License Apache-2.0 | [V] |
| Dense model | `unsloth/Qwen3.6-27B-GGUF` rev `82d411acf4a06cfb8d9b073a5211bf410bfc29bf`, `Qwen3.6-27B-IQ4_XS.gguf`, 15,440,005,344 bytes (= 14.38 GiB, article 14.37 GiB), sha256 `8a336575…5dc` | [V] |
| Perplexity text | Project Gutenberg #11 (Alice's Adventures in Wonderland), `pg11.txt`, sha256 `01b38ea4…725e`. Public domain. Surely in the training data: used only to compare placements of the *same* model, not to rate the model | [V] |

The article's build is unknown, so version differences are a declared limitation.

## 3. Configurations

Common flags (as in the article): `-p 512 -n 128 -ctk q8_0 -ctv q8_0 -fa on -o json`.
Repetitions: `-r 5` (article: 3). llama-bench reports mean and standard deviation; we report both.
Context depth: `-d 0` (as the article) and `-d 16384` ("long context", not tested in the article).

### Mac (Apple M4 Max, 48 GB unified memory, Metal)

| Run | Flags | Why |
|-----|-------|-----|
| mac-gpu | `-ngl 99 -ncmoe 0` | Everything on the GPU: the Mac "native" baseline |
| mac-ncmoe28 | `-ngl 99 -ncmoe 28` | The article's setting |
| mac-cmoe | `-ngl 99 -ncmoe 99` (all experts on CPU) | Extreme of the flag |
| mac-ngl-half | `-ngl 20` (no ncmoe) | Classic layer offload, half the layers |
| mac-cpu | `-ngl 0 -dev none` | CPU only, no Metal |
| mac-dense | 27B dense, `-ngl 99` | The article's dense comparison on a machine where it fits |

What the Mac can and cannot say:
- It **cannot** emulate an 8 GB VRAM card. There is no honest per-process GPU memory cap on unified memory (the `iogpu.wired_limit_mb` sysctl needs root and limits wired memory system-wide, not a separate VRAM pool). We do not fake it.
- It **can** answer: "is `--n-cpu-moe` a general speed trick?" (H4), "how much memory does this model really need?" (C5), "what does the same model do on a laptop with enough unified memory?" (the audience's obvious comparison).

### desktop (RTX 3080 12 GB, i7-8700K 6C/12T, 62 GB DDR4, PCIe Gen3 x16) — night window only

| Run | Flags | VRAM budget |
|-----|-------|-------------|
| cuda-ncmoe-sweep | `-ngl 99 -ncmoe 0,8,16,20,24,28,32,40` | 12 GB (failures recorded as data: they *are* the H1 result on Linux) |
| cuda-ngl-sweep | `-ngl 10,14,18,22,26` (no ncmoe) | 12 GB, honest baseline |
| cuda-fit | `-fitt 1024` (auto-fit, no manual placement) | 12 GB (H3) |
| cuda-cpu | `-ngl 0` in a container with `--cpus 12`, no GPU | reference |
| 8gb-* | same as the three sweeps above, with a VRAM ballast that leaves **8.0 GiB** free | emulated 8 GB card |
| dense | 27B dense `-ngl 99,40,30,20` and `-ncmoe` n/a | 12 GB and 8 GB |

The 8 GB emulation reproduces **memory capacity only**. The RTX 3080 has more bandwidth (760 GB/s) and compute than an RTX 3070 Mobile (448 GB/s), and our platform is PCIe Gen3 x16 with DDR4. Absolute numbers will differ from the laptop; ratios between configurations are the comparable quantity [I].

Ballast: a container with the same CUDA runtime allocates `free_MiB − 8192` MiB and holds it for the whole phase. Free VRAM is logged before and after.

## 4. Metrics

- pp512 and tg128, t/s, mean ± sd over 5 runs (llama-bench JSON).
- Peak memory per invocation: macOS `/usr/bin/time -l` (maximum resident set size and peak memory footprint); Linux `/usr/bin/time -v` max RSS plus `nvidia-smi --query-gpu=memory.used` sampled every 200 ms (peak VRAM).
- Environment snapshot per run: load average, free memory, thermals not available on macOS without root (declared).
- Out-of-memory / allocation failures are recorded as results, not discarded.

## 5. Thresholds for the verdict

- "Faster than I can read": average adult silent reading of English non-fiction ≈ 238 words/min [D, Brysbaert 2019 meta-analysis] ≈ 4 words/s ≈ **5–6 tokens/s** (Qwen tokenizer, ~1.3 tokens/word [I]). We use **≥ 10 t/s tg** as a comfortable "faster than reading" bar, and report the raw number.
- C2 "8×" is confirmed if our ncmoe-28 / ncmoe-0 tg ratio on an 8 GB budget is ≥ 5×; the verdict also depends on the honest-baseline ratio (H2).

Verdict scale (project BRIEF): Confirmed · True with asterisks · Misleading · Not reproducible · False.

## 6. Quality control (C4)

1. Greedy completion, same prompt, `--temp 0 --seed 42 -n 200 -c 4096`, raw completion (no chat template), for: all-GPU, ncmoe 28, CPU only. Outputs saved and diffed. Expectation: identical or diverging only late (float non-associativity across backends).
2. `llama-perplexity -f pg11.txt -c 2048 --chunks 16` for the same three placements. Expectation: PPL equal within ±0.5 %.

Prompts are in `protocol/prompts/`.

## 7. Noise and limits

- Mac: it is the author's daily machine; background apps (e.g. Steam/Wine at the time of writing) are not stopped. Load average is logged per run. Runs are on AC power.
- desktop: other containers keep running (CPU OCR, web services); llama.cpp is pinned to a CPU budget; the night window minimises interference.
- One machine per platform, one model family, one quantisation. No claim about other GPUs.

## Changelog

- 2026-11-02: first version.
- 2026-11-02 (after the first Mac QC, before any desktop GPU run): the Alice perplexity is ~1.09 on every placement, i.e. the text is memorised and the test cannot discriminate. **Added** a KL-divergence check (`llama-perplexity --kl-divergence-base` from the all-GPU run, then `--kl-divergence` for the other placements, `-c 512`) on a text written today (`data/fresh-text.txt` = this protocol + lab README, sha256 `840d5db4…a8e`), so it cannot be in the training data. Reported: mean KLD, 99.9 % KLD, "same top token" %. The original Alice PPL is kept and reported as planned.
- 2026-11-03 (recorded late; the deviations below were decided on 2026-11-02 when the night script was written, before any desktop GPU run, but were not logged here at the time — found by editorial review). The desktop night run (`scripts/desktop-night.sh`, night 2026-11-02) differs from §3 as follows:
  - **ncmoe sweep:** the article's two values are run first (`-ncmoe 0` and `-ncmoe 28`), then an **ascending search** `-ncmoe 4,8,12,16,20,24,32,40` that **stops at the first value that fits**. The protocol listed `0,8,16,20,24,28,32,40` run in full. Effect: at 12 GB the minimum is 20; at 8 GB the search jumps from 24 (OOM) to 32, so 28 was measured only as the article's run; 40 was never run.
  - **ngl sweep (honest baseline):** a **descending search** `-ngl 36,32,28,24,20,16,12,8` that stops at the first value that fits, plus one run 4 layers lower. The protocol listed `10,14,18,22,26`. Measured: 24 and 20 (12 GB), 16 and 12 (8 GB).
  - **Dense 27B:** `-ngl 99`, then a descending search `56,48,40,32,24,16` that stops at the first value that fits (protocol: `99,40,30,20`). Measured: 40 (12 GB), 24 (8 GB).
  - **Long context (`-d 16384`, `-r 3`):** only the best ncmoe, the article's ncmoe 28 and the best ngl; not auto-fit, not dense.
  - **Repetitions:** dense `-r 3`, CPU-only `-r 3` (protocol: 5).
  - **CPU-only:** `--cpus 10 -t 6` in the container (protocol: `--cpus 12`).
  - **Ballast:** as in §3 (torch in the vLLM image, allocates `free − 8192 MiB`). A reviewer added an explicit check that the free VRAM is 8,192 MiB (+512/−1,024) before the 8 GB phase. Measured: 8,192 MiB free.
  - **QC on desktop:** placements best ncmoe / ncmoe 28 / CPU only. There is no all-GPU reference because the model does not fit in 12 GB. No KLD on desktop.
  - **Peak RAM** via cgroup `memory.peak` does not include the memory-mapped model (already in page cache), so for RAM the Mac's max RSS is the reference.
- 2026-11-02: queued a Q8_0 reference (`Qwen3.6-35B-A3B-Q8_0.gguf`, same revision) to tell whether CPU-placed experts move the IQ4_XS output *away from* or *towards* a higher-precision model. Optional; results reported only if it fits in the Mac's Metal working set.
- 2026-11-03 (evening; decided before the run, the cool-down threshold after measuring the idle floor and before the first row; written down after the run): **clean Mac session** authorised by the author (Mac not in use, apps may be closed). Deviations from §3/§7 for this session only: user apps closed (§7 said they would not be); every d16k row at `-r 3` (CPU only had `-r 2`); cool-down of at least 120 s between rows, then wait for 1-min load < 2.0 and CPU idle ≥ 97 % (max 600 s) — the original idea of load < 1 is not reachable on this Mac (idle floor 1.44–1.80 measured at 19:47–19:50 with nothing of ours running); guard before every row and a 2 s sampler (load, swap, memory pressure level, `pmset -g therm` warnings), stop at the first swap > 0 or pressure ≥ warn; `caffeinate -dimsu` for the whole session. Runner `poc/mac-clean.sh`. QC as on 11-02. The optional Q8_0 reference runs only after the full suite, Q8_0 on Metal as KLD base, with a watchdog that kills it at swap > 0 or pressure ≥ warn.
- 2026-11-03 (after the clean session): the clean session becomes the **reference for the Mac**; 11-02 and the 11-03 morning re-test are kept as evidence of background-load noise (results and reasoning in `results/mac/RESULTS-mac.md`). Q8_0 reference done (Metal, no swap).
