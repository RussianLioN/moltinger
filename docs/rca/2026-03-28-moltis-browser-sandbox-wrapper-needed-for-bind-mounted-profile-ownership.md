# RCA: Moltis browser still timed out because the sibling browser sandbox mounted a host-owned profile directory that its non-root runtime could not lock

Date: 2026-03-28
Severity: high
Scope: production Moltis browser automation, Telegram user chat, Tavily-assisted flows, Docker sibling browser sandboxes
Status: fixed in git, pending canonical merge and deploy from `main`

## Summary

After the earlier browser fixes were already in `main` and production had:

- `profile_dir = "/tmp/moltis-browser-profile/browserless"`
- `persist_profile = false`
- `max_instances = 1`
- `container_host = "host.docker.internal"`

browser requests still timed out in Telegram with readiness-loop symptoms:

- `probe failed, still retrying ... Connection reset by peer`
- `browser container failed to become ready within 60s`
- `browser launch failed ...`

The decisive live capture showed that the transient sibling browser container still ran
the stock `browserless/chrome` image as `blessuser` (`uid=999 gid=999`) while mounting a
per-session host directory owned by `1000:1001` with mode `0755`. Chrome inside that
container then failed on:

- `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`
- `Failed to create a ProcessSingleton for your profile directory`

Primary root cause: the tracked browser contract had fixed routing and profile topology,
but had not yet normalized ownership of the bind-mounted per-session browser profile for
the actual non-root browserless runtime user.

## Official-first interpretation

The official Moltis docs were necessary, but not sufficient on their own:

- Browser automation docs require Dockerized Moltis to set `tools.browser.container_host`
  and, on Linux, map `host.docker.internal:host-gateway`.
- Sandbox docs explicitly allow a custom sandbox container image.

What the official docs did **not** specify was a safe ownership strategy for a
bind-mounted Chrome user-data-dir when the sandbox container runs non-root. That gap had
to be closed with live evidence against the real `browserless/chrome` runtime.

Secondary evidence used only after the official baseline:

- official Browserless OpenClaw guidance explains using browserless as the automation
  backend and controlling its runtime via container configuration;
- Browser/Chrome community reports around `SingletonLock` confirm that a non-writable
  user-data-dir fails exactly this way.

## Evidence

- Live production runtime still showed:
  - `sandbox_image = "browserless/chrome"`
  - not the tracked wrapper image.
- Live Moltis logs repeatedly showed:
  - `probe failed, still retrying ... Connection reset by peer (os error 104)`
  - `browser container failed to become ready within 60s`
- Live remote inspection of the transient container showed:
  - image: `browserless/chrome`
  - user: `blessuser`
  - mount:
    `/tmp/moltis-browser-profile/browserless/sandbox/browser-... => /data/browser-profile`
- Live remote container logs showed:
  - `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`
  - `Failed to create a ProcessSingleton for your profile directory`
- Live authoritative remote browser canary on `/opt/moltinger` failed the user-facing path:
  - first browser tool call timed out after `60000ms`
  - retry browser tool call started with `timeout_ms = 120000`
  - overall run then ended with `Agent run timed out after 90s`
- Live host permissions for that same session directory were:
  - parent sandbox root owned by `1000:1001`
  - session child dir owned by `1000:1001`
  - mode `drwxr-xr-x`
- Controlled host reproductions proved:
  - plain `browserless/chrome` without the bind mount starts normally;
  - restrictive bind mount reproduces the exact `SingletonLock` failure;
  - world-writable bind mount works;
  - forcing the whole container to `USER 1000` introduced different runtime issues;
  - root entrypoint -> `chown 999:999` -> writable HOME -> drop back to `999:999`
    works.

## 5 Whys

### 1. Why did browser requests still time out after the earlier fixes?

Because the sibling browser container still never became ready.

### 2. Why did the sibling browser container never become ready?

Because Chrome inside the stock `browserless/chrome` container could not create
`SingletonLock` inside its bind-mounted user-data-dir.

### 3. Why could Chrome not create `SingletonLock`?

Because the bind-mounted per-session host directory was owned by `1000:1001` with mode
`0755`, while the browserless runtime user was `999:999`.

### 4. Why was that mismatch not already guarded?

Because the earlier repair wave stopped at browser topology and profile layout:
`docker.sock`, `host.docker.internal`, dedicated child `profile_dir`, and
`max_instances = 1`. It did not yet prove the transient per-session directory ownership
contract of the actual browser image.

### 5. Why did this reach Telegram again?

Because closure criteria still treated “browser socket/gateway fixed” as almost enough,
instead of requiring exercised proof that the transient sandbox image can actually write
the mounted profile path as its real runtime user.

## Root Cause

Primary root cause:

- stock `browserless/chrome` ran non-root, but the bind-mounted per-session browser
  profile directories created by the surrounding runtime were not owned or writable for
  that non-root user.

Contributing root causes:

- the tracked sandbox image stayed on stock `browserless/chrome` after the first wave;
- deploy/runtime attestation had not yet encoded an image-level ownership-normalization
  contract;
- initial browser closure criteria were too coarse and stopped before transient
  container writeability was proven end-to-end.

## Fix

1. Keep the earlier official browser-in-Docker baseline:
   - `container_host = "host.docker.internal"`
   - `host.docker.internal:host-gateway`
   - dedicated child `profile_dir`
   - `persist_profile = false`
   - `max_instances = 1`
2. Introduce a tracked wrapper image:
   - `sandbox_image = "moltis-browserless-chrome:tracked"`
3. Build it from official `browserless/chrome`, but start with a short root entrypoint
   that:
   - `chown -R 999:999 "$profile_dir"`
   - creates a writable non-root `HOME`
   - drops privileges back to `uid=999 gid=999`
   - then execs the upstream browserless start path
4. Make deploy build that tracked wrapper image before rollout.
5. Make runtime attestation fail closed if the sandbox image is missing from the host.

## Verification

- `bash -n scripts/deploy.sh`
- `bash -n scripts/moltis-runtime-attestation.sh`
- `sh -n scripts/moltis-browser-sandbox/entrypoint.sh`
- `bash tests/static/test_config_validation.sh`
- `bash tests/unit/test_deploy_workflow_guards.sh`
- `bash tests/component/test_moltis_runtime_attestation.sh`
- `bash tests/component/test_moltis_browser_canary.sh`
- live production evidence before fix:
  - runtime config still on `sandbox_image = "browserless/chrome"`
  - transient container logs show `SingletonLock: Permission denied`

## Prevention

- Treat browser sandbox image behavior as part of the runtime contract, not just the
  TOML browser section.
- When sandbox containers bind-mount a Chrome user-data-dir, prove ownership and write
  semantics against the actual runtime UID/GID.
- Do not “solve” this class of problem by leaving the browser container running as root
  or by relying on ad-hoc `chmod 0777` fixes on the host.
- Do not call a browser incident closed until:
  - topology/routing are correct;
  - profile topology is correct;
  - sandbox image ownership normalization is correct;
  - live browser canary succeeds on the authoritative target.
