# Version Update Process

This document describes how to manage Docker image versions for the Moltis infrastructure.

## Checking Current Versions

Use the Makefile target to see currently configured versions:

```bash
make version-check
```

Output example:
```
Moltis version:
docker-compose.yml:    image: ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-v1.7.0}
docker-compose.prod.yml:    image: ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-v1.7.0}

Watchtower version:
docker-compose.yml:    image: containrrr/watchtower:v1.7.1
docker-compose.prod.yml:    image: containrrr/watchtower:v1.7.1
```

## Updating Moltis Version

The Moltis version is configured in both `docker-compose.yml` and `docker-compose.prod.yml`.

### Method 1: Environment Variable (Recommended for quick testing)

```bash
export MOLTIS_VERSION=v1.8.0
make deploy
```

### Method 2: Update Default Version (Persistent)

Edit both compose files to change the default version:

```bash
# Update docker-compose.yml
sed -i 's/MOLTIS_VERSION:-v1.7.0/MOLTIS_VERSION:-v1.8.0/' docker-compose.yml

# Update docker-compose.prod.yml
sed -i 's/MOLTIS_VERSION:-v1.7.0/MOLTIS_VERSION:-v1.8.0/' docker-compose.prod.yml
```

Or manually edit the files and change the image line:
```yaml
image: ghcr.io/moltis-org/moltis:${MOLTIS_VERSION:-v1.8.0}
```

### Git Commit for Version Changes

After updating versions, commit the changes:

```bash
git add docker-compose.yml docker-compose.prod.yml
git commit -m "chore: bump Moltis to v1.8.0"
git push
```

## Updating Watchtower Version

Watchtower handles automatic container updates. Pin to a specific version for stability.

### Steps

1. Check available releases: https://github.com/containrrr/watchtower/releases
2. Update both compose files:

```yaml
image: containrrr/watchtower:v2.0.0
```

3. Commit the change:

```bash
git add docker-compose.yml docker-compose.prod.yml
git commit -m "chore: bump Watchtower to v2.0.0"
git push
```

## Deployment Verification

After updating versions, verify the deployment:

### 1. Check Container Status

```bash
make status
```

### 2. Verify Image Version

```bash
docker inspect moltis --format '{{.Config.Image}}'
```

### 3. Health Check

```bash
make health-check
```

### 4. Check Logs

```bash
make logs LOGS_OPTS="-f --tail=100"
```

### 5. Verify Watchtower is Running

```bash
docker logs watchtower --tail=50
```

## Rollback Process

If a version update causes issues:

### Quick Rollback

```bash
# Stop current deployment
make stop

# Revert to previous version
export MOLTIS_VERSION=v1.7.0
make deploy
```

### Git-based Rollback

```bash
# Find the commit with the previous version
git log --oneline -10

# Revert the version change commit
git revert <commit-sha>
git push

# Redeploy
make deploy
```

## Version Pinning Best Practices

1. **Always pin versions** - Never use `:latest` tag in production
2. **Use semantic versioning** - Pin to major.minor.patch (e.g., `v1.7.0`)
3. **Test before production** - Deploy to dev/staging first
4. **Document changes** - Include version updates in release notes
5. **Monitor after updates** - Watch logs and metrics for anomalies

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `MOLTIS_VERSION` | `v1.7.0` | Moltis application version |
| `WATCHTOWER_VERSION` | `v1.7.1` | Watchtower auto-updater version |

## Related Documentation

- [Deployment Strategy](./deployment-strategy.md)
- [Infrastructure Overview](./INFRASTRUCTURE.md)
- [Quick Reference](./QUICK-REFERENCE.md)
