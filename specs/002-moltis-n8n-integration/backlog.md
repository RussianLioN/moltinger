# Moltis + n8n Integration (Backlog)

> Status note (2026-04-21): backlog-only exploratory package. It is not the
> source of truth for the current Moltis provider/runtime/deploy remediation;
> use `../041-project-remediation-blockers/` and
> `../042-project-hygiene-drift-closure/` for the active remediation wave.

**Priority**: Low
**Status**: Backlog
**Created**: 2026-02-16

## Overview

Integration between Moltis AI assistant and n8n workflow automation platform.

## Possible Integrations

1. **Webhook triggers**: n8n workflows triggered by Moltis events
2. **Moltis API calls**: n8n calling Moltis for AI processing
3. **Shared data**: Exchange session context between systems

## Dependencies

- Moltis running on /moltis path ✅
- n8n running on root path ✅
- Network connectivity (both on ainetic_net) ✅

## Notes

- Both services are now on the same network
- Can communicate via internal Docker DNS
- Consider security implications of inter-service communication
