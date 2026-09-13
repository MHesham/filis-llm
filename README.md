# Qwen Platform

Self-hosted **Qwen3.8-27B-FP8** served by **vLLM**, with **Open WebUI** as the multi-user chat front end, running on a Thunder Compute GPU instance.

- **Public chat URL:** `https://<instance-id>-3000.thundercompute.net` (`start-all.sh` prints the current one)
- **Model name in APIs:** `qwen3.8-27b`

> The instance ID, and therefore the URL, changes every time the machine is restored from a snapshot. `start-webui.sh` works it out automatically.

---

## Architecture

```
 Users (browser / coding tools)
            │  HTTPS (Thunder port forward, port 3000)
            ▼
 ┌─────────────────────────┐        ┌──────────────────────────────┐
 │ Open WebUI  :3000       │ ─────▶ │ vLLM  127.0.0.1:8000         │
 │ accounts, chats, API    │  key   │ Qwen3.8-27B-FP8 on RTX A6000 │
 └─────────────────────────┘        └──────────────────────────────┘
```

- **vLLM** listens only on `127.0.0.1` and requires an API key, so it is never reachable from the internet.
- **Open WebUI** is the only public service. It handles logins and forwards requests to vLLM.

| Component | Details |
|---|---|
| GPU | 1× NVIDIA RTX A6000, 48GB (Ampere) |
| Host | Thunder Compute instance, 250GB disk |
| Model | `Qwen/Qwen3.8-27B-FP8`, 28.9GB on GPU, vision + tools + thinking |
| Inference server | `vllm/vllm-openai:latest` (v0.29.0) |
| Chat UI | `ghcr.io/open-webui/open-webui:main` (v0.11.3 at setup) |
| Context window | 131,072 tokens per request; ~150–200K tokens of conversation memory shared across users |

---

## Files

| Path | Purpose |
|---|---|
| `start-all.sh` | Starts vLLM and Open WebUI, waits for the model, prints the public URL. **Use this after a restore.** |
| `start-vllm.sh` | (Re)creates the `vllm` container. |
| `start-webui.sh` | (Re)creates the `open-webui` container with the current instance's public URL. |
| `.env.example` | Template for `.env`. |
| `.gitignore` | Keeps secrets, the Open WebUI database, and model weights out of Git. |
| `MEMORY.md` | Gotchas and lessons learned. Read before changing anything. |

Local-only (not in Git):

| Path | Purpose |
|---|---|
| `.env` | Secrets: `VLLM_API_KEY`, `WEBUI_SECRET_KEY`. Mode 600. **Never commit or share.** |
| `admin-credentials.txt` | Optional note of the Open WebUI admin login. Mode 600. |
| `data/open-webui/` | Open WebUI database: users, chats, settings. Back this up. |
| `/home/ubuntu/models/Qwen3.8-27B-FP8/` | Model weights (28GB). |

---

## Setup from a fresh clone

Requirements: a Thunder Compute instance with a 48GB+ NVIDIA GPU and a disk of at least 250GB. Docker images are unpacked in full every time a container starts.

```bash
git clone git@github.com:MHesham/filis-llm.git ~/qwen-platform
cd ~/qwen-platform

# 1. Secrets
umask 077 && printf 'VLLM_API_KEY=%s\nWEBUI_SECRET_KEY=%s\n' \
  "$(openssl rand -hex 32)" "$(openssl rand -hex 32)" > .env

# 2. Model weights (~28GB)
pip install --user -U "huggingface_hub[hf_xet]"
~/.local/bin/hf download Qwen/Qwen3.8-27B-FP8 --local-dir /home/ubuntu/models/Qwen3.8-27B-FP8

# 3. Start everything (first start takes ~11–13 min)
./start-all.sh
```

4. **Right away, before sharing the URL**, open the public URL it prints and sign up. The first account becomes admin. Forwarded ports have no login of their own, so anyone who gets there first could claim it.

---

## Day-to-day operations

```bash
cd ~/qwen-platform

./start-all.sh            # start or restart everything and wait until ready
./start-vllm.sh           # restart only the model server (~7–13 min to load)
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
   - Base URL: `https://<instance-id>-3000.thundercompute.net/api` (`/api/v1` also works)
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

```bash
npm install -g @qwen-code/qwen-code@latest    # Node.js 22+
```

`~/.qwen/settings.json`:

```json
{
  "modelProviders": {
    "openai": [
      { "id": "qwen3.8-27b", "name": "Self-hosted Qwen3.8-27B",
        "baseUrl": "https://<instance-id>-3000.thundercompute.net/api/v1",
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

Test: ~440-token prompt, 300-token reply, thinking off, MTP **off** (current configuration).

| Users at once | Wait for first word | Speed per user |
|---|---|---|
| 1 | 0.4s | 16 tok/s |
| 4 | 1.4s | 15 tok/s |
| 8 | 2.5s | 14 tok/s |
| 16 | 4.0s | 11.5 tok/s |
| 24 | 5s typical, 32s worst (queued) | 11 tok/s |

- **Comfortable load:** up to ~16 people generating at the same moment. Beyond that, requests queue.
- **Thinking mode** adds 10–30s before the answer starts.
- **Long prompts and long chats** start slower and fill conversation memory sooner.

### Scaling options (estimates unless noted)

| Option | Cost | Effect |
|---|---|---|
| MTP speculative decoding | free | **Measured** 2× speed (36 tok/s single user), but **crashes vLLM 0.29.0**. Disabled; see `MEMORY.md`. |
| INT4 weights (`dbirks/Qwen3.8-27B-W4A16-AutoRound`) | free, 19.5GB download | ~1.3–1.5× speed, ~2× conversation memory, ~1 point quality loss |
| A100 80GB | $1.09/hr (vs $0.35) | ~2–2.5× speed, ~3.5× conversation memory |
| L40 | $0.79/hr | ~+12% speed. Not worth it. |
| Qwen3.8-Flash-Next (125B MoE) | ~4× A100, ~$4.36/hr | +1–5 points on most benchmarks; unverified on Ampere |

---

## Snapshots and restoring

Thunder has no stop/start. To pause and save money:

1. `tnr snapshot create` (the instance must be running).
2. Delete the instance once the snapshot is underway.
3. Later: `tnr create`, then pick the snapshot as the template. The disk must be at least 250GB. Restores take up to ~8 min per 100GB (~115GB used).

After the restore:

- **The instance ID and public URL change.** Share the new URL with users.
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
