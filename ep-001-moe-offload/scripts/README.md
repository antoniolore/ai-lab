# ep-001 — scripts

- `build_csv.py`: rebuilds `results.csv`, `results_summary.csv` and `quality.csv` from `../logs/` (standard library; run from the episode folder: `python3 scripts/build_csv.py`).
- `gguf_meta.py`: prints selected GGUF header keys (layers, experts, quantisation).
- `original/`: the runners used on 2026-11-02 and 2026-11-03 (Mac: `mac-run.sh`, `mac-retest.sh`, `mac-clean.sh`; desktop: `desktop-night.sh`; summaries: `summarize*.py`). Paths are parameterised and the site-specific inference-server stop/restore is replaced by stubs marked `[redacted]`. `summarize-mac.py` expects the original folder layout. For a rerun, start from `../commands.sh`.

Licence: MIT (`../../LICENSE`).

## Articles (ep01)

| Part | Medium | Substack |
|---|---|---|
| Part A | published 2026-11-17: {EP01_A_MEDIUM_URL} | published 2026-11-17: {EP01_A_SUBSTACK_URL} |
| Lab notes, part 1 | published 2026-11-18: {EP01_B1_MEDIUM_URL} | published 2026-11-18: {EP01_B1_SUBSTACK_URL} |
| Lab notes, part 2 | published 2026-11-19: {EP01_B2_MEDIUM_URL} | published 2026-11-19: {EP01_B2_SUBSTACK_URL} |
| Lab notes, part 3 | published 2026-11-20: {EP01_B3_MEDIUM_URL} | published 2026-11-20: {EP01_B3_SUBSTACK_URL} |

Episode overview, data and licences: [`../README.md`](../README.md).
