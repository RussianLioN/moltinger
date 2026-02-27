# Release Notes

User-facing release notes for all versions.

## v1.7.0

_Released on 2026-02-27_

### ✨ New Features

- **CI/CD**: Add scripts/ to GitOps sync (P0-3) + workflow edit permission
- **Security**: Add GitOps enforcement - P0 recommendations
- **permissions**: Add Context7 MCP to allowlist
- **scripts**: Add Moltis API test script + GitOps lessons
- **Security**: Enable sandbox mode with Zero Trust permissions
- **moltis**: Add self-learning infrastructure
- **config**: Add system prompt (soul) for GLM-5 (moltinger-z7k)

### 🐛 Bug Fixes

- **sandbox**: Allow ssh for automated testing
- **sandbox**: Allow git push for automated scripts
- **sandbox**: Allow .env.example and templates in deny list
- **settings**: Merge duplicate 'ask' keys in permissions
- **CI/CD**: Add concurrency control to prevent parallel deploys (moltinger-9q3)

---

_This release was automatically generated from 15 commits._

## v1.6.0

_Released on 2026-02-17_

### ✨ New Features

- **telegram**: Add Telegram bot configuration template
- **moltis**: Switch web search from Brave to Tavily (free, no card)
- **session**: Implement session context persistence system
- **moltis**: Update configuration with security fixes and free providers

### 🔒 Security

- Remove exposed API keys from git (moltinger-lzy)

### 🐛 Bug Fixes

- **moltis**: Update allowed_models with exact zai::model IDs
- **moltis**: Rename provider alias to 'zai', add explicit models whitelist
- **moltis**: Use exact model IDs in allowed_models to filter out gpt-4o and local-llm
- **moltis**: Use only API-discoverable GLM models (glm-4.7-flash not available via API)
- **moltis**: Restore glm-4.7-flash to allowed_models (verified via Z.ai rate limits page)
- **moltis**: Replace unavailable glm-4.7-flash with glm-4.6 in allowed_models
- **moltis**: Configure GLM-5 via OpenAI-compatible provider (molt-xxx)
- Add MOLTIS_PORT env var, disable Ollama provider
- **telegram**: Enable Telegram integration (moltinger-pmc)
- **moltis**: Correct server bind and port for Docker deployment (moltinger-35g)
- **moltis**: Use SSE transport for Tavily remote MCP server
- **CI/CD**: Generate .env from GitHub Secrets + add missing env vars
- **moltis**: Use official tavily-mcp package from Tavily docs
- **moltis**: Use correct npm package name for Tavily MCP server
- **config**: Remove duplicate resource_limits section causing TOML parse error
- **moltis**: Use npx instead of uvx for Tavily MCP server
- **CI/CD**: Sync config directory including moltis.toml

---

_This release was automatically generated from 37 commits._

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
