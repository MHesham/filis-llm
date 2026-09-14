#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Fronts Open WebUI with a stable custom domain instead of the changing
# thundercompute.net URL. Runs cloudflared as a native package + SysV service, not
# Docker: this instance's container runtime (proot/fastvfs storage driver) fails to
# materialize the cloudflared image, and there's no systemd here either, so
# `cloudflared service install` falls back to a SysV init script under /etc/init.d,
# managed with `service`, not `systemctl`.
#
# One-time setup, before this script will do anything (see "Custom domain
# (Cloudflare Tunnel)" in README.md for the full walkthrough):
#   curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
#   echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
#   sudo apt-get update && sudo apt-get install -y cloudflared
#   source .env && sudo cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN"
#
# That registration writes the token to /etc/cloudflared/token, so it only needs to
# run once per instance — it persists across reboots and snapshot restores since
# it's on disk, same as everything else under /etc. This script just (re)starts it.
#
# Starting at boot: this machine's init is s6-overlay, which never runs /etc/init.d scripts.
# The tunnel is registered as an s6 service in /etc/s6-overlay/s6-rc.d/cloudflared (listed in
# user/contents.d), so after a reboot or snapshot restore s6 starts and supervises it. Until the
# first reboot after that registration, fall back to the SysV script.
[ -x /usr/bin/cloudflared ] || { echo "cloudflared not installed — see README.md 'Custom domain' section."; exit 1; }
[ -f /etc/cloudflared/token ] || { echo "cloudflared not yet registered — see README.md 'Custom domain' section."; exit 1; }

if [ -e /run/service/cloudflared ]; then
  sudo /package/admin/s6/command/s6-svc -u /run/service/cloudflared
  echo "cloudflared (s6): $(sudo /package/admin/s6/command/s6-svstat /run/service/cloudflared)"
else
  sudo service cloudflared start
  echo "cloudflared (init.d): $(sudo service cloudflared status 2>&1)"
fi
