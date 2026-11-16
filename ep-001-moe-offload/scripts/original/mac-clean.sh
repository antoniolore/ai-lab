#!/bin/bash
# Debunking AI pilot — clean Mac session 2026-11-03 (evening).
# Same rows and flags as protocol §3 (Mac) / mac-run.sh, but:
#   - every d16k row uses -r 3 (mac-run.sh had -r 2 for CPU only);
#   - cool-down between rows: at least 90 s, then wait until 1-min load < 1.0 (max 600 s);
#   - guard before every row and a 2 s sampler during the whole session:
#     stop if swap used > 0 or kern.memorystatus_vm_pressure_level >= 2 (warn);
#   - QC (greedy, Alice PPL, KLD vs all-GPU) reuses mac-run.sh with R pointing here.
# Usage: mac-clean.sh suite|qc|q8|sampler-stop
set -u
W="$HOME/moe-offload-lab"
export R="$W/results-clean-2026-11-03"
B="$W/bin/llama-b12034"
M35="$W/models/Qwen3.6-35B-A3B-UD-IQ4_XS.gguf"
M27="$W/models/Qwen3.6-27B-IQ4_XS.gguf"
M8="$W/models/Qwen3.6-35B-A3B-Q8_0.gguf"
mkdir -p "$R/raw" "$R/qc" "$R/q8"
G="$R/guard.log"
COMMON=(-p 512 -n 128 -ctk q8_0 -ctv q8_0 -fa on -o json)

swap_mb() { sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+)M.*/\1/'; }
plevel()  { sysctl -n kern.memorystatus_vm_pressure_level; }
load1()   { sysctl -n vm.loadavg | awk '{print $2}'; }

sampler() { # background: one line every 2 s
  while :; do
    printf '%s load=%s swap=%sM plevel=%s free=%s therm=%s\n' "$(date +%T)" "$(load1)" "$(swap_mb)" "$(plevel)" \
      "$(memory_pressure | awk -F': ' '/free percentage/{print $2}')" \
      "$(pmset -g therm | grep -cv '^Note: No')" >> "$R/sampler.log"
    sleep 2
  done
}

guard() { # $1 = label
  local s p
  s=$(swap_mb); p=$(plevel)
  echo "$(date +%T) $1 load=$(load1) idle=$(idle)% swap=${s}M plevel=$p" | tee -a "$G"
  if [[ ${s%.*} -gt 0 || $p -ge 2 ]]; then echo "$(date +%T) STOP: swap or memory pressure ($1)" | tee -a "$G"; exit 3; fi
  if pmset -g therm | grep -qv '^Note: No'; then echo "$(date +%T) WARN thermal: $(pmset -g therm | tr '\n' ' ')" | tee -a "$G"; fi
}

idle() { top -l 2 -s 1 -n 0 | awk '/CPU usage/{v=$7} END{gsub("%","",v); print v}'; }
# Idle floor measured at 19:47-19:50 with nothing of ours running: load1 1.44-1.80, CPU idle 97.8-99.4 %.
# Load < 1 is not reachable on this Mac, so: min 120 s, then until load1 < 2.0 and CPU idle >= 97 %, max 600 s.
cooldown() {
  local t0=$SECONDS id
  sleep 120
  while (( SECONDS - t0 < 600 )); do
    id=$(idle)
    awk -v l="$(load1)" -v i="$id" 'BEGIN{exit !(l<2.0 && i>=97)}' && break
    sleep 10
  done
  echo "$(date +%T) cooldown $((SECONDS - t0)) s, load=$(sysctl -n vm.loadavg) idle=${id}%" | tee -a "$G"
}

envsnap() { # $1 = file
  {
    date -u +%FT%TZ
    sysctl -n vm.loadavg
    memory_pressure | tail -1
    sysctl kern.memorystatus_vm_pressure_level vm.swapusage
    pmset -g batt | head -1
    pmset -g therm
    ps -Ao pcpu,comm -r | head -8
  } > "$1" 2>&1
}

bench() { # name model depth reps extra-args...
  local name="$1" model="$2" depth="$3" reps="$4"; shift 4
  local out="$R/raw/$name.json"
  if [[ -s "$out" && "${FORCE:-0}" != 1 ]]; then echo "skip $name"; return 0; fi
  guard "pre $name"
  echo "== $name: $* -d $depth -r $reps"
  envsnap "$R/raw/$name.env.txt"
  echo "$B/llama-bench -m $model ${COMMON[*]} -d $depth -r $reps $*" > "$R/raw/$name.cmd.txt"
  local t0=$SECONDS
  /usr/bin/time -l "$B/llama-bench" -m "$model" "${COMMON[@]}" -d "$depth" -r "$reps" "$@" \
    > "$out.tmp" 2> "$R/raw/$name.stderr.txt" </dev/null
  local rc=$?
  echo "rc=$rc wall=$((SECONDS - t0))s" >> "$R/raw/$name.cmd.txt"
  envsnap "$R/raw/$name.post.txt"
  if [[ $rc -eq 0 ]]; then mv "$out.tmp" "$out"; else mv "$out.tmp" "$R/raw/$name.failed.json"; fi
  guard "post $name rc=$rc"
  cooldown
}

