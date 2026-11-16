# ai-lab

Raw data, scripts and protocols behind the AI-claims reruns by Antonio Lorè: sensational claims about AI, rerun with
reproducible tests on stated hardware. Every published number links back to a row or a log file here.

## Articles

| Episode | Topic | Medium | Substack | Data |
|---|---|---|---|---|
| ep00 | Glossary: what "7B", "4-bit" and "MoE" actually mean | [Medium](https://medium.com/@antonio.lore/what-7b-4-bit-and-moe-actually-mean-an-ai-glossary-for-checking-viral-claims-b642abf6d063) | — | none (no test) |
| ep01 Part A | One llama.cpp flag (`--n-cpu-moe`), an 8 GB GPU and a 35B MoE model. Verdict: True with asterisks | published 2026-11-17: {EP01_A_MEDIUM_URL} | published 2026-11-17: {EP01_A_SUBSTACK_URL} | [`ep-001-moe-offload/`](ep-001-moe-offload/) |
| ep01 Lab notes 1 | Setup, Mac and CPU baselines | published 2026-11-18: {EP01_B1_MEDIUM_URL} | published 2026-11-18: {EP01_B1_SUBSTACK_URL} | [`ep-001-moe-offload/`](ep-001-moe-offload/) |
| ep01 Lab notes 2 | RTX 3080 at 12 GB and emulated 8 GB | published 2026-11-19: {EP01_B2_MEDIUM_URL} | published 2026-11-19: {EP01_B2_SUBSTACK_URL} | [`ep-001-moe-offload/`](ep-001-moe-offload/) |
| ep01 Lab notes 3 | Quality, `--fit` default, verdict | published 2026-11-20: {EP01_B3_MEDIUM_URL} | published 2026-11-20: {EP01_B3_SUBSTACK_URL} | [`ep-001-moe-offload/`](ep-001-moe-offload/) |

Links marked "published <date>" are filled in after each release. Every code or data folder in this repository has a README with
the links to its articles.

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
Nothing is changed silently. Error reports, with numbers: as a GitHub Issue in this repository (https://github.com/antoniolore/ai-lab/issues) or in the comments of the articles.
