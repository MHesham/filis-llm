#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source .env
mkdir -p data/open-webui

# PUBLIC_DOMAIN (set in .env) fronts this with a stable domain via Cloudflare Tunnel —
# see start-cloudflared.sh. Without it, restoring a snapshot creates a new instance with
# a new ID, which changes the public URL.
if [ -n "${PUBLIC_DOMAIN:-}" ]; then
  PUBLIC_URL="https://${PUBLIC_DOMAIN}"
else
  INSTANCE_ID=$(python3 -c "import json; print(json.load(open('/etc/thunder/config.json'))['deviceId'])")
  PUBLIC_URL="https://${INSTANCE_ID}-3000.thundercompute.net"
fi

docker rm -f open-webui 2>/dev/null || true

# New sign-ups land as "pending" until an admin approves them.
# Analytics opt-outs: DO_NOT_TRACK and SCARF_NO_ANALYTICS are read by bundled libraries
# (huggingface_hub, unstructured). ANONYMIZED_TELEMETRY is not read by the current image; kept in
# case a future version uses it. See PRIVACY.md.
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
  -e ENABLE_ADMIN_CHAT_ACCESS=False \
  -e ENABLE_ADMIN_EXPORT=False \
  -e ANONYMIZED_TELEMETRY=False \
  -e DO_NOT_TRACK=true \
  -e SCARF_NO_ANALYTICS=true \
  ghcr.io/open-webui/open-webui:main

echo "Open WebUI starting on port 3000; follow with: docker logs -f open-webui"
