# LLM Runbook: Remote Moltis Docker Rollout

## Purpose

This document is a permanent instruction set for an LLM or operator that needs to deploy or repair the Moltis Docker image on the remote server.

It captures the exact failure patterns already observed on `ainetic.tech` and the safe sequence that avoids repeating them.

## Scope

Use this runbook when you need to:

- deploy a new Moltis image on the remote server
- switch the live container to a specific Moltis version
- preserve `openai-codex` OAuth state across recreate/restart
- debug broken UI, websocket handshake failures, or post-deploy regressions

This runbook assumes:

- host: `ainetic.tech`
- live service name: `moltis`
- compose project: `moltinger`
- active automation root: `/opt/moltinger-active`
- static git-synced config source: `/opt/moltinger-jb6-gpt54-primary` or another dedicated server worktree
- writable runtime config dir: `${MOLTIS_RUNTIME_CONFIG_DIR:-/opt/moltinger-state/config-runtime}`

## Non-Negotiable Rules

1. Never trust a cached `latest` image during manual rollout.
Always `docker pull` the explicit target tag before recreate.

2. Never assume the live version from UI hints alone.
Verify both:
- `docker ps`
- `docker exec moltis moltis --version`

3. Never store OAuth state in the git-synced static `config/` tree.
`oauth_tokens.json` must live in the writable runtime config dir.

4. Never start interactive OAuth before the user is explicitly ready in the browser.
OAuth is a human-in-the-loop checkpoint, not a background step.

5. Never treat websocket errors as a Traefik problem by default.
Check Moltis logs first. We already observed a backend protocol mismatch that looked like a proxy issue from the UI.

6. Never overwrite a dirty live server worktree blindly.
If `/opt/moltinger` is dirty, deploy from a separate server-side worktree.

7. Never let cron/systemd point directly at a historical worktree.
All installed automation must execute via `/opt/moltinger-active`, which is a symlink to the current live deploy root.

## Canonical Deploy Sequence

### 1. Inspect the live state first

```bash
ssh root@ainetic.tech
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
docker inspect moltis --format '{{json .Mounts}}' | jq .
docker exec moltis moltis --version
docker exec moltis moltis auth status || true
```

What to confirm:

- actual running image tag
- actual Moltis binary version
- runtime config mount is writable
- OAuth state is present or absent

## 2. If the main server worktree is dirty, use a dedicated server worktree

Check:

```bash
cd /opt/moltinger
git status --short
```

If dirty, do not deploy over it blindly.

Preferred pattern:

```bash
cd /opt
git worktree add /opt/moltinger-jb6-gpt54-primary origin/feat/moltinger-jb6-gpt54-primary
cp /opt/moltinger/.env /opt/moltinger-jb6-gpt54-primary/.env
cd /opt/moltinger-jb6-gpt54-primary
ln -sfn /opt/moltinger-jb6-gpt54-primary /opt/moltinger-active
```

## 3. Back up runtime config before touching the container

```bash
mkdir -p /var/backups/moltis/manual-hotfix
cp -a /opt/moltinger-state/config-runtime /var/backups/moltis/manual-hotfix/config-runtime.$(date +%s) 2>/dev/null || true
```

This is required because `oauth_tokens.json` lives there.

## 4. Prepare runtime config from static config

```bash
cd /opt/moltinger-active
bash ./scripts/prepare-moltis-runtime-config.sh ./config /opt/moltinger-state/config-runtime
```

What this must preserve:

- `oauth_tokens.json`
- `provider_keys.json`
- `credentials.json`

Additional invariant:

- if `provider_keys.json` already exists, `prepare-moltis-runtime-config.sh` must keep
  the tracked `providers.openai-codex.model` first in
  `provider_keys.json["openai-codex"].models`
- this preserves OAuth/provider state while preventing runtime model preference drift
  back to `gpt-5.4-mini`

## 5. Pull the exact image version explicitly

Do not skip this.

```bash
docker pull ghcr.io/moltis-org/moltis:20260421.05
```

If the feature targets another version, replace the tag, but still pull it explicitly.

## 6. Recreate the live container with the explicit version

