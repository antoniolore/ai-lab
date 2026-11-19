#!/bin/bash
# Mac runner — bitnet-cpu bench (PROTOCOL.md §3, changelog 2026-11-18). CPU only.
# Usage: mac-run.sh [bench|qc|all]   Idempotent: skips outputs that exist unless FORCE=1.
set -u
W=$LAB
R=${RDIR:-$W/results/mac}; mkdir -p $R/raw $R/qc $R/time
ST=$W/bin/llama-b12503/llama-b12503          # stock llama.cpp b12503 (Metal disabled with -dev none)
BN_V0=$W/src/BitNet-404980e/build/bin        # bitnet.cpp 404980e — Mac reference (correct output)
BN_01=$W/src/BitNet-01eb415/build/bin        # bitnet.cpp 01eb415 — fast, invalid output on M4
BN_HD=$W/src/BitNet/build/bin                # bitnet.cpp HEAD 0b341e5 — scalar, invalid output
M=$W/models; MM=$M/mainline
LOG=$R/run.log
COOL=${COOL:-20}; LOADMAX=${LOADMAX:-6.0}

log(){ echo "$(date '+%F %T') $*" | tee -a $LOG; }
state(){ echo "load=$(sysctl -n vm.loadavg | tr -d '{}' | xargs) swap=$(sysctl -n vm.swapusage | awk '{print $6}') pressure=$(sysctl -n kern.memorystatus_vm_pressure_level) therm=$(pmset -g therm 2>/dev/null | grep -c -i warning)"; }
cool(){ local i l; sleep $COOL; for i in $(seq 1 30); do l=$(sysctl -n vm.loadavg | awk '{print $2}'); awk -v l=$l -v m=$LOADMAX 'BEGIN{exit !(l<m)}' && return; sleep 10; done; log "WARN load still $l after cool-down"; }

# bench <row> <bin-dir> <model> <threads> <invocations> <reps> [extra...]
bench(){
  local row=$1 bin=$2 model=$3 t=$4 inv=$5 reps=$6; shift 6
  for i in $(seq 1 $inv); do
    local out=$R/raw/$row-t$t-i$i.json
    [ -s $out ] && [ "${FORCE:-0}" != 1 ] && continue
    cool
    log "START $row t=$t i=$i $(state)"
    /usr/bin/time -l $bin/llama-bench -m $model -p 512 -n 128 -r $reps -t $t -ngl 0 -o json "$@" > $out 2> $R/time/$row-t$t-i$i.txt
    log "END   $row t=$t i=$i rc=$? $(state)"
  done
}

run_bench(){
  log "=== bench session $(state)"
  for t in 12 2; do
    bench bn-i2s-v0        $BN_V0 $M/2b4t-gguf/ggml-model-i2_s.gguf          $t 3 5
    bench ll-f16           $ST    $MM/proxy2b4t-f16.gguf                     $t 3 5 -dev none
    bench ll-tq2           $ST    $MM/proxy2b4t-tq2_0.gguf                   $t 3 5 -dev none
    bench ll-tq2-embf16    $ST    $MM/proxy2b4t-tq2_0-embf16.gguf            $t 3 5 -dev none
    bench ll-tq1           $ST    $MM/proxy2b4t-tq1_0.gguf                   $t 3 5 -dev none
    bench ll-q40           $ST    $MM/proxy2b4t-q4_0.gguf                    $t 3 5 -dev none
    bench ll-qwen-q4km     $ST    $M/qwen/qwen2.5-1.5b-instruct-q4_k_m.gguf  $t 3 5 -dev none
    bench bn-large-i2s-v0  $BN_V0 $M/conv/large-i2s-arm-404980e.gguf         $t 3 5
    bench ll-large-f16     $ST    $MM/large-f16.gguf                         $t 3 5 -dev none
    bench ll-large-tq2     $ST    $MM/large-tq2_0.gguf                       $t 3 5 -dev none
    bench ll-large-tq1     $ST    $MM/large-tq1_0.gguf                       $t 3 5 -dev none
    bench ll-large-q40     $ST    $MM/large-q4_0.gguf                        $t 3 5 -dev none
    [ "${SKIP_01:-0}" = 1 ] || bench bn-i2s-01eb415-INVALID $BN_01 $M/conv/bitnet-2b4t-i2s-arm-01eb415.gguf $t 3 5
  done
  bench bn-i2s-head-INVALID $BN_HD $M/2b4t-gguf/ggml-model-i2_s.gguf 12 1 3
  log "=== bench done $(state)"
}

