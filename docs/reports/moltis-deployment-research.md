# Moltis Deep Documentation Research Report

**Research Date**: 2026-02-14
**Researcher**: Research Specialist
**Source**: https://docs.moltis.org/
**Purpose**: Expand specification for Docker deployment on ainetic.tech

---

## Executive Summary

This report provides comprehensive technical findings from the official Moltis documentation to support the deployment specification. Key findings include:

- **Complete environment variable reference** with cloud-specific considerations
- **Docker socket security implications** - equivalent to root access on host
- **Detailed authentication architecture** with three-tier model and local connection detection
- **Sandbox execution requirements** - Docker socket mount is critical for command isolation
- **Comprehensive configuration options** covering gateway, providers, sandbox, memory, hooks, TLS, and telemetry
- **Health monitoring capabilities** via `/health` endpoint and OpenTelemetry integration
- **Rate limiting details** with per-endpoint limits and throttling behavior

---

## 1. Docker Deployment

### 1.1 Container Image

**Repository**: `ghcr.io/moltis-org/moltis:latest`

**Multi-architecture Support**:
- `linux/amd64`
- `linux/arm64`

**Image Published**: GitHub Container Registry on every release

### 1.2 Quick Start Command

```bash
docker run -d \
--name moltis \
-p 13131:13131 \
-p 13132:13132 \
-v moltis-config:/home/moltis/.config/moltis \
-v moltis-data:/home/moltis/.moltis \
-v /var/run/docker.sock:/var/run/docker.sock \
ghcr.io/moltis-org/moltis:latest
```

**Port Explanation**:
- **13131**: Main gateway port (HTTP/WebSocket)
- **13132**: HTTP redirect port / CA certificate download server (defaults to gateway port + 1)

### 1.3 Volume Mounts

| Path | Contents | Purpose |
| --- | --- | --- |
| `/home/moltis/.config/moltis` | Configuration files: `moltis.toml`, `credentials.json`, `mcp-servers.json` | Persistent configuration storage |
| `/home/moltis/.moltis` | Runtime data: databases, sessions, memory files, logs | Persistent data storage |

**Volume Type Options**:

1. **Named Volumes** (as shown above):
   - Docker manages storage location
   - Good for production deployments
   - Less direct file access

2. **Bind Mounts**:
   ```bash
   docker run -d \
   --name moltis \
   -p 13131:13131 \
   -p 13132:13132 \
   -v ./config:/home/moltis/.config/moltis \
   -v ./data:/home/moltis/.moltis \
   -v /var/run/docker.sock:/var/run/docker.sock \
   ghcr.io/moltis-org/moltis:latest
   ```
   - Direct file access on host
   - Can edit `config/moltis.toml` directly
   - Better for development/testing

**Permission Requirements**:
```bash
# Create directories with proper permissions
mkdir -p ./config ./data
chmod 755 ./config ./data

# Container runs as user moltis (UID 1000)
sudo chown -R 1000:1000 ./config ./data
```

### 1.4 Docker Socket Mount (Critical for Sandbox)

**Mount Command**: `-v /var/run/docker.sock:/var/run/docker.sock`

**Purpose**: Required for sandboxed command execution

**Without socket mount**:
- Sandbox execution is **disabled**
- Agent works for chat-only interactions
- Any tool requiring shell commands **fails**

**SECURITY WARNING** (Critical):
> Mounting the Docker socket gives the container full access to the Docker daemon. This is equivalent to **root access on the host** for practical purposes. **Only run Moltis containers from trusted sources** (official images from `ghcr.io/moltis-org/moltis`).

**If socket cannot be mounted**:
- Moltis runs in "no sandbox" mode
- Commands execute directly inside Moltis container
- **No isolation** provided

### 1.5 Docker Compose Configuration

```yaml
services:
  moltis:
    image: ghcr.io/moltis-org/moltis:latest
    container_name: moltis
    restart: unless-stopped
    ports:
      - "13131:13131"
      - "13132:13132"
    volumes:
      - ./config:/home/moltis/.config/moltis
      - ./data:/home/moltis/.moltis
      - /var/run/docker.sock:/var/run/docker.sock
```

