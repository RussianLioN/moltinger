# Research: Clawdiy Remote OAuth Runtime Lifecycle

**Feature**: 017-clawdiy-remote-oauth-lifecycle  
**Date**: 2026-03-12  
**Status**: Complete  
**Primary durable source**: [docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md](/Users/rl/coding/moltinger-openclaw-control-plane/docs/research/clawdiy-openclaw-remote-oauth-runtime-2026-03-12.md)

## Summary

This feature inherits the Clawdiy platform baseline from [specs/001-clawdiy-agent-platform/research.md](/Users/rl/coding/moltinger-openclaw-control-plane/specs/001-clawdiy-agent-platform/research.md) and narrows it to one production problem: converting `codex-oauth` from metadata gate into a real runtime lifecycle for the live OpenClaw container on `ainetic.tech`.

## Official Evidence

- Official OpenClaw docs still prescribe `openclaw models auth login --provider codex-oauth --set-default`.
- Official remote/VPS FAQ still prescribes a manual paste-back callback flow through `http://localhost:1455/...`.
- Official runtime docs treat auth profiles as runtime state, not only deploy metadata.

## Community Evidence

- `openclaw/openclaw#41885`: remote paste-back flow can hang.
- `openclaw/openclaw#42291`: OAuth may write into the wrong locality.
- `openclaw/openclaw#40364`: provider may stay inactive without explicit config.
- `openclaw/openclaw#39994`: scopes may still be wrong after “successful” OAuth.

## Explicit Inference

- The repository must stop treating `CLAWDIY_OPENAI_CODEX_AUTH_PROFILE` as if it were a real runtime auth artifact.
- Production readiness requires three layers:
  - metadata gate
  - runtime auth store
  - post-auth canary evidence

## Planning Decision

Recommended now: bootstrap OAuth against the actual target runtime auth store, then keep verification/quarantine under GitOps.

Recommended later: upgrade to artifactized delivery of the runtime auth store after the repo gains a formal lifecycle for that artifact.
