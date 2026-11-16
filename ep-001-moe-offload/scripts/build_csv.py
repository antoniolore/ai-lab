#!/usr/bin/env python3
"""Rebuild the tidy CSV files of ep-001 from the raw logs in this folder.

Usage (from the episode folder):  python3 scripts/build_csv.py
Writes: results.csv (one row per llama-bench repetition, plus one row per failed run),
        results_summary.csv (one row per run and test, mean/sd as reported by llama-bench),
        quality.csv (perplexity, KL divergence, top-1 agreement, greedy-output prefixes).
Standard library only.
"""
import csv
import json
import re
import statistics
from pathlib import Path

EP = Path(__file__).resolve().parent.parent
EPISODE = "ep-001-moe-offload"
MODEL_FILES = {
    "Qwen3.6-35B-A3B-UD-IQ4_XS.gguf": "qwen3.6-35b-a3b-ud-iq4_xs",
    "Qwen3.6-27B-IQ4_XS.gguf": "qwen3.6-27b-iq4_xs",
}
SESSIONS = [
    # machine, session id, raw dir, vram budget default
    ("macbook-pro-m4-max", "2026-11-02", "logs/mac/2026-11-02/raw"),
    ("macbook-pro-m4-max", "2026-11-03-am", "logs/mac/2026-11-03-am/raw"),
    ("macbook-pro-m4-max", "2026-11-03-clean", "logs/mac/2026-11-03-clean/raw"),
    ("desktop-rtx3080", "2026-11-02-day", "logs/desktop/2026-11-02-day/raw"),
    ("desktop-rtx3080", "2026-11-02-night", "logs/desktop/2026-11-02-night/raw"),
]


def budget(machine, run):
    if machine.startswith("macbook"):
        return "unified_48GB"
    if run.startswith("12g-"):
        return "12GB"
    if run.startswith("8g-"):
        return "8GB_emulated"
    return "none_cpu_only"


def flag(cmd, name, default=""):
    m = re.search(rf"(?:^|\s){re.escape(name)}\s+(\S+)", cmd)
    return m.group(1) if m else default


def model_of(cmd):
    for f, short in MODEL_FILES.items():
        if f in cmd:
            return short
    return ""


def read(p):
    return p.read_text(errors="replace") if p.exists() else ""


def gib(x):
    return f"{x / 2**30:.2f}"


rows, summary = [], []
for machine, session, rel in SESSIONS:
    raw = EP / rel
    names = sorted({p.name.split(".")[0] for p in raw.iterdir()})
    for run in names:
        cmd = read(raw / f"{run}.cmd.txt")
        rc_m = re.search(r"rc=(\d+)", cmd)
        rc = int(rc_m.group(1)) if rc_m else None
        stderr = read(raw / f"{run}.stderr.txt")
        src = f"{rel}/{run}"
        # memory
        rss = re.search(r"(\d+)\s+maximum resident set size", stderr)
        foot = re.search(r"(\d+)\s+peak memory footprint", stderr)
        vram = ""
        vf = raw / f"{run}.vram.txt"
        if vf.exists():
            v = [int(x) for x in vf.read_text().split() if x.isdigit()]
            if v:
                vram = f"{(max(v) - v[0]) / 1024:.2f}"
        base = dict(
            episode=EPISODE, machine=machine, session=session, run_id=run, model=model_of(cmd),
            vram_budget=budget(machine, run), n_gpu_layers=flag(cmd, "-ngl"), n_cpu_moe=flag(cmd, "-ncmoe"),
            fit_target_mib=flag(cmd, "-fitt"), devices=flag(cmd, "-dev", "auto"), depth=flag(cmd, "-d"),
        )
        js = raw / f"{run}.json"
        if js.exists() and rc == 0:
            for t in json.loads(js.read_text()):
                test = f"pp{t['n_prompt']}" if t["n_prompt"] else f"tg{t['n_gen']}"
                common = dict(base, n_gpu_layers=t["n_gpu_layers"], n_cpu_moe=t["n_cpu_moe"],
                              fit_target_mib=t.get("fit_target", 0) or "", devices=t["devices"],
                              depth=t["n_depth"], test=test)
                for i, s in enumerate(t["samples_ts"], 1):
                    rows.append(dict(common, threads=t["n_threads"], rep=i, tokens_per_s=s, status="ok",
                                     test_time_utc=t["test_time"], build=f"b{t['build_number']}",
                                     build_commit=t["build_commit"], backends=t["backends"],
                                     source=f"{src}.json"))
                ss = t["samples_ts"]
                summary.append(dict(common, n_reps=len(ss), mean_ts=f"{t['avg_ts']:.2f}",
                                    sd_ts=f"{t['stddev_ts']:.2f}", median_ts=f"{statistics.median(ss):.2f}",
                                    min_ts=f"{min(ss):.2f}", max_ts=f"{max(ss):.2f}", status="ok", fail_reason="",
                                    vram_used_gib=vram, max_rss_gib=gib(int(rss.group(1))) if rss else "",
                                    peak_footprint_gib=gib(int(foot.group(1))) if foot else "",
                                    source=f"{src}.json"))
        else:
            if "cudaMalloc failed: out of memory" in stderr and rc == 1:
                st, why = "failed", "out_of_memory_at_load"
            elif rc == 139:
                st, why = "failed", "segfault_after_cuda_oom_in_first_batch"
            else:
                st, why = "failed", f"rc={rc}"
            rows.append(dict(base, threads="", test="", rep="", tokens_per_s="", status=st, test_time_utc="",
                             build="b12034", build_commit="1c5ed702c", backends="", source=f"{src}.stderr.txt"))
            summary.append(dict(base, test="", n_reps=0, mean_ts="", sd_ts="", median_ts="", min_ts="", max_ts="",
                                status=st, fail_reason=why, vram_used_gib=vram, max_rss_gib="",
                                peak_footprint_gib="", source=f"{src}.stderr.txt"))