**Start with**:
```bash
docker compose up -d
docker compose logs -f moltis  # Watch for startup messages
```

### 1.6 Environment Variables

| Variable | Description | Default |
| --- | --- | --- |
| `MOLTIS_CONFIG_DIR` | Override config directory | `~/.config/moltis` |
| `MOLTIS_DATA_DIR` | Override data directory | `~/.moltis` |
| `MOLTIS_PORT` | Gateway port | 13131 |
| `MOLTIS_HOST` | Listen address | `0.0.0.0` |
| `MOLTIS_NO_TLS` | Disable TLS | (not set) |
| `MOLTIS_BEHIND_PROXY` | Force remote connection treatment | (not set) |
| `MOLTIS_DEPLOY_PLATFORM` | Cloud platform identifier | (not set) |
| `MOLTIS_PASSWORD` | Pre-set initial password | (not set) |
| `MOLTIS_TLS__HTTP_REDIRECT_PORT` | Port for HTTP redirect server | gateway_port + 1 |

**Example with custom directories**:
```bash
docker run -d \
--name moltis \
-p 13131:13131 \
-p 13132:13132 \
-e MOLTIS_CONFIG_DIR=/config \
-e MOLTIS_DATA_DIR=/data \
-v ./config:/config \
-v ./data:/data \
-v /var/run/docker.sock:/var/run/docker.sock \
ghcr.io/moltis-org/moltis:latest
```

### 1.7 TLS Certificate Trust

Moltis generates a **self-signed CA** on first run. Browsers show security warning until CA is trusted.

**Download CA certificate** (port 13132 serves certificate over plain HTTP):
```bash
curl -o moltis-ca.pem http://localhost:13132/certs/ca.pem
```

**Trust CA on macOS**:
```bash
sudo security add-trusted-cert -d -r trustRoot \
-k /Library/Keychains/System.keychain moltis-ca.pem
```

**Trust CA on Linux (Debian/Ubuntu)**:
```bash
sudo cp moltis-ca.pem /usr/local/share/ca-certificates/moltis-ca.crt
sudo update-ca-certificates
```

**Note**: After trusting CA, restart browser. Warning will not appear again (CA persists in mounted config volume).

---

## 2. Configuration (moltis.toml)

### 2.1 Configuration File Location

| Platform | Default Path | Override Method |
| --- | --- | --- |
| macOS/Linux | `~/.config/moltis/moltis.toml` | `--config-dir` flag or `MOLTIS_CONFIG_DIR` |

**Generation**: On first run, complete configuration file is generated with sensible defaults.

### 2.2 Basic Settings

```toml
[gateway]
port = 13131              # HTTP/WebSocket port
host = "0.0.0.0"           # Listen address

[agent]
name = "Moltis"             # Agent display name
model = "gpt-5.4"     # Default model
timeout = 600               # Agent run timeout (seconds)
max_iterations = 25          # Max tool call iterations per run
```

### 2.3 LLM Providers

**Security Note**: Provider API keys are stored separately in `~/.config/moltis/provider_keys.json` for security. Configure through web UI or directly in JSON file.

```toml
[providers]
default = "openai"     # Default provider

[providers.openai]
enabled = true

[providers.github-copilot]
enabled = true

[providers.local]
enabled = true
model = "qwen2.5-coder-7b-q4_k_m"
```

**Available Providers**:
- **OpenAI** - API-based, frontier GPT models
- **GitHub Copilot** - OAuth-based, requires active Copilot subscription
- **Local LLM** - Runs models on your machine

### 2.4 Sandbox Configuration

Commands run inside isolated containers for security:

```toml
[tools.exec.sandbox]
enabled = true
backend = "docker"             # "docker" or "apple" (macOS 15+)
base_image = "ubuntu:25.10"
# Packages installed in the sandbox image
packages = [
  "curl",
  "git",
  "jq",
  "python3",
  "python3-pip",
  "nodejs",
  "npm",
]
```

