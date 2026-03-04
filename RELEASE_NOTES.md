# Release Notes

User-facing release notes for all versions.

## v1.9.0

_Released on 2026-03-04_

### ✨ New Features

- **Skills**: Add lessons skill for RCA lesson management (US6)
- **lessons**: Implement Lessons Architecture from RCA consilium
- **rca**: Complete Phase 8 - Integration & Polish
- **rca**: Complete Phase 7 - Test Generation (US5)
- **rca**: Complete Phase 6 - Chain-of-Thought Pattern (US4)
- **rca**: Complete Phase 5 - RCA Hub Architecture (US3)
- **rca**: Complete Phase 4 - Domain-Specific Templates (US2)
- **rca**: Complete Phase 3 - Auto-Context Collection (US1)
- **rca**: Complete Phase 2 - foundational enhancements
- **tasks**: Generate task list for RCA Skill Enhancements
- **plan**: Complete RCA Skill Enhancements planning phase
- **Skills**: Add rca-5-whys skill for Root Cause Analysis
- **tests**: Enhance E2E tests with session restore and rate limiting scenarios
- **CI/CD**: Add matrix testing, caching, and slack notifications
- **CI/CD**: Add comprehensive test suite CI/CD workflow
- **tests**: Add more test files and normalize line endings
- **tests**: Add test infrastructure framework
- **tools**: Add rate limit monitoring and OpenClaw clone plan
- **fallback-llm**: Add CI/CD validation for failover (T024-T026, moltinger-39q)
- **fallback-llm**: Add Ollama validation to preflight (T022-T023, moltinger-39q)
- **fallback-llm**: Add Prometheus alerts and AlertManager config (T020-T021, moltinger-39q)
- **fallback-llm**: Add Prometheus metrics export (T016-T019, moltinger-39q)
- **fallback-llm**: Implement circuit breaker state machine (T011-T015, moltinger-39q)
- **scripts**: Add it2attention fireworks for visible rate limit alerts
- **fallback-llm**: Add GLM/Ollama health checks (T010, moltinger-39q)
- **fallback-llm**: Add Ollama health check script (T009, moltinger-39q)
- **fallback-llm**: Add Ollama sidecar and configure failover (moltinger-39q)
- **moltis**: Add Gemini fallback for Z.ai rate limit resilience

### 🔧 Improvements

- **moltis**: Reduce timeout to 30s for fast failover
- **telegram**: Change allowed_users to env var format for whitelist support
- Move checklists from CLAUDE.md to LESSONS-LEARNED.md (token optimization)

### 🐛 Bug Fixes

- **telegram**: Use array format for allowed_users instead of env string
- **token-bloat**: Remove CLAUDE.md/MEMORY.md direct write instructions
- **rca-skill**: Remove token bloat contradiction (RCA-004)
- **instructions**: Add token limit warnings to prevent bloat (RCA-004)
- **rca**: Add mandatory lessons indexing step to RCA workflow
- **rca**: Add mandatory lessons indexing step to RCA workflow
- **tests**: Restore LOGIN_SUCCESS after invalid password test
- **tests**: Correct JSON escaping in E2E login test
- **instructions**: Strengthen RCA trigger for any non-zero exit code
- **Skills**: Integrate RCA 5 Whys into systematic-debugging
- **tests**: Fix api_request function and metrics endpoint
- **tests**: Use correct login endpoint /api/auth/login with JSON
- **tests**: Improve shell compatibility for zsh and bash
- **deploy**: Specify traefik.docker.network to use correct IP
- **deploy**: Set correct MOLTIS_DOMAIN to moltis.ainetic.tech
- **deploy**: Correct Traefik Host rule to moltis.ainetic.tech
- **deploy**: Use traefik-net instead of traefik_proxy
- **resources**: Adjust CPU limits to fit 2-CPU server (moltis: 2, ollama: 1.5)
- **CI/CD**: Sync docker-compose.prod.yml and use -f flag for all compose commands
- **deploy**: Use env vars instead of file secrets - secrets from GitHub via .env
- **CI/CD**: Use 'latest' image tag which exists on server
- **CI/CD**: Make image pull optional - use local image if pull fails
- **CI/CD**: Use v1.7.0 as default version instead of non-existent latest tag
- **CI/CD**: Quote boolean env vars and add defaults for TELEGRAM_ALLOWED_USERS
- **CI/CD**: Convert CRLF to LF line endings in docker-compose.prod.yml
- **CI/CD**: Use -S error to only report actual shellcheck errors
- **CI/CD**: Use -S style to only report shellcheck errors, not warnings
- **CI/CD**: Ignore SC2155 shellcheck style warning for bash scripts
- **CI/CD**: Remove --strict flag since secrets are in GitHub, not local files
- **CI/CD**: Initialize arrays without declare to avoid unbound variable in bash
- **CI/CD**: Remove -v syntax for array check, use simple length check
- **CI/CD**: Separate stdout/stderr in preflight to avoid JSON corruption
- **CI/CD**: Handle empty arrays and missing YAML validators gracefully
- **CI/CD**: Redirect CI mode message to stderr for valid JSON output
- **CI/CD**: Add --ci mode to preflight-check.sh for GitHub Actions
- **fallback-llm**: Use OLLAMA_API_KEY env var instead of Docker secret
- **scripts**: Use home directory for alert log (sandbox fix)
- **scripts**: Correct process count and add notification fallbacks
- **scripts**: Fix timezone and newline bugs in rate-check
- **scripts**: Detect Z.ai rate limit code "1302" in addition to HTTP 429
- **scripts**: Rate-check now monitors ALL parallel sessions

---

_This release was automatically generated from 107 commits._

## v1.8.0

_Released on 2026-02-28_

### ✨ New Features

- **deploy**: Complete Phase 10 - polish and cross-cutting concerns
- **deploy**: Complete P1 tasks and implement P2 JSON output modes
- **session**: Complete session automation framework
- **deploy**: Implement GitOps compliance and backup script enhancements
- **hooks**: Add session auto-save on Stop hook
- **deploy**: Implement P1 user stories - systemd, secrets templates, version pinning
- **deploy**: Complete Phase 1-2 of docker-deploy-improvements
- Add        2 agent(s), update docs
- **CI/CD**: Add pre-deployment tests and backup verification cron
- **AI Agents**: Add consilium expert panel for parallel discussions
- **uat**: Add UAT gate with GitOps checks (P2-6)
- **metrics**: Add GitOps SLO and metrics collection (P2-5)
- **iac**: Add manifest-based scripts management (P2-4)
- **scripts**: Add GitOps guards to server scripts (P1-3)
- **CI/CD**: Add GitOps drift detection cron job (P1-2)
- **CI/CD**: Add GitOps compliance check job (P1-1)
- **AI Agents**: Add worktree isolation to bug-fixer

### 🐛 Bug Fixes

- **hooks**: Use correct SESSION_SUMMARY.md filename
- **scripts**: Convert CRLF to LF line endings in shell scripts
- **sandbox**: Add SSH agent paths and git push to permissions (moltinger-session)
- **sandbox**: Add read permissions for ~/.beads directory
- **health**: Resolve MEDIUM priority bugs (moltinger-71r, moltinger-lxb)
- **health**: Resolve HIGH priority bugs from health check (moltinger-wisp-u7e)
- **sandbox**: Add ~/.beads to write allow list for daemon

---

_This release was automatically generated from 33 commits._

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
