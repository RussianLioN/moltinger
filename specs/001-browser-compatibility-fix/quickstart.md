# Quickstart: Browser Compatibility Fix

## Prerequisites

- SSH access to production server (`root@ainetic.tech`)
- Chrome, Yandex Browser, and Arc Browser installed locally
- Access to moltis.ainetic.tech (HTTPS)

## Diagnosis Steps

### 1. Check Current State

```bash
# Verify Moltis is running
ssh root@ainetic.tech "docker ps | grep moltis"

# Check recent Moltis logs for auth errors
ssh root@ainetic.tech "docker logs moltis --tail 50 2>&1 | grep -i 'auth\|error\|cookie'"

# Check Traefik routing for Moltis
ssh root@ainetic.tech "docker logs traefik 2>&1 | grep -i moltis | tail -10"
```

### 2. Browser Testing

For each browser (Chrome, Yandex, Arc):

1. Open DevTools (`F12` or `Cmd+Option+I`)
2. Go to **Network** tab, enable "Preserve log"
3. Navigate to `https://moltis.ainetic.tech`
4. Check:
   - Response headers (look for `Set-Cookie`, `WWW-Authenticate`)
   - WebSocket connection (filter by "WS")
   - Console errors
   - Cookie storage (Application → Cookies)

### 3. Compare Headers

Key headers to compare across browsers:

| Header | Expected | Issue If Missing |
|--------|----------|-----------------|
| `Set-Cookie: moltis_session=...` | Present on login | Auth won't persist |
| `SameSite=Strict` | Present | May cause loop in some browsers |
| `Upgrade: websocket` | Present on WS | Real-time features broken |
| `X-Forwarded-Proto: https` | Present | Moltis thinks connection is HTTP |

## Fix Application

After diagnosis, apply fixes via GitOps:

```bash
# 1. Edit config files locally
vim docker-compose.prod.yml  # Add Traefik middleware

# 2. Commit and push
git add docker-compose.prod.yml
git commit -m "fix(proxy): add browser compatibility headers"
git push

# 3. CI/CD deploys the tracked git version automatically,
#    or trigger the backup-safe helper on the server:
# ssh root@ainetic.tech "cd /opt/moltinger && ./scripts/deploy.sh --json moltis deploy"
```

## Verification

After fix is deployed, test all browsers:

```bash
# Quick health check
curl -sk -o /dev/null -w '%{http_code}' https://moltis.ainetic.tech/health

# Check cookie headers
curl -sI https://moltis.ainetic.tech/api/auth/login 2>&1 | grep -i 'set-cookie\|same-site'
```

Then manually verify in each browser:
1. Open moltis.ainetic.tech
2. Login with password
3. Verify UI loads
4. Send a test message (check WebSocket)
5. Close tab, reopen (check session persistence)
