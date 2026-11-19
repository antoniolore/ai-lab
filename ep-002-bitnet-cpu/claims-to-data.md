# ep-002 — claims to data (Part A)

Every measured number in Part A, with the file it comes from. Medians of 3 invocations (`scripts/summarize.py`) unless
stated. D = `results/desktop/2026-11-18/`, M = `results/mac/clean-2026-11-19/`. Declared numbers: `TRIAGE.md` § 1–3.

| Number in the article | Value | Source |
|---|---|---|
| bitnet.cpp, i7-8700K, 6 threads | 24.8 tok/s | D `raw/bn-i2s-head-t6-i{1,2,3}.json`, `summary.md` |
| llama.cpp FP16, i7-8700K | 6.8 tok/s | D `raw/ll-f16-t6-*.json` |
| ratio vs FP16, x86 | 3.65× | 24.8 / 6.8 from the unrounded medians; D `summary.md` (ratios, HEAD / stock F16, -t 6) |
| stock TQ2_0 with F16 embeddings, x86 | 24.5 tok/s → 1.01× | D `raw/ll-tq2-embf16-t6-*.json` |
| stock TQ2_0 default, x86 | 33.3 tok/s | D `raw/ll-tq2-t6-*.json` |
| Qwen2.5-1.5B Q4_K_M, x86 | 30.3 tok/s → 0.82× | D `raw/ll-qwen-q4km-t6-*.json` |
| bitnet.cpp `404980e`, M4 Max, 12 threads | 148.3 tok/s | M `raw/bn-i2s-v0-t12-*.json` |
| FP16 / TQ2_0 F16 emb. / TQ2_0 default / Qwen, M4 Max | 54.1 / 148.2 / 179.7 / 187.5 tok/s → 2.74× / 1.00× / — / 0.79× | M `raw/ll-f16-t12-*`, `ll-tq2-embf16-t12-*`, `ll-tq2-t12-*`, `ll-qwen-q4km-t12-*` |
| 0.7B pair, x86: bitnet.cpp vs F16 | 96.2 / 22.4 → 4.29× | D `raw/bn-large-i2s-head-t6-*`, `ll-large-f16-t6-*` |
| 100B layout, x86, 6 threads | 1.15 tok/s, both engines (1.153 / 1.154), one invocation | D `raw/dummy100b-bn-i2s-head-t6.json`, `raw/dummy100b-ll-tq2-t6.json` |
| 100B layout, M4 Max, 12 threads | 6.7 (bitnet.cpp) / 6.1 (stock) tok/s | M `raw/dummy100b-i2_s-t12-*`, `raw/dummy100b-tq2_0-t12-*` |
| 100B file sizes | 25.5 GB (I2_S), 26.3 GB (TQ2_0) | `results/desktop/RESULTS-desktop.md` § 100B |
| energy per token, bitnet.cpp vs FP16 | 1.60 vs 5.43 J/token net (−70.5 % net, −70.8 % gross) | D `energy/rapl.txt`, `night.log` (START–END of `energy-*` runs), idle 20.1 W; table in `results/desktop/RESULTS-desktop.md` § Energy |
| energy vs stock TQ2_0 (same weights) / vs Qwen 4-bit | −26 % / +18 % net | same |
| "about the same file size" | 1,187,801,280 bytes (2B4T I2_S) vs 1,117,320,736 bytes (Qwen Q4_K_M) | `manifest.yaml` › models |
| sanity checks (greedy output, perplexity 27.21 / 27.20 / 27.22) | — | `results/mac/2026-11-18/qc/` |
