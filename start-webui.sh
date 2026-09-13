#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source .env
mkdir -p data/open-webui

# Restoring a snapshot creates a new instance with a new ID, which changes the public URL.
INSTANCE_ID=$(python3 -c "import json; print(json.load(open('/etc/thunder/config.json'))['deviceId'])")
PUBLIC_URL="https://${INSTANCE_ID}-3000.thundercompute.net"

docker rm -f open-webui 2>/dev/null || true

# New sign-ups land as "pending" until an admin approves them.
docker run -d --name open-webui \
  --restart unless-stopped \
  -v "$PWD/data/open-webui:/app/backend/data" \
  -e PORT=3000 \
  -e WEBUI_URL="$PUBLIC_URL" \
  -e CORS_ALLOW_ORIGIN="$PUBLIC_URL" \
  -e OPENAI_API_BASE_URL=http://127.0.0.1:8000/v1 \
  -e OPENAI_API_KEY="$VLLM_API_KEY" \
  -e ENABLE_OLLAMA_API=False \
  -e WEBUI_SECRET_KEY="$WEBUI_SECRET_KEY" \
  -e DEFAULT_USER_ROLE=pending \
  ghcr.io/open-webui/open-webui:main

echo "Open WebUI starting on port 3000; follow with: docker logs -f open-webui"
