import OpenAI from "openai";
import dotenv from "dotenv";

dotenv.config();

const DEFAULT_BASE_URL = "https://api.fireworks.ai/inference/v1";
const DEFAULT_MODEL = "accounts/fireworks/models/glm-5";

let cachedClient = null;

function getEnv() {
  return {
    apiKey: process.env.OPENAI_API_KEY || "",
    baseURL: process.env.OPENAI_BASE_URL || DEFAULT_BASE_URL,
    model: process.env.MODEL_NAME || DEFAULT_MODEL,
  };
}

function getClient() {
  const { apiKey, baseURL } = getEnv();
  if (!apiKey) {
    throw new Error("LLM_CONFIG_MISSING_API_KEY");
  }
  if (!cachedClient) {
    cachedClient = new OpenAI({ apiKey, baseURL, timeout: 30_000 });
  }
  return cachedClient;
}

function normalizeContent(content) {
  if (typeof content === "string") {
    return content.trim();
  }
  if (Array.isArray(content)) {
    return content
      .map((part) => (typeof part?.text === "string" ? part.text : ""))
      .join("\n")
      .trim();
  }
  return "";
}

function stripCodeFence(value) {
  const text = (value || "").trim();
  if (!text.startsWith("```")) {
    return text;
  }
  return text.replace(/^```[a-zA-Z]*\n?/, "").replace(/\n?```$/, "").trim();
}

function extractJsonObject(rawText) {
  const text = stripCodeFence(rawText);
  try {
    return JSON.parse(text);
  } catch (_error) {
    // Continue with best-effort extraction from the first {...} block.
  }
  const firstBrace = text.indexOf("{");
  const lastBrace = text.lastIndexOf("}");
  if (firstBrace === -1 || lastBrace === -1 || lastBrace <= firstBrace) {
    throw new Error("LLM_JSON_PARSE_FAILED");
  }
  return JSON.parse(text.slice(firstBrace, lastBrace + 1));
}

export function isLLMConfigured() {
  return Boolean(process.env.OPENAI_API_KEY);
}

export async function chatCompletion(messages, opts = {}) {
  const client = getClient();
  const { model } = getEnv();
  const response = await client.chat.completions.create({
    model: opts.model || model,
    messages,
    temperature: typeof opts.temperature === "number" ? opts.temperature : 0.2,
    max_tokens: typeof opts.maxTokens === "number" ? opts.maxTokens : 1400,
  }, {
    timeout: typeof opts.timeout === "number" ? opts.timeout : 30_000,
  });
  const message = response?.choices?.[0]?.message;
  const content = normalizeContent(message?.content);
  if (!content) {
    throw new Error("LLM_EMPTY_RESPONSE");
  }
  return content;
}

export async function chatCompletionJSON(messages, opts = {}) {
  const text = await chatCompletion(messages, {
    ...opts,
    temperature: typeof opts.temperature === "number" ? opts.temperature : 0,
  });
  return extractJsonObject(text);
}
