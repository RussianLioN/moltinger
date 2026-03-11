# Quickstart: Portable Worktree Skill Extraction

## Goal

Проверить, что standalone репозиторий `worktree-skill` можно:

1. скачать локально;
2. скопировать в host project почти как есть;
3. при необходимости зарегистрировать выбранный adapter;
4. использовать для dedicated worktree и handoff;
5. держать рядом со Speckit-артефактами без конфликта.

## Scenario 1: Greenfield Project, Copy-Only Install

Use when the host project does not already have worktree skill assets.

1. Clone `worktree-skill` locally.
2. Copy `core/` into the host project using the documented overlay layout.
3. Copy exactly one adapter from `adapters/claude-code/`, `adapters/codex-cli/`, or `adapters/opencode/`.
4. If using Speckit, also copy `bridge/speckit/`.
5. Run the documented verification steps.

Expected result:

- no mandatory reference to `moltinger`
- no secrets or production hostnames required
- one documented invocation surface for the selected IDE
- one documented verification signal for the core install

## Scenario 2: Existing Project, Copy Plus Bootstrap

Use when the host project already has `.claude/`, `scripts/`, or existing worktree docs.

1. Clone `worktree-skill` locally.
2. Review the migration guide for path collisions and host-only boundaries.
3. Copy `core/` into a staging branch or run `install/bootstrap.sh`.
4. Merge only the adapter needed by the host project.
5. Run `install/verify.sh` or the equivalent documented checks.

Expected result:

- conflicting files are listed before overwrite
- host-only assets remain in the host project
- the portable core is installed without pulling unrelated Moltinger governance docs

## Scenario 3: Claude Code Activation

1. Install `core/`.
2. Install `adapters/claude-code/`.
3. Run the Claude-specific registration or discovery step if required.
4. Invoke the worktree skill using the documented Claude surface.
5. Verify that the response uses the portable worktree and handoff contract.

Expected result:

- Claude adapter is discoverable
- branch/worktree planning matches the core contract
- handoff stops at the documented boundary

## Scenario 4: Codex CLI Activation

1. Install `core/`.
2. Install `adapters/codex-cli/`.
3. Run the Codex bridge or registration step.
4. Invoke the worktree skill via the documented Codex surface.
5. Verify parity with the Claude behavior.

Expected result:

- Codex discovers the adapter without requiring unrelated Claude assets
- core behavior matches the Claude path
- any missing registration step produces a clear corrective action

## Scenario 5: OpenCode Activation

1. Install `core/`.
2. Install `adapters/opencode/`.
3. Follow the OpenCode-specific registration instructions.
4. Run the documented verification.
5. Invoke the worktree flow and compare against the shared core contract.

Expected result:

- supported capabilities and fallback boundaries are explicit
- OpenCode does not require Moltinger-specific hand edits to core prompts

## Scenario 6: Speckit Coexistence

1. Prepare a host project with `spec.md`, `plan.md`, and `tasks.md`.
2. Install `core/` plus the selected IDE adapter.
3. Install `bridge/speckit/`.
4. Run a dedicated worktree flow for a spec-driven feature branch.
5. Verify that `spec.md`, `plan.md`, and `tasks.md` remain the authoritative planning artifacts.

Expected result:

- `/speckit.spec`, `/speckit.plan`, and `/speckit.tasks` remain intact
- worktree handoff respects branch-spec alignment
- no hidden mutation of Speckit artifacts occurs

## Post-Install Verification Checklist

- The host project contains the expected copied or bootstrapped directories only.
- The selected adapter is discoverable in its IDE.
- The worktree skill invocation produces the documented handoff boundary.
- The verification docs do not mention Moltinger runtime or secrets as prerequisites.
- Optional layers (`bd`, topology registry, Speckit bridge) remain optional unless the user explicitly installed them.

## Acceptance Evidence for `portable repo ready`

- Repository skeleton exists and matches the canonical layout.
- Claude Code, Codex CLI, and OpenCode each have a documented install path.
- Greenfield and existing-project examples both complete successfully.
- Migration guide identifies what stays in the host project.
- Release policy and compatibility matrix are present.