**Important**: When packages list is modified and Moltis restarted, it automatically rebuilds sandbox image with new tag.

**Backend Selection**:
```toml
[tools.exec.sandbox]
backend = "auto"                # default — picks best available
# backend = "docker"             # force Docker
# backend = "apple-container"     # force Apple Container (macOS only)
```

**Backend Priority (auto mode)**:
| Priority | Backend | Platform | Isolation |
| --- | --- | --- | --- |
| 1 | Apple Container | macOS | VM (Virtualization.framework) |
| 2 | Docker | any | Linux namespaces / cgroups |
| 3 | none (host) | any | no isolation |

**Resource Limits**:
```toml
[tools.exec.sandbox.resource_limits]
memory_limit = "512M"
cpu_quota = 1.0
pids_max = 256
```

### 2.5 Memory System

Long-term memory uses embeddings for semantic search:

```toml
[memory]
enabled = true
embedding_model = "text-embedding-3-small"  # OpenAI embedding model
chunk_size = 512                            # Characters per chunk
chunk_overlap = 50                           # Overlap between chunks
# Directories to watch for memory files
watch_dirs = [
  "~/.moltis/memory",
]
```

### 2.6 Authentication

**Authentication is ONLY required when accessing Moltis from a non-localhost address**. When running on `localhost` or `127.0.0.1`, no authentication is needed by default.

When accessing from network address (e.g., `http://192.168.1.100:13131`), a **one-time setup code** is printed to terminal.

```toml
[auth]
disabled = false          # Set true to disable auth entirely
# Session settings
session_expiry = 604800   # Session lifetime in seconds (7 days)
```

**WARNING**: Only set `disabled = true` if Moltis is running on a trusted private network. **Never expose an unauthenticated instance to internet.**

### 2.7 Hooks

Configure lifecycle hooks:

```toml
[[hooks]]
name = "my-hook"
command = "./hooks/my-hook.sh"
events = ["BeforeToolCall", "AfterToolCall"]
timeout = 5                   # Timeout in seconds

[hooks.env]
MY_VAR = "value"             # Environment variables for the hook
```

### 2.8 MCP Servers

Connect to Model Context Protocol servers:

```toml
[[mcp.servers]]
name = "filesystem"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed"]

[[mcp.servers]]
name = "github"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-github"]
env = { GITHUB_TOKEN = "ghp_..." }
```

### 2.9 Telegram Integration

```toml
[telegram]
enabled = true
# Token is stored in provider_keys.json, not here
allowed_users = [123456789]  # Telegram user IDs allowed to chat
```

### 2.10 TLS / HTTPS

```toml
[tls]
enabled = true
cert_path = "~/.config/moltis/cert.pem"
key_path = "~/.config/moltis/key.pem"
# If paths don't exist, a self-signed certificate is generated
# Port for the plain-HTTP redirect / CA-download server
# Defaults to the gateway port + 1 when not set
# http_redirect_port = 13132
```

**Override via environment variable**: `MOLTIS_TLS__HTTP_REDIRECT_PORT=8080`

### 2.11 Tailscale Integration

Expose Moltis over your Tailscale network:

```toml
[tailscale]
enabled = true
mode = "serve"          # "serve" (private) or "funnel" (public)
```

### 2.12 Observability

```toml
[telemetry]
enabled = true
otlp_endpoint = "http://localhost:4317"  # OpenTelemetry collector
```

### 2.13 Complete Example

```toml
[gateway]
port = 13131
host = "0.0.0.0"

[agent]
name = "Atlas"
model = "gpt-5.4"
timeout = 600
max_iterations = 25

[providers]
default = "openai"

[tools.exec.sandbox]
enabled = true
backend = "docker"
base_image = "ubuntu:25.10"
packages = ["curl", "git", "jq", "python3", "nodejs"]

[memory]
enabled = true

[auth]
disabled = false

[[hooks]]
name = "audit-log"
command = "./hooks/audit.sh"
events = ["BeforeToolCall"]
timeout = 5
```

---

## 3. Reverse Proxy Setup

### 3.1 TLS Termination

