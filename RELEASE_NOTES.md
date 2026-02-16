# Release Notes

User-facing release notes for all versions.

## v1.5.0

_Released on 2026-02-16_

### ✨ New Features

- **CI/CD**: Implement GitOps-compliant deployment pipeline
- Moltis GitOps 2.0 Deployment to Production (#1)
- Init moltinger project with Moltis Docker deployment

### 🐛 Bug Fixes

- **docker**: Connect Moltis to ainetic_net for Traefik routing
- **traefik**: Move Moltis to subdomain moltis.ainetic.tech
- **traefik**: Move Moltis to /moltis path to restore n8n
- **CI/CD**: Make root path test non-blocking in smoke tests
- **CI/CD**: Accept 504/timeout for root path in smoke tests
- **CI/CD**: Smoke tests now accept 401 as valid (auth enabled)

---

_This release was automatically generated from 14 commits._
