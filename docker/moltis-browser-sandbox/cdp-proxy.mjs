import http from "node:http";
import net from "node:net";

const LISTEN_HOST = "0.0.0.0";
const LISTEN_PORT = 3000;
const TARGET_HOST = "127.0.0.1";
const TARGET_PORT = 9222;
let cachedBrowserWsPath = null;

function sendBadGateway(res, error) {
  const message = error instanceof Error ? error.message : String(error);
  res.writeHead(502, { "content-type": "text/plain; charset=utf-8" });
  res.end(message);
}

function extractBrowserWsPath(body) {
  const payload = JSON.parse(body);
  if (!payload.webSocketDebuggerUrl) {
    throw new Error("missing webSocketDebuggerUrl in /json/version payload");
  }

  const wsUrl = new URL(payload.webSocketDebuggerUrl);
  cachedBrowserWsPath = `${wsUrl.pathname}${wsUrl.search}`;
  return { payload, wsUrl };
}

function rewriteVersionPayload(body, hostHeader) {
  const { payload, wsUrl } = extractBrowserWsPath(body);
  payload.webSocketDebuggerUrl = `ws://${hostHeader}${wsUrl.pathname}${wsUrl.search}`;
  return JSON.stringify(payload);
}

function fetchActiveBrowserWsPath(callback) {
  const request = http.request(
    {
      host: TARGET_HOST,
      port: TARGET_PORT,
      path: "/json/version",
      method: "GET",
      headers: {
        host: `${TARGET_HOST}:${TARGET_PORT}`,
      },
    },
    (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
      response.on("end", () => {
        if ((response.statusCode || 500) >= 400) {
          callback(new Error(`upstream /json/version returned HTTP ${response.statusCode || 500}`));
          return;
        }

        try {
          const body = Buffer.concat(chunks).toString("utf8");
          extractBrowserWsPath(body);
          callback(null, cachedBrowserWsPath);
        } catch (error) {
          callback(error);
        }
      });
    },
  );

  request.on("error", (error) => callback(error));
  request.end();
}

function resolveUpstreamWebSocketPath(requestUrl, callback) {
  if (requestUrl && requestUrl !== "/") {
    callback(null, requestUrl);
    return;
  }

  if (cachedBrowserWsPath) {
    callback(null, cachedBrowserWsPath);
    return;
  }

  fetchActiveBrowserWsPath(callback);
}

function proxyHttp(req, res) {
  const upstreamReq = http.request(
    {
      host: TARGET_HOST,
      port: TARGET_PORT,
      path: req.url,
      method: req.method,
      headers: {
        ...req.headers,
        host: `${TARGET_HOST}:${TARGET_PORT}`,
      },
    },
    (upstreamRes) => {
      if (req.url === "/json/version") {
        const chunks = [];
        upstreamRes.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
        upstreamRes.on("end", () => {
          const headers = { ...upstreamRes.headers };
          delete headers["content-length"];
          delete headers["transfer-encoding"];

          let body = Buffer.concat(chunks).toString("utf8");
          try {
            body = rewriteVersionPayload(body, req.headers.host || `127.0.0.1:${LISTEN_PORT}`);
          } catch (error) {
            sendBadGateway(res, error);
            return;
          }

          res.writeHead(upstreamRes.statusCode || 200, headers);
          res.end(body);
        });
        return;
      }

      res.writeHead(upstreamRes.statusCode || 200, upstreamRes.headers);
      upstreamRes.pipe(res);
    },
  );

  upstreamReq.on("error", (error) => sendBadGateway(res, error));
  req.pipe(upstreamReq);
}

function proxyWebSocket(req, clientSocket, head) {
  resolveUpstreamWebSocketPath(req.url, (resolveError, upstreamPath) => {
    if (resolveError || !upstreamPath) {
      clientSocket.destroy(resolveError || new Error("missing upstream websocket path"));
      return;
    }

    const upstreamSocket = net.connect(TARGET_PORT, TARGET_HOST, () => {
      const headerLines = [`GET ${upstreamPath} HTTP/1.1`, `Host: ${TARGET_HOST}:${TARGET_PORT}`];

      for (const [key, value] of Object.entries(req.headers)) {
        if (key.toLowerCase() === "host") {
          continue;
        }

        if (Array.isArray(value)) {
          for (const item of value) {
            headerLines.push(`${key}: ${item}`);
          }
        } else if (value != null) {
          headerLines.push(`${key}: ${value}`);
        }
      }

      upstreamSocket.write(`${headerLines.join("\r\n")}\r\n\r\n`);
      if (head.length > 0) {
        upstreamSocket.write(head);
      }

      clientSocket.pipe(upstreamSocket);
      upstreamSocket.pipe(clientSocket);
    });

    upstreamSocket.on("error", () => clientSocket.destroy());
    clientSocket.on("error", () => upstreamSocket.destroy());
  });
}

const server = http.createServer(proxyHttp);
server.on("upgrade", proxyWebSocket);
server.listen(LISTEN_PORT, LISTEN_HOST);
