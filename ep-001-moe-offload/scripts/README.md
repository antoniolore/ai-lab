# ep-001 — scripts

- `build_csv.py`: rebuilds `results.csv`, `results_summary.csv` and `quality.csv` from `../logs/` (standard library; run from the episode folder: `python3 scripts/build_csv.py`).
- `gguf_meta.py`: prints selected GGUF header keys (layers, experts, quantisation).
- `original/`: the runners used on 2026-11-02 and 2026-11-03 (Mac: `mac-run.sh`, `mac-retest.sh`, `mac-clean.sh`; desktop: `desktop-night.sh`; summaries: `summarize*.py`). Paths are parameterised and the site-specific inference-server stop/restore is replaced by stubs marked `[redacted]`. `summarize-mac.py` expects the original folder layout. For a rerun, start from `../commands.sh`.

Licence: MIT (`../../LICENSE`).

## Articles (ep01)

| Part | Medium | Substack |
|---|---|---|
| Part A | <!-- link:ep01-a-medium -->[Medium](https://medium.com/@antonio.lore/one-llama-cpp-flag-and-an-8-gb-gpu-runs-a-35b-model-faster-than-reading-speed-5d2a3a0ddabe)<!-- /link --> | <!-- link:ep01-a-substack -->[Substack](https://antoniolore.substack.com/p/one-llamacpp-flag-and-an-8-gb-gpu)<!-- /link --> |
| Lab notes, part 1 | <!-- link:ep01-b1-medium -->[Medium](https://medium.com/@antonio.lore/lab-notes-part-1-rerunning-the-n-cpu-moe-claim-setup-mac-and-cpu-baselines-a82291e02935)<!-- /link --> | <!-- link:ep01-b1-substack -->[Substack](https://antoniolore.substack.com/p/lab-notes-part-1-rerunning-the-n)<!-- /link --> |
| Lab notes, part 2 | <!-- link:ep01-b2-medium -->out 2026-11-19<!-- /link --> | <!-- link:ep01-b2-substack -->out 2026-11-19<!-- /link --> |
| Lab notes, part 3 | <!-- link:ep01-b3-medium -->out 2026-11-20<!-- /link --> | <!-- link:ep01-b3-substack -->out 2026-11-20<!-- /link --> |

Episode overview, data and licences: [`../README.md`](../README.md).
