# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.9.0] - 2026-03-04

### Added
- **skills**: add lessons skill for RCA lesson management (US6) (72cfe89)
- **lessons**: implement Lessons Architecture from RCA consilium (0fac204)
- **rca**: complete Phase 8 - Integration & Polish (de22503)
- **rca**: complete Phase 7 - Test Generation (US5) (4506d43)
- **rca**: complete Phase 6 - Chain-of-Thought Pattern (US4) (9b5721c)
- **rca**: complete Phase 5 - RCA Hub Architecture (US3) (366c9e2)
- **rca**: complete Phase 4 - Domain-Specific Templates (US2) (02f263d)
- **rca**: complete Phase 3 - Auto-Context Collection (US1) (dd8b4bb)
- **rca**: complete Phase 2 - foundational enhancements (3481a2c)
- **tasks**: generate task list for RCA Skill Enhancements (8c0128b)
- **plan**: complete RCA Skill Enhancements planning phase (e307a57)
- **skills**: add rca-5-whys skill for Root Cause Analysis (c97f9cd)
- **tests**: enhance E2E tests with session restore and rate limiting scenarios (6c395cf)
- **ci**: add matrix testing, caching, and slack notifications (e9f3a3d)
- **ci**: add comprehensive test suite CI/CD workflow (03c4c1a)
- **tests**: add more test files and normalize line endings (1648c19)
- **tests**: add test infrastructure framework (907c383)
- **tools**: add rate limit monitoring and OpenClaw clone plan (d7fc975)
- **fallback-llm**: add CI/CD validation for failover (T024-T026, moltinger-39q) (19505b9)
- **fallback-llm**: add Ollama validation to preflight (T022-T023, moltinger-39q) (5ee89c2)
- **fallback-llm**: add Prometheus alerts and AlertManager config (T020-T021, moltinger-39q) (cf65a93)
- **fallback-llm**: add Prometheus metrics export (T016-T019, moltinger-39q) (68c6dbb)
- **fallback-llm**: implement circuit breaker state machine (T011-T015, moltinger-39q) (c1b2be5)
- **scripts**: add it2attention fireworks for visible rate limit alerts (a3810a3)
- **fallback-llm**: add GLM/Ollama health checks (T010, moltinger-39q) (fd06e46)
- **fallback-llm**: add Ollama health check script (T009, moltinger-39q) (5dc8f0b)
- **fallback-llm**: add Ollama sidecar and configure failover (moltinger-39q) (98ec7ba)
- **moltis**: add Gemini fallback for Z.ai rate limit resilience (7ab5a38)

### Changed
- **telegram**: change allowed_users to env var format for whitelist support (5b6fd2a)
- move checklists from CLAUDE.md to LESSONS-LEARNED.md (token optimization) (b04510a)
- **moltis**: reduce timeout to 30s for fast failover (25777e5)

