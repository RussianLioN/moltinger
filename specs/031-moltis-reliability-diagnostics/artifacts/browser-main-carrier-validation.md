# Browser Main Carrier Validation

**Date**: 2026-03-27  
**Branch**: `031-moltis-reliability-diagnostics`

## Goal

Validate that the current browser incident really requires a runtime-only carrier to `main` rather than another feature-branch-only explanation.

## Commands Run

### 1. Confirm current live runtime still uses the stock browser contract

```bash
ssh root@ainetic.tech "docker exec moltis sh -lc '
  grep -nE \"^\\[tools\\.browser\\]|sandbox_image|profile_dir|persist_profile|container_host\" \
    /home/moltis/.config/moltis/moltis.toml
'"
```

Observed:

- `sandbox_image = "browserless/chrome"`
- `container_host = "host.docker.internal"`
- no tracked `profile_dir`
- no tracked `persist_profile`

### 2. Prove the live browser runtime currently fails outside Telegram too

```bash
export MOLTIS_PASSWORD="$(ssh root@ainetic.tech "grep '^MOLTIS_PASSWORD=' /opt/moltinger/.env | tail -1 | cut -d= -f2-")"
MOLTIS_URL='https://moltis.ainetic.tech' \
CHAT_WAIT_MS=90000 \
EXPECTED_PROVIDER='openai-codex' \
EXPECTED_MODEL='openai-codex::gpt-5.4' \
bash scripts/test-moltis-api.sh \
  'Используй browser, открой https://docs.moltis.org/ и ответь только заголовком страницы.'
```

Observed:

- chat RPC started successfully
- no final event arrived within `CHAT_WAIT_MS=90000`
- returned event stream contained `tool_call_start tool=browser` followed by timeout error

### 3. Correlate with live Moltis logs

```bash
ssh root@ainetic.tech "docker logs --since 3m moltis 2>&1 | grep -E '
  921d7913-d6e2-4e08-8adc-5f8a4d3d1849|
  browser container failed readiness check|
  agent run timed out
' | tail -240"
```

Observed:

- `agent run timed out ... timeout_secs=30`
- `browser container failed readiness check, cleaning up`

### 4. Isolated host check for stock `browserless/chrome`

```bash
ssh root@ainetic.tech '
  name=moltis-browser-manual-$$
  cid=$(docker run -d --rm --name "$name" -p 127.0.0.1::3000 browserless/chrome)
  port=$(docker inspect "$cid" --format "{{(index (index .NetworkSettings.Ports \"3000/tcp\") 0).HostPort}}")
  sleep 5
  curl -sS "http://127.0.0.1:$port/json/version" | jq -r .webSocketDebuggerUrl
  docker rm -f "$cid" >/dev/null
'
```

Observed:

- stock `browserless/chrome` was healthy in isolation
- `/json/version` returned a root websocket URL:
  - `ws://127.0.0.1:<port>`

### 5. Hermetic local check for the tracked shim image

```bash
docker build -f docker/moltis-browser-sandbox/Dockerfile \
  -t moltinger/browserless-chrome-no-preboot:test .

cid=$(docker run -d --rm -p 127.0.0.1::3000 moltinger/browserless-chrome-no-preboot:test)
port=$(docker inspect "$cid" --format '{{(index (index .NetworkSettings.Ports "3000/tcp") 0).HostPort}}')
sleep 3
curl -sS "http://127.0.0.1:$port/json/version" | jq -r .webSocketDebuggerUrl
docker rm -f "$cid" >/dev/null
```

Observed:

- tracked shim returned a concrete DevTools websocket path:
  - `ws://127.0.0.1:<port>/devtools/browser/<id>`

## Result

The validation supports all three carrier assumptions:

1. **Current production is still on the stock browser contract from `main`.**
2. **The live browser runtime is genuinely failing now, even outside Telegram.**
3. **The tracked shim changes the websocket contract in the exact way the audited repair path expected.**

## Conclusion

The browser recurrence is not closed by more Telegram-only diagnostics.

The next safe move is a runtime-only browser carrier to `main`, followed by canonical deploy and live browser proof.
