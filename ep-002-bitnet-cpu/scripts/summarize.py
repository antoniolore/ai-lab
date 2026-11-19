#!/usr/bin/env python3
"""Summarise llama-bench JSON for the bitnet-cpu bench (PROTOCOL.md §3.2).

usage: summarize.py <results-dir>   (expects raw/<row>-t<T>-i<N>.json and time/<same>.txt)
Per row and thread count: median of the invocation means (pp, tg), min-max across invocations,
peak RSS (max across invocations). Then decode/prefill ratios of bitnet.cpp rows vs baselines.
"""
import json, re, statistics, sys
from collections import defaultdict
from pathlib import Path

d = Path(sys.argv[1])
rows = defaultdict(lambda: {"pp": [], "tg": [], "rss": [], "files": 0, "test": {}})
for f in sorted((d / "raw").glob("*.json")):
    m = re.match(r"(.+)-t(\d+)(?:-i(\d+))?$", f.stem)
    if not m:
        continue
    row, t = m.group(1), int(m.group(2))
    try:
        data = json.loads(f.read_text())
    except Exception:
        continue
    r = rows[(row, t)]
    r["files"] += 1
    for e in data:
        key = "pp" if e.get("n_gen", 0) == 0 else "tg"
        r[key].append(e["avg_ts"])
        r["test"][key] = f"{key}{e['n_prompt'] if key == 'pp' else e['n_gen']}"
    tf = d / "time" / (f.stem + ".txt")
    if tf.exists():
        s = tf.read_text()
        mm = re.search(r"(\d+)\s+maximum resident set size", s)          # macOS, bytes
        if mm:
            r["rss"].append(int(mm.group(1)) / 2**20)
        mm = re.search(r"Maximum resident set size \(kbytes\): (\d+)", s)  # GNU time, KiB
        if mm:
            r["rss"].append(int(mm.group(1)) / 1024)


def med(v):
    return statistics.median(v) if v else None


def fmt(v, nd=1):
    return "—" if v is None else f"{v:.{nd}f}"


print("| Row | -t | inv | pp (t/s) median [min–max] | tg (t/s) median [min–max] | peak RSS MiB |")
print("|-----|----|-----|---------------------------|---------------------------|--------------|")
for (row, t), r in sorted(rows.items(), key=lambda x: (x[0][1], x[0][0])):
    pp, tg = r["pp"], r["tg"]
    ps = f"{fmt(med(pp))} [{fmt(min(pp))}–{fmt(max(pp))}]" if pp else "—"
    ts = f"{fmt(med(tg))} [{fmt(min(tg))}–{fmt(max(tg))}]" if tg else "—"
    print(f"| {row} | {t} | {r['files']} | {ps} | {ts} | {fmt(max(r['rss']) if r['rss'] else None, 0)} |")

PAIRS = [  # (numerator, denominator, label)
    ("bn-i2s-v0", "ll-f16", "bitnet.cpp 404980e / stock F16 (faithful, 2B4T proxy)"),
    ("bn-i2s-head", "ll-f16", "bitnet.cpp HEAD / stock F16 (faithful, 2B4T proxy)"),
    ("bn-i2s-v0", "ll-tq2-embf16", "bitnet.cpp 404980e / stock TQ2_0 emb F16 (engine only)"),
    ("bn-i2s-head", "ll-tq2-embf16", "bitnet.cpp HEAD / stock TQ2_0 emb F16 (engine only)"),
    ("bn-i2s-v0", "ll-tq2", "bitnet.cpp 404980e / stock TQ2_0 (default emb Q6_K)"),
    ("bn-i2s-head", "ll-tq2", "bitnet.cpp HEAD / stock TQ2_0 (default emb Q6_K)"),
    ("bn-i2s-v0", "ll-q40", "bitnet.cpp 404980e / stock Q4_0"),
    ("bn-i2s-head", "ll-q40", "bitnet.cpp HEAD / stock Q4_0"),
    ("bn-i2s-v0", "ll-qwen-q4km", "bitnet.cpp 404980e / Qwen2.5-1.5B Q4_K_M"),
    ("bn-i2s-head", "ll-qwen-q4km", "bitnet.cpp HEAD / Qwen2.5-1.5B Q4_K_M"),
    ("ll-tq2-embf16", "ll-f16", "stock TQ2_0 emb F16 / stock F16 (weights only, same engine)"),
    ("bn-large-i2s-v0", "ll-large-f16", "large: bitnet.cpp 404980e / stock F16"),
    ("bn-large-i2s-head", "ll-large-f16", "large: bitnet.cpp HEAD / stock F16"),
    ("bn-large-i2s-v0", "ll-large-tq2", "large: bitnet.cpp 404980e / stock TQ2_0"),
    ("bn-large-i2s-head", "ll-large-tq2", "large: bitnet.cpp HEAD / stock TQ2_0"),
    ("bn-large-i2s-v0", "ll-large-q40", "large: bitnet.cpp 404980e / stock Q4_0"),
    ("bn-large-i2s-head", "ll-large-q40", "large: bitnet.cpp HEAD / stock Q4_0"),
]
print()
print("| Ratio | -t | pp | tg |")
print("|-------|----|----|----|")
threads = sorted({t for (_, t) in rows})
for a, b, label in PAIRS:
    for t in threads:
        ra, rb = rows.get((a, t)), rows.get((b, t))
        if not ra or not rb:
            continue
        pp = med(ra["pp"]) / med(rb["pp"]) if ra["pp"] and rb["pp"] else None
        tg = med(ra["tg"]) / med(rb["tg"]) if ra["tg"] and rb["tg"] else None
        print(f"| {label} | {t} | {fmt(pp, 2)}x | {fmt(tg, 2)}x |")