Do not rely on raw `up --force-recreate` against the existing fixed-name container.  
First stop it with an extended grace window, then remove it, then create the new one:

```bash
cd /opt/moltinger-active
docker stop --time 45 moltis || true
docker rm -f moltis || true
MOLTIS_VERSION=20260421.05 docker compose -p moltinger -f docker-compose.prod.yml up -d --no-deps moltis
```

Then verify immediately:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep '^moltis'
docker exec moltis moltis --version
docker inspect -f '{{.State.Health.Status}}' moltis
```

Expected:

- image shows `ghcr.io/moltis-org/moltis:20260421.05`
- binary shows `moltis 20260421.05`
- health becomes `healthy`

## 7. Verify OAuth persistence before trying re-auth

```bash
ls -l /opt/moltinger-state/config-runtime/oauth_tokens.json
docker exec moltis moltis auth status
```

If `auth status` is healthy, do not re-auth.
Ordinary deploy/restart must not require a fresh OAuth login.

If `oauth_tokens.json` still exists and `auth status` shows `openai-codex [expired]`,
do not jump straight to interactive re-auth. First run a real operator-path canary
that forces ordinary chat execution and then re-check `auth status`.
This deployment flow now does that automatically in runtime attestation for the
refreshable OAuth case.

## 8. Only if OAuth is missing, run interactive login

Run inside the live container:

```bash
docker exec -it moltis moltis auth login --provider openai-codex --no-tls
```

Rules:

- do this only when the user is already ready in the browser
- if callback auto-flow times out, use manual callback paste
- do not launch this in the background and then ask the user later

## 9. Verify restart survival

```bash
docker restart moltis
docker inspect -f '{{.State.Health.Status}}' moltis
docker exec moltis moltis auth status
ls -l /opt/moltinger-state/config-runtime/oauth_tokens.json
```

Expected:

- container returns to `healthy`
- `openai-codex` remains valid
- `oauth_tokens.json` still exists

## 10. Verify websocket and UI behavior

First check logs:

```bash
docker logs --since 3m moltis 2>&1 | tail -200
```

Healthy signs:

- `loaded openai-codex models catalog`
- `startup background model discovery complete`
- `ws: handshake complete`

Then open the UI and test:

1. Open `https://moltis.ainetic.tech/chats/main`
2. Hard refresh if the page was already open before deploy
3. Open the model selector
4. Choose `GPT 5.4 (Codex/OAuth)` if the session still points to an older saved model
5. Send `Reply with exactly OK and nothing else.`

Expected result:

- UI responds normally
- no endless red websocket spam
- response metadata shows `openai-codex / openai-codex::gpt-5.4`

## Canonical Runtime Proof

The strongest user-facing proof is:

- live UI session
- model selector set to `GPT 5.4 (Codex/OAuth)`
- prompt returns successfully
- logs confirm the same model

Useful live log filter:

```bash
docker logs --since 2m moltis 2>&1 | grep -E 'chat.send|streaming agent loop|openai-codex|gpt-5.4|handshake complete'
```

Expected proof lines:

- `chat.send ... model="openai-codex::gpt-5.4"`

## Browser Canary Discipline On Shared Production

When you run an operator browser canary against shared production:

1. Do not run it in the default `main` chat session.
2. Do not treat a standalone `sessions.switch` as proof that later `chat.send` calls are isolated.
3. Use one WS RPC connection for the whole browser smoke lifecycle:
   - `sessions.switch`
   - `chat.clear`
   - `chat.send`
   - `sessions.delete`
4. After the run, confirm the dedicated operator session no longer appears in `sessions.list`.

Reason:

- Moltis browser reuse is session-scoped.
- Shared production with tight browser capacity is vulnerable to false isolation.
- The operator path must not contaminate or starve user traffic.

If the browser canary still fails after the repo-owned Docker/profile fixes:

1. do not assume the remaining defect is still repo-owned;
2. inspect whether the failure shape changed to:
   - `browser connection dead`
   - stale `browser-*` session reuse
   - `pool exhausted: no browser instances available`
