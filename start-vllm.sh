#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source .env

# Model folder under /home/ubuntu/models, e.g. MODEL=Qwen3.8-27B-W4A16-AutoRound ./start-vllm.sh
MODEL="${MODEL:-Qwen3.8-27B-FP8}"
[ -e "/home/ubuntu/models/$MODEL/config.json" ] || { echo "Model not found: /home/ubuntu/models/$MODEL"; exit 1; }

docker rm -f vllm 2>/dev/null || true

# Thunder Compute: GPUs via --device, not --gpus; container network is shared with the host.
# Bound to 127.0.0.1 so only Open WebUI on this machine can reach it.
docker run -d --name vllm \
  --device nvidia.com/gpu=all \
  --ipc=host \
  --restart unless-stopped \
  -e TRITON_LIBCUDA_PATH=/usr/lib/x86_64-linux-gnu \
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
  --enable-auto-tool-choice --tool-call-parser qwen3_coder

echo "vLLM starting; follow with: docker logs -f vllm"
