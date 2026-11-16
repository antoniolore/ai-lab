#!/usr/bin/env python3
"""Compare Mac sessions: prints a markdown table of pp512/tg128 (mean ± sd) per run and session."""
import json, os, re, sys
base = os.path.dirname(os.path.abspath(__file__)) + "/../results/mac"
S = [("11-02", f"{base}/raw"), ("11-03 am", f"{base}/retest-2026-11-03/raw"), ("11-03 clean", f"{base}/clean-2026-11-03/raw")]
RUNS = ["mac-gpu", "mac-ncmoe28", "mac-cmoe", "mac-nglhalf", "mac-cpu", "mac-dense"]
def get(d, name):
    p = f"{d}/{name}.json"
    if not os.path.exists(p): return None
    r = {}
    for x in json.load(open(p)):
        r["pp" if x["n_prompt"] else "tg"] = (x["avg_ts"], x["stddev_ts"], len(x.get("samples_ts", [])))
    st = open(f"{d}/{name}.stderr.txt").read() if os.path.exists(f"{d}/{name}.stderr.txt") else ""
    m = re.search(r"(\d+)\s+maximum resident set size", st)
    r["rss"] = int(m.group(1)) / 2**30 if m else None
    return r
f = lambda v: f"{v[0]:.2f} ± {v[1]:.2f}" if v else "—"
for depth in ("d0", "d16k"):
    print(f"\n### {depth}\n\n| Run | " + " | ".join(f"pp {s}" for s, _ in S) + " | " + " | ".join(f"tg {s}" for s, _ in S) + " |")
    print("|---" * (1 + 2 * len(S)) + "|")
    for run in RUNS:
        rs = [get(d, f"{run}-{depth}") for _, d in S]
        print(f"| {run} | " + " | ".join(f(r and r.get("pp")) for r in rs) + " | " + " | ".join(f(r and r.get("tg")) for r in rs) + " |")
    print("\nRatio all-GPU / ncmoe28 (pp, tg):")
    for s, d in S:
        g, n = get(d, f"mac-gpu-{depth}"), get(d, f"mac-ncmoe28-{depth}")
        if g and n: print(f"- {s}: pp {g['pp'][0]/n['pp'][0]:.2f}×, tg {g['tg'][0]/n['tg'][0]:.2f}×")
