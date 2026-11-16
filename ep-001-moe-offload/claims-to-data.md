# ep-001 — claims to data

Every number in the published text, mapped to the row or log line it comes from.
Checked on 2026-11-16 against `results_summary.csv`, `quality.csv` and the files in `logs/`
(regenerate the CSVs with `python3 scripts/build_csv.py`). Ratios are recomputed from the means in `results_summary.csv`.

Key to the "Where" column: `S:<session>/<run_id>/<test>` = a row of `results_summary.csv` (column `mean_ts` unless stated);
`Q:<session>/<check>/<placement>/<metric>` = a row of `quality.csv`; a path = a file in this folder.
Status: **OK** = matches the data · **EXT** = not a measurement of this bench (declared by the source article or an external spec) ·
**NOTES** = recorded in the lab notes at the time, no raw log in this folder · **FIX** = does not match the data (see the end).

Sessions: `n` = `2026-11-02-night` (desktop, RTX 3080), `day` = `2026-11-02-day` (desktop, CPU only),
`c` = `2026-11-03-clean` (Mac reference), `am` = `2026-11-03-am` (Mac), `m1` = `2026-11-02` (Mac).

## Part A — the short version

| Text | Value in text | Where | Data | Status |
|---|---|---|---|---|
| XDA: with the flag / without | 32.82 / 4.02 t/s | source article table (`manifest.yaml` › claim) | — | EXT |
| Implied speed-up | ≈ 8× | 32.82 / 4.02 | 8.16 | OK (computed) |
| Article's setting at 8 GB | 36.1 t/s | S:n/8g-article-ncmoe28/tg128 | 36.14 ± 0.24 | OK |
| Same, 16k context | 36.3 t/s ("16,000 tokens") | S:n/8g-article-ncmoe28-d16k/tg128 | 36.29 ± 0.29 (depth 16384) | OK |
| Model file size | 17.7 GB | `manifest.yaml` › models (bytes) | 17,730,509,792 B | OK |
| "Before" without the flag | did not load, out of memory | S:n/8g-article-ncmoe0 and 12g-article-ncmoe0 (status failed, `out_of_memory_at_load`); `logs/desktop/2026-11-02-night/raw/8g-article-ncmoe0.stderr.txt` | cudaMalloc 16,383.34 MiB failed | OK |
| Classic offload at 8 GB | 15.9 t/s | S:n/8g-ngl16/tg128 | 15.85 ± 0.04 | OK |
| Gain vs fair setup, generation | 2.3× | 36.14 / 15.85 | 2.28 | OK |
| Gain, prompt | ~1.1× | S:n/8g-article-ncmoe28/pp512 ÷ S:n/8g-ngl16/pp512 | 564.27 / 503.99 = 1.12 | OK |
| CPU only, desktop | 9.4 t/s | S:n/cpu-d0/tg128 | 9.39 ± 0.04 | OK |
| CPU only, Mac | 47.8 t/s | S:c/mac-cpu-d0/tg128 | 47.79 ± 0.41 | OK |
| Dense 27B at 8 GB | 3.1 t/s | S:n/8g-dense-ngl24/tg128 | 3.12 ± 0.00 | OK |
| Dense 27B on the Mac GPU | 19.8 t/s | S:c/mac-dense-d0/tg128 | 19.81 ± 0.44 | OK |
| Auto-fit at 8 GB | 38.0 t/s | S:n/8g-fit/tg128 | 38.02 ± 0.47 | OK |
| Mac, flag vs all-GPU, generation | "about half the speed" | S:c/mac-ncmoe28-d0/tg128 ÷ S:c/mac-gpu-d0/tg128 | 46.10 / 89.35 = 0.52 | OK |
| Mac, prompt | 2.6× slower | S:c/mac-gpu-d0/pp512 ÷ S:c/mac-ncmoe28-d0/pp512 | 1661.91 / 629.83 = 2.64 | OK |
| Mac, short context: flag ≈ CPU only | "no faster" | S:c/mac-ncmoe28-d0/tg128 vs S:c/mac-cpu-d0/tg128 | 46.10 ± 1.97 vs 47.79 ± 0.41 | OK |
| Same top word (Mac, `-ncmoe 28`) | 97% | Q:c/kld_fresh_text_7x512/ncmoe28/same_top1_pct | 97.367 ± 0.379 | OK |
| Identical answers on the RTX 3080 (ncmoe 20 vs 28) | word-for-word | Q:n/greedy-1 and greedy-2/ncmoe28/identical_prefix_chars | 799 of 799, 706 of 706 | OK |
| Mac memory in use | "up to about 20 GB" | `max_rss_gib`, Mac rows of `results_summary.csv` | max 19.26 GiB = 20.7 GB | OK |
| Reading speed | ~5–6 t/s | Brysbaert (2019), 238 words/min × ~1.3 tokens/word | — | EXT |
| Tested on | "November 2, 2026" | dates in `manifest.yaml` | desktop runs 2026-11-02; Mac reference session and Q8_0 check 2026-11-03 | see note 5 |

