#!/bin/bash
# Debunking AI pilot — Mac bench runner (Apple Silicon, Metal).
# Runs llama-bench configurations from protocol/PROTOCOL.md §3 (Mac) one by one,
# each wrapped in /usr/bin/time -l for peak memory, and logs the environment.
# Usage: mac-run.sh <run-name>|all|qc   (idempotent: skips runs whose JSON exists unless FORCE=1)
set -u
W="${W:-$HOME/moe-offload-lab}"
B="$W/bin/llama-b12034"
M35="$W/models/Qwen3.6-35B-A3B-UD-IQ4_XS.gguf"
M27="$W/models/Qwen3.6-27B-IQ4_XS.gguf"
R="${R:-$W/results}"
mkdir -p "$R/raw" "$R/qc"
COMMON=(-p 512 -n 128 -ctk q8_0 -ctv q8_0 -fa on -o json)

envsnap() { # $1 = file
  {
    date -u +%FT%TZ
    sysctl -n vm.loadavg
    memory_pressure | tail -1
    pmset -g batt | head -1
    ps -Ao pcpu,comm -r | head -6
    sysctl vm.swapusage
  } > "$1" 2>&1
}

bench() { # name model depth reps extra-args...
  local name="$1" model="$2" depth="$3" reps="$4"; shift 4
  local out="$R/raw/$name.json"
  if [[ -s "$out" && "${FORCE:-0}" != 1 ]]; then echo "skip $name"; return 0; fi
  echo "== $name: $* -d $depth -r $reps"
  envsnap "$R/raw/$name.env.txt"
  echo "$B/llama-bench -m $model ${COMMON[*]} -d $depth -r $reps $*" > "$R/raw/$name.cmd.txt"
  /usr/bin/time -l "$B/llama-bench" -m "$model" "${COMMON[@]}" -d "$depth" -r "$reps" "$@" \
    > "$out.tmp" 2> "$R/raw/$name.stderr.txt"
  local rc=$?
  echo "rc=$rc" >> "$R/raw/$name.cmd.txt"
  if [[ $rc -eq 0 ]]; then mv "$out.tmp" "$out"; else mv "$out.tmp" "$R/raw/$name.failed.json"; fi
  grep -E "maximum resident set size|peak memory footprint|real" "$R/raw/$name.stderr.txt" | tail -3
}

run() {
  case "$1" in
    mac-gpu-d0)        bench "$1" "$M35" 0     5 -ngl 99 -ncmoe 0 ;;
    mac-gpu-d16k)      bench "$1" "$M35" 16384 5 -ngl 99 -ncmoe 0 ;;
    mac-ncmoe28-d0)    bench "$1" "$M35" 0     5 -ngl 99 -ncmoe 28 ;;
    mac-ncmoe28-d16k)  bench "$1" "$M35" 16384 5 -ngl 99 -ncmoe 28 ;;
    mac-cmoe-d0)       bench "$1" "$M35" 0     5 -ngl 99 -ncmoe 99 ;;
    mac-cmoe-d16k)     bench "$1" "$M35" 16384 3 -ngl 99 -ncmoe 99 ;;
    mac-nglhalf-d0)    bench "$1" "$M35" 0     5 -ngl 20 ;;
    mac-nglhalf-d16k)  bench "$1" "$M35" 16384 3 -ngl 20 ;;
    mac-cpu-d0)        bench "$1" "$M35" 0     5 -ngl 0 -dev none ;;
    mac-cpu-d16k)      bench "$1" "$M35" 16384 2 -ngl 0 -dev none ;;
    mac-dense-d0)      bench "$1" "$M27" 0     5 -ngl 99 ;;
    mac-dense-d16k)    bench "$1" "$M27" 16384 3 -ngl 99 ;;
    *) echo "unknown run $1" >&2; return 2 ;;
  esac
}

qc() {
  local P="$W/protocol/prompts" T="$W/data/pg11-alice.txt"
  for cfg in gpu ncmoe28 cpu; do
    case $cfg in
      gpu)     A=(-ngl 99) ;;
      ncmoe28) A=(-ngl 99 --n-cpu-moe 28) ;;
      cpu)     A=(-ngl 0 -dev none) ;;
    esac
    for p in "$P"/greedy-*.txt; do
      o="$R/qc/$(basename "$p" .txt)-$cfg.txt"
      [[ -s "$o" && "${FORCE:-0}" != 1 ]] && continue
      "$B/llama-completion" -m "$M35" "${A[@]}" -f "$p" -n 200 --temp 0 --seed 42 -c 4096 \
        -no-cnv --no-display-prompt -fit off -fa on -ctk q8_0 -ctv q8_0 > "$o" 2> "$o.log" </dev/null
    done
    o="$R/qc/ppl-$cfg.txt"
    if [[ ! -s "$o" || "${FORCE:-0}" == 1 ]]; then
      "$B/llama-perplexity" -m "$M35" "${A[@]}" -f "$T" -c 2048 --chunks 16 -fit off -fa on \
        -ctk q8_0 -ctv q8_0 > "$o" 2>&1 </dev/null
      grep -E "Final estimate" "$o"
    fi
  done
}

kld() {
  local T="$W/data/fresh-text.txt" BASE="$R/qc/kld-base-gpu.bin" X=(-c 512 -fit off -fa on -ctk q8_0 -ctv q8_0)
  [[ -s "$BASE" ]] || "$B/llama-perplexity" -m "$M35" -ngl 99 -f "$T" "${X[@]}" --kl-divergence-base "$BASE" > "$R/qc/kld-base-gpu.txt" 2>&1 </dev/null
  for cfg in ncmoe28 cpu gpu; do
    case $cfg in
      gpu)     A=(-ngl 99) ;;
      ncmoe28) A=(-ngl 99 --n-cpu-moe 28) ;;
      cpu)     A=(-ngl 0 -dev none) ;;
    esac
    o="$R/qc/kld-$cfg.txt"
    [[ -s "$o" && "${FORCE:-0}" != 1 ]] && continue
    "$B/llama-perplexity" -m "$M35" "${A[@]}" "${X[@]}" --kl-divergence-base "$BASE" --kl-divergence > "$o" 2>&1 </dev/null
  done
}

ALL=(mac-gpu-d0 mac-ncmoe28-d0 mac-cmoe-d0 mac-nglhalf-d0 mac-cpu-d0 mac-dense-d0
     mac-gpu-d16k mac-ncmoe28-d16k mac-cmoe-d16k mac-nglhalf-d16k mac-dense-d16k mac-cpu-d16k)
case "${1:-}" in
  all) for r in "${ALL[@]}"; do run "$r"; done ;;
  qc)  qc ;;
  kld) kld ;;
  "")  echo "usage: $0 <run>|all|qc"; exit 2 ;;
  *)   for r in "$@"; do run "$r"; done ;;
esac

# --- amendment 2026-11-02 (after first QC): KL divergence between placements on a text written today ---
# usage: KLD=1 mac-run.sh kld
