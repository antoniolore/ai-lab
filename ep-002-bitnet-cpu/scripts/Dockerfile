# Lab image for the bitnet-cpu bench (the bench author, 2026-11-18). Build deps only; runs use --network none.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      clang-18 libomp-18-dev cmake make git python3 python3-venv python3-pip time ca-certificates libgomp1 libcurl4 \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s /usr/bin/clang-18 /usr/bin/clang && ln -s /usr/bin/clang++-18 /usr/bin/clang++
RUN python3 -m venv /venv && /venv/bin/pip install --no-cache-dir --extra-index-url https://download.pytorch.org/whl/cpu \
      "torch==2.11.0" "numpy~=2.2.6" "sentencepiece>=0.1.98,<0.3.0" "transformers==4.57.6" "safetensors" "protobuf>=4.21,<5"
ENV PATH=/venv/bin:$PATH
WORKDIR /work