## Part B1 — setup, Mac and CPU baselines

| Text | Value in text | Where | Data | Status |
|---|---|---|---|---|
| XDA table (27B 38.83/0.75; 35B ncmoe 0 109.66/4.02; ncmoe 28 341.37/32.82; sizes 14.37/16.50 GiB) | | source article | — | EXT |
| Ratios from XDA table | 8.2× tg, 3.1× pp | 32.82/4.02, 341.37/109.66 | 8.16, 3.11 | OK (computed) |
| Model structure | 40 layers, 256 experts, 8 active | `model-metadata.txt` (GGUF header) | block_count 40, expert_count 256, expert_used_count 8 | OK, see note 4 |
| Reading speed | 238 words/min | Brysbaert (2019) | — | EXT |
| Mac hardware (Mac16,6, 12P+4E, 40-core GPU, 48 GB) | | `logs/mac/env-hardware.txt` | as stated | OK |
| Metal working set | 40,200 MB | any `logs/mac/*/raw/*.stderr.txt` | 40200.90 MB | OK |
| macOS 27.0.1; Linux 7.2.5; Z370, PCIe Gen3 x16; 62 GB DDR4 | | lab notes | — | NOTES |
| NVIDIA driver | 610.57.04 | `logs/desktop/2026-11-02-night/env-nvidia.txt` | 610.57.04 | OK |
| CUDA-visible VRAM | 11,887 MiB | night `raw/*.stderr.txt` | 11887 MiB | OK |
| GPU in use with server stopped | 479 MiB | `logs/desktop/2026-11-02-night/night.log` | 479 MiB | OK |
| Clean-session idle floor | load ≥ 1.44 (1.44–1.80), CPU 98–99 % idle | `scripts/original/mac-clean.sh` comment (measured 19:47–19:50, before the sampler started) | 1.44–1.80, 97.8–99.4 % | NOTES |
| Day CPU run, load before the run | 2.28 | `logs/desktop/2026-11-02-day/raw/desktop-cpu6-d0.env.txt` | **2.24** (10:54:00) | **FIX** (note 3) |
| llama.cpp release / commit | b12034, `1c5ed702c…` | every JSON (`build_number`, `build_commit`) | 12034, 1c5ed702c | OK |
| Model files | 17,730,509,792 B (16.51 GiB); 15,440,005,344 B (14.38 GiB); revisions | `manifest.yaml` › models | as stated | OK |
| Repetitions | 5 at d0, 3 at 16k (clean), 3 for desktop CPU/dense | `n_reps` in `results_summary.csv` | as stated | OK |
| Earlier sessions' reps at 16k | 5 all-GPU and flag, 2 CPU only | S:m1 and S:am d16k rows, `n_reps` | 5, 5, 2 | OK |
| Mac clean table (18 values ± sd) | 1661.91 … 18.41 | S:c/mac-*/pp512, tg128 | all match to 2 decimals | OK |
| Anomalous repetition, flag at 16k | 30.1, 41.3, 41.8; median 41.3 | `results.csv` rows S:c/mac-ncmoe28-d16k/tg128 | 30.08, 41.26, 41.84 | OK |
| Max RSS, clean | 16.5–19.2 GiB (35B), 14.6–16.0 GiB (dense) | `max_rss_gib`, S:c rows | 16.50–19.25, 14.56–15.98 | OK |
| Peak memory footprint | 0.4–3.3 GiB | `peak_footprint_gib`, all Mac rows | **0.41–3.11 GiB** (= 0.44–3.34 GB) | **FIX** (note 2) |
| Three-session table (36 values) | | S:m1, S:am, S:c | all match | OK |
| Noise on GPU path | −2 % tg, 0 % pp (am → clean) | S:am vs S:c mac-gpu-d0 | −2.3 %, +0.07 % | OK |
| Noise on CPU paths | +62 % CPU only, +51 % flag | S:am vs S:c mac-cpu-d0 / mac-ncmoe28-d0 tg128 | +62.4 %, +50.8 % | OK |
| Nov 2 all-GPU prompt | −21 % vs clean | S:m1 vs S:c mac-gpu-d0/pp512 | −20.6 % | OK |
| Largest between-session move | +112 % | S:m1 vs S:c mac-cpu-d0/tg128 | 22.54 → 47.79 = +112 % | OK |
| Mac slowdown, clean session | 1.94× / 1.93× tg; 1.76× on the 16k median; 2.64× / 1.81× pp | S:c mac-gpu ÷ mac-ncmoe28 | 1.938, 1.931, 72.86/41.26 = 1.766, 2.639, 1.813 | OK |
| Mac slowdown across three sessions | "1.9–3× slower, at every depth and for both metrics" | S:m1, S:am, S:c mac-gpu ÷ mac-ncmoe28 | generation 1.93–2.99×; **prompt 1.70–2.82×** (1.70× at 16k on Nov 2 and Nov 3 am) | **FIX** (note 1) |
| Flag ≈ CPU only at d0; flag faster at 16k | 47.79 vs 46.10; 37.73 (median 41.3) vs 24.62 | S:c rows | as stated | OK |
| Flag on Mac across sessions | 30.58–46.10 t/s | S:m1, S:am, S:c mac-ncmoe28-d0/tg128 | 34.53, 30.58, 46.10 | OK |
| All experts on CPU | 25.81 t/s | S:c/mac-cmoe-d0/tg128 | 25.81 ± 0.22 | OK |
| Long context, flag | 46.10 → 37.73 (median 41.3) | S:c mac-ncmoe28 d0/d16k | as stated | OK |
| Desktop CPU only, day / night | 52.07 ± 0.89, 8.54 ± 0.34 / 60.62 ± 0.95, 9.39 ± 0.04 | S:day/desktop-cpu6-d0, S:n/cpu-d0 | as stated | OK |
| Day / night run times | ~10:55 / ~22:46 CET | JSON `test_time` (09:54Z) / `night.log` (22:46:17) | as stated | OK |

