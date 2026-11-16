#!/usr/bin/env bash
# Debunking AI pilot — desktop night GPU bench (RTX 3080 12 GB).
#
# What it does (protocol/PROTOCOL.md §3, desktop):
#   1. Guards: start window 22:00–03:59 Europe/Rome, single instance (flock), preflight checks.
#   2. [redacted] Stopped the operator's resident inference server (site-specific).
#   3. Runs llama-bench (llama.cpp b12034 CUDA, prebuilt, in a throwaway container: no network,
#      no env, read-only binaries/models) at 12 GB and with a VRAM ballast leaving 8 GiB free.
#   4. [redacted] Restored the inference server on exit (site-specific).
#
# Idempotent: each step writes its own result file and is skipped on re-run; a finished night
# leaves results/desktop/<night>/DONE. Hard deadline: no new step after 04:15, bench killed at 04:30.
#
# Usage:  poc/desktop-night.sh            (real run, in window)
#         poc/desktop-night.sh --dry-run  (preflight only: no vLLM stop, no GPU use; any time)
# Env:    NIGHT=<YYYY-MM-DD> to resume a given night dir (default: the evening date of the window)
# NOTE (public copy): this is the runner used on the night of 2026-11-02, with paths parameterised.
# On the test machine a resident local inference server (vLLM, behind a gateway) held the GPU.
# The original stopped it before the bench, checked VRAM was released, and restored it on exit
# (trap), checking its health endpoint. That part depends on the operator's private stack and is
# replaced below by stubs marked [redacted]: before running, make sure no other process uses the GPU.
# Set LAB to a folder with bin/cuda/llama-b12034, bin/cuda/cudart-..., models/, protocol/prompts/, data/.
set -Eeuo pipefail
export TZ=Europe/Rome

LAB="${LAB:?set LAB to the lab folder}"
LLAMA_DIR="$LAB/bin/cuda/llama-b12034"
MODELS="$LAB/models"
M35=Qwen3.6-35B-A3B-UD-IQ4_XS.gguf
M27=Qwen3.6-27B-IQ4_XS.gguf
SHA35=649d7508507b84638732c4f52c24c8b15843c6dca2f3ff793ae07c14a67ebbb3
SHA27=8a3365759dc1b33b52c4e7d91d5a67d5ee1418e8408aa54196f04a98da53e5dc
CUDART_DIR="$LAB/bin/cuda/cudart-llama-b12034-bin-ubuntu-cuda-12.8-x64"
# Runtime userland only (Ubuntu 24.04 + libgomp/ssl): its own llama.cpp is NOT used, entrypoint is overridden.
RUN_IMAGE=ghcr.io/ggml-org/llama.cpp@sha256:3e7673cce183a55f97a1bc3c80817f3c61452483c13bc088a6766388af4775fe
BALLAST_IMAGE=vllm/vllm-openai:v0.30.0     # already on the host; used only for torch.cuda allocation
CPUS=10                                    # leave 2 threads to the host
THREADS=6                                  # physical cores of the i7-8700K
COMMON=(-p 512 -n 128 -ctk q8_0 -ctv q8_0 -fa on -o json)
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1

