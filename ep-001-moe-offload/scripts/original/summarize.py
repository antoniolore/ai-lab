#!/usr/bin/env python3
"""Summarise llama-bench JSON results of the Debunking AI pilot into a Markdown table.

Usage: summarize.py <raw-dir>   (Mac: results/raw, desktop: results/desktop/<night>/raw)
Reads <name>.json (+ .stderr.txt / .mempeak.bytes / .vram.txt / .failed) per run.
"""
import json
import re
import sys
from pathlib import Path


def peak_mem(raw: Path, name: str) -> str:
    st = raw / f"{name}.stderr.txt"
    out = []
    if st.exists():
        t = st.read_text(errors="replace")
        m = re.search(r"(\d+)\s+maximum resident set size", t)
        if m:
            out.append(f"RSS {int(m.group(1)) / 2**30:.1f} GiB")
        m = re.search(r"(\d+)\s+peak memory footprint", t)
        if m:
            out.append(f"footprint {int(m.group(1)) / 2**30:.1f} GiB")
    mp = raw / f"{name}.mempeak.bytes"
    if mp.exists() and mp.read_text().strip():
        out.append(f"cgroup {int(mp.read_text()) / 2**30:.1f} GiB")
    vr = raw / f"{name}.vram.txt"
    if vr.exists():
        vals = [int(x) for x in vr.read_text().split() if x.isdigit()]
        if vals:
            out.append(f"VRAM peak {max(vals)} MiB")
    return ", ".join(out)


def main() -> None:
    raw = Path(sys.argv[1])
    rows = []
    for f in sorted(raw.glob("*.cmd.txt")):
        name = f.name[: -len(".cmd.txt")]
        cmd = f.read_text().splitlines()[0]
        res = raw / f"{name}.json"
        if not res.exists():
            rows.append((name, cmd, "FAILED / not run", "", "", peak_mem(raw, name)))
            continue
        try:
            data = json.loads(res.read_text())
        except json.JSONDecodeError:
            rows.append((name, cmd, "unparsable", "", "", ""))
            continue
        pp = tg = ""
        depth = ""
        for r in data:
            depth = r.get("n_depth", 0)
            s = f"{r['avg_ts']:.2f} ± {r['stddev_ts']:.2f}"
            if r.get("n_prompt", 0) > 0 and r.get("n_gen", 0) == 0:
                pp = s
            elif r.get("n_gen", 0) > 0:
                tg = s
        rows.append((name, cmd, pp, tg, str(depth), peak_mem(raw, name)))
    print("| run | depth | pp512 t/s (mean ± sd) | tg128 t/s (mean ± sd) | peak memory | command |")
    print("|-----|-------|------------------------|------------------------|-------------|---------|")
    for name, cmd, pp, tg, depth, mem in rows:
        print(f"| {name} | {depth} | {pp} | {tg} | {mem} | `{cmd}` |")


if __name__ == "__main__":
    main()