## Part B2 — RTX 3080, 12 GB and emulated 8 GB

| Text | Value in text | Where | Data | Status |
|---|---|---|---|---|
| Window | 22:15–22:48 CET | `night.log` | 22:15:00–22:48:46 | OK |
| VRAM ballast; free before 8 GB phase | 3,092,840,448 B; 8,192 MiB | `night.log` | as stated | OK |
| Bandwidth RTX 3080 / RTX 3070 Mobile | 760 / 448 GB/s | NVIDIA specifications (not measured) | — | EXT (note 6) |
| 12 GB table (pp, tg, 16k, VRAM used ~7.1…~10.3) | | S:n/12g-* rows, `vram_used_gib` | all match | OK |
| 8 GB table (pp, tg, 16k, VRAM used ~5.7…~7.2) | | S:n/8g-* rows, `vram_used_gib` | all match | OK |
| Sweep: ncmoe 4–24 do not fit at 8 GB | | S:n/8g-ncmoe4…24 status failed | 6 of 6 failed | OK |
| Failures | 28 runs; 27 OOM at load; 1 crash | `status`/`fail_reason` in `results_summary.csv` | 28; 27 `out_of_memory_at_load`; 1 segfault | OK |
| Failure groups | ncmoe 0 both; 4–16 at 12 GB; 4–24 at 8 GB; ngl ≥ 28 / ≥ 20; dense ≥ 48 / ≥ 40 | failed rows | as stated | OK |
| Weights buffer | 16,383 MiB | `raw/12g-article-ncmoe0.stderr.txt` | 16383.34 MiB | OK |
| Ratios | 2.28×, 2.21×, 1.12×, 1.06×, 2.78×, 2.50×, 3.85×, 11.6× | S:n rows | 2.280, 2.209, 1.120, 1.061, 2.777, 2.501, 3.849, 11.58 | OK |
| Auto-fit vs flag at 8 GB | +5 % tg, +17 % pp | S:n/8g-fit vs 8g-article-ncmoe28 | +5.2 %, +16.7 % | OK |
| Auto-fit vs best at 12 GB | 48.69 vs 47.79; +25 % pp | S:n/12g-fit vs 12g-ncmoe20 | +25.4 % pp | OK |
| Container memory peak | 0.3–0.9 GiB | `raw/*.mempeak.bytes` (successful runs) | 0.29–0.91 GiB | OK |
| Mac RSS (Nov 2 session) | 16.6–18.8 GiB at d0, up to 19.0 at 16k | `max_rss_gib`, S:m1 35B rows | 16.56–18.77; 18.95 | OK |
| Recap: Mac across three sessions | "1.9–3× across three sessions" | as B1 | true for generation only | **FIX** (note 1) |

## Part B3 — quality, auto-fit, limits, verdict

