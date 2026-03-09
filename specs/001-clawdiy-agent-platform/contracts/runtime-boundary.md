# Contract: Runtime Boundary

**Feature**: 001-clawdiy-agent-platform  
**Purpose**: Define minimum isolation and ownership boundaries between Moltinger and Clawdiy.

## Required Separation

Clawdiy must have separate:

- compose project identity
- config root
- state root
- human auth secret
- service auth secret
- Telegram bot token
- provider auth profiles
- backup/restore scope
- health and alert ownership labels

## Shared Infrastructure Allowed

Clawdiy may reuse:

- Traefik host and `traefik-net`
- existing monitoring stack, as long as labels/targets are distinct
- GitHub Actions deployment mechanism
- operator documentation conventions

## Forbidden Coupling

The implementation must not:

- share Moltinger session cookies or password material
- reuse Moltinger persistent state directories
- use Telegram as the only authoritative inter-agent handoff path
- require Codex OAuth for baseline platform health
- break Moltinger deployment or rollback semantics

## Required Runtime Checks

- duplicate identity/domain/bot detection
- per-agent health endpoint verification
- per-agent secret presence verification
- route authorization verification
- rollback eligibility verification