**Cloud deployments**: All cloud providers terminate TLS at the edge, so Moltis must run in plain HTTP mode.

**Common configuration**:
| Setting | Value | Purpose |
| --- | --- | --- |
| `--no-tls` or `MOLTIS_NO_TLS=true` | Disable TLS | Provider handles HTTPS |
| `--bind 0.0.0.0` | Bind all interfaces | Required for container networking |
| `--port <port>` | Listen port | Must match provider's expected internal port |

### 3.2 MOLTIS_BEHIND_PROXY Environment Variable

**Purpose**: Force all connections to be treated as remote (for authentication and throttling)

**When to use**:
- Bare proxies (no forwarding headers) that can appear local
- All cloud deployments
- Any reverse proxy deployment

**Effect on local connection detection**:
A connection is classified as **local** ONLY when **ALL FOUR** checks pass:
1. `MOLTIS_BEHIND_PROXY` env var is **NOT** set
2. No proxy headers present (`X-Forwarded-For`, `X-Real-IP`, `CF-Connecting-IP`, `Forwarded`)
3. The `Host` header resolves to a loopback address (or is absent)
4. The TCP source IP is loopback (`127.0.0.1`, `::1`)

**If ANY check fails**, connection is treated as remote.

### 3.3 Proxy Header Requirements

**Required headers**:
- `Origin` - for WebSocket CWSH protection
- `Host` - for WebSocket CWSH protection
- `X-Forwarded-For` or equivalent - for correct client IP detection

**Throttling behavior with proxy**:
When `MOLTIS_BEHIND_PROXY=true`, throttling is keyed by **forwarded client IP headers** (`X-Forwarded-For`, `X-Real-IP`, `CF-Connecting-IP`) instead of direct socket address.

### 3.4 Nginx Configuration Example

```nginx
server {
    listen 443 ssl http2;
    server_name ainetic.tech;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # WebSocket upgrade headers
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    # Forward real client IP
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP $remote_addr;

    # Required headers
    proxy_set_header Host $host;
    proxy_set_header Origin $http_origin;

    location / {
        proxy_pass http://localhost:13131;
    }
}
```

### 3.5 Caddy Configuration Example

```
ainetic.tech {
    reverse_proxy localhost:13131 {
        header_up Host {host}
        header_up Origin {headerOrigin}
        header_up X-Forwarded-For {remote_host}
        header_up X-Real-IP {remote_host}
    }
}
```

---

## 4. Authentication

### 4.1 Authentication Architecture

All HTTP requests pass through a single `auth_gate` middleware before reaching any handler. The middleware calls `check_auth()` — the **ONLY** function in the codebase that decides whether a request is authenticated. This eliminates a class of bugs where different code paths disagree on auth status.

**Request Flow**:
```
Request
    |
    v
auth_gate middleware
    |
    |-- Public path? (/health, /assets/*, /api/auth/*, ...) -> pass through
    |
    |-- No credential store? -> pass through
    |
    `-- check_auth()
        |
        |-- Allowed -> insert AuthIdentity into request, continue
        |-- SetupRequired -> 401 (API/WS) or redirect to /onboarding (pages)
        `-- Unauthorized -> 401 (API/WS) or serve SPA login page (pages)
```

**WebSocket connections** also use `check_auth()` for the HTTP upgrade handshake. After upgrade, the WS protocol has its own param-based auth (API key or password in the `connect` message) for clients that cannot set HTTP headers.

### 4.2 Decision Matrix

`check_auth()` evaluates conditions in order and returns the first match:

| # | Condition | Result | Auth method |
| --- | --- | --- | --- |
| 1 | `auth_disabled` is true | **Allowed** | Loopback |
| 2 | Setup not complete + local connection | **Allowed** | Loopback |
| 3 | Setup not complete + remote connection | **SetupRequired** | — |
| 4 | Valid session cookie | **Allowed** | Password |
| 5 | Valid Bearer API key | **Allowed** | ApiKey |
| 6 | None of the above | **Unauthorized** | — |

