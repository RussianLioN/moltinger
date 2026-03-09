import fs from "node:fs";
import http from "node:http";

const registry = JSON.parse(fs.readFileSync(process.env.HANDOFF_REGISTRY_FILE, "utf8"));
const policy = JSON.parse(fs.readFileSync(process.env.HANDOFF_POLICY_FILE, "utf8"));
const portFile = process.env.HANDOFF_PORT_FILE;
const submitPath = process.env.HANDOFF_SUBMIT_PATH ?? "/internal/v1/agent-handoffs";
const ackPathTemplate =
  process.env.HANDOFF_ACK_PATH_TEMPLATE ?? "/internal/v1/agent-handoffs/{correlation_id}/acks";
const statusPathTemplate =
  process.env.HANDOFF_STATUS_PATH_TEMPLATE ?? "/internal/v1/agent-handoffs/{correlation_id}";
const authorizationHeader =
  (process.env.HANDOFF_AUTHORIZATION_HEADER ?? "Authorization").toLowerCase();
const agentHeader = (process.env.HANDOFF_AGENT_HEADER ?? "X-Agent-Id").toLowerCase();
const correlationHeader =
  (process.env.HANDOFF_CORRELATION_HEADER ?? "X-Correlation-Id").toLowerCase();
const idempotencyHeader =
  (process.env.HANDOFF_IDEMPOTENCY_HEADER ?? "Idempotency-Key").toLowerCase();

const recordsByCorrelation = new Map();
const correlationByIdempotency = new Map();