3. if yes, treat it as a likely upstream runtime/browser lifecycle gap and open an explicit
   upstream issue artifact instead of continuing blind local tweaking.

## Official Sandbox Mode Reminder

Official Moltis docs:

- browser sandbox follows the current session sandbox mode;
- sandboxed browser runs in a Docker container with readiness detection;
- Dockerized Moltis must use sibling-container routing with `container_host`;
- Docker-backed sandbox/workspace mounts must use host-visible paths.

Official OpenClaw docs:

- Pairing covers DM approval and device/node approval;
- sandbox/runtime config changes point toward recreate/reset, not UI Pair as the default fix.

Operationally this means:

1. browser/session incidents should be triaged first as sandbox/runtime lifecycle issues;
2. `Pair` should be used only when the evidence actually shows missing paired state, login/QR,
   or explicit session-state drift;
3. after sandbox/runtime changes, prefer recreate/revalidation and a real browser canary before
   returning to Telegram user-path testing.

## Telegram Pairing Triage

Do not jump to “pair again” by default.

Re-pair Telegram Web only when one of these is true:

- authoritative state file is missing
- helper shows login inputs / QR / verification prompt instead of an active chat
- helper returns `missing_session_state`

Do not blame pairing first when:

- the outgoing probe was observed successfully
- the bot already produced a reply
- the incident evidence points to browser/session/tooling drift instead

In other words: pairing is an operational checkpoint, not the default root cause for browser/session incidents.

## Telegram Delivery Contract

Treat user-facing Telegram delivery as an explicit runtime contract, not an implicit default.

Official Moltis sources are currently split:

- the public channels page still describes Telegram as a polling channel with no streaming;
- changelog `0.8.38` added Telegram reply streaming plus per-account
  `stream_mode` gating, where `off` keeps the classic final-message delivery path.

Safe repo policy for user-facing Telegram bots:

- explicitly pin `stream_mode = "off"` under `[channels.telegram.<account>]`;
- do not rely on the runtime default if the bot is allowed to talk to real users;
- if you intentionally test streaming, do it only in a controlled debug lane, not in the
  main user chat.

Inspect:

```bash
docker exec moltis sh -lc 'sed -n "455,470p" /home/moltis/.config/moltis/moltis.toml'
sqlite3 /opt/moltinger/data/moltis.db 'select slug, config from channels where kind = "telegram";'
```

If users see `Activity log`, raw tool names, or partial progress in Telegram:

1. confirm the live Telegram account config actually contains `stream_mode = "off"`;
2. confirm the runtime channel state or DB override did not drift from tracked config;
3. only after that continue with browser/runtime investigation.
- if the task would require browser/search/memory-heavy multi-step work while the browser path
  is still unstable, temporarily move the user to the web UI/operator lane instead of silently
  triggering the same Telegram failure mode again.
- `starting streaming agent loop provider="openai-codex"`
- `openai-codex stream_with_tools request model=gpt-5.4`
- `agent run complete ... response=OK`

## Closure Criteria For The Current Browser/Telegram Incident

Do not close the incident until all of the following are proven on the authoritative target:

1. `t.me/...` browser canary succeeds, not only `docs.moltis.org/...`.
2. repeated browser runs do not reuse a stale `browser-*` session after failure.
3. Telegram authoritative UAT shows no `Activity log` / internal progress leakage.
4. browser death no longer degrades into `PoolExhausted`.

## Known Failure Patterns And Fixes

### Symptom: UI floods with `Handshake failed: WebSocket disconnected`

Likely cause:

- backend/frontend protocol mismatch
- stale old Moltis image still running after deploy

What we actually saw:

- live container stayed on `0.9.10`
- UI looked newer
- Moltis logs showed `ws: handshake failed error=missing field minProtocol`

Fix:

1. Verify real image and binary version
2. `docker pull` explicit target tag
3. force recreate `moltis`
4. hard refresh the browser

### Symptom: OAuth looked successful once, then disappeared after recreate/restart

Likely cause:

- token was stored in the wrong path
- runtime config layout was wrong

Fix:

- keep `oauth_tokens.json` in `${MOLTIS_RUNTIME_CONFIG_DIR}`
- never rely on the image filesystem layer
- verify restart survival explicitly

### Symptom: `Error: Read-only file system` during OAuth save

Likely cause:

- container attempted to write OAuth state into a read-only config mount

Fix:

- use writable runtime config mounted at `/home/moltis/.config/moltis`
- prepare it from static `./config` before restart

### Symptom: Moltis UI still shows `glm-5.1` after a successful GPT-5.4 rollout

Likely cause:

- the current session has an old session-level model selection persisted

Fix:

- open the model selector and manually switch the session to `GPT 5.4 (Codex/OAuth)`

### Symptom: `auth status` is valid, but live chat still runs `openai-codex::gpt-5.4-mini`

Likely cause:

- runtime-managed `/opt/moltinger-state/config-runtime/provider_keys.json` still prefers
  `gpt-5.4-mini` ahead of tracked `providers.openai-codex.model = "gpt-5.4"`

Inspect:

```bash
jq -r '."openai-codex".models' /opt/moltinger-state/config-runtime/provider_keys.json
docker logs --since 2m moltis 2>&1 | grep -E 'chat.send|openai-codex stream_with_tools request model='
```

Fix:

```bash
cd /opt/moltinger-active
bash ./scripts/prepare-moltis-runtime-config.sh ./config /opt/moltinger-state/config-runtime
docker restart moltis
```

Expected proof:

- `jq -r '."openai-codex".models[0]' .../provider_keys.json` returns `gpt-5.4`
- `docker exec moltis moltis auth status` still shows `openai-codex [valid ...]`
- live canary reports `provider=openai-codex`, `model=openai-codex::gpt-5.4`

### Symptom: Traefik looks healthy, but chat still fails

Likely cause:

- problem is inside Moltis runtime, not in the reverse proxy

Fix:

- inspect `docker logs moltis` before changing Traefik
- do not guess at websocket headers first

### Symptom: Browser tool fails with `failed to pull browser image` or Docker `permission denied`

Likely cause:

- `/var/run/docker.sock` is mounted, but the live Moltis process does not have the
  socket's numeric GID in its supplementary groups
- or containerized Moltis is still trying to reach sibling browser containers via
  loopback instead of the host gateway

Inspect:

```bash
docker inspect moltis --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
docker exec moltis sh -lc 'id -G && stat -c "%g %a" /var/run/docker.sock'
docker exec moltis sh -lc 'grep host.docker.internal /etc/hosts || true'
docker exec moltis sh -lc 'sed -n "470,505p" /home/moltis/.config/moltis/moltis.toml'
```

Fix:

- ensure compose passes `group_add` with the real host `docker.sock` GID
- ensure deploy-time `DOCKER_SOCKET_GID` comes from `stat -c %g /var/run/docker.sock`
- ensure `tools.browser.container_host` is not left at loopback for a Dockerized
  Moltis runtime
- ensure the container maps `host.docker.internal:host-gateway`

Why this matters:

- the official Moltis browser docs require sibling-container routing when Moltis
  runs inside Docker
- Docker socket access is controlled by numeric UID/GID, not the textual group name
  shown inside the container

### Symptom: Browser tool no longer shows Docker `permission denied`, but browser container never becomes ready

Likely cause:

- the sibling browser container can now start, but Chrome cannot initialize the
  configured `profile_dir`
- the tracked profile contract is reusing a shared/stale Chrome user-data-dir
  instead of a dedicated non-persistent child directory

Inspect:

```bash
docker logs moltis --since 20m | rg 'browser container failed readiness check|tool execution failed tool=browser|SingletonLock|ProcessSingleton' -n
docker ps --format '{{.Names}}' | rg '^moltis-browser-' | tail -n 1
docker logs "$(docker ps --format '{{.Names}}' | rg '^moltis-browser-' | tail -n 1)" 2>&1 | tail -n 50
docker exec moltis sh -lc 'sed -n "478,498p" /home/moltis/.config/moltis/moltis.toml'
ls -la /tmp/moltis-browser-profile
find /tmp/moltis-browser-profile -maxdepth 2 -mindepth 1 -printf '%M %u:%g %p\n' | head -n 50
docker run --rm browserless/chrome sh -lc 'id'
```