**"Setup complete"**: When at least one credential (password or passkey) has been registered. The `setup_complete` flag is recomputed whenever credentials are added or removed.

### 4.3 Three-Tier Authentication Model

| Tier | Condition | Behaviour |
| --- | --- | --- |
| **1 — Full auth** | Password or passkey is configured | Auth **ALWAYS** required (any IP) |
| **2 — Local dev** | No credentials + direct local connection | Full access (dev convenience) |
| **3 — Remote setup** | No credentials + remote/proxied connection | Setup flow only |

**Practical Scenarios**:

| Scenario | No credentials | Credentials configured |
| --- | --- | --- |
| Local browser on `localhost:13131` | Full access (Tier 2) | Login required (Tier 1) |
| Local CLI/wscat on `localhost:13131` | Full access (Tier 2) | Login required (Tier 1) |
| Internet via reverse proxy | Onboarding only (Tier 3) | Login required (Tier 1) |
| `MOLTIS_BEHIND_PROXY=true`, any source | Onboarding only (Tier 3) | Login required (Tier 1) |

### 4.4 Credential Types

### Password
- Set during initial setup or added later via Settings
- Hashed with **Argon2id** before storage
- Minimum 8 characters
- Verified against `auth_password` table

### Passkey (WebAuthn)
- Registered during setup or added later via Settings
- Supports hardware keys (YubiKey), platform authenticators (Touch ID, Windows Hello), and cross-platform authenticators
- Stored in `passkeys` table as serialized WebAuthn credential data
- Multiple passkeys can be registered per instance

### Session Cookie
- HTTP-only `moltis_session` cookie, `SameSite=Strict`
- Created on successful login (password or passkey)
- **30-day expiry**
- Validated against `auth_sessions` table
- When request arrives on a `.localhost` subdomain (e.g., `moltis.localhost`), cookie includes `Domain=localhost` so it is shared across all loopback hostnames

### API Key
- Created in Settings > Security > API Keys
- Prefixed with `mk_` for identification
- Stored as **SHA-256 hash** (the raw key is shown once at creation)
- Passed via `Authorization: Bearer` header (HTTP) or in the `connect` handshake `auth.api_key` field (WebSocket)
- **MUST have at least one scope** — keys without scopes are denied

**API Key Scopes**:

| Scope | Permissions |
| --- | --- |
| `operator.read` | View status, list jobs, read history |
| `operator.write` | Send messages, create jobs, modify configuration |
| `operator.admin` | All permissions (superset of all scopes) |
| `operator.approvals` | Handle command approval requests |
| `operator.pairing` | Manage device/node pairing |

**TIP**: Use the minimum necessary scopes. A monitoring integration only needs `operator.read`. A CI pipeline that triggers agent runs needs `operator.read` and `operator.write`.

### 4.5 Public Paths

These paths are accessible without authentication, even when credentials are configured:

| Path | Purpose |
| --- | --- |
| `/health` | Health check endpoint |
| `/api/auth/*` | Auth status, login, setup, passkey flows |
| `/assets/*` | Static assets (JS, CSS, images) |
| `/auth/callback` | OAuth callback |
| `/manifest.json` | PWA manifest |
| `/sw.js` | Service worker |

### 4.6 Request Throttling (Rate Limiting)

Moltis applies built-in endpoint throttling **per client IP** only when auth is required for the current request.

**Requests bypass IP throttling when**:
- The request is already authenticated (session or API key)
- Auth is not currently enforced (`auth_disabled = true`)
- Setup is incomplete and the request is allowed by local Tier-2 access

**Default Limits**:

| Scope | Default |
| --- | --- |
| `POST /api/auth/login` | **5 requests per 60 seconds** |
| Other `/api/auth/*` | **120 requests per 60 seconds** |
| Other `/api/*` | **180 requests per 60 seconds** |
| `/ws` upgrade | **30 requests per 60 seconds** |

**When limit exceeded**:
- API endpoints return `429 Too Many Requests`
- Responses include `Retry-After` header
- JSON API responses also include `retry_after_seconds`

