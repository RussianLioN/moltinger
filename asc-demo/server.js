import path from "node:path";
import { fileURLToPath } from "node:url";
import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import { getArtifact, getSession } from "./src/sessions.js";
import { handleTurn } from "./src/router.js";
import { buildErrorFallbackResponse, buildGatePendingResponse } from "./src/response-builder.js";

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = Number(process.env.PORT || 3000);
const app = express();

app.use(cors());
app.use(express.json({ limit: "5mb" }));
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, "public")));

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#39;");
}

function renderInlineMarkdown(value) {
  return escapeHtml(value)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
}

function renderMarkdownToHtml(markdown) {
  const lines = String(markdown ?? "").replace(/\r\n/g, "\n").split("\n");
  const blocks = [];
  let paragraph = [];
  let listItems = [];
  let listTag = "";

  const flushParagraph = () => {
    const text = paragraph.join(" ").trim();
    if (!text) {
      paragraph = [];
      return;
    }
    blocks.push(`<p>${renderInlineMarkdown(text)}</p>`);
    paragraph = [];
  };

  const flushList = () => {
    if (!listItems.length || !listTag) {
      listItems = [];
      listTag = "";
      return;
    }
    blocks.push(`<${listTag}>${listItems.join("")}</${listTag}>`);
    listItems = [];
    listTag = "";
  };

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) {
      flushParagraph();
      flushList();
      continue;
    }

    const headingMatch = line.match(/^(#{1,3})\s+(.+)$/);
    if (headingMatch) {
      flushParagraph();
      flushList();
      const level = Math.min(headingMatch[1].length, 3);
      blocks.push(`<h${level}>${renderInlineMarkdown(headingMatch[2])}</h${level}>`);
      continue;
    }

    const unorderedMatch = line.match(/^[-*]\s+(.+)$/);
    const orderedMatch = line.match(/^\d+\.\s+(.+)$/);
    if (unorderedMatch || orderedMatch) {
      flushParagraph();
      const nextTag = unorderedMatch ? "ul" : "ol";
      if (listTag && listTag !== nextTag) {
        flushList();
      }
      listTag = nextTag;
      listItems.push(`<li>${renderInlineMarkdown((unorderedMatch || orderedMatch)[1])}</li>`);
      continue;
    }

    flushList();
    paragraph.push(line);
  }

  flushParagraph();
  flushList();

  if (!blocks.length) {
    return "<p>Артефакт пока пуст.</p>";
  }

  return blocks.join("\n");
}

function buildPreviewHtml(artifact) {
  const title = escapeHtml(artifact?.download_name || artifact?.artifact_kind || "Artifact preview");
  const body = renderMarkdownToHtml(artifact?.content || "");
  return [
    "<!doctype html>",
    "<html lang=\"ru\">",
    "<head>",
    "  <meta charset=\"utf-8\">",
    "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
    `  <title>${title}</title>`,
    "  <style>",
    "    :root { color-scheme: light; }",
    "    body { max-width: 880px; margin: 0 auto; padding: 32px 20px 48px; font: 16px/1.6 -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: #172033; background: #f7f8fb; }",
    "    main { background: #fff; border: 1px solid #d8deeb; border-radius: 16px; padding: 24px; box-shadow: 0 16px 40px rgba(23, 32, 51, 0.08); }",
    "    h1, h2, h3 { line-height: 1.25; color: #0f172a; margin: 1.4em 0 0.6em; }",
    "    h1 { margin-top: 0; font-size: 2rem; }",
    "    h2 { font-size: 1.4rem; }",
    "    h3 { font-size: 1.1rem; }",
    "    p { margin: 0 0 1em; }",
    "    ul, ol { margin: 0 0 1em 1.3em; padding: 0; }",
    "    li { margin: 0.2em 0; }",
    "    code { font-family: 'SFMono-Regular', ui-monospace, monospace; font-size: 0.95em; background: #eef2ff; border-radius: 6px; padding: 0.1em 0.35em; }",
    "  </style>",
    "</head>",
    "<body>",
    "  <main>",
    body,
    "  </main>",
    "</body>",
    "</html>",
  ].join("\n");
}

app.get("/health", (_req, res) => {
  const demoDomain = process.env.DEMO_DOMAIN || "demo.ainetic.tech";
  const publicBaseUrl = process.env.DEMO_PUBLIC_BASE_URL || `https://${demoDomain}`;
  res.json({
    status: "ok",
    service: "asc-demo-backend",
    llm_configured: Boolean(process.env.OPENAI_API_KEY),
    model: process.env.MODEL_NAME || "accounts/fireworks/models/glm-5",
    demo_domain: demoDomain,
    public_base_url: publicBaseUrl,
  });
});

app.post("/api/turn", async (req, res) => {
  const payload = req.body || {};
  try {
    const response = await handleTurn(payload);
    res.json(response);
  } catch (error) {
    console.error("[asc-demo] server.api.turn:", error?.message || error);
    const sessionId = payload?.web_demo_session?.web_demo_session_id || "web-demo-session-fallback";
    const fallbackSession = {
      sessionId,
      projectKey: payload?.browser_project_pointer?.project_key || "",
      accessGranted: false,
      stage: "gate_pending",
      uploadedFiles: [],
      briefVersion: 0,
      displayProjectTitle: "Новый проект",
    };
    const fallback = buildErrorFallbackResponse(
      fallbackSession,
      payload,
      `backend_error: ${error?.message || "unknown_error"}`,
    );
    res.status(500).json(fallback);
  }
});

app.get("/api/session", (req, res) => {
  const sessionId = String(req.query.session_id || "").trim();
  if (!sessionId) {
    const fallbackSession = {
      sessionId: "",
      projectKey: "",
      accessGranted: false,
      stage: "gate_pending",
      uploadedFiles: [],
      briefVersion: 0,
      displayProjectTitle: "Новый проект",
    };
    return res.status(200).json(
      buildGatePendingResponse(fallbackSession, {}, "session_id не указан"),
    );
  }
  const session = getSession(sessionId);
  if (!session || !session.lastResponse) {
    const fallbackSession = {
      sessionId,
      projectKey: "",
      accessGranted: false,
      stage: "gate_pending",
      uploadedFiles: [],
      briefVersion: 0,
      displayProjectTitle: "Новый проект",
    };
    return res.status(200).json(
      buildGatePendingResponse(
        fallbackSession,
        {
          web_conversation_envelope: { request_id: "session-fetch", ui_action: "request_status", user_text: "" },
        },
        "Сессия не найдена или ещё не инициализирована.",
      ),
    );
  }
  return res.json(session.lastResponse);
});

app.get("/api/download/:sessionId/:artifactKind", (req, res) => {
  const { sessionId, artifactKind } = req.params;
  const artifact = getArtifact(sessionId, artifactKind);
  if (!artifact) {
    return res.status(404).json({ error: "artifact_not_found" });
  }
  const filename = artifact.download_name || `${artifactKind}.md`;
  res.setHeader("Content-Type", "text/markdown; charset=utf-8");
  res.setHeader("Content-Disposition", `attachment; filename="${filename}"`);
  return res.status(200).send(artifact.content || "");
});

app.get("/api/preview/:sessionId/:artifactKind", (req, res) => {
  const { sessionId, artifactKind } = req.params;
  const artifact = getArtifact(sessionId, artifactKind);
  if (!artifact) {
    return res.status(404).json({ error: "artifact_not_found" });
  }
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("X-Content-Type-Options", "nosniff");
  return res.status(200).send(buildPreviewHtml(artifact));
});

app.get("*", (_req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`ASC Demo backend listening on http://localhost:${PORT}`);
});
