# ep-001 — llama.cpp MoE expert offload (`--n-cpu-moe`)

**Claim** (Abhinav Raj, XDA Developers, 2026-10-22): "I changed one llama.cpp flag, and my 8GB laptop GPU now runs a 35B model
faster than I can read" — [source](https://www.xda-developers.com/i-stopped-thinking-my-8gb-gpu-was-too-small-after-learning-to-offload-moe-llm-layers-to-ram/).

**Verdict: True with asterisks.** With 8 GB of free VRAM, Qwen3.6-35B-A3B runs at 36.14 t/s with the article's `-ncmoe 28`;
the no-flag "before" does not load on Linux (out of memory); against the most whole layers that fit (`-ngl 16`, 15.85 t/s)
the flag's gain is 2.28×, not the 8× implied by the article's table.

## Articles

| Part | Medium | Substack |
|---|---|---|
| Part A — the short version | <!-- link:ep01-a-medium -->[Medium](https://medium.com/@antonio.lore/one-llama-cpp-flag-and-an-8-gb-gpu-runs-a-35b-model-faster-than-reading-speed-5d2a3a0ddabe)<!-- /link --> | <!-- link:ep01-a-substack -->[Substack](https://antoniolore.substack.com/p/one-llamacpp-flag-and-an-8-gb-gpu)<!-- /link --> |
| Lab notes, part 1 — setup, Mac and CPU baselines | <!-- link:ep01-b1-medium -->[Medium](https://medium.com/@antonio.lore/lab-notes-part-1-rerunning-the-n-cpu-moe-claim-setup-mac-and-cpu-baselines-a82291e02935)<!-- /link --> | <!-- link:ep01-b1-substack -->[Substack](https://antoniolore.substack.com/p/lab-notes-part-1-rerunning-the-n)<!-- /link --> |
| Lab notes, part 2 — RTX 3080, 12 GB and emulated 8 GB | <!-- link:ep01-b2-medium -->[Medium](https://medium.com/@antonio.lore/lab-notes-part-2-the-rtx-3080-at-12-gb-and-emulated-8-gb-9bf333287983)<!-- /link --> | <!-- link:ep01-b2-substack -->[Substack](https://antoniolore.substack.com/p/lab-notes-part-2-the-rtx-3080-at)<!-- /link --> |
| Lab notes, part 3 — quality, `--fit` default, verdict | <!-- link:ep01-b3-medium -->[Medium](https://medium.com/@antonio.lore/lab-notes-part-3-answer-quality-the-fit-default-and-the-verdict-76a988537da4)<!-- /link --> | <!-- link:ep01-b3-substack -->[Substack](https://antoniolore.substack.com/p/lab-notes-part-3-answer-quality-the)<!-- /link --> |

Links are filled in after each release. Error reports, with numbers: as a GitHub Issue in this repository (https://github.com/antoniolore/ai-lab/issues) or in the comments of the articles.

## Contents

| Path | What |
|------|------|
| `manifest.yaml` | Hardware, software (release, commit, binary hashes), models (repo, revision, bytes, sha256), texts, dates, redactions |
| `PROTOCOL.md` | Test protocol, written on 2026-11-02 before any measurement; amendments in its changelog |
| `commands.sh` | The exact commands, grouped by machine and phase |
| `results.csv` | Tidy: one row per llama-bench repetition (440 rows: 412 measurements + 28 failed runs) |
| `results_summary.csv` | One row per run and test: mean and sd as reported by llama-bench, median, min, max, VRAM used, max RSS |
| `quality.csv` | Perplexity, KL divergence, top-1 agreement, greedy-output identical prefixes |
| `claims-to-data.md` | Every number in the articles, mapped to a CSV row or a log file |
| `model-metadata.txt` | GGUF header keys of the three model files (layers, experts, quantisation) |
| `prompts/` | The two greedy prompts |
| `charts/` | Chart data (`*.csv`), plotting script, draft SVGs |
| `logs/mac/<session>/` | MacBook Pro M4 Max: `raw/` (llama-bench JSON, `.cmd.txt`, `.stderr.txt` with `/usr/bin/time -l`, `.env.txt` / `.post.txt` snapshots), `qc/`, `q8/`, guard and sampler logs |
| `logs/desktop/<session>/` | Linux desktop, RTX 3080: `raw/` (JSON, command + exit code, stderr, VRAM samples every 200 ms, container memory peak), `qc/`, `night.log`, `env-nvidia.txt` |
| `scripts/build_csv.py` | Regenerates the three CSV files from `logs/` (standard library only) |
| `scripts/gguf_meta.py` | Reads GGUF header keys |
| `scripts/original/` | The runners used at the time (paths parameterised, see below) |

## Sessions

| Session | Machine | When (CET) | Notes |
|---|---|---|---|
| `2026-11-02` | Mac | 2026-11-02 morning | Machine in daily use (Steam/Wine running) |
| `2026-11-03-am` | Mac | 2026-11-03 11:40–11:49 | Main rows only; browser renderer ~1 core, screen sharing active |
| `2026-11-03-clean` | Mac | 2026-11-03 19:50–20:42 | **Mac reference**: user apps closed, 120 s cool-down, guard and 2 s sampler; QC and Q8_0 reference |
| `2026-11-02-day` | Desktop | 2026-11-02 ~10:54 | CPU only, container `--cpus 6`, other services running |
| `2026-11-02-night` | Desktop | 2026-11-02 22:15–22:48 | RTX 3080 at 12 GB and emulated 8 GB, QC, CPU only; resident inference server stopped |

Run names: `mac-gpu` (`-ngl 99 -ncmoe 0`), `mac-ncmoe28` (article), `mac-cmoe` (`-ncmoe 99`), `mac-nglhalf` (`-ngl 20`),
`mac-cpu` (`-ngl 0 -dev none`), `mac-dense` (27B, `-ngl 99`); suffix `-d0` / `-d16k` = depth. Desktop: `12g-` / `8g-` = VRAM budget,
`article-ncmoe0/28` = the article's command, `ncmoeN` / `nglN` = sweeps, `fit` = `-fitt 1024`, `dense-nglN` = 27B.
The full flags of every run are in its `.cmd.txt` and in the JSON.

## How to read the numbers

- `tokens_per_s` in `results.csv` is llama-bench's per-repetition `samples_ts`; `mean_ts` / `sd_ts` in `results_summary.csv` are
  llama-bench's own `avg_ts` / `stddev_ts`. `pp512` = prompt processing of 512 tokens, `tg128` = generation of 128 tokens.
- `vram_used_gib` (desktop): peak of `nvidia-smi memory.used` sampled every 200 ms minus the first sample of the same file
  (taken before the container starts), in GiB.
- `max_rss_gib` (Mac): maximum resident set size from `/usr/bin/time -l`; it includes the memory-mapped model file.
  `peak_footprint_gib`: macOS "peak memory footprint" (excludes file-backed pages).
- The desktop container memory peak (`*.mempeak.bytes`) does not include the memory-mapped model.
- Failed runs are data: `status = failed`, reason in `fail_reason`, stderr in the log.

## Reproduce

1. Get llama.cpp release b12034 and the model files listed in `manifest.yaml`; check the sha256 hashes.
2. Get `pg11.txt` from Project Gutenberg (hash of the copy used in `manifest.yaml`). The KLD text is not published
   (see `manifest.yaml` › texts): any text written after the model's release works, absolute KLD values will differ.
3. Run the blocks in `commands.sh` (read it first). On a discrete GPU, free the GPU before running; for the 8 GB budget hold a
   VRAM block so that exactly 8,192 MiB stay free.
4. Regenerate the tables from your logs with `scripts/build_csv.py` (same folder layout).

## Redactions

Absolute paths and user names were replaced (`~/moe-offload-lab`, `$LAB`); the desktop's host name is `desktop`; internal
container and service names were replaced. In process snapshots, commands are reduced to their base name and a few
third-party utilities are shown as `[redacted: third-party utility]`. The night runner's code that stopped and restarted the
operator's local inference server is replaced by stubs marked `[redacted]`. Not included: the full process lists taken before
apps were closed on the Mac, an internal notification script, the KLD logit files (`.bin`), model weights and binaries.
No measured value was changed.
