#!/usr/bin/env bash
# ep-001 — exact commands used, in order. Reference only: read before running.
# Each block is copied from the runners in scripts/original/ and the *.cmd.txt files in logs/.
# Paths: LLAMA = folder with the llama.cpp b12034 binaries, MODELS = folder with the GGUF files
# (hashes in manifest.yaml), TEXTS = folder with pg11-alice.txt and a fresh text of your own.
set -euo pipefail
LLAMA="${LLAMA:?folder with llama-bench, llama-perplexity, llama-completion}"
MODELS="${MODELS:?folder with the .gguf files}"
TEXTS="${TEXTS:?folder with pg11-alice.txt and fresh-text.txt}"
PROMPTS="$(dirname "$0")/prompts"
OUT="${OUT:-./out}"; mkdir -p "$OUT"

M35="$MODELS/Qwen3.6-35B-A3B-UD-IQ4_XS.gguf"
M27="$MODELS/Qwen3.6-27B-IQ4_XS.gguf"
M8="$MODELS/Qwen3.6-35B-A3B-Q8_0.gguf"
COMMON=(-p 512 -n 128 -ctk q8_0 -ctv q8_0 -fa on -o json)

# 0. Verify the model files (expected hashes in manifest.yaml)
sha256sum "$M35" "$M27"

# ---------------------------------------------------------------------------
# A. MacBook Pro M4 Max (Metal). Threads: llama-bench default (12).
#    Each run was wrapped in `/usr/bin/time -l` (max RSS) — see scripts/original/mac-run.sh.
#    Reference session 2026-11-03-clean: -r 5 at depth 0, -r 3 at depth 16384, 120 s cool-down between rows.
# ---------------------------------------------------------------------------
mac() {
  for d in "0 5" "16384 3"; do
    set -- $d; depth=$1 reps=$2
    "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" -d "$depth" -r "$reps" -ngl 99 -ncmoe 0  > "$OUT/mac-gpu-d$depth.json"      # all on GPU
    "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" -d "$depth" -r "$reps" -ngl 99 -ncmoe 28 > "$OUT/mac-ncmoe28-d$depth.json"  # article's setting
    "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" -d "$depth" -r "$reps" -ngl 99 -ncmoe 99 > "$OUT/mac-cmoe-d$depth.json"     # all experts on CPU
    "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" -d "$depth" -r "$reps" -ngl 20           > "$OUT/mac-nglhalf-d$depth.json"  # classic offload
    "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" -d "$depth" -r "$reps" -ngl 0 -dev none  > "$OUT/mac-cpu-d$depth.json"      # CPU only
    "$LLAMA/llama-bench" -m "$M27" "${COMMON[@]}" -d "$depth" -r "$reps" -ngl 99           > "$OUT/mac-dense-d$depth.json"    # dense 27B
  done
}

# Quality control (Mac): greedy output, Alice perplexity, KL divergence vs all-GPU, Q8_0 reference.
mac_qc() {
  local cfg A
  for cfg in gpu ncmoe28 cpu; do
    case $cfg in gpu) A=(-ngl 99);; ncmoe28) A=(-ngl 99 --n-cpu-moe 28);; cpu) A=(-ngl 0 -dev none);; esac
    for p in "$PROMPTS"/greedy-*.txt; do
      "$LLAMA/llama-completion" -m "$M35" "${A[@]}" -f "$p" -n 200 --temp 0 --seed 42 -c 4096 \
        -no-cnv --no-display-prompt -fit off -fa on -ctk q8_0 -ctv q8_0 > "$OUT/$(basename "$p" .txt)-$cfg.txt" </dev/null
    done
    "$LLAMA/llama-perplexity" -m "$M35" "${A[@]}" -f "$TEXTS/pg11-alice.txt" -c 2048 --chunks 16 -fit off -fa on \
      -ctk q8_0 -ctv q8_0 > "$OUT/ppl-$cfg.txt" 2>&1 </dev/null
  done
  local X=(-c 512 -fit off -fa on -ctk q8_0 -ctv q8_0)
  "$LLAMA/llama-perplexity" -m "$M35" -ngl 99 -f "$TEXTS/fresh-text.txt" "${X[@]}" --kl-divergence-base "$OUT/kld-base-gpu.bin" > "$OUT/kld-base-gpu.txt" 2>&1
  for cfg in ncmoe28 cpu gpu; do
    case $cfg in gpu) A=(-ngl 99);; ncmoe28) A=(-ngl 99 --n-cpu-moe 28);; cpu) A=(-ngl 0 -dev none);; esac
    "$LLAMA/llama-perplexity" -m "$M35" "${A[@]}" "${X[@]}" --kl-divergence-base "$OUT/kld-base-gpu.bin" --kl-divergence > "$OUT/kld-$cfg.txt" 2>&1
  done
  # Q8_0 reference (needs ~34 GB of RAM): base logits from Q8_0 on Metal, then the three IQ4_XS placements
  "$LLAMA/llama-perplexity" -m "$M8" -ngl 99 -f "$TEXTS/fresh-text.txt" "${X[@]}" --kl-divergence-base "$OUT/kld-base-q8-gpu.bin" > "$OUT/kld-base-q8-gpu.txt" 2>&1
  for cfg in gpu ncmoe28 cpu; do
    case $cfg in gpu) A=(-ngl 99);; ncmoe28) A=(-ngl 99 --n-cpu-moe 28);; cpu) A=(-ngl 0 -dev none);; esac
    "$LLAMA/llama-perplexity" -m "$M35" "${A[@]}" "${X[@]}" --kl-divergence-base "$OUT/kld-base-q8-gpu.bin" --kl-divergence > "$OUT/kld-iq4-$cfg-vs-q8-gpu.txt" 2>&1
  done
}

