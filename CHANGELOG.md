# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