**NOTE**: When `MOLTIS_BEHIND_PROXY=true`, throttling is keyed by forwarded client IP headers (`X-Forwarded-For`, `X-Real-IP`, `CF-Connecting-IP`) instead of direct socket address.

### 4.7 Setup Flow

On first run (no credentials configured):
1. A random **6-digit setup code** is printed to terminal
2. Local connections get full access (Tier 2) — no setup code needed
3. Remote connections are redirected to `/onboarding` (Tier 3) — setup code is required to set a password or register a passkey
4. After setting up, setup code is cleared and a session is created

**WARNING**: The setup code is **single-use** and only valid until first credential is registered. If you lose it, restart server to generate a new one.

### 4.8 MOLTIS_PASSWORD Environment Variable

**Purpose**: Pre-set authentication password via environment variable

**Usage**:
```bash
docker run -d \
--name moltis \
-e MOLTIS_PASSWORD="your-secure-password" \
...
ghcr.io/moltis-org/moltis:latest
```

**Effect**: Pre-configures password so setup code flow is skipped. This is the easiest approach for cloud deployments.

**Alternative**: Set via cloud provider secrets management (e.g., Fly.io: `fly secrets set MOLTIS_PASSWORD="your-password"`)

### 4.9 Removing Authentication

The "Remove all auth" action in Settings:
1. Deletes all passwords, passkeys, sessions, and API keys
2. Sets `auth_disabled = true` in config
3. Generates a new setup code for re-setup
4. All subsequent requests are allowed through (Tier 1 check: `auth_disabled`)

To re-enable auth, complete setup flow again with the new setup code.

### 4.10 WebSocket Authentication

WebSocket connections are authenticated at two levels:

**1. HTTP upgrade (header auth)**
The WebSocket upgrade request passes through `check_auth()` like any other HTTP request. If browser has a valid session cookie, connection is pre-authenticated.

**2. Connect message (param auth)**
After WebSocket is established, client sends a `connect` message. Non-browser clients (CLI tools, scripts) that cannot set HTTP headers authenticate here:
```json
{
  "method": "connect",
  "params": {
    "client": { "id": "my-tool", "version": "1.0.0" },
    "auth": {
      "api_key": "mk_abc123..."
    }
  }
}
```

The `auth` object can contain `api_key` or `password`. If neither is provided and connection was not pre-authenticated via headers, connection is rejected.

### 4.11 Session Management API

| Operation | Endpoint | Auth required |
| --- | --- | --- |
| Check status | `GET /api/auth/status` | No |
| Set password (setup) | `POST /api/auth/setup` | Setup code |
| Login with password | `POST /api/auth/login` | No (validates password) |
| Login with passkey | `POST /api/auth/passkey/auth/*` | No (validates passkey) |
| Logout | `POST /api/auth/logout` | Session |
| Change password | `POST /api/auth/password/change` | Session |
| List API keys | `GET /api/auth/api-keys` | Session |
| Create API key | `POST /api/auth/api-keys` | Session |
| Revoke API key | `DELETE /api/auth/api-keys/{id}` | Session |
| Register passkey | `POST /api/auth/passkey/register/*` | Session |
| Remove passkey | `DELETE /api/auth/passkeys/{id}` | Session |
| Remove all auth | `POST /api/auth/reset` | Session |

---

## 5. Sandboxed Execution

### 5.1 Sandbox Backends

Moltis runs LLM-generated commands inside containers to protect host system. The sandbox backend controls which container technology is used.

**Backend Selection** (configure in `moltis.toml`):
```toml
[tools.exec.sandbox]
backend = "auto"                # default — picks best available
# backend = "docker"             # force Docker
# backend = "apple-container"     # force Apple Container (macOS only)
```

**Backend Priority (auto mode)**:
| Priority | Backend | Platform | Isolation |
| --- | --- | --- | --- |
| 1 | Apple Container | macOS | VM (Virtualization.framework) |
| 2 | Docker | any | Linux namespaces / cgroups |
| 3 | none (host) | any | no isolation |

### 5.2 Apple Container (recommended on macOS)

