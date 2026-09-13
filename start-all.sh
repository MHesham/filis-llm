#!/usr/bin/env bash
# Bring up vLLM + Open WebUI, e.g. after restoring this instance from a snapshot.
set -euo pipefail
cd "$(dirname "$0")"

# start-vllm.sh checks that the selected model folder exists.
[ -e .env ] || { echo "Missing .env — see 'Setup from a fresh clone' in README.md"; exit 1; }

./start-vllm.sh
./start-webui.sh

INSTANCE_ID=$(python3 -c "import json; print(json.load(open('/etc/thunder/config.json'))['deviceId'])")
PUBLIC_URL="https://${INSTANCE_ID}-3000.thundercompute.net"

echo "Waiting for vLLM to load the model (typically 11-13 minutes)..."
for i in $(seq 1 180); do
  [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/health)" = 200 ] && break
  if [ "$(docker inspect -f '{{.State.Status}}' vllm 2>/dev/null)" != running ]; then
    echo "vLLM container stopped. Last logs:"; docker logs vllm 2>&1 | tail -30; exit 1
  fi
  sleep 10
done
[ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/health)" = 200 ] || { echo "vLLM not ready after 30 minutes; check: docker logs vllm"; exit 1; }

echo
echo "vLLM:       ready"
echo "Open WebUI: $(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/health) (200 = ok)"
echo "Public URL: $PUBLIC_URL"
if [ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$PUBLIC_URL")" = 200 ]; then
  echo "Public URL is reachable."
else
  echo "Public URL not reachable yet. From your laptop run:  tnr ports forward $INSTANCE_ID --add 3000"
fi