### Fixed
- **telegram**: use array format for allowed_users instead of env string (f30fe19)
- **token-bloat**: remove CLAUDE.md/MEMORY.md direct write instructions (72b7740)
- **rca-skill**: remove token bloat contradiction (RCA-004) (6f50a95)
- **instructions**: add token limit warnings to prevent bloat (RCA-004) (1420dce)
- **rca**: add mandatory lessons indexing step to RCA workflow (d3ad740)
- **rca**: add mandatory lessons indexing step to RCA workflow (90e9530)
- **tests**: restore LOGIN_SUCCESS after invalid password test (65c9942)
- **tests**: correct JSON escaping in E2E login test (7559ee0)
- **instructions**: strengthen RCA trigger for any non-zero exit code (b28dda2)
- **skills**: integrate RCA 5 Whys into systematic-debugging (dbe6f39)
- **tests**: fix api_request function and metrics endpoint (1c431e7)
- **tests**: use correct login endpoint /api/auth/login with JSON (a9cd1d7)
- **tests**: improve shell compatibility for zsh and bash (d493a71)
- **deploy**: specify traefik.docker.network to use correct IP (df36060)
- **deploy**: set correct MOLTIS_DOMAIN to moltis.ainetic.tech (53194c0)
- **deploy**: correct Traefik Host rule to moltis.ainetic.tech (5572c0c)
- **deploy**: use traefik-net instead of traefik_proxy (e47e309)
- **resources**: adjust CPU limits to fit 2-CPU server (moltis: 2, ollama: 1.5) (b619f36)
- **ci**: sync docker-compose.prod.yml and use -f flag for all compose commands (89aac32)
- **deploy**: use env vars instead of file secrets - secrets from GitHub via .env (a87d745)
- **ci**: use 'latest' image tag which exists on server (d909755)
- **ci**: make image pull optional - use local image if pull fails (505fa76)
- **ci**: use v1.7.0 as default version instead of non-existent latest tag (112504c)
- **ci**: quote boolean env vars and add defaults for TELEGRAM_ALLOWED_USERS (65b6321)
- **ci**: convert CRLF to LF line endings in docker-compose.prod.yml (3ea97ec)
- **ci**: use -S error to only report actual shellcheck errors (1f44237)
- **ci**: use -S style to only report shellcheck errors, not warnings (61e41ac)
- **ci**: ignore SC2155 shellcheck style warning for bash scripts (881c30e)
- **ci**: remove --strict flag since secrets are in GitHub, not local files (44aaa7f)
- **ci**: initialize arrays without declare to avoid unbound variable in bash (6bf2079)
- **ci**: remove -v syntax for array check, use simple length check (0b7edd2)
- **ci**: separate stdout/stderr in preflight to avoid JSON corruption (cf88fe1)
- **ci**: handle empty arrays and missing YAML validators gracefully (6c11ead)
- **ci**: redirect CI mode message to stderr for valid JSON output (eabeea7)
- **ci**: add --ci mode to preflight-check.sh for GitHub Actions (7b5788f)
- **fallback-llm**: use OLLAMA_API_KEY env var instead of Docker secret (41e2724)
- **scripts**: use home directory for alert log (sandbox fix) (499ab56)
- **scripts**: correct process count and add notification fallbacks (c369935)
- **scripts**: fix timezone and newline bugs in rate-check (13f3752)
- **scripts**: detect Z.ai rate limit code "1302" in addition to HTTP 429 (3e60b09)
- **scripts**: rate-check now monitors ALL parallel sessions (d15e581)

### Other
- update project files (00ae79f)
- update docs (9062f00)
- Merge branch '001-rca-skill-upgrades' into main (7b9a361)
- **beads**: close moltinger-wk1 after feature completion (e6bedf0)
- **session**: update with final token bloat commits (f9d713f)
- **session**: extended summary for RCA Skill Enhancements final session (65fd15a)
- **rca**: add lesson from unauthorized file deletion attempt (P0) (bbc4f2a)
- sync beads issues (moltinger-5ls closed) (118ad56)
- **rca**: complete T044 and T054 - autonomous testing passed (31b3e44)
- **session**: update with US6 lessons skill completion (4760c95)
- update LESSONS-LEARNED.md date (de92ff7)
- **spec**: add US6 Lessons Query Skill to RCA enhancements (475e890)
- **session**: update with RCA Skill Enhancements completion (b6a3478)
- **beads**: add lessons skill task to backlog (moltinger-wk1) (03e7c5c)
- **rca**: comprehensive test of enhanced RCA skill (e2b537a)
- **rca**: add RCA-003 for git branch confusion (5ca3139)
- **backlog**: add testing technical debt for Fallback LLM (9fa1231)
- **session**: update with RCA Skill Enhancements progress (839cd4d)
- **spec**: add RCA Skill Enhancements specification (d0a8c45)
- **session**: add test suite bug fixes and server validation results (414d286)
- **session**: add test suite CI/CD integration to session summary (e552a74)
- **memory**: comprehensive project configuration and structure (0454076)
- **lessons**: add Docker Network lesson #14 (Traefik routing) (5ef983b)
- **session**: add CI/CD smoke test 404 fix to history (4148183)
- **session**: update with 2026-03-02 session - CI/CD debug & lessons (648ba87)
- **lessons**: add Incident #003 retrospective - self-inflicted CI/CD failures (0974da7)
- trigger CI/CD retry after SSH unblock (7bf59dd)
- trigger deploy with OLLAMA_API_KEY (0b38c2f)
- **session**: add rate monitoring tools to session history (bfe6b91)
- **session**: mark Fallback LLM feature as complete (e129990)
- **fallback-llm**: complete Phase 6 - documentation and close epic (T028-T032, moltinger-39q) (88f59df)
- **fallback-llm**: update SESSION_SUMMARY and .gitignore (T027, T030, moltinger-39q) (e4d02b8)
- **session**: update with Docker Deployment Improvements completion (39471d7)
- **beads**: close Docker Deployment Improvements epic - all phases complete (molt-6ys) (789fba8)
- **session**: update with session automation framework (a709a53)

