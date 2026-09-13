# Benchmarks: RTX A6000 vs L40, FP8 vs INT4

Same model family, same vLLM settings, same load test, **MTP off in every run**.

| Configuration | GPU | Weights |
|---|---|---|
| **A6000 FP8** | RTX A6000 48GB | `Qwen/Qwen3.8-27B-FP8` (block-wise FP8) |
| **L40 FP8** | L40 46GB | `Qwen/Qwen3.8-27B-FP8` |
| **L40 INT4** | L40 46GB | `dbirks/Qwen3.8-27B-W4A16-AutoRound` (4-bit weights, 16-bit activations) |

**Summary:**
- **INT4 is the biggest win.** On the same L40 it streams **29–47% faster** than FP8, reaches the first word ~20% sooner, and has **2.15× the conversation memory**.
- **The L40 alone** is 14–17% faster than the A6000 with FP8, but has 22% less conversation memory and costs ~2× per token.
- **Cheapest per token:** the A6000 with FP8 (~$0.53 per million output tokens).
- **Fastest and most capacity:** the L40 with INT4, at ~$0.81 per million.
- **Quality of INT4 was not measured here.** Published evals show it within the margin of error of the unquantized model (see [Quality](#quality)).

---

## Setup

Identical for all runs:

| Setting | Value |
|---|---|
| Server | vLLM 0.29.0 (`vllm/vllm-openai:latest`), `start-vllm.sh` |
| Key flags | `--max-num-seqs 16 --max-model-len 131072 --gpu-memory-utilization 0.92`, prefix caching on (default), **MTP off** |
| Host | Thunder Compute, 6 vCPUs, NVIDIA driver 610.43.02 |
| Test | [`benchmarks/loadtest.py`](benchmarks/loadtest.py): 438-token prompt, exactly 300 output tokens, thinking off, streaming |
| Method | 1 warm-up request, then one run per concurrency level; all users start at once |

Reproduce from the repo root (pick the model with `MODEL`, restart, wait until ready, then):

```bash
./start-vllm.sh                          # INT4 (the default)
MODEL=Qwen3.8-27B-FP8 ./start-vllm.sh    # or FP8
set -a; source .env; set +a
python3 benchmarks/loadtest.py 1 2 4 8 16 24
```

> Run it when nobody is using the server. Switching models means ~9–13 minutes with no model, and the 24-user level queues real requests for ~30s.

---

## Hardware and memory

| | A6000 FP8 | L40 FP8 | L40 INT4 |
|---|---|---|---|
| Architecture | Ampere (compute 8.6) | Ada Lovelace (compute 8.9) | Ada Lovelace (compute 8.9) |
| VRAM | 48GB | 46GB | 46GB |
| Memory bandwidth (spec) | 768 GB/s | 864 GB/s | 864 GB/s |
| Weights on GPU | 28.9 GiB | 28.9 GiB | **17.7 GiB** |
| Kernel vLLM selected | Marlin FP8, weight-only | Marlin FP8, weight-only | Marlin INT4 (`CompressedTensorsWNA16`) |
| Conversation memory (KV cache) | 196,608 tokens | 152,917 tokens | **329,186 tokens** |
| Full 131K-token requests that fit at once | 1.50 | 1.17 | **2.51** |
| Thunder price | $0.35/hr | $0.79/hr | $0.79/hr |
| Measured | 2026-09-12 | 2026-09-13 | 2026-09-13 |

---

## Results

### Speed per user while streaming (median, worst in parentheses)

| Users at once | A6000 FP8 | L40 FP8 | L40 INT4 | INT4 vs L40 FP8 |
|---|---|---|---|---|
| 1 | 16.1 tok/s | 18.9 tok/s | **27.8 tok/s** | **+47%** |
| 2 | 15.4 (15.3) | 17.8 (17.7) | **25.8** (25.8) | +45% |
| 4 | 15.1 (15.0) | 17.2 (17.2) | **24.2** (24.1) | +41% |
| 8 | 14.2 (13.6) | 16.2 (15.7) | **21.1** (20.2) | +30% |
| 16 | 11.5 (10.6) | 13.1 (12.1) | **16.9** (15.7) | +29% |
| 24 | 10.9 (10.6) | 12.4 (12.1) | **16.0** (15.5) | +29% |

### Wait for the first word (median, worst in parentheses)

| Users at once | A6000 FP8 | L40 FP8 | L40 INT4 | INT4 vs L40 FP8 |
|---|---|---|---|---|
| 1 | 0.43s | 0.34s | **0.27s** | −21% |
| 2 | 0.78s (0.81s) | 0.59s (0.62s) | **0.47s** (0.49s) | −20% |
| 4 | 1.39s | 1.07s | **0.93s** | −13% |
| 8 | 2.49s (2.55s) | 1.96s (2.02s) | **1.61s** (1.66s) | −18% |
| 16 | 3.95s (4.98s) | 3.11s (3.92s) | **2.52s** (3.16s) | −19% |
| 24 | 4.92s (32.3s) | 3.86s (27.9s) | **3.13s** (21.9s) | −19% (worst −22%) |

At 24 users, requests beyond the 16-request limit wait in line, which is what produces the long worst-case waits.

### Cost per token (rough)

At 16 simultaneous users, adding up every user's streaming speed:

| | A6000 FP8 | L40 FP8 | L40 INT4 |
|---|---|---|---|
| Combined streaming speed | 184.8 tok/s | 208.9 tok/s | 270.5 tok/s |
| Tokens per hour | ~665K | ~752K | ~974K |
| **Cost per million output tokens** | **~$0.53** | **~$1.05** | **~$0.81** |

---

## Takeaways

1. **Smaller weights beat a faster GPU.** For a model this size, streaming speed tracks how much data moves through GPU memory per token.
   - Moving from the A6000 to the L40 added 12.5% bandwidth and gave +14–17%.
   - Cutting the weights by 39% (28.9 → 17.7 GiB) gave +29–47%.
2. **INT4's lead shrinks under load** (+47% for one user, +29% at 16), because parts of the model stay 16-bit and batching spreads the work.
3. **INT4 more than doubles conversation memory** on the L40 (153K → 329K tokens), so long chats and coding-agent sessions stop competing for space.
4. **Estimates held.** INT4 was estimated at ~1.3–1.5× and measured 1.29–1.47×. The L40 was estimated at ~+12% and measured +14–17%.
5. **For this server:**
   - **L40 INT4** is the best balance of speed and capacity.
   - **A6000 INT4** (not measured) would likely be the cheapest per token, if its speed is enough.

---

## Quality

Not measured on this server. Published results for the builds tested here:

| Build | Result vs unquantized (BF16) |
|---|---|
| `dbirks/Qwen3.8-27B-W4A16-AutoRound` (tested here) | GSM8K, HumanEval, and MMLU-Pro all within the margin of error |
| `RedHatAI/Qwen3.8-27B-INT4` (similar recipe) | 98.5–101% of BF16 scores on GPQA Diamond, IFEval, MMLU-Pro, MATH-500, AIME25 |
| `Qwen/Qwen3.8-27B-FP8` | Qwen reports performance nearly identical to BF16 |

This build keeps the vision tower, `lm_head`, the MTP head, and the small `in_proj_a`/`in_proj_b` layers at 16-bit.

---

## FP8 on the L40

The L40 supports FP8 compute, but vLLM doesn't use it for Qwen's FP8 checkpoint:

- **The checkpoint is block-wise** (`weight_block_size: [128, 128]`).
- **vLLM 0.29.0 has no native block-FP8 kernel for Ada GPUs.** Inside the container, `cutlass_fp8_supported()` returns `True` but `cutlass_block_fp8_supported()` returns `False`.
- **So it falls back to the same Marlin weight-only kernel as on the A6000**, and logs the misleading warning "Your GPU does not have native support for FP8".
- **Native FP8 on the L40** would need a per-channel or per-tensor FP8 build. Not tested.

---

## Caveats

- **One run per level**; run-to-run variation wasn't measured, so treat differences under ~5% as noise.
- **The A6000 runs were on a different instance and day**; all runs are on Thunder Compute's virtualized GPUs.
- **Thinking was off and output length was forced.** Real chats with thinking on take much longer to start answering.
- **Traffic:**
  - A6000 run: only the admin account existed.
  - L40 FP8 run: no other requests in the 2 minutes before.
  - L40 INT4 run: no other requests in the 15 minutes before.

---

## Raw output

**A6000 FP8** (2026-09-12)
```
  1 users | first word: median  0.43s worst  0.43s | speed per user: median  16.1 worst  16.1 tok/s | total   16.1 tok/s | prompt 438 tok | wall 19s
  2 users | first word: median  0.78s worst  0.81s | speed per user: median  15.4 worst  15.3 tok/s | total   30.7 tok/s | prompt 438 tok | wall 20s
  4 users | first word: median  1.39s worst  1.39s | speed per user: median  15.1 worst  15.0 tok/s | total   60.2 tok/s | prompt 438 tok | wall 21s
  8 users | first word: median  2.49s worst  2.55s | speed per user: median  14.2 worst  13.6 tok/s | total  112.9 tok/s | prompt 438 tok | wall 24s
 16 users | first word: median  3.95s worst  4.98s | speed per user: median  11.5 worst  10.6 tok/s | total  184.8 tok/s | prompt 438 tok | wall 30s
 24 users | first word: median  4.92s worst 32.33s | speed per user: median  10.9 worst  10.6 tok/s | total  287.4 tok/s | prompt 438 tok | wall 53s
```

**L40 FP8** (2026-09-13 16:20 UTC)
```
  1 users | first word: median  0.34s worst  0.34s | speed per user: median  18.9 worst  18.9 tok/s | total   18.9 tok/s | prompt 438 tok | wall 16s
  2 users | first word: median  0.59s worst  0.62s | speed per user: median  17.8 worst  17.7 tok/s | total   35.5 tok/s | prompt 438 tok | wall 17s
  4 users | first word: median  1.07s worst  1.07s | speed per user: median  17.2 worst  17.2 tok/s | total   68.9 tok/s | prompt 438 tok | wall 18s
  8 users | first word: median  1.96s worst  2.02s | speed per user: median  16.2 worst  15.7 tok/s | total  129.5 tok/s | prompt 438 tok | wall 20s
 16 users | first word: median  3.11s worst  3.92s | speed per user: median  13.1 worst  12.1 tok/s | total  208.9 tok/s | prompt 438 tok | wall 26s
 24 users | first word: median  3.86s worst 27.94s | speed per user: median  12.4 worst  12.1 tok/s | total  323.3 tok/s | prompt 438 tok | wall 47s
```

**L40 INT4** (2026-09-13 17:39 UTC)
```
  1 users | first word: median  0.27s worst  0.27s | speed per user: median  27.8 worst  27.8 tok/s | total   27.8 tok/s | prompt 438 tok | wall 11s
  2 users | first word: median  0.47s worst  0.49s | speed per user: median  25.8 worst  25.8 tok/s | total   51.7 tok/s | prompt 438 tok | wall 12s
  4 users | first word: median  0.93s worst  0.93s | speed per user: median  24.2 worst  24.1 tok/s | total   96.5 tok/s | prompt 438 tok | wall 13s
  8 users | first word: median  1.61s worst  1.66s | speed per user: median  21.1 worst  20.2 tok/s | total  167.8 tok/s | prompt 438 tok | wall 16s
 16 users | first word: median  2.52s worst  3.16s | speed per user: median  16.9 worst  15.7 tok/s | total  270.5 tok/s | prompt 438 tok | wall 20s
 24 users | first word: median  3.13s worst 21.89s | speed per user: median  16.0 worst  15.5 tok/s | total  434.0 tok/s | prompt 438 tok | wall 35s
```