Fix:

- keep `tools.browser.container_host = "host.docker.internal"` and the Docker socket
  contract from the official docs
- use a dedicated child `profile_dir` such as
  `/tmp/moltis-browser-profile/browserless`, not a shared multi-instance path
- keep `persist_profile = false`
- pin `max_instances = 1`
- purge and recreate the configured browser `profile_dir` during deploy
- if the live runtime still uses stock `browserless/chrome` and transient container
  logs show `SingletonLock` / `ProcessSingleton`, switch to the tracked wrapper image
  that normalizes bind-mounted profile ownership before dropping back to the upstream
  non-root runtime user

Why this matters:

- official Moltis docs cover sibling-container routing, not a shared Chrome
  profile strategy
- Chrome user-data-dirs are lock-sensitive; concurrent or stale reuse shows up as
  `SingletonLock` / `ProcessSingleton` failures even when Docker connectivity is fine

### Symptom: Dedicated `profile_dir` + `max_instances = 1` are already in place, but transient browser containers still fail with `SingletonLock: Permission denied`

Likely cause:

- the transient browser container is still the stock `browserless/chrome` image;
- the per-session bind-mounted profile directory is owned by a different host UID/GID
  than the image's runtime user (`blessuser`, `999:999`);
- Chrome cannot create `SingletonLock` inside `/data/browser-profile`.

Inspect:

```bash
docker ps --format '{{.Names}} {{.Image}}' | grep '^moltis-browser-'
name="$(docker ps --format '{{.Names}}' | grep '^moltis-browser-' | tail -n 1)"
docker inspect "$name" --format 'image={{.Config.Image}} user={{.Config.User}} mounts={{range .Mounts}}{{.Source}}=>{{.Destination}} rw={{.RW}};{{end}}'
docker logs "$name" 2>&1 | tail -n 80
ls -ld /tmp/moltis-browser-profile/browserless /tmp/moltis-browser-profile/browserless/sandbox /tmp/moltis-browser-profile/browserless/sandbox/*
```

Fix:

- pin `sandbox_image = "moltis-browserless-chrome:tracked"`
- build that tracked wrapper image during deploy
- let the wrapper:
  - start as root briefly
  - `chown -R 999:999` the bind-mounted profile dir
  - create a writable runtime `HOME`
  - drop privileges back to `999:999`
  - exec the upstream browserless start path

Why this matters:

- official Moltis sandbox docs explicitly allow custom sandbox images;
- official browserless/OpenClaw guidance still leaves user-data-dir ownership as an
  operator/runtime concern;
- this is safer than leaving the browser container running as root or relying on
  host-only `chmod 0777`.

### Symptom: Browser tool now starts, but the run still ends with `Timed out: Agent run timed out after 30s`

Likely cause:

- browser launch/storage contract is already repaired, but the overall agent run
  timeout still equals the browser navigation timeout, so the run dies before
  follow-up browser actions and the final assistant reply can complete
- or the operator canary is stale and still testing retired `/login` +
  `/api/v1/chat` instead of the current auth + WS RPC surface

Inspect:

```bash
docker exec moltis sh -lc 'sed -n "286,296p" /home/moltis/.config/moltis/moltis.toml'
docker exec moltis sh -lc 'sed -n "478,496p" /home/moltis/.config/moltis/moltis.toml'
TEST_BASE_URL=http://localhost:13131 TEST_TIMEOUT=30 node /server/tests/lib/ws_rpc_cli.mjs request \
  --method chat.send \
  --params '{"text":"Используй browser, а не web_fetch. Открой https://docs.moltis.org/ и ответь только точным заголовком страницы без пояснений."}' \
  --wait-ms 90000 \
  --subscribe chat
```

Fix:

- keep `tools.browser.navigation_timeout_ms` as the page-load budget unless the
  site itself is slow
- raise `[tools].agent_timeout_secs` above that browser budget; tracked baseline
  is `90` so the run has headroom for `navigate`, a follow-up browser action, and
  the final reply