hour=$((10#$(date +%H)))
if [[ -z "${NIGHT:-}" ]]; then
  if (( hour < 12 )); then NIGHT=$(date -d yesterday +%F); else NIGHT=$(date +%F); fi
fi
RES="$LAB/results/desktop/$NIGHT"
mkdir -p "$RES/raw" "$RES/qc" "$LAB/run"
LOG="$RES/night.log"
log() { echo "$(date +%FT%T%z) $*" | tee -a "$LOG" >&2; }

# ---------- guards ----------
exec 9>"$LAB/run/night.lock"
flock -n 9 || { echo "another instance is running" >&2; exit 0; }
[[ -f "$RES/DONE" && "${FORCE:-0}" != 1 ]] && { log "DONE already present for $NIGHT, nothing to do"; exit 0; }
if (( DRY == 0 )); then
  if ! (( hour >= 22 || hour < 4 )); then log "outside window (22:00–03:59 Europe/Rome), refusing"; exit 3; fi
fi
# deadline: next 04:15 (no new step after it) and 04:30 (kill bench)
if (( hour >= 22 )); then dday=$(date -d tomorrow +%F); else dday=$(date +%F); fi
SOFT_DL=$(date -d "$dday 04:15" +%s); HARD_DL=$(date -d "$dday 04:30" +%s)
time_left() { echo $(( HARD_DL - $(date +%s) )); }
can_start() { (( $(date +%s) < SOFT_DL )); }

# ---------- preflight ----------
preflight() {
  log "preflight night=$NIGHT dry=$DRY"
  [[ -x "$LLAMA_DIR/llama-bench" ]] || { log "missing $LLAMA_DIR/llama-bench"; exit 4; }
  for f in "$M35:$SHA35" "$M27:$SHA27"; do
    local n=${f%%:*} s=${f##*:} mark="$LAB/run/sha-ok-${f%%:*}"
    [[ -f "$MODELS/$n" ]] || { log "missing model $n"; exit 4; }
    if [[ ! -f "$mark" ]]; then
      log "sha256 $n ..."
      echo "$s  $MODELS/$n" | sha256sum -c --quiet - || { log "sha256 mismatch $n"; exit 4; }
      touch "$mark"
    fi
  done
  docker info --format '{{json .Runtimes}}' | grep -q nvidia || { log "no nvidia runtime"; exit 4; }
  docker image inspect "$RUN_IMAGE" >/dev/null 2>&1 || { log "run image $RUN_IMAGE not present"; exit 4; }
  docker image inspect "$BALLAST_IMAGE" >/dev/null 2>&1 || { log "ballast image missing"; exit 4; }
  local avail; avail=$(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo)
  log "MemAvailable=${avail}GiB"; (( avail >= 20 )) || { log "less than 20 GiB available, refusing"; exit 4; }
  { date; uname -a; nvidia-smi; free -g; nproc; uptime; "$LLAMA_DIR/llama-bench" --version 2>&1 | tail -2 || true
    docker image inspect -f '{{.Id}} {{.RepoDigests}}' "$RUN_IMAGE"; } > "$RES/env.txt" 2>&1
}

# ---------- [redacted] inference server stop/restore (site-specific) ----------
STOPPED=0
restore() {
  local rc=$?
  set +e
  trap - EXIT
  local j; for j in $(jobs -p); do kill "$j" 2>/dev/null; done
  docker rm -f dbk-bench dbk-ballast >/dev/null 2>&1
  exit "$rc"
}
stop_vllm() { # [redacted] original: stop the server, wait until VRAM used < 1500 MiB
  local used; used=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1)
  log "VRAM used before the bench: ${used} MiB"
  (( used < 1500 )) || { log "GPU busy: free it first"; return 1; }
}

# ---------- bench helpers ----------
ballast_on() { # leave $1 MiB free
  docker rm -f dbk-ballast >/dev/null 2>&1 || true
  docker run -d --name dbk-ballast --gpus all --network none --entrypoint python3 "$BALLAST_IMAGE" -c "
import torch, time
torch.cuda.init(); torch.zeros(1, device='cuda')
free, total = torch.cuda.mem_get_info()
n = free - $1 * 2**20
x = torch.empty(max(n, 0), dtype=torch.uint8, device='cuda')
print('ballast_bytes', n, 'free_after', torch.cuda.mem_get_info()[0], flush=True)
time.sleep(10**7)" >/dev/null
  # [review] the original returned the status of the last nvidia-smi|tee, i.e. always 0: a failed ballast
  # would have run the "8g" phase at 12 GB. Now verified explicitly (no grep -q under pipefail: SIGPIPE).
  local logs="" free
  for _ in $(seq 1 60); do
    logs=$(docker logs dbk-ballast 2>&1 || true); [[ $logs == *ballast_bytes* ]] && break
    [[ "$(docker inspect -f '{{.State.Running}}' dbk-ballast 2>/dev/null)" == true ]] || break
    sleep 2
  done
  printf '%s\n' "$logs" >> "$LOG"
  nvidia-smi --query-gpu=memory.used,memory.free --format=csv | tee -a "$LOG" >&2
  free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
  if [[ $logs != *ballast_bytes* ]] || (( free > $1 + 512 || free < $1 - 1024 )); then
    log "ballast failed (free=${free} MiB, target $1 MiB)"; ballast_off; return 1
  fi
}
ballast_off() { docker rm -f dbk-ballast >/dev/null 2>&1 || true; }

# run_bench <name> <model> <gpu:yes|no> <llama-bench args...>; returns llama-bench rc
run_bench() {
  local name=$1 model=$2 gpu=$3; shift 3
  local out="$RES/raw/$name.json"
  [[ -s "$out" || -f "$RES/raw/$name.failed" ]] && { log "skip $name"; [[ -s "$out" ]]; return; }
  can_start || { log "soft deadline reached, not starting $name"; return 99; }
  local gpuflag=(); [[ $gpu == yes ]] && gpuflag=(--gpus all)
  log "run $name: $*"
  echo "llama-bench -m /models/$model ${COMMON[*]} $*" > "$RES/raw/$name.cmd.txt"
  nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -lms 200 > "$RES/raw/$name.vram.txt" 2>/dev/null &
  local smi=$!
  docker rm -f dbk-bench >/dev/null 2>&1 || true
  docker run -d --name dbk-bench "${gpuflag[@]}" --cpus "$CPUS" --network none --user "$(id -u):$(id -g)" \
    --read-only --tmpfs /tmp -e LD_LIBRARY_PATH=/opt/llama:/opt/cudart \
    -v "$LLAMA_DIR":/opt/llama:ro -v "$CUDART_DIR":/opt/cudart:ro -v "$MODELS":/models:ro --entrypoint /opt/llama/llama-bench \
    "$RUN_IMAGE" -m "/models/$model" "${COMMON[@]}" -t "$THREADS" "$@" >/dev/null
  local cid; cid=$(docker inspect -f '{{.Id}}' dbk-bench)
  # the cgroup disappears when the container exits: sample memory.peak (monotonic) while it runs
  ( f="/sys/fs/cgroup/system.slice/docker-$cid.scope/memory.peak"
    while [[ -r "$f" ]]; do v=$(cat "$f" 2>/dev/null) && [[ -n "$v" ]] && echo "$v" > "$RES/raw/$name.mempeak.bytes"; sleep 1; done ) &
  local memp=$!
  # [review] wait in background + `wait`: a trapped signal interrupts `wait` at once (a foreground
  # child would defer the trap until llama-bench ends)
  timeout -k 30 "$(time_left)" docker wait dbk-bench > "$RES/raw/$name.rc" 2>/dev/null &
  wait $! || true
  local rc; rc=$(head -1 "$RES/raw/$name.rc" 2>/dev/null); rc=${rc:-124}; rm -f "$RES/raw/$name.rc"
  [[ "$rc" == 124 ]] && docker kill dbk-bench >/dev/null 2>&1
  docker logs dbk-bench > "$out.tmp" 2> "$RES/raw/$name.stderr.txt"
  docker rm dbk-bench >/dev/null 2>&1 || true
  kill "$smi" "$memp" 2>/dev/null || true
  echo "rc=$rc" >> "$RES/raw/$name.cmd.txt"
  if [[ "$rc" == 0 ]]; then mv "$out.tmp" "$out"; return 0; fi
  mv "$out.tmp" "$RES/raw/$name.failed.json"; touch "$RES/raw/$name.failed"
  log "  $name failed rc=$rc (recorded as a result)"; return 1
}

# tg mean of a result file (0 if missing)
tg_of() { jq -r '[.[] | select(.n_gen>0) | .avg_ts] | first // 0' "$RES/raw/$1.json" 2>/dev/null || echo 0; }

# ---------- phases ----------
phase_budget() { # $1 = tag (12g|8g)
  local t=$1 d0=(-d 0 -r 5)
  # (a) the article's command: ncmoe 0 and 28, as published
  run_bench "$t-article-ncmoe0"  "$M35" yes -ngl 99 -ncmoe 0  "${d0[@]}" || true
  run_bench "$t-article-ncmoe28" "$M35" yes -ngl 99 -ncmoe 28 "${d0[@]}" || true
  # (b) smallest ncmoe that fits (best use of VRAM), ascending
  local n best_n=""
  for n in 4 8 12 16 20 24 32 40; do
    if run_bench "$t-ncmoe$n" "$M35" yes -ngl 99 -ncmoe "$n" "${d0[@]}"; then best_n=$n; break; fi
  done
  # (c) honest baseline: most layers that fit with classic -ngl (no ncmoe), descending
  local g best_g=""
  for g in 36 32 28 24 20 16 12 8; do
    if run_bench "$t-ngl$g" "$M35" yes -ngl "$g" "${d0[@]}"; then best_g=$g; break; fi
  done
  [[ -n "$best_g" && "$best_g" -gt 8 ]] && run_bench "$t-ngl$((best_g-4))" "$M35" yes -ngl $((best_g-4)) "${d0[@]}" || true
  # (d) auto-fit, no manual placement
  run_bench "$t-fit" "$M35" yes -fitt 1024 "${d0[@]}" || true
  # (e) long context for the winners
  [[ -n "$best_n" ]] && run_bench "$t-ncmoe$best_n-d16k" "$M35" yes -ngl 99 -ncmoe "$best_n" -d 16384 -r 3 || true
  run_bench "$t-article-ncmoe28-d16k" "$M35" yes -ngl 99 -ncmoe 28 -d 16384 -r 3 || true
  [[ -n "$best_g" ]] && run_bench "$t-ngl$best_g-d16k" "$M35" yes -ngl "$best_g" -d 16384 -r 3 || true
  # (f) dense 27B: as published (-ngl 99) and the most layers that fit
  run_bench "$t-dense-ngl99" "$M27" yes -ngl 99 -d 0 -r 3 || true
  for g in 56 48 40 32 24 16; do
    run_bench "$t-dense-ngl$g" "$M27" yes -ngl "$g" -d 0 -r 3 && break
  done
  echo "best_ncmoe=$best_n best_ngl=$best_g" > "$RES/$t-summary.txt"
}

phase_qc() { # greedy + perplexity, 12 GB budget, three placements of the same model
  local P=/lab/protocol/prompts T=/lab/data/pg11-alice.txt
  local best_n; best_n=$(sed -n 's/.*best_ncmoe=\([0-9]*\).*/\1/p' "$RES/12g-summary.txt" 2>/dev/null); best_n=${best_n:-28}
  local cfg
  for cfg in "ncmoe$best_n:-ngl 99 --n-cpu-moe $best_n" "ncmoe28:-ngl 99 --n-cpu-moe 28" "cpu:-ngl 0 -dev none"; do
    local tag=${cfg%%:*} args=${cfg#*:} gpu=yes
    [[ $tag == cpu ]] && gpu=no
    [[ -s "$RES/qc/ppl-$tag.txt" ]] && continue
    can_start || return 0
    local gpuflag=(); [[ $gpu == yes ]] && gpuflag=(--gpus all)
    log "qc $tag"
    # shellcheck disable=SC2086
    # [review] --init (sh as PID 1 ignores SIGTERM), timeout -k, background+wait, rm -f after: on timeout the
    # attached `docker run --rm` did not stop the container and the next cfg failed on the name clash
    docker rm -f dbk-bench >/dev/null 2>&1 || true
    timeout -k 30 "$(time_left)" docker run --rm --init --name dbk-bench "${gpuflag[@]}" --cpus "$CPUS" --network none \
      --user "$(id -u):$(id -g)" --read-only --tmpfs /tmp -e LD_LIBRARY_PATH=/opt/llama:/opt/cudart \
      -v "$LLAMA_DIR":/opt/llama:ro -v "$CUDART_DIR":/opt/cudart:ro -v "$MODELS":/models:ro -v "$LAB":/lab:ro -v "$RES/qc":/out \
      --entrypoint /bin/sh "$RUN_IMAGE" -c "
        for p in $P/greedy-*.txt; do b=\$(basename \$p .txt);
          /opt/llama/llama-completion -m /models/$M35 $args -t $THREADS -f \$p -n 200 --temp 0 --seed 42 -c 4096 \
            -no-cnv --no-display-prompt -fit off -fa on -ctk q8_0 -ctv q8_0 > /out/\$b-$tag.txt 2> /out/\$b-$tag.log </dev/null; done
        /opt/llama/llama-perplexity -m /models/$M35 $args -t $THREADS -f $T -c 2048 --chunks 16 -fit off -fa on \
            -ctk q8_0 -ctv q8_0 > /out/ppl-$tag.txt 2>&1 </dev/null" &
    wait $! || log "qc $tag failed"
    docker rm -f dbk-bench >/dev/null 2>&1 || true
  done
}

phase_cpu() {
  run_bench "cpu-d0" "$M35" no -ngl 0 -dev none -d 0 -r 3 || true
}

# ---------- main ----------
preflight
if (( DRY == 1 )); then
  log "dry-run: preflight OK, GPU free MiB now: $(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)"
  exit 0
fi
trap restore EXIT
trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
stop_vllm
phase_budget 12g
if can_start; then
  ballast_on 8192 && phase_budget 8g || log "8 GB phase skipped/failed"
  ballast_off
fi
phase_qc
phase_cpu
can_start && touch "$RES/DONE" || log "stopped at deadline: re-run another night to finish (idempotent)"
log "bench finished, restoring"
exit 0
