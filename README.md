# Qwen Platform

Self-hosted **Qwen3.8-27B** (INT4 weights by default, FP8 available) served by **vLLM**, with **Open WebUI** as the multi-user chat front end, running on a Thunder Compute GPU instance.

- **Public chat URL:** `https://<instance-id>-3000.thundercompute.net` (`start-all.sh` prints the current one)
- **Model name in APIs:** `qwen3.8-27b`

> The instance ID, and therefore the URL, changes every time the machine is restored from a snapshot. `start-webui.sh` works it out automatically. Set `PUBLIC_DOMAIN` in `.env` to front this with your own domain instead — see [Custom domain (Cloudflare Tunnel)](#custom-domain-cloudflare-tunnel).

---

## Architecture

```
 Users (browser / coding tools)
            │  HTTPS (Thunder port forward, port 3000)
            ▼
 ┌─────────────────────────┐        ┌──────────────────────────────┐
 │ Open WebUI  :3000       │ ─────▶ │ vLLM  127.0.0.1:8000         │
 │ accounts, chats, API    │  key   │ Qwen3.8-27B INT4 on L40      │
 └─────────────────────────┘        └──────────────────────────────┘
```

- **vLLM** listens only on `127.0.0.1` and requires an API key, so it is never reachable from the internet.
- **Open WebUI** is the only public service. It handles logins and forwards requests to vLLM.

| Component | Details |
|---|---|
| GPU | 1× NVIDIA L40, 46GB (Ada Lovelace). Previously RTX A6000; see `BENCHMARKS.md` |
| Host | Thunder Compute instance, 250GB disk |
| Model (default) | `dbirks/Qwen3.8-27B-W4A16-AutoRound`, INT4 weights, 17.7GB on GPU, vision + tools + thinking |
| Model (fallback) | `Qwen/Qwen3.8-27B-FP8`, 28.9GB on GPU; slower on this GPU but slightly closer to the original model |
| Inference server | `vllm/vllm-openai:latest` (v0.29.0) |
| Chat UI | `ghcr.io/open-webui/open-webui:main` (v0.11.3 at setup) |
| Context window | 131,072 tokens per request; ~329K tokens of conversation memory shared across users (INT4 on the L40) |

---

## Files

| Path | Purpose |
|---|---|
| `start-all.sh` | Starts vLLM and Open WebUI, waits for the model, prints the public URL. **Use this after a restore.** |
| `start-vllm.sh` | (Re)creates the `vllm` container. Pick the model with `MODEL=`. |
| `start-webui.sh` | (Re)creates the `open-webui` container with the current instance's public URL, or `PUBLIC_DOMAIN` if set. |
| `start-cloudflared.sh` | Optional: fronts Open WebUI with `PUBLIC_DOMAIN` via Cloudflare Tunnel. |
| `.env.example` | Template for `.env`. |
| `.gitignore` | Keeps secrets, the Open WebUI database, and model weights out of Git. |
| `MEMORY.md` | Gotchas and lessons learned. Read before changing anything. |
| `BENCHMARKS.md` | Measured speed, capacity, and cost: RTX A6000 vs L40, FP8 vs INT4. |
| `benchmarks/loadtest.py` | The load test behind those numbers. |

Local-only (not in Git):

| Path | Purpose |
|---|---|
| `.env` | Secrets: `VLLM_API_KEY`, `WEBUI_SECRET_KEY`. Mode 600. **Never commit or share.** |
| `admin-credentials.txt` | Optional note of the Open WebUI admin login. Mode 600. |
| `data/open-webui/` | Open WebUI database: users, chats, settings. Back this up. |
| `/home/ubuntu/models/Qwen3.8-27B-W4A16-AutoRound/` | INT4 model weights (19GB), the default. |
| `/home/ubuntu/models/Qwen3.8-27B-FP8/` | FP8 model weights (28GB), kept for rollback. Select with `MODEL=Qwen3.8-27B-FP8`. |

---

## Setup from a fresh clone

Requirements: a Thunder Compute instance with a 46GB+ NVIDIA GPU (tested on RTX A6000 and L40) and a disk of at least 250GB. Docker images are unpacked in full every time a container starts.

```bash
git clone git@github.com:MHesham/filis-llm.git ~/qwen-platform
cd ~/qwen-platform

# 1. Secrets
umask 077 && printf 'VLLM_API_KEY=%s\nWEBUI_SECRET_KEY=%s\n' \
  "$(openssl rand -hex 32)" "$(openssl rand -hex 32)" > .env

# 2. Model weights: INT4, the default (~19GB)
pip install --user -U "huggingface_hub[hf_xet]"
~/.local/bin/hf download dbirks/Qwen3.8-27B-W4A16-AutoRound --local-dir /home/ubuntu/models/Qwen3.8-27B-W4A16-AutoRound
#    Optional FP8 fallback (~28GB):
#    ~/.local/bin/hf download Qwen/Qwen3.8-27B-FP8 --local-dir /home/ubuntu/models/Qwen3.8-27B-FP8

# 3. Start everything (first start takes ~9–13 min)
./start-all.sh
```

4. **Right away, before sharing the URL**, open the public URL it prints and sign up. The first account becomes admin. Forwarded ports have no login of their own, so anyone who gets there first could claim it.

---

## Day-to-day operations

```bash
cd ~/qwen-platform

./start-all.sh            # start or restart everything and wait until ready
./start-vllm.sh           # restart only the model server with INT4 (~9–13 min to load)
MODEL=Qwen3.8-27B-FP8 ./start-vllm.sh   # same, with the FP8 weights instead
./start-webui.sh          # restart only Open WebUI (~30s)

docker ps                 # both containers should be "Up"
docker logs -f vllm       # model server logs
docker logs -f open-webui # UI logs
curl -s localhost:8000/health -o /dev/null -w '%{http_code}\n'   # 200 = model ready
```

- Both containers use `--restart unless-stopped`, so they come back after a crash or reboot.
- While vLLM is loading, Open WebUI works but lists no model.
- The vLLM log prints a harmless `deep_ep ... FileNotFoundError` trace at startup. Ignore it.

---

## Managing users (Open WebUI)

- **Your admin account:** see `admin-credentials.txt`.
- **Sign-ups:** anyone with the URL can sign up, but new accounts are **pending** until an admin approves them in **Admin Panel → Users** (change role to *user*).
- **Invite-only:** add accounts in **Admin Panel → Users → Add User**, then turn off sign-up in **Admin Panel → Settings → General**.
- **Hide the built-in `arena-model`** entry in the admin model settings if users find it confusing.

---

## Using the model from code and coding agents

Tool calling is verified on every route below, including streamed tool calls.

### Option A: through Open WebUI (remote, per-user keys)

1. Admin: **Admin Panel → Settings → General → enable API Keys** (off by default).
2. Each user: **Settings → Account → API Keys → create key**.
3. Point any OpenAI-compatible client at:
   - Base URL: `https://<your-domain>/api` (`/api/v1` also works) — your `PUBLIC_DOMAIN`
     from `.env` if set, otherwise the `<instance-id>-3000.thundercompute.net` URL
   - API key: the user's Open WebUI key
   - Model: `qwen3.8-27b`

### Option B: directly against vLLM (on the instance, or through an SSH tunnel)

```bash
ssh -L 8000:127.0.0.1:8000 <instance>     # from your laptop, if not on the instance
```

- OpenAI format: `http://127.0.0.1:8000/v1`
- Anthropic Messages format: `http://127.0.0.1:8000/v1/messages`
- Key: `VLLM_API_KEY` from `.env`

### Qwen Code (Qwen's terminal coding agent)

Node.js isn't preinstalled on this instance. Install Node 22+, then Qwen Code:

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
npm install -g @qwen-code/qwen-code@latest
```

`~/.qwen/settings.json`:

```json
{
  "modelProviders": {
    "openai": [
      { "id": "qwen3.8-27b", "name": "Self-hosted Qwen3.8-27B",
        "baseUrl": "https://<your-domain>/api/v1",
        "envKey": "OPENAI_API_KEY" }
    ]
  },
  "security": { "auth": { "selectedType": "openai" } },
  "model": { "name": "qwen3.8-27b" }
}
```

Then run `export OPENAI_API_KEY=<your Open WebUI key>` and `qwen`.

**Cline / Roo Code (VS Code):** choose provider *OpenAI Compatible*, then enter the same base URL, key, and model ID.

**Claude Code:** not an option. Anthropic doesn't support routing Claude Code to non-Claude models.

### Thinking and sampling

- **Thinking is on by default** (`reasoning_effort=xhigh`), so answers start late.
- **Faster starts:** send `reasoning_effort: "medium"` or `"low"`, or turn thinking off with `chat_template_kwargs: {"enable_thinking": false}`.
- **Qwen's recommended sampling:**
  - Thinking: `temperature=1.0, top_p=0.95, top_k=20`
  - Non-thinking: `temperature=0.7, top_p=0.8, top_k=20, presence_penalty=1.5`

---

## Performance (measured on this setup)

Current setup: **NVIDIA L40 with the INT4 weights**. Test: ~440-token prompt, 300-token reply, thinking off, MTP off. Full results, including FP8 and the RTX A6000, are in [`BENCHMARKS.md`](BENCHMARKS.md).

| Users at once | Wait for first word | Speed per user |
|---|---|---|
| 1 | 0.3s | 28 tok/s |
| 4 | 0.9s | 24 tok/s |
| 8 | 1.6s | 21 tok/s |
| 16 | 2.5s | 17 tok/s |
| 24 | 3.1s typical, 22s worst (queued) | 16 tok/s |

- **Comfortable load:** up to ~16 people generating at the same moment. Beyond that, requests queue.
- **Thinking mode** adds 10–30s before the answer starts.
- **Long prompts and long chats** start slower and fill conversation memory sooner.

### Scaling options (estimates unless noted)

| Option | Cost | Effect |
|---|---|---|
| MTP speculative decoding | free | **Measured** 2× speed on the A6000 (36 tok/s single user), but **crashes vLLM 0.29.0**. Disabled; see `MEMORY.md`. |
| FP8 weights (previous default) | free, already on disk | **Measured on the L40:** 22–32% slower than INT4, less than half the conversation memory (153K tokens), slightly closer to the original model's quality. Run with `MODEL=Qwen3.8-27B-FP8 ./start-vllm.sh` |
| RTX A6000 (previous GPU) | $0.35/hr (vs $0.79 for the L40) | **Measured with FP8:** ~13% slower streaming than the L40, about half the cost per token. INT4 on the A6000 not measured |
| A100 80GB | $1.09/hr | ~2–2.5× the A6000's speed, ~3.5× its conversation memory |
| Qwen3.8-Flash-Next (125B MoE) | ~4× A100, ~$4.36/hr | +1–5 points on most benchmarks; unverified on Ampere |

---

## Custom domain (Cloudflare Tunnel)

Front Open WebUI with your own domain (e.g. `chat.example.com`) instead of the
infra-assigned `*.thundercompute.net` URL. `cloudflared` makes an outbound-only
connection to Cloudflare's edge, so this needs no inbound port-forwarding, and it
keeps working across snapshot restores since the tunnel's identity lives in a token
file on disk, not in the instance's changing device ID.

> **Runs as a native package + SysV service, not Docker.** This instance's container
> runtime (`fastvfs` storage driver, via `proot`) fails to materialize the
> `cloudflare/cloudflared` image (`proot warning: can't sanitize binding ...:
> Permission denied`) — reproduced across multiple image tags, so it's a platform
> limitation, not a bad flag. There's also no systemd here (`system has not been
> booted with systemd as init system`), so `cloudflared service install` falls back
> to a classic `/etc/init.d` script, managed with `service`, not `systemctl`.

Dashboard setup (your domain must already be on Cloudflare):

1. **Zero Trust > Networks > Tunnels > Create a tunnel** (Cloudflared connector). Name it
   anything — it's just a label, not part of the public URL.
2. On the **Install and run a connector** step, pick **Debian** and copy just the token
   (the string after `--token` in the command shown — don't run that command as-is).
3. On the tunnel's **Public Hostname** tab, add: your domain/subdomain → Service Type
   `HTTP` → URL `localhost:3000`. Cloudflare auto-creates the DNS record for you.

On the instance:

```bash
# In .env:
PUBLIC_DOMAIN=chat.example.com
CLOUDFLARE_TUNNEL_TOKEN=<the token from step 2>

# One-time install + registration:
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt-get update && sudo apt-get install -y cloudflared
source .env && sudo cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN"

# Then, same as vLLM/Open WebUI:
./start-webui.sh   # picks up PUBLIC_DOMAIN for CORS_ALLOW_ORIGIN
```

`WEBUI_URL` is a different story: once Open WebUI's database exists, it's a DB-persisted
admin setting, not something `start-webui.sh`'s env var can change on a rerun (verified
2026-09-13 — see `MEMORY.md`). Fix it once after switching domains via **Admin Panel →
Settings → General → WebUI URL**, or the API:
```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:3000/api/v1/auths/signin \
  -H 'Content-Type: application/json' \
  -d '{"email":"<admin email>","password":"<admin password>"}' | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
curl -s http://127.0.0.1:3000/api/v1/auths/admin/config -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); d['WEBUI_URL']='https://$PUBLIC_DOMAIN'; print(json.dumps(d))" \
  | curl -s -X POST http://127.0.0.1:3000/api/v1/auths/admin/config \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data @-
```

`start-cloudflared.sh` (called automatically by `start-all.sh` when
`CLOUDFLARE_TUNNEL_TOKEN` is set) just runs `sudo service cloudflared start` — the
one-time `apt-get install` + `service install` above only needs to happen once per
instance, since the package and `/etc/cloudflared/token` persist on disk across
reboots and snapshot restores.

Once this is live, note that Cloudflare's edge — not just Thunder Compute's — sits in
the plaintext path (it terminates TLS to route the request); see `PRIVACY.md` if
you're maintaining privacy claims about this deployment.

---

## Snapshots and restoring

Thunder has no stop/start. To pause and save money:

1. `tnr snapshot create` (the instance must be running).
2. Delete the instance once the snapshot is underway.
3. Later: `tnr create`, then pick the snapshot as the template. The disk must be at least 250GB. Restores take up to ~8 min per 100GB (~115GB used).

After the restore:

- **The instance ID and public URL change** — unless you've set `PUBLIC_DOMAIN`
  (see [Custom domain](#custom-domain-cloudflare-tunnel)), in which case the domain
  stays the same and there's nothing to share. Otherwise, share the new URL with users.
- **Both containers start automatically, but Open WebUI keeps the *old* URL setting.** Run:
  ```bash
  cd ~/qwen-platform && ./start-webui.sh      # or ./start-all.sh
  ```
- **Port forwarding** carried over on the 2026-09-13 restore. If the URL doesn't load, run `tnr ports forward <new-id> --add 3000` from your laptop.

---

## Security checklist

- [x] vLLM bound to `127.0.0.1` with an API key; port 8000 not publicly forwarded
- [x] Open WebUI admin account claimed before exposure (the first sign-up becomes admin)
- [x] New sign-ups require approval (`DEFAULT_USER_ROLE=pending`)
- [x] Secrets in `.env` and `admin-credentials.txt`, mode 600
- [ ] Change the admin password from the generated one
- [ ] Enable Open WebUI API keys only if users need programmatic access
- [ ] Back up `data/open-webui/` before risky changes
