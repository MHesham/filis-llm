#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source .env

# Model folder under /home/ubuntu/models. INT4 is the default; use MODEL=Qwen3.8-27B-FP8 ./start-vllm.sh for FP8.
MODEL="${MODEL:-Qwen3.8-27B-W4A16-AutoRound}"
[ -e "/home/ubuntu/models/$MODEL/config.json" ] || { echo "Model not found: /home/ubuntu/models/$MODEL"; exit 1; }

docker rm -f vllm 2>/dev/null || true

# Thunder Compute: GPUs via --device, not --gpus; container network is shared with the host.
# Bound to 127.0.0.1 so only Open WebUI on this machine can reach it.
# VLLM_NO_USAGE_STATS turns off vLLM's anonymized usage-stats reporting.
# --no-enable-log-requests keeps prompt/completion text out of `docker logs vllm` (already the
# default in v0.29.0; set explicitly so it stays off). vLLM refuses to start on an unknown flag and
# this one has been renamed before, so after changing the image re-check with:
#   docker exec vllm vllm serve --help=all | grep log-requests
docker run -d --name vllm \
  --device nvidia.com/gpu=all \
  --ipc=host \
  --restart unless-stopped \
  -e TRITON_LIBCUDA_PATH=/usr/lib/x86_64-linux-gnu \
  -e VLLM_NO_USAGE_STATS=1 \
  -v /home/ubuntu/models:/models:ro \
  vllm/vllm-openai:latest \
  --model "/models/$MODEL" \
  --served-model-name qwen3.8-27b \
  --host 127.0.0.1 --port 8000 \
  --api-key "$VLLM_API_KEY" \
  --max-model-len 131072 \
  --max-num-seqs 16 \
  --gpu-memory-utilization 0.92 \
  --reasoning-parser qwen3 \
  --enable-auto-tool-choice --tool-call-parser qwen3_coder \
  --no-enable-log-requests

echo "vLLM starting; follow with: docker logs -f vllm"