## [1.8.0] - 2026-02-28

### Added
- **deploy**: complete Phase 10 - polish and cross-cutting concerns (80764d8)
- **deploy**: complete P1 tasks and implement P2 JSON output modes (e606064)
- **session**: complete session automation framework (f8dab74)
- **deploy**: implement GitOps compliance and backup script enhancements (609ee42)
- **hooks**: add session auto-save on Stop hook (7246333)
- **deploy**: implement P1 user stories - systemd, secrets templates, version pinning (062bb61)
- **deploy**: complete Phase 1-2 of docker-deploy-improvements (72de559)
- add        2 agent(s), update docs (cc52210)
- **ci**: add pre-deployment tests and backup verification cron (2aaa763)
- **agents**: add consilium expert panel for parallel discussions (768564e)
- **uat**: add UAT gate with GitOps checks (P2-6) (62a08ac)
- **metrics**: add GitOps SLO and metrics collection (P2-5) (61cd539)
- **iac**: add manifest-based scripts management (P2-4) (70b24d5)
- **scripts**: add GitOps guards to server scripts (P1-3) (688efee)
- **ci**: add GitOps drift detection cron job (P1-2) (dac5a33)
- **ci**: add GitOps compliance check job (P1-1) (fddfc17)
- **agents**: add worktree isolation to bug-fixer (406edef)

### Fixed
- **hooks**: use correct SESSION_SUMMARY.md filename (9d89adb)
- **scripts**: convert CRLF to LF line endings in shell scripts (ca54dd1)
- **sandbox**: add SSH agent paths and git push to permissions (moltinger-session) (6fd4f13)
- **sandbox**: add read permissions for ~/.beads directory (15c8ee6)
- **health**: resolve MEDIUM priority bugs (moltinger-71r, moltinger-lxb) (ef5cbfc)
- **health**: resolve HIGH priority bugs from health check (moltinger-wisp-u7e) (39a7f76)
- **sandbox**: add ~/.beads to write allow list for daemon (83cff41)

### Other
- sync linter changes and beads (09b4745)
- add P4 backlog priorities and update SESSION_SUMMARY (4dcca50)
- sync beads (04a1136)
- sync beads (final) (77c740c)
- sync beads issues (78c411a)
- update SESSION_SUMMARY with P4 tasks completion (5bca102)
- update SESSION_SUMMARY with GitOps framework progress (afb1e60)
- update Claude Code config and agents (b8c9bc4)
- **incident**: add file deletion safety rules (2026-02-28) (2b8ef8c)

## [1.7.0] - 2026-02-27

### Added
- **ci**: add scripts/ to GitOps sync (P0-3) + workflow edit permission (c74ce8e)
- **security**: add GitOps enforcement - P0 recommendations (1133cd6)
- **permissions**: add Context7 MCP to allowlist (b9c8db7)
- **scripts**: add Moltis API test script + GitOps lessons (7e1ccfb)
- **security**: enable sandbox mode with Zero Trust permissions (27041d2)
- **moltis**: add self-learning infrastructure (022ea93)
- **config**: add system prompt (soul) for GLM-5 (moltinger-z7k) (a0f13ee)

### Fixed
- **sandbox**: allow ssh for automated testing (86783ee)
- **sandbox**: allow git push for automated scripts (cd3c38c)
- **sandbox**: allow .env.example and templates in deny list (8626692)
- **settings**: merge duplicate 'ask' keys in permissions (b9ed51d)
- **ci**: add concurrency control to prevent parallel deploys (moltinger-9q3) (66c559d)

### Other
- create unified GitOps & Infrastructure roadmap (bc9933d)
- update docs (bb871d2)
- **sandbox**: add heredoc workaround instructions (1b2da3b)

