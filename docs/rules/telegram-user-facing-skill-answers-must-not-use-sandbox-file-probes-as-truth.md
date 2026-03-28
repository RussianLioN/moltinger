# Rule: Telegram user-facing skill answers must not use sandbox file probes as truth

For user-facing Telegram or other sandboxed messaging surfaces:

1. If a skill is already advertised by the live runtime as available, do not disprove that skill
   through `exec`, `cat`, `find`, or other filesystem probes against:
   - `/home/moltis/.moltis/skills`
   - `/server`
   - or similar host/runtime paths
2. Sandbox-invisible host paths are not proof that the skill is absent.
3. User-facing replies must not expose internal host/runtime paths such as:
   - `/home/moltis/.moltis/skills/...`
   - `/server/scripts/...`
4. For remote Moltis surfaces, `codex-update` must be treated as an advisory capability unless a
   trusted operator/local surface explicitly proves direct runtime execution is available.
5. If the canonical local runtime path is not reachable on the current surface:
   - use official external sources as the primary truth for release/advisory status; or
   - answer honestly that the surface can provide advisory status but not perform local update execution.

## Why

- Live runtime discovery and sandbox-visible filesystem are not always the same surface.
- Telegram user-facing chats must not receive false negatives caused by sandbox isolation.
- Telegram user-facing chats must not leak internal host paths or repo runtime details.

## Required checks

1. Prefer authoritative runtime truth:
   - `/api/skills`
   - runtime-advertised Available Skills
   - channel/runtime RPC state
2. Treat sandbox `exec` only as local evidence about that sandbox surface, not as global truth
   for skill existence.
3. Extend authoritative UAT to fail on:
   - host path leakage
   - false skill-missing replies
   - `Activity log` leakage

## Special note for `codex-update`

`codex-update` originated from a local Codex workflow. On remote Moltis surfaces it must not imply
that the server/container can update the user's local Codex CLI installation. Until the full
redesign lands, the remote-safe contract is advisory/notification only.

