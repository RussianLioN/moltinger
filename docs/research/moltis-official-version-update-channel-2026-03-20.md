# Moltis Official Version-Update Channel Research (2026-03-20)

**Status**: complete  
**Audience**: operators, CI/CD maintainers, LLM agents  
**Purpose**: define a safe and deterministic contract for upgrading Moltis to the freshest official version without accidental rollback.

## Sources

1. Official Docker docs: `https://docs.moltis.org/docker.html`
2. Official releases API: `https://api.github.com/repos/moltis-org/moltis/releases/latest`
3. Official GHCR image endpoint: `ghcr.io/moltis-org/moltis`

## Verified Evidence

### A) Official Docker channel

`docs.moltis.org/docker.html` states the image is published on every release and all examples use:

- `ghcr.io/moltis-org/moltis:latest`

Collected on 2026-03-20 via:

```bash
curl -sS https://docs.moltis.org/docker.html -o /tmp/moltis-docker-doc.html
xmllint --html --xpath "string(//main)" /tmp/moltis-docker-doc.html 2>/dev/null | rg "published to GitHub Container Registry|ghcr.io/moltis-org/moltis:latest"
```

### B) Freshest official release

Latest upstream release at verification time:

- `tag_name: v0.10.18`
- `published_at: 2026-03-09T18:14:25Z`

Collected via:

```bash
curl -sS https://api.github.com/repos/moltis-org/moltis/releases/latest | jq -r '.tag_name, .published_at, .html_url'
```

### C) Pullable GHCR tag format

For `v0.10.18`, GHCR pullable tag is `0.10.18` (without leading `v`):

```bash
docker manifest inspect ghcr.io/moltis-org/moltis:0.10.18 >/dev/null && echo ok
docker manifest inspect ghcr.io/moltis-org/moltis:v0.10.18 >/dev/null && echo ok
```

Observed result on 2026-03-20:

- `0.10.18` is present
- `v0.10.18` is missing

## Final Upgrade Contract (for operators and LLM)

1. Use official Moltis Docker channel as source of truth.
2. In GitOps, track an explicit immutable GHCR tag in compose defaults (not `latest`).
3. Normalize release tag `vX.Y.Z` to GHCR tag `X.Y.Z` before writing tracked version.
4. Reject tracked versions with leading `v` in `scripts/moltis-version.sh assert-tracked`.
5. Deploy only tracked git version; disallow ad-hoc version drift in production workflow.

## Update Procedure

1. Resolve latest release and normalize:

```bash
LATEST_RELEASE="$(curl -sS https://api.github.com/repos/moltis-org/moltis/releases/latest | jq -r '.tag_name')"
TRACKED_TAG="${LATEST_RELEASE#v}"
```

2. Verify GHCR tag exists:

```bash
docker manifest inspect "ghcr.io/moltis-org/moltis:${TRACKED_TAG}" >/dev/null
```

3. Update tracked compose defaults to `${MOLTIS_VERSION:-${TRACKED_TAG}}`.
4. Run static checks, then deploy through GitHub Actions backup-safe flow.

## Why this contract

- Official docs guarantee distribution channel (`latest` path and release publishing).
- GitOps production requires deterministic rollback-safe behavior, so runtime rollout must be pinned to a verified immutable tag.
- This hybrid keeps upstream compatibility while preventing accidental old-version stickiness or non-pullable tag pins.
