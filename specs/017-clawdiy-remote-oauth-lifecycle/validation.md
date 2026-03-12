# Validation: Clawdiy Remote OAuth Runtime Lifecycle

**Feature**: `017-clawdiy-remote-oauth-lifecycle`  
**Status**: Draft validation checklist and evidence inventory

## Purpose

Provide one operator-facing place to record what was attempted, what evidence was collected, and whether Clawdiy `codex-oauth` is still metadata-only, runtime-ready, or fully promoted.

## Preferred First Bootstrap Path

Primary operator path:

1. Open the live Clawdiy UI at `https://clawdiy.ainetic.tech`
2. Sign in with the current Clawdiy web credential
3. Navigate to the Clawdiy Settings area for model/provider authentication
4. Start the `OpenAI Codex` / `codex-oauth` login from the live UI

Fallback path:

- Use the remote CLI / paste-back flow only if the live UI path is unavailable or clearly fails to write auth into the actual runtime store.

## Evidence Inventory

### Baseline Before OAuth

- [ ] Clawdiy health URL returns `200`
- [ ] Metadata gate visible in `/opt/moltinger/clawdiy/.env`
- [ ] Current runtime auth store state captured
- [ ] Current provider status captured

Recommended evidence:

```bash
./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider codex-oauth --json
./scripts/clawdiy-smoke.sh --json --stage auth
ssh root@ainetic.tech "docker exec clawdiy openclaw models status --json"
```

### After UI OAuth Attempt

- [ ] Runtime auth store path exists
- [ ] Runtime auth store path is writable/readable by the Clawdiy runtime user
- [ ] `codex-oauth` appears in runtime provider/model status
- [ ] Metadata gate still matches expected scope/model policy

Recommended evidence:

```bash
ssh root@ainetic.tech "docker exec clawdiy openclaw models status --json"
ssh root@ainetic.tech "docker exec clawdiy sh -lc 'ls -l /home/node/.openclaw-data/state/agents/main/agent/auth-profiles.json'"
./scripts/clawdiy-auth-check.sh --env-file /opt/moltinger/clawdiy/.env --provider codex-oauth --json
```

### Promotion Gate

- [ ] Post-auth canary executed
- [ ] `gpt-5.4` canary evidence stored
- [ ] Provider promoted only after canary success

## Recording Template

| Timestamp | Attempt type | Runtime auth store result | Provider activation result | Canary result | Notes |
|---|---|---|---|---|---|
| pending | UI-first / CLI-fallback | pending | pending | pending | pending |