# ---------------------------------------------------------------------------
# B. Linux desktop, RTX 3080 12 GB (CUDA 12.8 build). Original runs: throwaway container,
#    --network none, --cpus 10 (night) / 6 (day), -t 6, read-only mounts (scripts/original/desktop-night.sh).
#    The GPU must be free. For the 8 GB budget, hold a VRAM block so that exactly 8192 MiB stay free
#    (the original used torch: torch.empty(free - 8192 MiB, dtype=uint8, device='cuda')).
# ---------------------------------------------------------------------------
desktop_budget() { # $1 = tag (12g | 8g); run once without ballast, once with it
  local t=$1 b=(-t 6)
  "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" "${b[@]}" -ngl 99 -ncmoe 0  -d 0 -r 5 > "$OUT/$t-article-ncmoe0.json"  || true  # out of memory at load
  "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" "${b[@]}" -ngl 99 -ncmoe 28 -d 0 -r 5 > "$OUT/$t-article-ncmoe28.json"
  # smallest -ncmoe that fits, ascending: 4 8 12 16 20 24 32 40 (stop at the first that loads)
  for n in 4 8 12 16 20 24 32 40; do
    "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" "${b[@]}" -ngl 99 -ncmoe "$n" -d 0 -r 5 > "$OUT/$t-ncmoe$n.json" && break || true
  done
  # honest baseline: most whole layers that fit, descending: 36 32 28 24 20 16 12 8; then 4 fewer
  for g in 36 32 28 24 20 16 12 8; do
    "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" "${b[@]}" -ngl "$g" -d 0 -r 5 > "$OUT/$t-ngl$g.json" && break || true
  done
  "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" "${b[@]}" -ngl $((g - 4)) -d 0 -r 5 > "$OUT/$t-ngl$((g - 4)).json"
  # auto-fit, no manual placement
  "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" "${b[@]}" -fitt 1024 -d 0 -r 5 > "$OUT/$t-fit.json"
  # long context for the winners
  "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" "${b[@]}" -ngl 99 -ncmoe "$n"  -d 16384 -r 3 > "$OUT/$t-ncmoe$n-d16k.json"
  "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" "${b[@]}" -ngl 99 -ncmoe 28    -d 16384 -r 3 > "$OUT/$t-article-ncmoe28-d16k.json"
  "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" "${b[@]}" -ngl "$g"            -d 16384 -r 3 > "$OUT/$t-ngl$g-d16k.json"
  # dense 27B: as published (-ngl 99), then the most layers that fit: 56 48 40 32 24 16
  "$LLAMA/llama-bench" -m "$M27" "${COMMON[@]}" "${b[@]}" -ngl 99 -d 0 -r 3 > "$OUT/$t-dense-ngl99.json" || true
  for g in 56 48 40 32 24 16; do
    "$LLAMA/llama-bench" -m "$M27" "${COMMON[@]}" "${b[@]}" -ngl "$g" -d 0 -r 3 > "$OUT/$t-dense-ngl$g.json" && break || true
  done
}

desktop_qc() { # 12 GB, no ballast; reference placement is the best -ncmoe at 12 GB (20)
  local cfg A
  for cfg in ncmoe20 ncmoe28 cpu; do
    case $cfg in ncmoe20) A=(-ngl 99 --n-cpu-moe 20);; ncmoe28) A=(-ngl 99 --n-cpu-moe 28);; cpu) A=(-ngl 0 -dev none);; esac
    for p in "$PROMPTS"/greedy-*.txt; do
      "$LLAMA/llama-completion" -m "$M35" "${A[@]}" -t 6 -f "$p" -n 200 --temp 0 --seed 42 -c 4096 \
        -no-cnv --no-display-prompt -fit off -fa on -ctk q8_0 -ctv q8_0 > "$OUT/$(basename "$p" .txt)-$cfg.txt" </dev/null
    done
    "$LLAMA/llama-perplexity" -m "$M35" "${A[@]}" -t 6 -f "$TEXTS/pg11-alice.txt" -c 2048 --chunks 16 -fit off -fa on \
      -ctk q8_0 -ctv q8_0 > "$OUT/ppl-$cfg.txt" 2>&1 </dev/null
  done
}

desktop_cpu() { # no GPU
  "$LLAMA/llama-bench" -m "$M35" "${COMMON[@]}" -t 6 -ngl 0 -dev none -d 0 -r 3 > "$OUT/cpu-d0.json"
}

case "${1:-}" in
  mac) mac ;; mac-qc) mac_qc ;;
  desktop-12g) desktop_budget 12g ;; desktop-8g) desktop_budget 8g ;;
  desktop-qc) desktop_qc ;; desktop-cpu) desktop_cpu ;;
  *) echo "usage: $0 mac|mac-qc|desktop-12g|desktop-8g|desktop-qc|desktop-cpu" >&2; exit 2 ;;
esac
