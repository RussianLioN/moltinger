# Compatibility Matrix

| Surface | Status | Install Surface | Core Behavior |
|---------|--------|-----------------|---------------|
| Claude Code | Supported | Copy adapter files into `.claude/`-compatible locations | Shared portable worktree flow |
| Codex CLI | Supported | Copy adapter files and run Codex registration bridge if needed | Shared portable worktree flow |
| OpenCode | Supported with manual registration fallback | Copy adapter files and follow OpenCode registration steps | Shared portable worktree flow |
| Speckit bridge | Optional | Copy `bridge/speckit/` alongside `core/` | Does not change core behavior |

## Rules

- Adapters may change discovery and registration only.
- Adapters may not fork branch/worktree semantics.
- Optional integrations like issue trackers remain optional.
- Host-project governance remains outside this repository.
