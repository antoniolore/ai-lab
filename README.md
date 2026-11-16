# Debunking AI — raw data

Raw data, commands and scripts behind each episode of *Debunking AI* (working title): sensational claims about AI, rerun
with reproducible tests on stated hardware. Every published number links back to a row or a log file here.

| Episode | Claim | Verdict | Articles | Data |
|---|---|---|---|---|
| ep-001 | XDA Developers, 2026-10-22: one llama.cpp flag (`--n-cpu-moe`) lets an 8 GB GPU run a 35B MoE model "faster than I can read" | True with asterisks | {PART_A_URL} · lab notes {PART_B1_URL}, {PART_B2_URL}, {PART_B3_URL} | [`ep-001-moe-offload/`](ep-001-moe-offload/) |

## Layout of an episode folder

| File | Content |
|---|---|
| `README.md` | Claim, verdict, contents, sessions, how to read the numbers, redactions |
| `manifest.yaml` | Hardware, software (versions, commits, binary hashes), models (source, revision, sha256 — never the weights), dates |
| `PROTOCOL.md` | Protocol written before measuring, with a changelog of amendments |
| `commands.sh` | The exact commands |
| `results.csv` | Tidy data: one row per observation (one benchmark repetition) |
| `results_summary.csv`, `quality.csv` | Derived tables, regenerated from the logs by `scripts/build_csv.py` |
| `claims-to-data.md` | Every number in the articles, mapped to the data |
| `logs/` | Raw tool output: JSON, stderr, environment snapshots |
| `scripts/`, `charts/` | Scripts used at the time (sanitised) and chart sources |

## Reproducing

Each episode's `README.md` lists the steps. In short: same software release and model files (hashes in `manifest.yaml`),
the commands in `commands.sh`, then `python3 scripts/build_csv.py` to rebuild the tables from new logs.
Absolute speeds depend on the hardware; ratios between configurations on the same machine are the comparable quantity.

## Licence

- **Data** (CSV files, logs, `manifest.yaml`, `PROTOCOL.md`, `claims-to-data.md`, chart data and images, prompts):
  [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/) — see `LICENSE-DATA.md`.
- **Code** (`*.sh`, `*.py`): MIT — see `LICENSE`.

Why: CC BY 4.0 is the usual licence for open research data: anyone may reuse, chart or republish the numbers, also
commercially, as long as the source is credited — which is exactly what a fact-checking project wants (traceable reuse,
no barrier). MIT for scripts because CC licences are not designed for software; MIT is short, permissive and compatible with
llama.cpp (MIT) and the model licences (Apache-2.0). Third-party material keeps its own terms: model outputs quoted in the logs
come from Qwen3.6 (Apache-2.0); llama.cpp log lines are tool output; the quoted claim belongs to its publisher and is quoted
for commentary.

## Corrections

If an error is shown, the episode folder gets a dated entry in `CHANGELOG.md` and the article a dated correction note.
Nothing is changed silently. Error reports, with numbers: {CORRECTIONS_CONTACT}.