function sendJson(res, statusCode, body) {
  const payload = JSON.stringify(body);
  res.writeHead(statusCode, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

function parseJson(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1024 * 1024) {
        reject(new Error("request too large"));
      }
    });
    req.on("end", () => {
      if (!body) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

function findAgent(agentId) {
  return registry.agents.find((agent) => agent.agent_id === agentId) ?? null;
}

function findRoute(caller, recipient) {
  return policy.routes.find(
    (route) =>
      route.caller === caller &&
      route.recipient === recipient &&
      route.transport === "http-json",
  ) ?? null;
}

function findCapabilityPolicy(recipient, capability) {
  return policy.capability_authorization.find(
    (entry) => entry.recipient === recipient && entry.capability === capability,
  ) ?? null;
}

function parseTimestamp(input, fallbackMs) {
  const parsed = Date.parse(input ?? "");
  if (Number.isNaN(parsed)) {
    return fallbackMs;
  }
  return parsed;
}

function evaluateTimeout(record) {
  const nowMs = Date.now();
  if (record.state === "submitted" && nowMs > record.deliveryDeadlineMs) {
    record.state = "timed_out";
    record.terminal_reason = "delivery_ack_deadline_exceeded";
  } else if (
    (record.state === "accepted" || record.state === "started" || record.state === "progress") &&
    nowMs > record.absoluteDeadlineMs
  ) {
    record.state = "timed_out";
    record.terminal_reason = "terminal_timeout_exceeded";
  }
}

function currentStatus(record) {
  evaluateTimeout(record);
  return {
    correlation_id: record.correlation_id,
    state: record.state,
    attempt_count: record.attempt_count,
    deadlines: {
      delivery: new Date(record.deliveryDeadlineMs).toISOString(),
      absolute: new Date(record.absoluteDeadlineMs).toISOString(),
    },
    last_progress_at: record.last_progress_at,
    terminal_reason: record.terminal_reason,
    evidence_refs: [],
  };
}

function requiredHeadersPresent(headers) {
  return (
    Boolean(headers[authorizationHeader]) &&
    Boolean(headers[agentHeader]) &&
    Boolean(headers[correlationHeader]) &&
    Boolean(headers[idempotencyHeader])
  );
}

function extractCorrelationId(pathname, template) {
  const [prefix, suffix] = template.split("{correlation_id}");
  if (!pathname.startsWith(prefix)) {
    return null;
  }
  if (suffix && !pathname.endsWith(suffix)) {
    return null;
  }
  return pathname.slice(prefix.length, pathname.length - suffix.length);
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://127.0.0.1");
    if (req.method === "GET" && url.pathname === "/health") {
      sendJson(res, 200, { ok: true });
      return;
    }

    if (req.method === "POST" && url.pathname === submitPath) {
      if (!requiredHeadersPresent(req.headers)) {
        sendJson(res, 401, { status: "rejected", reason: "missing_required_headers" });
        return;
      }

      const body = await parseJson(req);
      const caller = req.headers[agentHeader];
      const recipient = body?.recipient?.agent_id;
      const capability = body?.recipient?.capability;
      const correlationId = body?.correlation_id;
      const idempotencyKey = req.headers[idempotencyHeader];

      if (
        correlationId !== req.headers[correlationHeader] ||
        body?.idempotency_key !== idempotencyKey
      ) {
        sendJson(res, 400, { status: "rejected", reason: "header_body_mismatch" });
        return;
      }

      if (correlationByIdempotency.has(idempotencyKey)) {
        const existing = recordsByCorrelation.get(correlationByIdempotency.get(idempotencyKey));
        sendJson(res, 200, {
          status: "duplicate",
          correlation_id: existing.correlation_id,
          state: currentStatus(existing).state,
        });
        return;
      }

      const route = findRoute(caller, recipient);
      const recipientAgent = findAgent(recipient);
      if (
        !route ||
        !recipientAgent ||
        !route.allowed_callers.includes(caller) ||
        !route.capabilities.includes(capability) ||
        !recipientAgent.capabilities.includes(capability)
      ) {
        const rejected = {
          correlation_id: correlationId,
          idempotency_key: idempotencyKey,
          state: "rejected",
          attempt_count: 1,
          deliveryDeadlineMs: Date.now(),
          absoluteDeadlineMs: Date.now(),
          terminal_reason: "unknown_or_unauthorized_capability",
          last_progress_at: null,
        };
        recordsByCorrelation.set(correlationId, rejected);
        correlationByIdempotency.set(idempotencyKey, correlationId);
        sendJson(res, 422, {
          status: "rejected",
          correlation_id: correlationId,
          reason: rejected.terminal_reason,
        });
        return;
      }

      const capabilityPolicy = findCapabilityPolicy(recipient, capability);
      const submittedMs = parseTimestamp(body.submitted_at, Date.now());
      const expiresAtMs = parseTimestamp(
        body.expires_at,
        submittedMs + (capabilityPolicy?.terminal_timeout_seconds ?? 900) * 1000,
      );
      const deliveryDeadlineMs = Math.min(
        submittedMs + (capabilityPolicy?.delivery_ack_deadline_seconds ?? 10) * 1000,
        expiresAtMs,
      );

      const record = {
        correlation_id: correlationId,
        idempotency_key: idempotencyKey,
        state: "submitted",
        attempt_count: 1,
        deliveryDeadlineMs,
        absoluteDeadlineMs: expiresAtMs,
        terminal_reason: null,
        last_progress_at: null,
      };
      recordsByCorrelation.set(correlationId, record);
      correlationByIdempotency.set(idempotencyKey, correlationId);
      sendJson(res, 202, {
        status: "accepted_for_delivery",
        correlation_id: correlationId,
        delivery_deadline: new Date(deliveryDeadlineMs).toISOString(),
      });
      return;
    }

    const ackCorrelationId = extractCorrelationId(url.pathname, ackPathTemplate);
    if (req.method === "POST" && ackCorrelationId) {
      const correlationId = ackCorrelationId;
      const record = recordsByCorrelation.get(correlationId);
      if (!record) {
        sendJson(res, 404, { status: "not_found" });
        return;
      }

      const body = await parseJson(req);
      const ackType = body?.ack_type;
      switch (ackType) {
        case "delivery":
          break;
        case "accept":
          record.state = "accepted";
          break;
        case "reject":
          record.state = "rejected";
          record.terminal_reason = body?.status_summary ?? "rejected";
          break;
        case "start":
          record.state = "started";
          break;
        case "progress":
          record.state = "progress";
          record.last_progress_at = body?.emitted_at ?? new Date().toISOString();
          break;
        case "terminal":
          if (/cancel/i.test(body?.status_summary ?? "")) {
            record.state = "cancelled";
          } else if (/complete/i.test(body?.status_summary ?? "")) {
            record.state = "completed";
          } else {
            record.state = "failed";
          }
          record.terminal_reason = body?.status_summary ?? null;
          break;
        case "cancel_accept":
          record.state = "cancelled";
          record.terminal_reason = body?.status_summary ?? "cancelled";
          break;
        default:
          sendJson(res, 400, { status: "rejected", reason: "unsupported_ack_type" });
          return;
      }

      sendJson(res, 200, {
        ok: true,
        correlation_id: correlationId,
        state: record.state,
      });
      return;
    }

    const statusCorrelationId = extractCorrelationId(url.pathname, statusPathTemplate);
    if (req.method === "GET" && statusCorrelationId) {
      const correlationId = statusCorrelationId;
      const record = recordsByCorrelation.get(correlationId);
      if (!record) {
        sendJson(res, 404, { status: "not_found" });
        return;
      }
      sendJson(res, 200, currentStatus(record));
      return;
    }

    sendJson(res, 404, { status: "not_found" });
  } catch (error) {
    sendJson(res, 500, {
      status: "error",
      message: error instanceof Error ? error.message : String(error),
    });
  }
});

server.listen(0, "127.0.0.1", () => {
  const address = server.address();
  if (typeof address === "object" && address) {
    fs.writeFileSync(portFile, String(address.port));
  }
});

process.on("SIGTERM", () => {
  server.close(() => process.exit(0));
});
