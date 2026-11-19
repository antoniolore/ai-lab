#!/usr/bin/env bash
# Debunking AI — bitnet-cpu bench, desktop CPU-only night run (i7-8700K 6C/12T, AVX2).
# Protocol: debunking-ai/bench/2026-11-bitnet-cpu/PROTOCOL.md (§3, changelog 2026-11-18).
#
# Same safety pattern as the pilot ($PILOT_LAB/poc/desktop-night.sh, reviewed by the operator):
#   1. Guards: start window 22:00–03:59 Europe/Rome, flock, preflight (sha256, images, RAM, the local inference server healthy).
#   2. Stops the local inference server (compose service `vllm`) ONLY if running and healthy — to free host RAM/CPU for a clean CPU
#      bench and the ~26 GB 100B layouts. No GPU is used by this bench.
#   3. Runs llama-bench of stock llama.cpp b12503 (prebuilt CPU) and of bitnet.cpp (three builds) in a
#      throwaway container: --network none, no env, read-only binaries/models.
#   4. ALWAYS restores the local inference server (trap), waits for /health, checks the inference gateway `main`. Writes RESTORE_STATUS.
# Idempotent per output file; DONE marker at the end. No new step after 04:15, hard stop 04:30.
#
# Usage:  desktop-night.sh            (real run, in window)
#         desktop-night.sh --dry-run  (preflight only, any time: no the local inference server stop, no bench)
# Env:    NIGHT=<YYYY-MM-DD>; NOTIFY_CMD="..." (called with a message if the restore fails); SKIP_100B=1
#
# the operator review 2026-11-18 (originals kept as *.orig-leonardo). Scheduled by the user units
# poc/systemd/debunking-ai-bitnet-night.{service,timer} (Type=exec, RuntimeMaxSec backstop, ExecStopPost=night-post.sh).
#   D1 run(): deadline re-checked AFTER the cool-down (cool can take ~5.5 min); timeout clamped to left-30 s and
#      never 0 (`timeout 0` = no timeout); a run with < 2 min left is skipped; `timeout --kill-after=20`.
#   D2 run(): container memory cap = MemAvailable-3 GiB (max 48), no swap (--memory-swap = --memory): a runaway
#      allocation on the 100B layouts gets OOM-killed inside the container instead of pushing the host into zram.
#   D3 run(): failed runs are renamed raw/<name>.failed (night-post.sh counts *.failed; before it always said 0).
#   D4 restore(): bounded waits (the local inference server /health max 10 min, the inference gateway `main` max 3 tries x 60 s) so trap+post end before 05:00.
#   D5 the inference gateway master key passed to curl on stdin (-H @-), no longer on the command line (/proc/*/cmdline).
#   D6 preflight: sha-ok invalidated if any model is newer than it; env.txt also records the active user services
#      (hourly backup-dev rsync reads ~/dev, models included).
#   Writes: only $LAB/results/desktop/<night>/ and $LAB/run/ (plus the throwaway container layer). Nothing in bench/.
set -Eeuo pipefail
export TZ=Europe/Rome

LAB=$LAB
IMAGE=lab-bitnet:2026-11-18
ST="$LAB/bin/llama-b12503-x64/llama-b12503"          # stock llama.cpp b12503, mounted at /st
declare -A BN=( [head]="$LAB/build/BitNet-HEAD" [01eb415]="$LAB/build/BitNet-01eb415" [v0]="$LAB/build/BitNet-404980e" )
M="$LAB/models"
VLLM_CONTAINER=inference-server
MARKER="$LAB/run/vllm-stopped-by-bitnet-bench"
COOL=${COOL:-30}
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1

