# Consilium Report

## Question

Какой durable fix нужен для production Moltis browser incident, где после уже исправленных
`docker.sock` / `host.docker.internal` / dedicated `profile_dir` браузер всё ещё не
становится ready и в Telegram уходит timeout с browser failure?

## Execution Mode

Mode C: Autonomous Expert Matrix

Причина: в момент анализа лимит параллельных agent threads уже был исчерпан, поэтому
консилиум проведён в sanctioned single-agent evidence-first режиме по локальному
`consilium` skill.

## Evidence

- `origin/main` уже содержит прошлую browser wave (`3ea4c93`), но live runtime всё ещё
  показывает:
  - `sandbox_image = "browserless/chrome"`
  - `profile_dir = "/tmp/moltis-browser-profile/browserless"`
  - `persist_profile = false`
  - `max_instances = 1`
- Live Moltis logs на production повторяют:
  - `probe failed, still retrying ... Connection reset by peer`
  - `browser container failed to become ready within 60s`
- Live transient browser container inspection показывает:
  - image: `browserless/chrome`
  - user: `blessuser`
  - mount:
    `/tmp/moltis-browser-profile/browserless/sandbox/browser-... => /data/browser-profile`
- Live transient container logs показывают:
  - `Failed to create /data/browser-profile/SingletonLock: Permission denied (13)`
  - `Failed to create a ProcessSingleton for your profile directory`
- Live authoritative remote browser canary currently fails on the same production path:
  - first browser tool call times out after `60000ms`
  - retry browser tool call starts with `timeout_ms = 120000`
  - overall run ends with `Agent run timed out after 90s`
- Live host perms для того же session dir:
  - parent sandbox root: `1000:1001`
  - session child dir: `1000:1001`
  - mode: `0755`
- Controlled reproductions:
  - stock `browserless/chrome` without bind mount works;
  - restrictive bind mount reproduces exact failure;
  - `chmod 0777` bind mount works but is not a durable contract;
  - forcing the whole image to `USER 1000` triggered different runtime issues;
  - root wrapper -> `chown 999:999` -> writable HOME -> drop to `999:999` works.
- Official docs checked:
  - Moltis browser automation: Dockerized Moltis must set `tools.browser.container_host`
    and Linux deployments must publish `host.docker.internal:host-gateway`.
  - Moltis sandbox docs: custom sandbox container images are allowed.
  - Browserless/OpenClaw docs: browserless container runtime and user-data-dir remain an
    operator/runtime concern.

## Expert Opinions

### Architect

- Opinion: this is an image/runtime contract gap, not another TOML-only bug.
- Key points:
  - routing baseline was already fixed;
  - profile topology baseline was already improved;
  - remaining failure sits exactly at transient image/user/mount interaction.

### SRE

- Opinion: current repo-side remediation is correct only if it includes exercised live
  proof, not just static guards.
- Key points:
  - attestation must verify image availability;
  - closure requires live browser canary on the authoritative target;
  - Telegram retest comes after browser canary, not before.

### DevOps

- Opinion: fix must stay Git-tracked and deployable from `main`.
- Key points:
  - build the wrapper image inside tracked deploy flow;
  - do not rely on manual host chmod/chown steps;
  - keep rollback easy by only changing `sandbox_image` and tracked scripts.

### Security

- Opinion: long-lived root browser runtime is the wrong fix.
- Key points:
  - short root prelude is acceptable only to normalize mount ownership;
  - the actual browser process must run non-root;
  - host-wide `0777` should stay a diagnostic proof, not the production design.

### QA

- Opinion: static + component checks are necessary but not sufficient.
- Key points:
  - add explicit regression checks for wrapper behavior;
  - do not close the incident until live production canary passes;
  - then re-check Telegram on the same user-facing path.

### Moltis/OpenClaw Domain Specialist

- Opinion: the fix should use official Moltis extensibility, not local hacks.
- Key points:
  - official sandbox docs allow custom container images;
  - that makes a tracked wrapper the most canonical way to patch image-level behavior;
  - user-data-dir ownership is outside what the official docs guarantee automatically.

