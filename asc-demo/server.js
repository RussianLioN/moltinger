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

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "asc-demo-backend",
    llm_configured: Boolean(process.env.OPENAI_API_KEY),
    model: process.env.MODEL_NAME || "accounts/fireworks/models/glm-5",
  });
});

app.post("/api/turn", async (req, res) => {
  const payload = req.body || {};
  try {
    const response = await handleTurn(payload);
    res.json(response);
  } catch (error) {
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
    res.status(200).json(fallback);
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

app.get("*", (_req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`ASC Demo backend listening on http://localhost:${PORT}`);
});