| Text | Value in text | Where | Data | Status |
|---|---|---|---|---|
| Mac PPL Alice | 1.0963 / 1.0948 / 1.0975 (± 0.0057/0.0056/0.0059) | Q:c/ppl_alice_16x2048 | as stated | OK |
| Mac KLD vs all-GPU | 0.00234 ± 0.00013; 0.00928 ± 0.00038; p99.9 0.00005 / 0.0518 / 0.1509 | Q:c/kld_fresh_text_7x512 | as stated | OK |
| Mac top-1 agreement | 97.37 ± 0.38 %; 92.33 ± 0.63 % | Q:c/…/same_top1_pct | as stated | OK |
| Mac greedy prefixes | 107 of 824; 0 (first token); 636 of 689 (both) | Q:c/greedy-* | as stated | OK |
| Desktop PPL | 1.0969 / 1.0969 / 1.0943 | Q:n/ppl_alice_16x2048 | as stated | OK |
| Desktop greedy | 799/799, 706/706; 283 of 799, 636 of 706 | Q:n/greedy-* | as stated | OK |
| Mac QC bit-identical Nov 2 vs clean | | `logs/mac/2026-11-02/qc` vs `logs/mac/2026-11-03-clean/qc` | six greedy outputs byte-identical; same PPL/KLD | OK |
| Q8_0 file | 36,903,140,320 B | `manifest.yaml` | as stated | OK |
| Q8_0 own PPL | 8.610 ± 0.554 | `logs/mac/2026-11-03-clean/q8/kld-base-q8-gpu.txt` | 8.6102 ± 0.55367 | OK |
| Q8_0 table | 8.667/8.680/8.720; 1.0076/1.0092/1.0138 (± 0.0080/0.0081/0.0081); 0.03469/0.03471/0.03490; 0.898/0.654/0.650; 87.68/88.01/88.12 % | Q:c/q8_0_reference_fresh_text_7x512 | as stated | OK |
| Quantisation vs placement | "4–15 times larger" | 0.0347 / 0.00928 and 0.0347 / 0.00234 | 3.7× and 14.9× | OK (3.7 rounded to 4) |
| PPL drift all-GPU → CPU | +0.6 % | 8.720 / 8.667 | +0.61 % | OK |
| Auto-fit | 38.02 at 8 GB, 48.69 at 12 GB | S:n/8g-fit, 12g-fit | as stated | OK |
| OOM crash | `8g-dense-ngl32`, `ggml_cuda_mul_mat_q`, `mmq.cu:283`, segfault | `logs/desktop/2026-11-02-night/raw/8g-dense-ngl32.stderr.txt`, `cmd.txt` rc=139 | as stated | OK |
| Limits: Mac noise | +62 %, +51 %, −2 % | as B1 | as B1 | OK |
| Verdict items | 36 t/s; 2.3× (2.2× at 12 GB); ~1.1×; 3.8×; 9.4; 47.8; 3.1; 19.8; 38.0 vs 36.1 | as above | as above | OK |
| Verdict item 5 | "≈1.9× … 1.8–2.6× (clean); 1.9–3× across three sessions" | as B1 | generation only | **FIX** (note 1) |

## Items to fix (status at 2026-11-16)

1. **Mac slowdown across the three sessions — "1.9–3×, at every depth and for both metrics" (B1 § 6).**
   Prompt processing at depth 16384 was 1.70× slower on Nov 2 (701.41 / 413.79) and 1.70× on Nov 3 morning (809.13 / 475.61).
   Correct range across sessions: generation 1.93–2.99×, prompt processing 1.70–2.82×; both metrics together **1.7–3×**.
   The same "1.9–3× across three sessions" in the B2 recap, B3 verdict item 5 and the changelogs is correct only if read as
   generation. Suggested text: "1.9–3× slower in generation and 1.7–2.8× in prompt processing across three sessions".
2. **Peak memory footprint "0.4–3.3 GiB" (B1 § 6, Memory).** The raw files give 0.41–3.11 GiB (0.44–3.34 GB): the upper value
   is in GB, not GiB. Suggested: "0.4–3.1 GiB".
3. **Day CPU run, "1-min load 2.28 before the run" (B1 § 3 hardware card and § 7 table).** The only logged value is 2.24
   (`uptime` at 10:54:00, `desktop-cpu6-d0.env.txt`). Suggested: "2.24".
4. **"[measured: llama-bench model metadata]" (B1 § 1).** The values (40 layers, 256 experts, 8 active) are right, but llama-bench
   does not print them; they come from the GGUF header (`model-metadata.txt`). Suggested tag: "[measured: GGUF metadata]".
5. **"Tested on … November 2, 2026" (verdict card, all parts).** The desktop runs are from Nov 2; the Mac figures used in the text
   (clean session) and the Q8_0 check are from Nov 3. Suggested: "November 2–3, 2026".
6. **RTX 3080 / RTX 3070 Mobile bandwidth (B2 § 8).** 760 and 448 GB/s are vendor specifications, not measurements: fine as
   context, but the source should be cited.
