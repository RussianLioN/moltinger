#!/bin/sh
set -eu

# Moltis 0.10.18 still bind-mounts /data/browser-profile for sibling browser
# containers even when persist_profile=false, and the stock browserless preboot
# path plus its websocket root endpoint are not compatible with the live Moltis
# containerized-browser contract. Run Chrome directly and front it with a small
# proxy that rewrites /json/version to a real /devtools/browser/* websocket URL.
export PREBOOT_CHROME=false

mkdir -p /tmp/browser-profile

/usr/bin/google-chrome \
  --headless=new \
  --no-sandbox \
  --disable-dev-shm-usage \
  --no-first-run \
  --remote-allow-origins=* \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port=9222 \
  --window-size=2560,1440 \
  --user-data-dir=/tmp/browser-profile \
  about:blank >/tmp/moltis-browser-chrome.log 2>&1 &
chrome_pid=$!

cleanup() {
  kill "$chrome_pid" 2>/dev/null || true
  wait "$chrome_pid" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

exec node /usr/local/bin/cdp-proxy.mjs
