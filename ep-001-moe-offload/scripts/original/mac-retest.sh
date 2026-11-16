#!/bin/bash
# Mac retest 2026-11-03: main rows only, stop on memory pressure or swap. Results in results-retest-2026-11-03/.
W="$HOME/moe-offload-lab"
export R="$W/results-retest-2026-11-03"
mkdir -p "$R"
for r in mac-gpu-d0 mac-ncmoe28-d0 mac-cpu-d0 mac-gpu-d16k mac-ncmoe28-d16k mac-cpu-d16k; do
  sw=$(sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+)M.*/\1/')
  fr=$(memory_pressure | awk -F': ' '/free percentage/{gsub("%","",$2); print $2}')
  echo "$(date +%T) pre $r swap_used=${sw}M free=${fr}%" | tee -a "$R/guard.log"
  if [[ ${sw%.*} -gt 0 || ${fr:-0} -lt 40 ]]; then echo "STOP: memory pressure/swap" | tee -a "$R/guard.log"; exit 3; fi
  "$W/poc/mac-run.sh" "$r"
done
echo "$(date +%T) done" | tee -a "$R/guard.log"
