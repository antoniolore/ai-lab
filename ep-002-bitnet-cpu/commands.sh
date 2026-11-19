#!/usr/bin/env bash
# ep-002-bitnet-cpu: the benchmark commands (read before running). The runners actually used are in scripts/
# (desktop-night.sh, mac-run.sh); this file lists the commands they issue. MIT licence.
set -euo pipefail
B=${B:-512}; N=${N:-128}

# --- x86 (i7-8700K), inside a container with --network none, CPUs 0-11; threads 6, 12, 2; 3 invocations per row,
#     30 s cool-down plus load < 2.5 between invocations
for T in 6 12 2; do
  llama-bench -m ggml-model-i2_s.gguf               -t $T -ngl 0 -o json -p $B -n $N -r 5   # bitnet.cpp, official 2B4T file
  llama-bench -m proxy2b4t-f16.gguf                 -t $T -ngl 0 -o json -p $B -n $N -r 5   # stock, F16 (the report's baseline type)
  llama-bench -m proxy2b4t-tq2_0-embf16.gguf        -t $T -ngl 0 -o json -p $B -n $N -r 5   # stock, TQ2_0, F16 embeddings
  llama-bench -m proxy2b4t-tq2_0.gguf               -t $T -ngl 0 -o json -p $B -n $N -r 5   # stock, TQ2_0 default
  llama-bench -m proxy2b4t-tq1_0.gguf               -t $T -ngl 0 -o json -p $B -n $N -r 5
  llama-bench -m proxy2b4t-q4_0.gguf                -t $T -ngl 0 -o json -p $B -n $N -r 5
  llama-bench -m qwen2.5-1.5b-instruct-q4_k_m.gguf  -t $T -ngl 0 -o json -p $B -n $N -r 5
  # 0.7B pair (bitnet_b1_58-large): large-i2s (bitnet.cpp), large-f16 / -tq2_0 / -tq1_0 / -q4_0 (stock), same flags
done

# --- Mac (M4 Max CPU): same lines at -t 12 and -t 2; stock llama.cpp with -dev none (Metal off); 45 s cool-down + load < 3.5

# --- 100B random-weight layout (x86 -t 6 and -t 12, 1 invocation; Mac -t 12, 3 invocations)
llama-bench -m 100B-tq2_0.gguf -t 6 -ngl 0 -o json -p 64 -n 32 -r 3   # stock llama.cpp
llama-bench -m 100B-i2_s.gguf  -t 6 -ngl 0 -o json -p 64 -n 32 -r 3   # bitnet.cpp

# --- Energy (x86 only): decode-only, package counter read before and after (needs root)
cat /sys/class/powercap/intel-rapl:0/energy_uj
llama-bench -m <model> -t 6 -ngl 0 -o json -p 0 -n 256 -r 3
cat /sys/class/powercap/intel-rapl:0/energy_uj

# Each invocation was wrapped in GNU `time -v` (Linux) or `/usr/bin/time -l` (macOS) for peak memory.
