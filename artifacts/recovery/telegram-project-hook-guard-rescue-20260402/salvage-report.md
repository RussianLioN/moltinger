# Telegram Project Hook Guard Rescue Report

Date: 2026-04-02
Rescue branch: `fix/telegram-project-hook-guard-rescue`
Rescue base: `origin/main` @ `e6e2767fde88fc30a65032233cf64aabbc3bf346`
Preservation bundle: `artifacts/recovery/root-worktree-main-20260402T130646Z/`
Preserved root-main snapshot: `main` @ `5f2064d3e7970405773fc0f3e03d9054357d696d`

## Scope

This rescue pass reviewed only the preserved guard-related slice requested by the operator:

- `.moltis/hooks/telegram-safe-llm-guard/HOOK.md`
- `.moltis/hooks/telegram-safe-llm-guard/handler.sh`
- `tests/component/test_telegram_safe_llm_guard.sh`
- `tests/static/test_config_validation.sh`
- `scripts/deploy.sh`
- `package.json`
- `package-lock.json`

`docs/GIT-TOPOLOGY-REGISTRY.md` stayed out of scope. No topology publish step was performed.

## Verdict

No runtime-file replay was applied.

Reason: the preserved slice came from a dirty root `main` snapshot captured on 2026-04-02 while that worktree was `ahead 1, behind 42`. The clean rescue branch based on current `origin/main` already contains a broader and newer implementation of the same hook/deploy/test contract. Literal replay of the preserved stage3/staged payloads would downgrade the hook surface, shrink regression coverage, or introduce package-manager noise.

## File Outcomes

| Path | Preserved intent | Outcome | Why |
| --- | --- | --- | --- |
| `.moltis/hooks/telegram-safe-llm-guard/HOOK.md` | Keep a tracked project-local Telegram-safe hook bundle with shell-only runtime requirements | `drop literal replay, keep current origin/main` | Current `origin/main` already ships a richer manifest: it preserves project-hook packaging, keeps shell-only bins, and extends the event set to `BeforeLLMCall`, `AfterLLMCall`, `BeforeToolCall`, and `MessageSending`. Replaying stage3 would remove `BeforeLLMCall` and narrow the contract. |
| `.moltis/hooks/telegram-safe-llm-guard/handler.sh` | Keep a project-local handler for the hook bundle | `drop literal replay, keep current origin/main` | The saved stage3 handler is a smaller standalone awk sanitizer. Current `origin/main` uses a bundle-local wrapper with fallback resolution into the tracked script and supports the wider modern guard behavior exercised by the current component suite. Replaying stage3 would regress the live guard surface. |
| `tests/component/test_telegram_safe_llm_guard.sh` | Cover the project-local hook path rather than only the top-level script path | `drop literal replay, keep current origin/main` | Current `origin/main` already tests both the tracked script and the bundle handler, plus direct-fastpath, persisted-intent, `BeforeToolCall`, `MessageSending`, and observed live-wording regressions. The saved stage3 file is much smaller and would remove critical coverage. |
| `tests/static/test_config_validation.sh` | Assert that the repo ships the project-local hook package and that deploy verifies live registration | `drop literal replay, keep current origin/main` | Current `origin/main` already contains stronger static assertions for the hook bundle, deploy prestaging, runtime hook discovery, and related contracts. The saved stage3 file reverts many later validations and older provider/status assumptions. |
| `scripts/deploy.sh` | Verify that the live runtime sees the project-local telegram-safe hook bundle | `drop staged replay, keep current origin/main` | Current `origin/main` already prestages repo hooks into the runtime data dir and verifies live hook discovery through `verify_moltis_repo_hook_discovery`. The preserved staged hunk is an older, narrower check that shells out to `jq` inside the container and would not improve the current contract. |
| `package.json` | Add top-level dependency `playwright` `^1.58.2` | `drop` | The preservation bundle contains no corresponding runtime/test change that requires a new top-level `playwright` dependency. Current `origin/main` already carries `@playwright/test` in `devDependencies`; adding a second top-level dependency here would be unrelated salvage noise. |
| `package-lock.json` | Preserve npm lockfile generated next to the staged `package.json` edit | `drop` | The repository does not track `package-lock.json`, and the paired `package.json` change is being dropped. Keeping the lockfile would add pure noise. |

## Evidence Used

- Preservation manifest: `artifacts/recovery/root-worktree-main-20260402T130646Z/manifest.yaml`
- Preservation summary: `artifacts/recovery/root-worktree-main-20260402T130646Z/salvage-report.md`
- Staged patch evidence: `artifacts/recovery/root-worktree-main-20260402T130646Z/diffs/staged-package-and-deploy.diff`
- Hook stage diff: `artifacts/recovery/root-worktree-main-20260402T130646Z/diffs/.moltis__hooks__telegram-safe-llm-guard__HOOK.md.stage2-vs-stage3.diff`
- Handler stage diff: `artifacts/recovery/root-worktree-main-20260402T130646Z/diffs/.moltis__hooks__telegram-safe-llm-guard__handler.sh.stage2-vs-stage3.diff`
- Component-test stage diff: `artifacts/recovery/root-worktree-main-20260402T130646Z/diffs/tests__component__test_telegram_safe_llm_guard.sh.stage2-vs-stage3.diff`
- Static-test stage diff: `artifacts/recovery/root-worktree-main-20260402T130646Z/diffs/tests__static__test_config_validation.sh.stage2-vs-stage3.diff`

## Checks

Executed in the clean rescue worktree:

1. `./tests/component/test_telegram_safe_llm_guard.sh`
   Result: pass, `88/88`.
2. `bash -n scripts/deploy.sh`
   Result: pass.
3. `bash ./tests/unit/test_deploy_verify_failure_contract.sh`
   Result: pass, `3/3`.
4. `./tests/static/test_config_validation.sh`
   Result: hook/deploy-related assertions passed, suite overall `139/140`.
   Residual unrelated failure:
   `static_telegram_remote_uat_enforces_status_and_activity_semantics`.

## Final Outcome

- Clean rescue lane created from updated `origin/main`.
- Dirty root `main` was not used as a development base.
- No guard/deploy/test/package replay patch was necessary after reconciliation against current upstream.
- Deliverable for this lane is this salvage report plus the executed verification evidence.