RCOLS = ["episode", "machine", "session", "run_id", "model", "vram_budget", "n_gpu_layers", "n_cpu_moe",
         "fit_target_mib", "devices", "threads", "depth", "test", "rep", "tokens_per_s", "status",
         "test_time_utc", "build", "build_commit", "backends", "source"]
SCOLS = ["episode", "machine", "session", "run_id", "model", "vram_budget", "n_gpu_layers", "n_cpu_moe",
         "fit_target_mib", "devices", "depth", "test", "n_reps", "mean_ts", "sd_ts", "median_ts", "min_ts",
         "max_ts", "status", "fail_reason", "vram_used_gib", "max_rss_gib", "peak_footprint_gib", "source"]
for name, cols, data in (("results.csv", RCOLS, rows), ("results_summary.csv", SCOLS, summary)):
    with open(EP / name, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, lineterminator="\n")
        w.writeheader()
        w.writerows(data)

# ---------- quality ----------
q = []
QCOLS = ["episode", "machine", "session", "check", "placement", "reference", "metric", "value", "error", "source"]


def add(machine, session, check, placement, ref, metric, value, err, source):
    q.append(dict(episode=EPISODE, machine=machine, session=session, check=check, placement=placement,
                  reference=ref, metric=metric, value=value, error=err, source=source))


def ppl_final(p):
    m = re.search(r"Final estimate: PPL = ([0-9.]+) \+/- ([0-9.]+)", read(p))
    return m.groups() if m else None


def kld_stats(p):
    t = read(p)
    out = {}
    for key, rx in (("mean_ppl_q", r"Mean PPL\(Q\)\s*:\s*([0-9.]+) ±\s*([0-9.]+)"),
                    ("ppl_ratio_q_over_base", r"Mean PPL\(Q\)/PPL\(base\)\s*:\s*([0-9.]+) ±\s*([0-9.]+)"),
                    ("mean_kld", r"Mean\s+KLD:\s*([-0-9.]+) ±\s*([0-9.]+)"),
                    ("kld_p99_9", r"99\.9%\s+KLD:\s*([-0-9.]+)()"),
                    ("same_top1_pct", r"Same top p:\s*([0-9.]+) ±\s*([0-9.]+)")):
        m = re.search(rx, t)
        if m:
            out[key] = m.groups()
    return out


def prefix(a, b):
    n = 0
    for x, y in zip(a, b):
        if x != y:
            break
        n += 1
    return n


QC = [
    ("macbook-pro-m4-max", "2026-11-02", "logs/mac/2026-11-02/qc", ["gpu", "ncmoe28", "cpu"], "gpu"),
    ("macbook-pro-m4-max", "2026-11-03-clean", "logs/mac/2026-11-03-clean/qc", ["gpu", "ncmoe28", "cpu"], "gpu"),
    ("desktop-rtx3080", "2026-11-02-night", "logs/desktop/2026-11-02-night/qc", ["ncmoe20", "ncmoe28", "cpu"], "ncmoe20"),
]
for machine, session, rel, places, ref in QC:
    d = EP / rel
    for pl in places:
        r = ppl_final(d / f"ppl-{pl}.txt")
        if r:
            add(machine, session, "ppl_alice_16x2048", pl, "", "ppl", r[0], r[1], f"{rel}/ppl-{pl}.txt")
        k = kld_stats(d / f"kld-{pl}.txt")
        for metric, (v, e) in k.items():
            add(machine, session, "kld_fresh_text_7x512", pl, ref, metric, v, e, f"{rel}/kld-{pl}.txt")
        for g in ("greedy-1", "greedy-2"):
            a, b = d / f"{g}-{ref}.txt", d / f"{g}-{pl}.txt"
            if a.exists() and b.exists() and pl != ref:
                ta, tb = a.read_text(), b.read_text()
                add(machine, session, f"{g}_200tok_temp0", pl, ref, "identical_prefix_chars", prefix(ta, tb), "",
                    f"{rel}/{g}-{pl}.txt")
                add(machine, session, f"{g}_200tok_temp0", pl, ref, "reference_length_chars", len(ta), "",
                    f"{rel}/{g}-{ref}.txt")
                add(machine, session, f"{g}_200tok_temp0", pl, ref, "placement_length_chars", len(tb), "",
                    f"{rel}/{g}-{pl}.txt")
# Q8_0 reference (Mac, clean session)
rel = "logs/mac/2026-11-03-clean/q8"
r = ppl_final(EP / rel / "kld-base-q8-gpu.txt")
if r:
    add("macbook-pro-m4-max", "2026-11-03-clean", "q8_0_reference_fresh_text_7x512", "q8_0_gpu", "", "ppl", r[0], r[1],
        f"{rel}/kld-base-q8-gpu.txt")
for pl in ("gpu", "ncmoe28", "cpu"):
    p = EP / rel / f"kld-iq4-{pl}-vs-q8-gpu.txt"
    for metric, (v, e) in kld_stats(p).items():
        add("macbook-pro-m4-max", "2026-11-03-clean", "q8_0_reference_fresh_text_7x512", pl, "q8_0_gpu", metric, v, e,
            f"{rel}/{p.name}")

with open(EP / "quality.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=QCOLS, lineterminator="\n")
    w.writeheader()
    w.writerows(q)
print(f"results.csv {len(rows)} rows, results_summary.csv {len(summary)} rows, quality.csv {len(q)} rows")