run() {
  case "$1" in
    mac-gpu-d0)        bench "$1" "$M35" 0     5 -ngl 99 -ncmoe 0 ;;
    mac-gpu-d16k)      bench "$1" "$M35" 16384 3 -ngl 99 -ncmoe 0 ;;
    mac-ncmoe28-d0)    bench "$1" "$M35" 0     5 -ngl 99 -ncmoe 28 ;;
    mac-ncmoe28-d16k)  bench "$1" "$M35" 16384 3 -ngl 99 -ncmoe 28 ;;
    mac-cmoe-d0)       bench "$1" "$M35" 0     5 -ngl 99 -ncmoe 99 ;;
    mac-cmoe-d16k)     bench "$1" "$M35" 16384 3 -ngl 99 -ncmoe 99 ;;
    mac-nglhalf-d0)    bench "$1" "$M35" 0     5 -ngl 20 ;;
    mac-nglhalf-d16k)  bench "$1" "$M35" 16384 3 -ngl 20 ;;
    mac-cpu-d0)        bench "$1" "$M35" 0     5 -ngl 0 -dev none ;;
    mac-cpu-d16k)      bench "$1" "$M35" 16384 3 -ngl 0 -dev none ;;
    mac-dense-d0)      bench "$1" "$M27" 0     5 -ngl 99 ;;
    mac-dense-d16k)    bench "$1" "$M27" 16384 3 -ngl 99 ;;
    *) echo "unknown run $1" >&2; return 2 ;;
  esac
}

# Q8_0 reference: KLD base from Q8_0 on the fresh text, then the three IQ4_XS placements against it.
# A watchdog kills llama-perplexity at the first swap > 0 or pressure level >= 2.
q8() {
  local T="$W/data/fresh-text.txt" X=(-c 512 -fit off -fa on -ctk q8_0 -ctv q8_0)
  local dev="$1" A                      # gpu | cpu : where the Q8_0 base runs
  case $dev in gpu) A=(-ngl 99) ;; cpu) A=(-ngl 0 -dev none) ;; esac
  local BASE="$R/q8/kld-base-q8-$dev.bin"
  guard "pre q8-base-$dev"
  ( while sleep 1; do
      s=$(swap_mb); p=$(plevel)
      if [[ ${s%.*} -gt 0 || $p -ge 2 ]]; then
        echo "$(date +%T) WATCHDOG kill llama-perplexity swap=${s}M plevel=$p" | tee -a "$G"; pkill -9 -f llama-perplexity; exit 0; fi
    done ) & local wd=$!
  [[ -s "$BASE" ]] || /usr/bin/time -l "$B/llama-perplexity" -m "$M8" "${A[@]}" -f "$T" "${X[@]}" \
      --kl-divergence-base "$BASE" > "$R/q8/kld-base-q8-$dev.txt" 2>&1 </dev/null
  echo "$(date +%T) q8 base $dev rc=$?" | tee -a "$G"
  [[ -s "$BASE" ]] || { kill $wd; return 3; }
  for cfg in gpu ncmoe28 cpu; do
    case $cfg in gpu) A=(-ngl 99) ;; ncmoe28) A=(-ngl 99 --n-cpu-moe 28) ;; cpu) A=(-ngl 0 -dev none) ;; esac
    o="$R/q8/kld-iq4-$cfg-vs-q8-$dev.txt"
    [[ -s "$o" && "${FORCE:-0}" != 1 ]] && continue
    "$B/llama-perplexity" -m "$M35" "${A[@]}" "${X[@]}" --kl-divergence-base "$BASE" --kl-divergence > "$o" 2>&1 </dev/null
    echo "$(date +%T) q8-$dev vs iq4-$cfg rc=$?" | tee -a "$G"
  done
  kill $wd 2>/dev/null
  guard "post q8-$dev"
}

ALL=(mac-gpu-d0 mac-ncmoe28-d0 mac-cmoe-d0 mac-nglhalf-d0 mac-cpu-d0 mac-dense-d0
     mac-gpu-d16k mac-ncmoe28-d16k mac-cmoe-d16k mac-nglhalf-d16k mac-dense-d16k mac-cpu-d16k)

case "${1:-}" in
  sampler)      sampler ;;
  all)          sampler & SP=$!; ( "$0" suite && "$0" qc ); rc=$?; kill $SP; echo "$(date +%T) all done rc=$rc" | tee -a "$G" ;;
  suite)        for r in "${ALL[@]}"; do run "$r"; done; echo "$(date +%T) suite done" | tee -a "$G" ;;
  qc)           guard "pre qc"; "$W/poc/mac-run.sh" qc; guard "mid qc"; "$W/poc/mac-run.sh" kld; guard "post qc" ;;
  q8)           q8 "${2:-gpu}" ;;
  *)            echo "usage: $0 suite|qc|q8 gpu|cpu|sampler"; exit 2 ;;
esac
