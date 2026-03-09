# Contract: Worktree Planning Report

## Canonical Fields

```json
{
  "slug": "remote-uat-hardening",
  "issue_id": null,
  "branch_name": "feat/remote-uat-hardening",
  "path_preview": "../moltinger-remote-uat-hardening",
  "worktree_path": "/absolute/path",
  "decision": "create_clean",
  "topology_state": "ok",
  "question": null,
  "candidates": [],
  "next_steps": [
    "Create a clean worktree on feat/remote-uat-hardening"
  ],
  "warnings": []
}
```

## Field Rules

- `slug`: required normalized or user-supplied slug intent
- `issue_id`: optional
- `branch_name`: required resolved branch proposal
- `path_preview`: required user-facing sibling preview
- `worktree_path`: required absolute target path
- `decision`: required one of:
  - `create_clean`
  - `attach_existing_branch`
  - `reuse_existing`
  - `needs_clarification`
- `topology_state`: required one of:
  - `ok`
  - `stale`
  - `unavailable`
- `question`: required when `decision == needs_clarification`
- `candidates`: ordered list of exact or similar branch/worktree matches
- `next_steps`: ordered list of concrete next actions
- `warnings`: optional ordered list of user-facing caveats

## Behavioral Guarantees

- `create_clean` means no exact or risky similar collision was found in live `git`.
- `attach_existing_branch` means the resolved branch already exists locally and should be attached instead of recreated.
- `reuse_existing` means an existing worktree already owns the resolved branch and should be reused instead of duplicated.
- `needs_clarification` means automatic choice is risky; the workflow must ask at most one short question that includes the clean-new option and the strongest candidate alternatives.
- `topology_state=stale` must not block planning; it means live `git` was used and a registry refresh is still required after mutation.