Apple Container runs each sandbox in a **lightweight virtual machine** using Apple's Virtualization.framework. Every container gets its own kernel, so a kernel exploit inside the sandbox **cannot reach the host** — unlike Docker, which shares the host kernel.

**Install**:
```bash
# Download installer package
gh release download --repo apple/container --pattern "container-installer-signed.pkg" --dir /tmp

# Install (requires admin)
sudo installer -pkg /tmp/container-installer-signed.pkg -target /

# First-time setup — downloads a default Linux kernel
container system start
```

**Verify**:
```bash
container --version

# Run a quick test
container run --rm ubuntu echo "hello from VM"
```

Once installed, restart `moltis gateway` — startup banner will show `sandbox: apple-container backend`.

### 5.3 Docker

Docker is supported on macOS, Linux, and Windows. On macOS it runs inside a Linux VM managed by Docker Desktop, so it is reasonably isolated but adds more overhead than Apple Container.

**Install from**: https://docs.docker.com/get-docker/

### 5.4 No Sandbox

If neither runtime is found, commands execute directly on the host. The startup banner will show a warning. This is **NOT recommended** for untrusted workloads.

### 5.5 Cloud Deployment Limitation

**WARNING**: Most cloud providers do not support Docker-in-Docker. The sandboxed command execution feature (where LLM runs shell commands inside isolated containers) **will not work** on these platforms.

The agent will still function for:
- Chat
- Tool calls that don't require shell execution
- MCP server connections

**Providers affected**: Fly.io, DigitalOcean App Platform, Render (and similar)

**Workaround**: Use a VPS/Droplet with Docker instead of app platform.

### 5.6 Resource Limits

```toml
[tools.exec.sandbox.resource_limits]
memory_limit = "512M"
cpu_quota = 1.0
pids_max = 256
```

### 5.7 Per-Session Overrides

The web UI allows toggling sandboxing per session and selecting a custom container image. These overrides persist across gateway restarts.

---

## 6. Health Monitoring

### 6.1 Health Check Endpoint

**Path**: `/health`
**Method**: `GET`
**Expected Status**: `200`

**Purpose**: Gateway readiness check

**Usage**:
```bash
curl http://localhost:13131/health
# Expected: HTTP 200
```

**Docker Healthcheck Integration**:
Configure Docker healthcheck to use `/health` endpoint. When container is unhealthy, Docker marks container as unhealthy.

**Cloud Provider Health Checks**:
All provider configs use `/health` endpoint which returns HTTP 200 when gateway is ready. Configure provider's health check:
- **Path**: `/health`
- **Method**: `GET`
- **Expected status**: `200`

### 6.2 Metrics & Observability

Moltis supports OpenTelemetry for metrics and tracing:

```toml
[telemetry]
enabled = true
otlp_endpoint = "http://localhost:4317"  # OpenTelemetry collector
```

**Configuration**:
- Enable in `moltis.toml` under `[telemetry]`
- Set OTLP endpoint to OpenTelemetry collector
- Collector must be running and accessible

**Note**: At time of research, specific metrics and spans documentation was not available in the public docs.

---

## 7. Recommendations for Specification Enhancement

### 7.1 Critical Security Considerations (MUST ADD)

1. **Docker Socket Mount Warning**:
   - Add explicit security warning about Docker socket mount
   - Document that it's equivalent to root access on host
   - Recommend only using official images from `ghcr.io/moltis-org/moltis`

2. **Authentication Configuration**:
   - Document `MOLTIS_PASSWORD` for cloud deployments
   - Add three-tier authentication model explanation
   - Include local connection detection logic

3. **MOLTIS_BEHIND_PROXY Configuration**:
   - Add to all reverse proxy scenarios
   - Explain effect on authentication and throttling
   - Document proxy header requirements

### 7.2 Missing from Current Spec

1. **Complete Environment Variables Table**:
   - Add all documented variables with descriptions
   - Include cloud-specific variables (`MOLTIS_DEPLOY_PLATFORM`)

