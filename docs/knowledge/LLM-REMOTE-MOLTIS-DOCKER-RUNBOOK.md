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

## 5. Pull the exact image version explicitly

Do not skip this.

```bash
docker pull ghcr.io/moltis-org/moltis:0.10.18
```

If the feature targets another version, replace the tag, but still pull it explicitly.

## 6. Recreate the live container with the explicit version

```bash
cd /opt/moltinger-active
MOLTIS_VERSION=0.10.18 docker compose -p moltinger -f docker-compose.prod.yml up -d --force-recreate --no-deps moltis
```

Then verify immediately:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep '^moltis'
docker exec moltis moltis --version
docker inspect -f '{{.State.Health.Status}}' moltis
```

Expected:

- image shows `ghcr.io/moltis-org/moltis:0.10.18`
- binary shows `moltis 0.10.18`
- health becomes `healthy`

## 7. Verify OAuth persistence before trying re-auth

```bash
ls -l /opt/moltinger-state/config-runtime/oauth_tokens.json
docker exec moltis moltis auth status
```

If `auth status` is healthy, do not re-auth.
Ordinary deploy/restart must not require a fresh OAuth login.

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
- `starting streaming agent loop provider="openai-codex"`
- `openai-codex stream_with_tools request model=gpt-5.4`
- `agent run complete ... response=OK`

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

### Symptom: Moltis UI still shows `glm-5` after a successful GPT-5.4 rollout

Likely cause:

- the current session has an old session-level model selection persisted

Fix:

- open the model selector and manually switch the session to `GPT 5.4 (Codex/OAuth)`

### Symptom: Traefik looks healthy, but chat still fails

Likely cause:

- problem is inside Moltis runtime, not in the reverse proxy

Fix:

- inspect `docker logs moltis` before changing Traefik
- do not guess at websocket headers first

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
