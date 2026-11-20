# ep-001 — raw logs

| Folder | Content |
|---|---|
| `mac/2026-11-02/`, `mac/2026-11-03-am/`, `mac/2026-11-03-clean/` | MacBook Pro M4 Max: `raw/` llama-bench JSON, `.cmd.txt` (command + exit code), `.stderr.txt` (with `/usr/bin/time -l`), `.env.txt` / `.post.txt` snapshots; `qc/` greedy, perplexity, KLD; `q8/` Q8_0 reference; guard and sampler logs |
| `desktop/2026-11-02-day/`, `desktop/2026-11-02-night/` | Linux desktop, RTX 3080: `raw/` JSON, `.cmd.txt`, `.stderr.txt`, `.vram.txt` (nvidia-smi every 200 ms), `.mempeak.bytes`, `.failed` markers; `qc/`; `night.log`; `env-nvidia.txt` |

Redactions are listed in `../README.md`. Licence: CC BY 4.0 (`../../LICENSE-DATA.md`).

## Articles (ep01)

| Part | Medium | Substack |
|---|---|---|
| Part A | <!-- link:ep01-a-medium -->[Medium](https://medium.com/@antonio.lore/one-llama-cpp-flag-and-an-8-gb-gpu-runs-a-35b-model-faster-than-reading-speed-5d2a3a0ddabe)<!-- /link --> | <!-- link:ep01-a-substack -->[Substack](https://antoniolore.substack.com/p/one-llamacpp-flag-and-an-8-gb-gpu)<!-- /link --> |
| Lab notes, part 1 | <!-- link:ep01-b1-medium -->[Medium](https://medium.com/@antonio.lore/lab-notes-part-1-rerunning-the-n-cpu-moe-claim-setup-mac-and-cpu-baselines-a82291e02935)<!-- /link --> | <!-- link:ep01-b1-substack -->[Substack](https://antoniolore.substack.com/p/lab-notes-part-1-rerunning-the-n)<!-- /link --> |
| Lab notes, part 2 | <!-- link:ep01-b2-medium -->[Medium](https://medium.com/@antonio.lore/lab-notes-part-2-the-rtx-3080-at-12-gb-and-emulated-8-gb-9bf333287983)<!-- /link --> | <!-- link:ep01-b2-substack -->[Substack](https://antoniolore.substack.com/p/lab-notes-part-2-the-rtx-3080-at)<!-- /link --> |
| Lab notes, part 3 | <!-- link:ep01-b3-medium -->[Medium](https://medium.com/@antonio.lore/lab-notes-part-3-answer-quality-the-fit-default-and-the-verdict-76a988537da4)<!-- /link --> | <!-- link:ep01-b3-substack -->[Substack](https://antoniolore.substack.com/p/lab-notes-part-3-answer-quality-the)<!-- /link --> |

Episode overview, data and licences: [`../README.md`](../README.md).