- use the repo `scripts/test-moltis-api.sh` helper only after it is on the current
  `/api/auth/login` + WS RPC contract
- rerun the browser canary after the config change and only then re-check Telegram

Why this matters:

- official Moltis docs describe browser navigation as a separate browser-side
  timeout budget and browser automation as slower than `web_fetch`
- if the outer run budget equals the browser page budget, the agent can still time
  out even though the browser container itself is healthy

## Skill Discovery vs Sandbox Filesystem

### Symptom: Telegram says a skill path does not exist even though the skill is listed as available

Likely cause:

- live runtime discovery and sandbox-visible filesystem are not the same surface
- the active Telegram session may advertise available skills from runtime state while sandboxed
  `exec` cannot read the corresponding host-style paths

Inspect authoritative truth in this order:

```bash
curl -sS -c /tmp/moltis.cookies -H 'Content-Type: application/json' \
  -d "{\"password\":\"$MOLTIS_PASSWORD\"}" \
  https://moltis.ainetic.tech/api/auth/login >/dev/null
curl -sS -b /tmp/moltis.cookies https://moltis.ainetic.tech/api/skills | jq .
node /server/tests/lib/ws_rpc_cli.mjs request --method channels.list --params '{}' | jq .
node /server/tests/lib/ws_rpc_cli.mjs request --method chat.raw_prompt --params '{}' | jq .
```

Then compare that to what the session sandbox can actually see before trusting any `exec` probe.

Rule:

- `/api/skills` and runtime-advertised Available Skills are the authoritative proof that a skill
  is discoverable
- `exec cat /home/moltis/.moltis/skills/...` inside a sandboxed Telegram session is not global
  truth for skill existence

### Special note for `codex-update`

For remote Moltis surfaces, `codex-update` must be treated as advisory/notification capability.
Do not promise that the server/container can update the user's local Codex CLI installation.
If the current surface cannot safely reach the canonical local runtime path, use official external
release sources or provide an honest advisory-only answer.

## Telegram Activity Log Leakage Triage

If the user still sees `📋 Activity log` in Telegram, do not stop at `stream_mode = "off"`.

Check:

1. tracked `config/moltis.toml`
2. authoritative `channels.list`
3. whether the Telegram account is pinned to a dedicated text-only provider lane
   (`model_provider` + provider `tool_mode = "off"`)
4. `chat.history`
5. whether the leak appears in final assistant content or only in delivered chat artifacts

If `chat.history` final reply is clean but the user still sees `Activity log`, treat it as
transport/channel delivery leakage and prepare upstream handoff instead of only rewriting prompt
text.

## Anti-Patterns

Do not do any of the following:

- `docker compose up` without a prior explicit `docker pull` of the target image
- assume `latest` means the latest pulled image is already on the host
- re-auth on every deploy “just in case”
- start OAuth before the user is ready
- copy OAuth state into git-tracked `config/`
- diagnose websocket UI issues only from the browser without checking server logs
- trust an already open browser tab after backend upgrade without a refresh

## Minimal Safe Checklist

- [ ] Actual image tag verified with `docker ps`
- [ ] Actual binary version verified with `docker exec moltis moltis --version`
- [ ] Runtime config mount is writable
- [ ] `oauth_tokens.json` exists in runtime config dir
- [ ] `docker exec moltis moltis auth status` is healthy
- [ ] Container survives restart without losing auth
- [ ] UI loads cleanly
- [ ] WebSocket handshake completes
- [ ] `GPT 5.4 (Codex/OAuth)` is selectable
- [ ] Live prompt succeeds on `openai-codex::gpt-5.4`

## Final Instruction To Future LLM Sessions

If the user reports that Moltis UI is broken after deploy, do not start by editing config.

First answer these in order:

1. What image tag is really running?
2. What Moltis binary version is really inside the container?
3. Is runtime config writable?
4. Does `oauth_tokens.json` exist in runtime storage?
5. Does `auth status` still show valid `openai-codex`?
6. Do Moltis logs show websocket handshake failure or success?

Only after these answers are concrete should you change config, OAuth, or proxy behavior.
