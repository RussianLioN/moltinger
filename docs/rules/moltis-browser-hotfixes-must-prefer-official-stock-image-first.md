# Rule: Moltis Browser Hotfixes Must Prefer Official Stock Image First

When fixing a Moltis browser incident on a live Docker-backed host, do not default to a custom browser image if the current official stock image can already pass the same host-level browser job with only profile-dir/storage fixes.

Required decision order:

1. Re-check the official Moltis browser/sandbox baseline first.
2. Prove whether the current stock browser image fails because of:
   - Docker/socket access
   - `container_host`
   - non-writable host-visible browser profile storage
3. If stock `browserless/chrome` succeeds on the same host once the profile bind is writable, keep stock image as the tracked default hotfix path.
4. Only keep or introduce a repo-specific browser image when a separate live or isolated canary proves that the stock image remains insufficient after the writable-profile contract is already fixed.

Interpretation:

- `profile_dir` / mount / permission fixes are first-class incident fixes.
- A custom browser shim is a fallback, not the default, unless current evidence proves it is necessary.
- This keeps the repair closer to the official path and reduces repo-specific blast radius for production hotfixes.
