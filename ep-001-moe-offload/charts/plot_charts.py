#!/usr/bin/env python3
"""Chart data and draft charts for ep-001, built from ../results_summary.csv.

Usage (from the episode folder):  python3 charts/plot_charts.py
Writes charts/claim-vs-reality.csv and charts/mac-placements.csv (always, standard library only)
and, if matplotlib is installed, charts/claim-vs-reality.svg and charts/mac-placements.svg.
The published article charts are designed separately from these CSVs; the SVGs are plain drafts.
"""
import csv
from pathlib import Path

EP = Path(__file__).resolve().parent.parent
OUT = EP / "charts"
S = {}
for r in csv.DictReader(open(EP / "results_summary.csv")):
    S[(r["session"], r["run_id"], r["test"])] = r

NIGHT, CLEAN = "2026-11-02-night", "2026-11-03-clean"

# 1. Claim vs Reality: tg128 (tokens/s), 8 GB budget
claim_rows = [
    # label, kind, value, note
    ("XDA, without the flag (-ncmoe 0)", "declared", "4.02", "RTX 3070 Mobile 8 GB, Windows (article table)"),
    ("XDA, -ncmoe 28", "declared", "32.82", "RTX 3070 Mobile 8 GB, Windows (article table)"),
]
for label, run, note in (
    ("Without the flag (-ncmoe 0)", "8g-article-ncmoe0", "did not load: out of memory"),
    ("Classic offload, most layers that fit (-ngl 16)", "8g-ngl16", ""),
    ("Article's setting (-ncmoe 28)", "8g-article-ncmoe28", ""),
    ("Auto-fit (-fitt 1024)", "8g-fit", ""),
    ("CPU only, no GPU (i7-8700K)", "cpu-d0", "reference"),
):
    r = S.get((NIGHT, run, "tg128")) or S.get((NIGHT, run, ""))
    val = r["mean_ts"] if r and r["status"] == "ok" else ""
    sd = r["sd_ts"] if r and r["status"] == "ok" else ""
    claim_rows.append((label, "measured", val, note or f"RTX 3080, 8 GB emulated; sd {sd}"))
with open(OUT / "claim-vs-reality.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["label", "kind", "tg128_tokens_per_s", "note"])
    w.writerows(claim_rows)

# 2. Mac (clean session): generation speed by placement, depth 0 and 16384
mac_rows = []
for label, run in (("All on GPU", "mac-gpu"), ("-ncmoe 28 (article)", "mac-ncmoe28"),
                   ("All experts on CPU (-ncmoe 99)", "mac-cmoe"), ("Classic offload (-ngl 20)", "mac-nglhalf"),
                   ("CPU only", "mac-cpu"), ("Dense 27B, all on GPU", "mac-dense")):
    for d in ("d0", "d16k"):
        for t in ("pp512", "tg128"):
            r = S[(CLEAN, f"{run}-{d}", t)]
            mac_rows.append((label, r["depth"], t, r["mean_ts"], r["sd_ts"], r["median_ts"], r["n_reps"]))
with open(OUT / "mac-placements.csv", "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["placement", "depth", "test", "mean_tokens_per_s", "sd", "median", "reps"])
    w.writerows(mac_rows)

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ImportError:
    print("CSV written; matplotlib not installed, SVGs skipped")
    raise SystemExit(0)

fig, ax = plt.subplots(figsize=(8, 4.2))
labels = [r[0] for r in claim_rows]
vals = [float(r[2]) if r[2] else 0 for r in claim_rows]
colors = ["#9aa0a6" if r[1] == "declared" else "#3b6ea8" for r in claim_rows]
y = range(len(labels))[::-1]
ax.barh(list(y), vals, color=colors)
for yi, r, v in zip(y, claim_rows, vals):
    ax.text(v + 0.5, yi, r[2] if r[2] else "did not load (out of memory)", va="center", fontsize=9)
ax.set_yticks(list(y), labels, fontsize=9)
ax.axvspan(5, 6, color="#f2b705", alpha=0.25, lw=0)
ax.text(5.5, len(labels) - 0.4, "reading speed ~5-6", ha="center", fontsize=8)
ax.set_xlabel("Generation speed, tg128 (tokens/s) — grey: declared by XDA; blue: measured, 8 GB budget")
ax.set_xlim(0, 45)
for s in ("top", "right"):
    ax.spines[s].set_visible(False)
fig.tight_layout()
fig.savefig(OUT / "claim-vs-reality.svg")

fig, ax = plt.subplots(figsize=(8, 4.2))
pl = [r[0] for r in mac_rows if r[1] == "0" and r[2] == "tg128"]
d0 = [float(r[3]) for r in mac_rows if r[1] == "0" and r[2] == "tg128"]
d16 = [float(r[3]) for r in mac_rows if r[1] == "16384" and r[2] == "tg128"]
x = range(len(pl))
ax.bar([i - 0.2 for i in x], d0, 0.4, label="depth 0", color="#3b6ea8")
ax.bar([i + 0.2 for i in x], d16, 0.4, label="depth 16384", color="#9ec1e6")
ax.set_xticks(list(x), pl, rotation=20, ha="right", fontsize=8)
ax.set_ylabel("tg128 (tokens/s), mean")
ax.set_title("MacBook Pro M4 Max, clean session 2026-11-03", fontsize=10)
ax.legend(frameon=False, fontsize=8)
for s in ("top", "right"):
    ax.spines[s].set_visible(False)
fig.tight_layout()
fig.savefig(OUT / "mac-placements.svg")
print("CSV and SVG written")
