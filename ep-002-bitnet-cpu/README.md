# ep-002 — bitnet.cpp on a CPU: "100B on a single CPU", "up to 6.17x faster"

**Claim** ([a post on X](https://x.com/byteonai/status/2122717876054310952), 2026-11-17): bitnet.cpp "can run a
100B-parameter BitNet model on a single CPU, no GPU needed", "up to 6.17x faster on x86 CPUs", "up to 82.2% less energy".
The numbers come from the README of [microsoft/BitNet](https://github.com/microsoft/BitNet) and arXiv 2410.16144.

**Verdict: Misleading.** Every number exists in Microsoft's sources, but the 100B model is a random-weight dummy (no 100B
BitNet model is published) and the 6.17x is measured against 16-bit weights. On the one real model, BitNet b1.58 2B4T:
bitnet.cpp decodes 3.65x faster than llama.cpp FP16 on an i7-8700K (2.74x on an M4 Max CPU), 1.01x (1.00x) against stock
llama.cpp with the same ternary weights, and 0.82x (0.79x) against Qwen2.5-1.5B Q4_K_M. A 100B random-weight layout decodes
at 1.15 tok/s on the i7-8700K and 6.7 / 6.1 tok/s on the M4 Max, in both engines.

## Articles

| Part | Medium | Substack |
|---|---|---|
| Part A — the short version | <!-- link:ep02-a-medium -->out 2026-11-25<!-- /link --> | <!-- link:ep02-a-substack -->[Substack](https://antoniolore.substack.com/p/bitnetcpp-100b-on-one-cpu-up-to-617)<!-- /link --> |
| Lab notes, part 1 — sources, protocol, setup | <!-- link:ep02-b1-medium -->out 2026-11-26<!-- /link --> | <!-- link:ep02-b1-substack -->[Substack](https://antoniolore.substack.com/p/lab-notes-part-1-where-100b-617x)<!-- /link --> |
| Lab notes, part 2 — results, the 100B layout, energy, verdict | <!-- link:ep02-b2-medium -->out 2026-11-27<!-- /link --> | <!-- link:ep02-b2-substack -->out 2026-11-27<!-- /link --> |

Links are filled in after each release. Error reports, with numbers: as a GitHub Issue in this repository (https://github.com/antoniolore/ai-lab/issues) or in the comments of the articles.

## Contents

| Path | What |
|------|------|
| `manifest.yaml` | Hardware, software (releases, commits, binary hashes), models (repo, bytes, sha256), dates, redactions |
| `TRIAGE.md` | The claim traced to its sources (README, arXiv 2410.16144 and 2502.11880, model cards), read before the bench |
| `PROTOCOL.md` | Test protocol, written on 2026-11-18 before any measurement; amendments in its changelog |
| `commands.sh` | The exact benchmark commands, by machine |
| `claims-to-data.md` | The numbers of Part A, mapped to the files below |
| `results/desktop/2026-11-18/` | Intel i7-8700K, night of 2026-11-18 → 19: `raw/` (llama-bench JSON, one file per invocation), `time/` (GNU `time -v`), `energy/rapl.txt`, `summary.md`, `night.log`, `env.txt` |
| `results/desktop/RESULTS-desktop.md` | Consolidated x86 results, ratios and energy table |
| `results/mac/clean-2026-11-19/` | MacBook Pro M4 Max, **clean session** (reference for every Mac speed figure): `raw/`, `time/` (`/usr/bin/time -l`), `summary.md`, `run.log`, `env*.txt` |
| `results/mac/2026-11-18/` | First Mac session (apps open, not used for speed figures); its `qc/` holds the sanity checks (greedy output, perplexity) |
| `results/mac/RESULTS-mac.md` | Consolidated Mac results, both sessions |
| `scripts/summarize.py` | Medians and ratios from `raw/` and `time/` (the `summary.md` files) |
| `scripts/gen_dummy_bitnet.py` | Writes the 100B random-weight layout directly in TQ2_0 or I2_S (timing only) |
| `scripts/desktop-night.sh`, `scripts/mac-run.sh`, `scripts/Dockerfile` | The runners used at the time (paths parameterised, host-specific parts redacted) |
| `patches/` | The three patches (ARM build fix, clang const fix, 2B4T conversion for stock llama.cpp as a speed proxy) |
| `prompts/` | The two greedy prompts |
| `env/` | sha256 of downloads and of every model file used in the night run |

## How to read the numbers

- Speeds are llama-bench `avg_ts` per invocation (5 repetitions each, `-p 512 -n 128`); the articles use the **median of 3
  invocations** (`scripts/summarize.py`). Row names: `bn-*` = bitnet.cpp (`head` = `0b341e5`, `v0` = `404980e`,
  `01eb415`), `ll-*` = stock llama.cpp b12503; `large` = the 0.7B `bitnet_b1_58-large`; `-t<N>` = threads; `-i<N>` = invocation.
- **Stock llama.cpp rows on 2B4T are speed proxies**: stock llama.cpp loads 2B4T only with the conversion patch and then
  writes degenerate text (wrong activation). Same bytes and matrix sizes, never a quality comparison. The 0.7B pair runs
  correctly in both engines.
- `dummy100b-*`: random ternary weights in the report's 100B layout (≈100.2B parameters). x86: one invocation of 3
  repetitions (`-p 64 -n 32`); Mac: 3 invocations.
- Energy (x86 only): RAPL package counter before and after each decode-only invocation (`-p 0 -n 256 -r 3`), one invocation
  per row, idle power (20.1 W) subtracted for the net figure. The counter covers the whole host.
- `*-INVALID-*` files (Mac): bitnet.cpp commits that give invalid output on Apple Silicon; kept as evidence, never used.

## Reproduce

1. Get llama.cpp release b12503 (prebuilt CPU binaries, hashes in `env/sha256-downloads.txt`) and build bitnet.cpp at the
   commits in `manifest.yaml` (patches in `patches/`).
2. Download the model files listed in `manifest.yaml` and check the sha256; convert and quantise 2B4T as in `PROTOCOL.md` § 2.
3. Optional: write the 100B layouts with `scripts/gen_dummy_bitnet.py` (about 26 GB each).
4. Run `commands.sh` (read it first), then `python3 scripts/summarize.py <results-dir>`.
Absolute speeds depend on the hardware; ratios between configurations on the same machine are the comparable quantity.

## Redactions

Absolute paths and user names were replaced (`$LAB`, `~`); the Linux host is called `desktop`. In `env.txt` files the lists
of other containers, user services, processes and applications are replaced by a count. In `scripts/desktop-night.sh` the
code that stopped and restarted the operator's local inference server is replaced by stubs marked `[redacted]`; the post-run
notification script is not included. Crew names in the notes are replaced by roles. Not included: model weights, binaries,
the perplexity text (written on the test day; its sha256 is in `env/fresh-text.sha256`). No measured value was changed.
