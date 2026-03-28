# Rule: Moltis non-persistent browser profiles must use a dedicated child directory and single-instance concurrency

## Scope

Applies whenever Moltis runs browser automation in Docker via sibling browser
containers, especially with `browserless/chrome`.

## Rule

If `[tools.browser].persist_profile = false`, then all of the following must hold:

1. `profile_dir` must be a dedicated child path under the mounted browser profile root.
2. `profile_dir` must not be the mount root itself.
3. `max_instances` must be `1`.
4. Deploy must purge and recreate the configured `profile_dir`.
5. Runtime attestation must fail closed when any of the above is false.

## Why

- Chrome protects a user-data-dir with `SingletonLock`.
- A shared multi-instance profile path can deadlock or fail readiness even after the
  Docker socket and host-gateway contract is otherwise correct.
- Official Moltis docs require sibling-container routing in Docker, but they do not
  require a shared persistent browser profile strategy.

## Minimum Verification

- tracked `config/moltis.toml` keeps:
  - `container_host = "host.docker.internal"`
  - `persist_profile = false`
  - `max_instances = 1`
  - a dedicated child `profile_dir`
- `scripts/deploy.sh` purges/recreates the configured `profile_dir`
- `scripts/moltis-runtime-attestation.sh` rejects:
  - root-colliding `profile_dir`
  - non-persistent multi-instance browser configs
  - non-writable browser profile root/dir
- `scripts/moltis-browser-canary.sh` uses a realistic wait budget
