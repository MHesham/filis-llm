"""Concurrency load test against the local vLLM server.

Each simulated user sends the same ~440-token prompt and receives exactly
300 tokens (thinking off). Reports time to first word and per-user streaming
speed at each concurrency level.

Usage (from the repo root):
    set -a; source .env; set +a
    python3 benchmarks/loadtest.py 1 2 4 8 16 24
"""
import json, os, statistics, sys, threading, time, urllib.request

KEY = os.environ["VLLM_API_KEY"]
URL = "http://127.0.0.1:8000/v1/chat/completions"
OUT_TOKENS = 300
CONTEXT = ("You are helping a small business owner. Background notes: " + "The shop sells handmade ceramics, ships across the country, and has three employees. " * 25)


def one_request(results, idx):
    body = {
        "model": "qwen3.8-27b",
        "messages": [{"role": "system", "content": CONTEXT},
                     {"role": "user", "content": f"Write a detailed marketing plan, variant {idx}."}],
        "max_tokens": OUT_TOKENS, "min_tokens": OUT_TOKENS, "ignore_eos": True,
        "stream": True, "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(URL, data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    t0 = time.time(); first = last = None; usage = None
    with urllib.request.urlopen(req, timeout=600) as r:
        for raw in r:
            line = raw.decode().strip()
            if not line.startswith("data: ") or line == "data: [DONE]":
                continue
            d = json.loads(line[6:])
            if d.get("usage"):
                usage = d["usage"]
            if d.get("choices") and d["choices"][0]["delta"].get("content"):
                now = time.time(); first = first or now; last = now
    n = usage["completion_tokens"]
    results.append({"ttft": first - t0, "tps": (n - 1) / (last - first), "prompt": usage["prompt_tokens"]})


def run(c):
    results = []
    threads = [threading.Thread(target=one_request, args=(results, i)) for i in range(c)]
    start = time.time()
    for t in threads: t.start()
    for t in threads: t.join()
    wall = time.time() - start
    tps = [r["tps"] for r in results]; ttft = [r["ttft"] for r in results]
    print(f"{c:>3} users | first word: median {statistics.median(ttft):5.2f}s worst {max(ttft):5.2f}s | "
          f"speed per user: median {statistics.median(tps):5.1f} worst {min(tps):5.1f} tok/s | "
          f"total {sum(tps):6.1f} tok/s | prompt {results[0]['prompt']} tok | wall {wall:.0f}s", flush=True)


run(1)  # warm-up, not reported
print("--- measured ---", flush=True)
for c in [int(x) for x in sys.argv[1:]] or [1, 2, 4, 8, 16, 24]:
    run(c)