### Delivery/GitOps

- Opinion: no feature-branch production mutations.
- Key points:
  - finish in a fresh lane from `main`;
  - PR to `main`;
  - canonical deploy from `main`;
  - keep remote smoke/UAT read-only until merge/deploy.

## Root Cause Analysis

- Primary root cause:
  stock `browserless/chrome` runs as `999:999`, but the bind-mounted per-session browser
  profile directories arrive owned by `1000:1001` with `0755`, so Chrome cannot create
  `SingletonLock`.
- Contributing factors:
  - earlier repair wave closed the routing layer but not the transient image/user/mount layer;
  - live runtime still used stock `browserless/chrome`;
  - closure proof stopped too early.
- Confidence: High

## Solution Options

1. **Tracked wrapper image with short root prelude**  
   Pros: Git-tracked, uses official `sandbox_image` extension point, keeps browser non-root during actual runtime.  
   Cons: introduces one custom image artifact to maintain.  
   Risk: low-medium.  
   Effort: medium.

2. **Host-side `chmod 0777` / `chown` only**  
   Pros: fast diagnostic workaround.  
   Cons: drift-prone, unauditable, easy to regress, weak security posture.  
   Risk: high.  
   Effort: low.

3. **Run browserless permanently as root**  
   Pros: likely masks the symptom.  
   Cons: wrong security boundary, larger blast radius, poor long-term posture.  
   Risk: high.  
   Effort: low.

4. **Force the whole browser image to `USER 1000:1001`**  
   Pros: superficially matches host-created dirs.  
   Cons: already reproduced different runtime breakage; drifts from upstream assumptions.  
   Risk: high.  
   Effort: medium.

5. **Remove bind-mounted profile dir entirely**  
   Pros: avoids ownership conflict.  
   Cons: drifts from tracked runtime contract and Moltis sandbox expectations; may remove needed observability/control.  
   Risk: medium-high.  
   Effort: medium.

6. **Patch Moltis upstream to create session dirs as `999:999`**  
   Pros: elegant if upstream accepts it.  
   Cons: slower, external dependency, does not fix production today.  
   Risk: medium.  
   Effort: high.

## Recommended Plan

1. Keep the earlier official browser-in-Docker baseline intact:
   - `container_host`
   - `host-gateway`
   - dedicated `profile_dir`
   - `persist_profile = false`
   - `max_instances = 1`
2. Pin tracked `sandbox_image = "moltis-browserless-chrome:tracked"`.
3. Build that wrapper image during deploy from official `browserless/chrome`.
4. In the wrapper entrypoint:
   - normalize bind-mounted profile ownership to `999:999`
   - create writable non-root `HOME`
   - drop privileges back to `999:999`
   - exec upstream browserless start
5. Fail closed in runtime attestation if the sandbox image is missing.
6. Run live browser canary after deploy.
7. Only after browser canary passes, rerun the Telegram user-facing repro.

## Rollback Plan

- revert `sandbox_image` to the prior tracked value;
- remove the wrapper image build step from tracked deploy flow;
- redeploy from `main`;
- keep earlier routing/profile topology fixes intact.

## Verification Checklist

- [ ] `bash -n scripts/deploy.sh`
- [ ] `bash -n scripts/moltis-runtime-attestation.sh`
- [ ] `sh -n scripts/moltis-browser-sandbox/entrypoint.sh`
- [ ] `bash tests/static/test_config_validation.sh`
- [ ] `bash tests/unit/test_deploy_workflow_guards.sh`
- [ ] `bash tests/component/test_moltis_runtime_attestation.sh`
- [ ] `bash tests/component/test_moltis_browser_canary.sh`
- [ ] live runtime shows `sandbox_image = "moltis-browserless-chrome:tracked"`
- [ ] live browser canary passes
- [ ] Telegram repro no longer emits browser permission/timeout failure
