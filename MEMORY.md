# MEMORY: gotchas and hard-earned lessons

Read this before changing the deployment or letting an agent operate on it. Each entry says what happened, why, and what to do instead.

---

## 1. Production safety

### Don't load-test or experiment on the live server
- **What happened (2026-09-13):** a ~30K-token test prompt, sent while two real users were chatting, crashed vLLM's engine. Those users got `EngineCore encountered an issue`, and the model was down for about 13 minutes.
- **Instead:** test when nobody is using it (check `docker logs vllm | grep "POST /v1"` for recent traffic), or warn users first. Every vLLM restart means ~7–13 minutes without a model.

### MTP speculative decoding is off on purpose
- **Measured:** it doubled speed (16 → 36 tok/s).
- **But:** on vLLM **0.29.0**, MTP + prefix caching + this hybrid-attention Qwen model (Gated DeltaNet) crashes with `CUDA error: an illegal memory access`. Long prompts mixed with concurrent chats trigger it, which is exactly coding-agent traffic.
- **Related bugs:** #35288 and #43559 report **silent output corruption** (repeated text, dropped tool calls) with MTP on the same model family, including Qwen3.6-27B-FP8 on a single 48GB card.
- **Fix status (checked 2026-09-13):** open PRs #50021, #51599, and #53613 are **not merged and not in any release**. People report stability only on custom-patched builds.
- **Re-enable only when all of these hold:**
  1. A vLLM release includes a fix for this crash.
  2. You rerun a replay: a ~30K-token prompt while 2+ chats (3K and 12K tokens) are generating, plus a repeated A → B → A prefix pattern.
  3. You do it while no users are on the server.

### Web-sourced "mitigations" for the MTP crash were wrong. Verify every flag.
A pasted list of fixes turned out to be mostly false when checked against the sources:

| Claimed fix | Reality |
|---|---|
| `--disable-async-output-proc` | **Doesn't exist in vLLM 0.29.0** (old-engine flag). vLLM would refuse to start. |
| `--max-num-seqs 3` | Crash reproduced with `--max-num-seqs 1` (#50021) and under single-client load (#43559). It would also cut capacity from 16 to 3 users. |
| `--kv-cache-dtype fp8` | Crashes were reproduced *with* FP8 conversation memory (#43559, #50021). |
| `num_speculative_tokens=1` | No evidence found either way. |

**Rule:** check flags with `docker exec vllm vllm serve --help=all | grep -- <flag>` (exec into the running container; a fresh `docker run` unpacks the 21GB image first). Read the actual GitHub threads, not summaries.

---

## 2. Thunder Compute platform quirks

- **GPUs in Docker:** use `--device nvidia.com/gpu=all`. `--gpus` and `--runtime=nvidia` are rejected.
- **No Docker Compose.** Use plain `docker run` scripts. The old `docker-compose.yml` never worked.
- **Container networking isn't isolated.** Every container shares the host network, so `-p` is meaningless and ports can collide. That's why vLLM binds `127.0.0.1` explicitly.
- **Images unpack completely on every container start**, so you need free disk about the size of the image (~21GB for vLLM). The first launch failed with `disk quota exceeded` on the original 100GB disk. Resized to 250GB.
- **Triton can't find the CUDA library in containers**, so vLLM crashes with `libcuda.so cannot found`. Fix: `-e TRITON_LIBCUDA_PATH=/usr/lib/x86_64-linux-gnu` (already in `start-vllm.sh`).
- **Don't trust `gpuType` in `/etc/thunder/config.json`.** It said `"T4"` on the RTX A6000 instance; after the L40 swap it correctly said `"L40"`. Check with `nvidia-smi`. The `deviceId` field has been reliable and is the ID in the public URL.
- **Disk usage:** `du -x /` doesn't count the base image layers, so `df` showed 82GB used while `du` found ~10MB. It's overlayfs; reclaim space by resizing the disk, not by deleting files.
- **Forwarded ports have no login of their own.** The first person to sign up on a fresh Open WebUI becomes admin, so claim the admin account *before* the URL is shared.
- **No stop/start:** snapshot → delete → create new instance from snapshot. The new instance has a **new ID and URL**.
- **After a restore, containers come back automatically but keep their old settings** (Open WebUI still had the old `WEBUI_URL`). Rerun `./start-webui.sh`. Port forwarding survived the 2026-09-13 restore.

---

## 3. vLLM and model gotchas

- **Needs vLLM ≥ 0.17** for the Qwen3.5-series architecture Qwen3.8 uses. Tested on 0.29.0.
- **Qwen's FP8 checkpoint runs weight-only (Marlin fallback) on both Ampere and Ada.**
  - It's block-wise FP8 (128×128 blocks). vLLM 0.29.0 has no native block-FP8 kernel below compute capability 9.0: on the L40, `cutlass_fp8_supported()` is True but `cutlass_block_fp8_supported()` is False.
  - So the L40's FP8 hardware goes unused, and the "Your GPU does not have native support for FP8" warning is misleading there.
  - Native FP8 on Ada would need a per-channel or per-tensor FP8 checkpoint (untested).
  - Measured result: the L40 is only ~15% faster than the A6000 (see `BENCHMARKS.md`).
- **Harmless startup noise:** a `deep_ep ... libnccl.so.2 FileNotFoundError` traceback inside a WARNING. It's an optional multi-GPU library. **Don't treat log tracebacks as failures.**
- **"Up N seconds" with empty logs and ~0 GPU memory is normal.** Startup is: unpack image → load weights (~1.5 min) → compile and capture CUDA graphs (~5 min). First start took 11–13 min; after a restore it took ~7.5 min.
- **Conversation memory depends on the GPU's usable VRAM:** 196,608 tokens on the RTX A6000 (48GB), 152,917 on the L40 (46GB), with identical settings.
  - This was first misread as random variation between restarts. The 2026-09-13 "restore" was actually the GPU swap.
  - Run `nvidia-smi` before explaining a change in capacity, and read the `GPU KV cache size` log line after each start.
- **Thinking mode is on by default at `xhigh` effort.** It's great for quality, but answers start 10–30s late. `reasoning_effort` and `enable_thinking` control it per request.
- **Tool calling works** with `--enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3`. It's verified on `/v1/chat/completions`, `/v1/messages` (Anthropic format), and through Open WebUI's `/api/chat/completions`, including streamed calls.

---

## 4. Model download and verification

- **`safetensors-md5sum.txt` in the FP8 repo is empty.** Use `crc32.txt` instead.
- **3 small files fail CRC** (`chat_template.jinja`, `generation_config.json`, `tokenizer_config.json`) because Qwen re-uploaded them after writing the checksum list. They match HF `main`; compare against the live file before assuming corruption.
- **Unauthenticated `hf download` works** for Qwen repos (not gated) and took minutes for 28GB.

---

## 5. Lessons for agents operating this box

- **Watch health, not log text.** Two watchers false-alarmed by grepping for `Traceback` / `ERROR`. Reliable signals: `docker inspect -f '{{.State.Status}} {{.RestartCount}}' vllm` plus `curl localhost:8000/health` returning 200.
- **Don't assume a stall from wall-clock guesses.** Once, a "no logs for minutes" concern turned out to be a 47-second gap. Compare `date -u` against the log timestamps.
- **`source .env` doesn't export to child processes.** Python scripts got `KeyError: 'VLLM_API_KEY'`. Use `set -a; source .env; set +a`.
- **`@triton.jit` kernels can't be defined in `python -c`.** Put test kernels in a file.
- **Background jobs and `/tmp` output files don't survive a session end or snapshot restore.** Re-check real state (`docker ps`, `/health`) instead of waiting for old notifications.
- **Search-engine summaries are unreliable for this stack:**
  - One summary merged *Qwen Code* with *OpenCode* and got the config paths wrong.
  - Another gave Qwen's Artificial Analysis Intelligence Index as 52, while the primary page says 34.
  - Always open the primary source: model card, official docs, GitHub thread.
- **Benchmarks in model cards are vendor-reported.** Qwen compares against "Opus 4.6 **Max**". There are no published non-Max Opus 4.6 numbers; Artificial Analysis puts it between 26 (no thinking) and 32 (Max).
- **Label estimates as estimates.**
  - The L40 was estimated at ~+12% from memory bandwidth and measured at +14–17%, so that method roughly holds.
  - INT4 was estimated at ~1.3–1.5× and measured at 1.29–1.47× on the L40.
  - A100 numbers in the README are still estimates. INT4 *quality* has not been measured on this server.
  - MTP, both GPU baselines, INT4 speed, and the concurrency numbers were measured.
- **Check the whole path before exposing anything.** Port 3000 was already publicly forwarded before setup finished; checking `https://<id>-3000.thundercompute.net` caught it in time to claim the admin account.
