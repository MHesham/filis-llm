// Reverse-proxies chat.filis.dev to the tunnel's internal hostname
// (env.ORIGIN_HOSTNAME). Any failure to reach it — connection error, timeout,
// or a 5xx (502 when cloudflared can't reach a stopped container, 521/522/523/530
// when the tunnel itself is down) — serves the banner below instead.

const ORIGIN_TIMEOUT_MS = 8000;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    url.hostname = env.ORIGIN_HOSTNAME;

    try {
      const response = await fetch(url.toString(), {
        method: request.method,
        headers: request.headers,
        body: ["GET", "HEAD"].includes(request.method) ? undefined : request.body,
        redirect: "manual",
        signal: AbortSignal.timeout(ORIGIN_TIMEOUT_MS),
      });

      if (response.status >= 500) {
        return bannerResponse();
      }
      return response;
    } catch {
      return bannerResponse();
    }
  },
};

function bannerResponse() {
  return new Response(BANNER_HTML, {
    status: 503,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "retry-after": "20",
    },
  });
}

const BANNER_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="20">
<title>Chat Offline</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
  :root {
    --bg: #f6f7fb;
    --text: #171a2b;
    --muted: #5b6180;
    --accent: #c96f14;
    --border: #e2e4f0;
    --bar-track: #e9eaf3;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #0b0d16;
      --text: #e9eaf4;
      --muted: #8d92ac;
      --accent: #f5a83c;
      --border: #242840;
      --bar-track: #1d2032;
    }
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    min-height: 100vh;
    background: var(--bg);
    color: var(--text);
    font-family: "IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
  }
  main {
    width: 100%;
    max-width: 420px;
  }
  .eyebrow {
    display: flex;
    align-items: center;
    gap: 8px;
    font-family: "IBM Plex Mono", ui-monospace, monospace;
    font-size: 0.72rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: var(--muted);
    margin-bottom: 20px;
  }
  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--accent);
    flex-shrink: 0;
    animation: pulse 2s ease-in-out infinite;
  }
  @media (prefers-reduced-motion: reduce) {
    .dot { animation: none; }
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.5; }
  }
  h1 {
    font-size: 1.5rem;
    font-weight: 600;
    line-height: 1.3;
    margin: 0 0 12px;
    text-wrap: balance;
  }
  p {
    font-size: 0.95rem;
    line-height: 1.6;
    color: var(--muted);
    margin: 0 0 28px;
    max-width: 34ch;
  }
  .load {
    display: flex;
    gap: 4px;
    align-items: flex-end;
    height: 20px;
    margin-bottom: 28px;
  }
  .load span {
    flex: 1;
    background: var(--bar-track);
    border-radius: 1px;
  }
  .load span:nth-child(1) { height: 30%; }
  .load span:nth-child(2) { height: 55%; }
  .load span:nth-child(3) { height: 20%; }
  .load span:nth-child(4) { height: 70%; background: var(--accent); animation: idle 2.4s ease-in-out infinite; }
  .load span:nth-child(5) { height: 40%; }
  .load span:nth-child(6) { height: 65%; }
  .load span:nth-child(7) { height: 25%; }
  .load span:nth-child(8) { height: 50%; }
  .load span:nth-child(9) { height: 15%; }
  .load span:nth-child(10) { height: 35%; }
  @keyframes idle {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.4; }
  }
  @media (prefers-reduced-motion: reduce) {
    .load span:nth-child(4) { animation: none; }
  }
  hr {
    border: none;
    border-top: 1px solid var(--border);
    margin: 0 0 16px;
  }
  .meta {
    display: flex;
    justify-content: space-between;
    font-family: "IBM Plex Mono", ui-monospace, monospace;
    font-size: 0.78rem;
    color: var(--muted);
    font-variant-numeric: tabular-nums;
  }
  .meta strong {
    color: var(--text);
    font-weight: 500;
  }
  .contact {
    margin: 20px 0 0;
    font-size: 0.85rem;
    color: var(--muted);
  }
  .contact a {
    color: var(--accent);
    text-decoration: none;
  }
  .contact a:hover,
  .contact a:focus-visible {
    text-decoration: underline;
  }
</style>
</head>
<body>
<main>
  <div class="eyebrow"><span class="dot"></span>qwen-platform &middot; gpu-worker</div>
  <h1>Chat is offline</h1>
  <p>This runs on a personal GPU instance that isn't kept on around the clock &mdash; it gets shut down from time to time to save cost, with no fixed schedule for coming back. Feel free to check back whenever.</p>
  <div class="load" aria-hidden="true">
    <span></span><span></span><span></span><span></span><span></span>
    <span></span><span></span><span></span><span></span><span></span>
  </div>
  <hr>
  <div class="meta">
    <span>next check in <strong id="countdown">20s</strong></span>
    <span>last checked <strong id="clock">--:--:--</strong></span>
  </div>
  <p class="contact">Questions? Reach out at <a href="mailto:chatsupport@filis.dev">chatsupport@filis.dev</a>.</p>
</main>
<script>
  var n = 20;
  var cd = document.getElementById('countdown');
  setInterval(function () {
    n = n > 0 ? n - 1 : 20;
    cd.textContent = n + 's';
  }, 1000);

  var clock = document.getElementById('clock');
  function tick() {
    var d = new Date();
    var p = function (x) { return String(x).padStart(2, '0'); };
    clock.textContent = p(d.getHours()) + ':' + p(d.getMinutes()) + ':' + p(d.getSeconds());
  }
  tick();
  setInterval(tick, 1000);
</script>
</body>
</html>`;