## [1.6.0] - 2026-02-17

### Security
- remove exposed API keys from git (moltinger-lzy) (41945e0)

### Added
- **telegram**: add Telegram bot configuration template (95eb3c9)
- **moltis**: switch web search from Brave to Tavily (free, no card) (34a0695)
- **session**: implement session context persistence system (ecd72fb)
- **moltis**: update configuration with security fixes and free providers (b916ed5)

### Fixed
- **moltis**: update allowed_models with exact zai::model IDs (1374fc5)
- **moltis**: rename provider alias to 'zai', add explicit models whitelist (a46921f)
- **moltis**: use exact model IDs in allowed_models to filter out gpt-4o and local-llm (4c972d8)
- **moltis**: use only API-discoverable GLM models (glm-4.7-flash not available via API) (de86084)
- **moltis**: restore glm-4.7-flash to allowed_models (verified via Z.ai rate limits page) (8d2450c)
- **moltis**: replace unavailable glm-4.7-flash with glm-4.6 in allowed_models (63e1b7f)
- **moltis**: configure GLM-5 via OpenAI-compatible provider (molt-xxx) (1ecbaa2)
- add MOLTIS_PORT env var, disable Ollama provider (3da3bf5)
- **telegram**: enable Telegram integration (moltinger-pmc) (2507d4e)
- **moltis**: correct server bind and port for Docker deployment (moltinger-35g) (af08cdc)
- **moltis**: use SSE transport for Tavily remote MCP server (630bf5d)
- **ci**: generate .env from GitHub Secrets + add missing env vars (b5e9606)
- **moltis**: use official tavily-mcp package from Tavily docs (b68bb7e)
- **moltis**: use correct npm package name for Tavily MCP server (dbc31b2)
- **config**: remove duplicate resource_limits section causing TOML parse error (fc4c5b7)
- **moltis**: use npx instead of uvx for Tavily MCP server (8e2027a)
- **ci**: sync config directory including moltis.toml (9595de9)

### Other
- update docs (6d164f6)
- update SESSION_SUMMARY with GLM-5 configuration session (b71f618)
- **moltis**: remove local-llm and other providers from offered list, keep only openai (GLM) (b40ed89)
- **moltis**: finalize allowed_models to 3 GLM models only (glm-5, glm-4.7, glm-4.5-air) (3b8e0da)
- **moltis**: filter allowed_models to 4 GLM models only (glm-5, glm-4.7, glm-4.7-flash, glm-4.5-air) (eba33d1)
- update session summary - health check complete, all issues fixed (40c0dbe)
- sync beads issues (063a53e)
- update session summary with pending issues and test plan (f83c5e3)
- update secrets status - Telegram configured (2770ad6)
- add Lessons Learned from Tavily MCP integration incident (a458e18)
- update secrets status - TAVILY_API_KEY added (7fcb066)
- plan session context persistence system (P0 blocking) (4be7f69)
- add secrets management policy (5177c10)
- add research reports for TTS/STT, sandbox, and Web Search API alternatives (5ecf531)
- **beads**: close all Moltis deployment tasks (08cf277)

## [1.5.0] - 2026-02-16

### Added
- **ci**: implement GitOps-compliant deployment pipeline (1b16181)
- Moltis GitOps 2.0 Deployment to Production (#1) (2b553ec)
- init moltinger project with Moltis Docker deployment (c4c69fc)

### Fixed
- **docker**: connect Moltis to ainetic_net for Traefik routing (1664d49)
- **traefik**: move Moltis to subdomain moltis.ainetic.tech (19d0c64)
- **traefik**: move Moltis to /moltis path to restore n8n (c108e08)
- **ci**: make root path test non-blocking in smoke tests (982c8cd)
- **ci**: accept 504/timeout for root path in smoke tests (fded5d5)
- **ci**: smoke tests now accept 401 as valid (auth enabled) (75493c4)

### Other
- remove completed plan file (ee3997a)
- update SESSION_SUMMARY with subdomain migration (6890841)
- **gitops**: clarify scp vs git pull approaches (d6fe552)
- update SESSION_SUMMARY with Traefik fix and user testing plan (6f37aea)
- update SESSION_SUMMARY - GitOps 2.0 complete, production live (d3dac5f)
