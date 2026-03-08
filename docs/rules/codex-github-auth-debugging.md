# Rule: Codex GitHub Auth Debugging

When a GitHub operation from Codex fails with auth, SSH, or network symptoms, do not immediately conclude that the user's GitHub setup is broken.

## Required Sequence

1. Record the failing command and whether it ran inside the sandbox or outside it.
2. Inspect sandbox evidence:
   - `env | rg '^(SSH|GIT|GH)_' || true`
   - `ssh-add -l`
   - `ssh -T git@github.com`
   - `gh auth status`
3. Treat sandbox failures as provisional only.
4. Rerun the same checks outside the sandbox before making any host-level conclusion.
5. Only after that, decide whether the issue is:
   - sandbox isolation
   - DNS/network path
   - SSH key selection
   - Keychain/passphrase access
   - real GitHub credential failure

## Interpretation Rules

- No `SSH_AUTH_SOCK` inside sandbox does not prove host SSH is broken.
- Sandbox `gh auth status` failures do not prove the stored host token is invalid.
- If direct `ssh -T git@github.com` succeeds outside the sandbox, the host SSH path is healthy.
- If traced `git push --dry-run` reaches `git-receive-pack`, Git transport auth is healthy.

## Reporting Rule

Before telling the user that GitHub auth is broken, include:

- which context failed
- which context succeeded
- the exact command that proved the final diagnosis

If contexts disagree, report that mismatch explicitly instead of collapsing them into one conclusion.
