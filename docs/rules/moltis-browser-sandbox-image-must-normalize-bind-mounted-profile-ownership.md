# Rule: Moltis browser sandbox images must normalize bind-mounted profile ownership before Chrome starts

## Scope

Applies when Moltis launches sibling browser containers in Docker and those containers
bind-mount a browser profile path such as `/data/browser-profile`.

## Rule

If the browser sandbox image runs Chrome as a non-root user and receives a bind-mounted
profile directory, then all of the following must hold:

1. The tracked browser `sandbox_image` must be explicit.
2. The image may start as root only long enough to normalize the bind-mounted profile
   directory and create a writable non-root `HOME`.
3. The entrypoint must drop privileges back to the intended browser runtime user before
   starting Chrome.
4. Deploy must build or fetch that exact tracked image before Moltis rollout.
5. Runtime attestation must fail closed if the tracked browser sandbox image is missing.

## Why

- Official Moltis browser/sandbox docs cover sibling-container routing and allow custom
  sandbox images, but they do not guarantee that a bind-mounted Chrome profile path will
  already be owned by the browser image's runtime UID/GID.
- Chrome protects its user-data-dir via `SingletonLock`.
- A non-writable bind-mounted user-data-dir fails before the browser becomes ready,
  typically as a readiness loop plus `SingletonLock` / `ProcessSingleton` errors.

## Required Behavior

- Keep the browser image non-root during actual browser execution.
- Do not rely on host-only `chmod 0777` as the durable fix.
- Do not swap the whole browser image to a different long-lived UID/GID unless the
  upstream runtime is explicitly validated for that path.
- Prefer a tracked wrapper built from the official upstream image.

## Minimum Verification

- tracked `config/moltis.toml` pins the intended `sandbox_image`
- tracked wrapper image exists in git
- wrapper entrypoint:
  - normalizes the mounted profile dir ownership
  - creates a writable non-root `HOME`
  - drops privileges before starting browserless
- deploy builds the tracked wrapper image before Moltis comes up
- runtime attestation rejects a missing browser sandbox image
- live browser canary succeeds on the authoritative target