run_qc(){
  local P=$W/prompts T=$W/data/fresh-text.txt
  for p in 1 2; do
    $BN_V0/llama-cli -m $M/2b4t-gguf/ggml-model-i2_s.gguf -f $P/greedy-$p.txt -n 128 --temp 0 --seed 42 -t 12 -ngl 0 > $R/qc/greedy-$p-bn-i2s-v0.txt 2> $R/qc/greedy-$p-bn-i2s-v0.log
    $BN_01/llama-cli -m $M/conv/bitnet-2b4t-i2s-arm-01eb415.gguf -f $P/greedy-$p.txt -n 128 --temp 0 --seed 42 -t 12 -ngl 0 > $R/qc/greedy-$p-bn-i2s-01eb415.txt 2> $R/qc/greedy-$p-bn-i2s-01eb415.log
    $BN_V0/llama-cli -m $M/conv/large-i2s-arm-404980e.gguf -f $P/greedy-$p.txt -n 128 --temp 0 --seed 42 -t 12 -ngl 0 > $R/qc/greedy-$p-bn-large-i2s-v0.txt 2> $R/qc/greedy-$p-bn-large-i2s-v0.log
    for m in large-f16 large-tq2_0 proxy2b4t-f16 proxy2b4t-tq2_0; do
      $ST/llama-completion -m $MM/$m.gguf -f $P/greedy-$p.txt -n 128 --temp 0 --seed 42 -t 12 -ngl 0 -dev none -no-cnv > $R/qc/greedy-$p-ll-$m.txt 2> $R/qc/greedy-$p-ll-$m.log
    done
  done
  $BN_V0/llama-perplexity -m $M/2b4t-gguf/ggml-model-i2_s.gguf -f $T -c 512 --chunks 16 -t 12 -ngl 0 > $R/qc/ppl-bn-i2s-v0.txt 2>&1
  $BN_V0/llama-perplexity -m $M/conv/large-i2s-arm-404980e.gguf -f $T -c 512 --chunks 16 -t 12 -ngl 0 > $R/qc/ppl-bn-large-i2s-v0.txt 2>&1
  for m in large-f16 large-tq2_0; do
    $ST/llama-perplexity -m $MM/$m.gguf -f $T -c 512 --chunks 16 -t 12 -ngl 0 -dev none > $R/qc/ppl-ll-$m.txt 2>&1
  done
}

# 100B random-weight layouts (PROTOCOL §3.4): one type at a time, only if >= 8 GB stay free after generation;
# watchdog kills llama-bench at memory pressure "critical" (4); file deleted after the runs.
run_100b(){
  local typ=$1 bin=$2 tpl=$3 extra=$4 f=$M/dummy/100B-$1.gguf need=27
  local free; free=$(df -g ~ | awk 'NR==2{print $4}')
  if (( free - need < 8 )); then log "100B $typ SKIPPED: ${free} GB free, ${need} GB needed, margin < 8 GB"; return; fi
  log "100B $typ generating (free ${free} GB)"
  PYTHONPATH=$W/src/gguf-py $W/.venv/bin/python $W/poc/gen_dummy_bitnet.py --layout 100B --type $typ --template $tpl --out $f >> $LOG 2>&1 || { log "100B $typ generation FAILED"; rm -f $f; return; }
  log "100B $typ generated, free now $(df -g ~ | awk 'NR==2{print $4}') GB"
  ( while sleep 2; do p=$(sysctl -n kern.memorystatus_vm_pressure_level); [ "$p" -ge 4 ] && { pkill llama-bench; echo "$(date '+%F %T') WATCHDOG killed llama-bench (pressure $p)" >> $LOG; }; done ) & local wd=$!
  local i; for i in 1 2 3; do
    local out=$R/raw/dummy100b-$typ-t12-i$i.json
    [ -s $out ] && continue
    cool; log "START dummy100b-$typ t=12 i=$i $(state)"
    /usr/bin/time -l $bin/llama-bench -m $f -p 64 -n 32 -r 3 -t 12 -ngl 0 -o json $extra > $out 2> $R/time/dummy100b-$typ-t12-i$i.txt
    log "END   dummy100b-$typ t=12 i=$i rc=$? $(state)"
  done
  kill $wd 2>/dev/null
  rm -f $f; log "100B $typ file deleted, free now $(df -g ~ | awk 'NR==2{print $4}') GB"
}

case "${1:-all}" in
  bench) run_bench ;;
  qc) run_qc ;;
  all) run_qc; run_bench ;;
  100b) run_100b tq2_0 $ST $MM/large-f16.gguf "-dev none"; run_100b i2_s $BN_V0 $M/conv/large-f32.gguf "" ;;
  clean) run_qc; run_bench; run_100b tq2_0 $ST $MM/large-f16.gguf "-dev none"; run_100b i2_s $BN_V0 $M/conv/large-f32.gguf "" ;;
esac