2. **Detailed Authentication Flow**:
   - Setup code generation and usage
   - Passkey (WebAuthn) support
   - API key scopes and management
   - Session management endpoints

3. **Rate Limiting Details**:
   - Per-endpoint limits
   - 429 response behavior
   - Throttling bypass conditions

4. **Sandbox Backend Configuration**:
   - Apple Container option for macOS
   - Backend selection priority
   - Resource limits
   - Per-session overrides

5. **Health Check Configuration**:
   - `/health` endpoint details
   - Docker healthcheck integration
   - Cloud provider health check configuration

6. **TLS Certificate Management**:
   - Self-signed CA generation
   - Certificate trust procedures
   - HTTP redirect port (13132) purpose

### 7.3 Additional User Stories to Consider

1. **API Key Management** (P2):
   - As administrator, I want to create API keys for programmatic access
   - As developer, I want to scope API keys to minimum necessary permissions

2. **Passkey Authentication** (P2):
   - As user, I want to use hardware keys for authentication
   - As administrator, I want to support multiple passkeys per instance

3. **Monitoring Integration** (P3):
   - As DevOps engineer, I want to export metrics to OpenTelemetry
   - As administrator, I want to track gateway health via `/health`

4. **Sandbox Configuration** (P2):
   - As administrator, I want to customize sandbox resource limits
   - As user, I want to select custom container images per session

5. **Session Persistence** (P2):
   - As user, I want sessions to persist across container restarts
   - As administrator, I want to configure session expiry (default 30 days)

### 7.4 Edge Cases to Document

1. **Docker Socket Loss**:
   - What happens when Docker socket becomes unavailable during runtime?
   - How does Moltis handle socket permission errors?

2. **Setup Code Loss**:
   - What happens if setup code is lost before credential setup?
   - How to regenerate setup code without data loss?

3. **Certificate Expiry**:
   - What happens when self-signed certificate expires?
   - How to regenerate CA certificate without losing configuration?

4. **Volume Full Scenarios**:
   - What happens when config or data volume fills up?
   - How does Moltis handle disk space exhaustion?

5. **Concurrent Connection Limits**:
   - What is the maximum number of concurrent WebSocket connections?
   - How does system behave under connection overload?

6. **Provider Authentication Failures**:
   - What happens when OAuth token expires?
   - How does Moltis handle provider API rate limits?

---

## 8. Sources

**Primary Sources**:
- Docker Deployment: https://docs.moltis.org/docker.html
- Configuration: https://docs.moltis.org/configuration.html
- Authentication: https://docs.moltis.org/authentication.html
- Cloud Deployment: https://docs.moltis.org/cloud-deploy.html
- Providers: https://docs.moltis.org/providers.html
- Sandbox: https://docs.moltis.org/sandbox.html
- Main Documentation: https://docs.moltis.org/

**Key Documentation Sections**:
- Chapter 21: Docker
- Chapter 3: Configuration
- Chapter 18: Authentication
- Chapter 22: Cloud Deploy
- Chapter 11: Sandbox
- Chapter 6: LLM Providers

**Version**: Documentation accessed 2026-02-14

---

## 9. Implementation Checklist

Based on research findings, verify these items are addressed in implementation:

- [ ] Docker socket mount with security warning in documentation
- [ ] `MOLTIS_BEHIND_PROXY` environment variable configured for reverse proxy
- [ ] `MOLTIS_PASSWORD` or setup code flow documented for initial authentication
- [ ] Volume permissions configured (UID 1000 for moltis user)
- [ ] Health check endpoint `/health` configured for monitoring
- [ ] TLS termination at reverse proxy with `MOLTIS_NO_TLS=true`
- [ ] Proper proxy headers forwarded (`X-Forwarded-For`, `Host`, `Origin`)
- [ ] Rate limiting considerations documented for authenticated endpoints
- [ ] Sandbox limitations documented for cloud deployments
- [ ] Certificate trust procedures included if using Moltis TLS
- [ ] Session persistence confirmed via data volume mount
- [ ] API key scoping documented if programmatic access needed
- [ ] Resource limits configured if sandbox resource constraints needed