hour=$((10#$(date +%H)))
if [[ -z "${NIGHT:-}" ]]; then
  if (( hour < 12 )); then NIGHT=$(date -d yesterday +%F); else NIGHT=$(date +%F); fi
fi
RES="$LAB/results/desktop/$NIGHT"
mkdir -p "$RES/raw" "$RES/qc" "$RES/time" "$RES/energy" "$LAB/run"
LOG="$RES/night.log"
log() { echo "$(date +%FT%T%z) $*" | tee -a "$LOG" >&2; }

exec 9>"$LAB/run/night.lock"
flock -n 9 || { echo "another instance is running" >&2; exit 0; }
[[ -f "$RES/DONE" && "${FORCE:-0}" != 1 ]] && { log "DONE already present for $NIGHT"; exit 0; }
if (( DRY == 0 )); then
  if ! (( hour >= 22 || hour < 4 )); then log "outside window (22:00–03:59 Europe/Rome), refusing"; exit 3; fi
fi
if (( hour >= 22 )); then dday=$(date -d tomorrow +%F); else dday=$(date +%F); fi
SOFT_DL=$(date -d "$dday 04:15" +%s); HARD_DL=$(date -d "$dday 04:30" +%s)
time_left() { echo $(( HARD_DL - $(date +%s) )); }
can_start() { (( $(date +%s) < SOFT_DL )); }

SHA_LIST="$LAB/logs/sha256-night.txt"   # written in daytime by the bench author (sha256sum of every model used)
preflight() {
  log "preflight night=$NIGHT dry=$DRY"
  [[ -x "$ST/llama-bench" ]] || { log "missing stock llama-bench"; exit 4; }
  local k; for k in "${!BN[@]}"; do [[ -x "${BN[$k]}/build/bin/llama-bench" ]] || { log "missing bitnet build $k"; exit 4; }; done
  docker image inspect "$IMAGE" >/dev/null 2>&1 || { log "image $IMAGE missing"; exit 4; }
  if [[ -f "$LAB/run/sha-ok" ]] && [[ -n "$(find "$M" -name '*.gguf' -newer "$LAB/run/sha-ok" -print -quit)" ]]; then
    log "a model is newer than run/sha-ok: re-checking"; rm -f "$LAB/run/sha-ok"
  fi
  if [[ ! -f "$LAB/run/sha-ok" ]]; then
    log "sha256 check of models ..."; (cd / && sha256sum -c --quiet "$SHA_LIST") || { log "sha256 mismatch"; exit 4; }
    touch "$LAB/run/sha-ok"
  fi
  local avail; avail=$(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo)
  log "MemAvailable=${avail}GiB (the local inference server still up)"; (( avail >= 20 )) || { log "less than 20 GiB available, refusing"; exit 4; }
  # [redacted] check that the local inference server is up before stopping it
  sudo -n true 2>/dev/null && log "sudo -n ok (RAPL energy enabled)" || log "no sudo -n: energy not measured"
  { date; uname -a; lscpu; free -g; uptime; docker ps --format '{{.Names}} {{.Status}}';
    "$ST/llama-bench" --version 2>&1 | tail -2 || true; docker image inspect -f '{{.Id}}' "$IMAGE";
    for k in "${!BN[@]}"; do echo "bitnet $k: $(git -C "$LAB/src/BitNet" rev-parse HEAD 2>/dev/null) build dir ${BN[$k]}"; done;
    echo "--- active user services"; systemctl --user list-units --type=service --state=active --no-legend --plain 2>/dev/null | awk '{print $1}'; } > "$RES/env.txt" 2>&1
}

STOPPED=0
# [redacted] The operator's local inference server was stopped before the runs and restored afterwards, with a
# health check (functions stop_vllm / restore). That code is specific to the host and is not published.
restore() { local rc=$?; set +e; trap - EXIT; docker rm -f bnb-bench >/dev/null 2>&1; exit "$rc"; }  # [redacted stub]
stop_vllm() { :; }  # [redacted stub]

state() { echo "load=$(cut -d' ' -f1-3 /proc/loadavg) memavail=$(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo)G"; }
cool() { sleep "$COOL"; local i; for i in $(seq 1 30); do awk '{exit !($1<2.5)}' /proc/loadavg && return; sleep 10; done; log "WARN load still $(cut -d' ' -f1 /proc/loadavg)"; }
rapl() { sudo -n cat /sys/class/powercap/intel-rapl:0/energy_uj 2>/dev/null || echo NA; }

# run <out-name> <engine:st|head|01eb415|v0> <model-relative-to-models> <threads> <timeout-s> <llama-bench args...>
run() {
  local name=$1 eng=$2 model=$3 t=$4 to=$5; shift 5
  local out="$RES/raw/$name.json"
  [[ -s "$out" && "${FORCE:-0}" != 1 ]] && return 0
  can_start || { log "soft deadline reached, skip $name"; return 0; }
  local bin binmount
  if [[ $eng == st ]]; then bin=/st; binmount=(-v "$ST:/st:ro"); else bin=/w/build/bin; binmount=(-v "${BN[$eng]}:/w:ro"); fi
  cool
  # D1: re-check after the cool-down; never pass 0 or a negative value to timeout
  can_start || { log "soft deadline reached after cool-down, skip $name"; return 0; }
  local left; left=$(time_left)
  (( left >= 120 )) || { log "less than 2 min to the hard deadline, skip $name"; return 0; }
  (( to > left - 30 )) && to=$(( left - 30 ))
  # D2: memory cap for the container, no swap
  local lim; lim=$(( $(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo) - 3 ))
  (( lim > 48 )) && lim=48; (( lim < 8 )) && lim=8
  log "START $name $(state) timeout=${to}s memcap=${lim}G"
  local e0; e0=$(rapl)
  docker run --rm --name bnb-bench --network none --cpuset-cpus 0-11 --memory "${lim}g" --memory-swap "${lim}g" \
    -u "$(id -u):$(id -g)" "${binmount[@]}" -v "$M:/models:ro" "$IMAGE" \
    timeout --kill-after=20 "$to" /usr/bin/time -v "$bin/llama-bench" -m "/models/$model" -t "$t" -ngl 0 -o json "$@" \
    > "$out.tmp" 2> "$RES/time/$name.txt" &
  local rc=0; wait $! || rc=$?
  if (( rc == 0 )); then mv "$out.tmp" "$out"
  else mv -f "$out.tmp" "$RES/raw/$name.failed" 2>/dev/null || true; log "FAIL $name rc=$rc (output in raw/$name.failed)"; fi  # D3
  local e1; e1=$(rapl)
  echo "$name e0_uj=$e0 e1_uj=$e1 end=$(date +%s)" >> "$RES/energy/rapl.txt"
  log "END   $name $(state)"
}

bench_all() {  # $@ = thread counts, in order (Antonio 2026-11-18: t6 -> 100B -> t12 -> t2 -> energy)
  local t inv
  for t in "$@"; do for inv in 1 2 3; do
    local P=(-p 512 -n 128 -r 5)
    run bn-i2s-head-t$t-i$inv       head    2b4t-gguf/ggml-model-i2_s.gguf               $t 1200 "${P[@]}"
    run bn-i2s-01eb415-t$t-i$inv    01eb415 2b4t-gguf/ggml-model-i2_s.gguf               $t 1200 "${P[@]}"
    run bn-i2s-v0-t$t-i$inv         v0      2b4t-gguf/ggml-model-i2_s.gguf               $t 1200 "${P[@]}"
    run ll-f16-t$t-i$inv            st      mainline/proxy2b4t-f16.gguf                  $t 1800 "${P[@]}"
    run ll-tq2-t$t-i$inv            st      mainline/proxy2b4t-tq2_0.gguf                $t 1200 "${P[@]}"
    run ll-tq2-embf16-t$t-i$inv     st      mainline/proxy2b4t-tq2_0-embf16.gguf         $t 1200 "${P[@]}"
    run ll-tq1-t$t-i$inv            st      mainline/proxy2b4t-tq1_0.gguf                $t 1200 "${P[@]}"
    run ll-q40-t$t-i$inv            st      mainline/proxy2b4t-q4_0.gguf                 $t 1200 "${P[@]}"
    run ll-qwen-q4km-t$t-i$inv      st      qwen/qwen2.5-1.5b-instruct-q4_k_m.gguf       $t 1200 "${P[@]}"
    run bn-large-i2s-head-t$t-i$inv head    conv/large-i2s-x86.gguf                      $t 900  "${P[@]}"
    run ll-large-f16-t$t-i$inv      st      mainline/large-f16.gguf                      $t 900  "${P[@]}"
    run ll-large-tq2-t$t-i$inv      st      mainline/large-tq2_0.gguf                    $t 900  "${P[@]}"
    run ll-large-tq1-t$t-i$inv      st      mainline/large-tq1_0.gguf                    $t 900  "${P[@]}"
    run ll-large-q40-t$t-i$inv      st      mainline/large-q4_0.gguf                     $t 900  "${P[@]}"
  done; done
}
energy_all() {  # tg-only runs at t=6 for J/token (package counter, includes the rest of the host)
  local s0 s1; s0=$(rapl); sleep 60; s1=$(rapl); echo "idle60s e0_uj=$s0 e1_uj=$s1" >> "$RES/energy/rapl.txt"
  local r
  for r in "bn-i2s-head head 2b4t-gguf/ggml-model-i2_s.gguf" "ll-f16 st mainline/proxy2b4t-f16.gguf" \
           "ll-tq2-embf16 st mainline/proxy2b4t-tq2_0-embf16.gguf" "ll-qwen-q4km st qwen/qwen2.5-1.5b-instruct-q4_k_m.gguf"; do
    set -- $r; run energy-$1-t6 $2 $3 6 900 -p 0 -n 256 -r 3
  done
}
dummy_100b() {
  [[ "${SKIP_100B:-0}" == 1 ]] && return 0
  local avail; avail=$(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo)
  (( avail >= 32 )) || { log "100B skipped: MemAvailable ${avail}GiB < 32"; return 0; }
  run dummy100b-ll-tq2-t6     st   dummy/100B-tq2_0.gguf 6 2400 -p 64 -n 32 -r 3
  run dummy100b-bn-i2s-head-t6 head dummy/100B-i2_s.gguf 6 2400 -p 64 -n 32 -r 3
  run dummy100b-ll-tq2-t12    st   dummy/100B-tq2_0.gguf 12 2400 -p 64 -n 32 -r 3
  run dummy100b-bn-i2s-head-t12 head dummy/100B-i2_s.gguf 12 2400 -p 64 -n 32 -r 3
}

preflight
(( DRY == 1 )) && { log "dry-run ok"; exit 0; }
trap restore EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
stop_vllm
# Order (Antonio, 2026-11-18): t6 first (core x86 data for the verdict), then the two 100B layouts
# (so they cannot be cut by the 04:15 soft deadline), then t12, t2, energy.
bench_all 6
dummy_100b
bench_all 12
bench_all 2
energy_all
touch "$RES/DONE"; log "night done"
