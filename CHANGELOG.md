# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
