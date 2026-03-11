# OpenCode Registration Example

Use this file as a host-project-specific registration template when OpenCode does not support one-click discovery.

Recommended shape:

1. Point OpenCode to the portable command files under `core/.claude/commands/` or host-local wrappers.
2. Keep adapter-specific registration metadata in the host project.
3. Do not duplicate the core behavior inside the registration file.
