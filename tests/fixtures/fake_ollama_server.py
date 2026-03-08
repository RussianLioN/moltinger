#!/usr/bin/env python3
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

HOST = "0.0.0.0"
PORT = 11434
MODEL = "test-model"


def response_json(handler, payload, status=200):
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def response_sse(handler, events, status=200):
    handler.send_response(status)
    handler.send_header("Content-Type", "text/event-stream")
    handler.send_header("Cache-Control", "no-cache")
    handler.send_header("Connection", "close")
    handler.end_headers()
    for event in events:
        chunk = f"data: {json.dumps(event)}\n\n".encode("utf-8")
        handler.wfile.write(chunk)
        handler.wfile.flush()
    handler.wfile.write(b"data: [DONE]\n\n")
    handler.wfile.flush()


def extract_prompt(payload):
    prompt = payload.get("prompt") or ""
    messages = payload.get("messages") or []
    if messages and isinstance(messages, list):
        last_message = messages[-1]
        if isinstance(last_message, dict):
            content = last_message.get("content", prompt)
            if isinstance(content, list):
                parts = []
                for item in content:
                    if isinstance(item, dict) and item.get("type") == "text":
                        parts.append(item.get("text", ""))
                prompt = " ".join(part for part in parts if part).strip()
            else:
                prompt = content
    return prompt or "ok"


def openai_chat_completion(payload):
    prompt = extract_prompt(payload)
    model = payload.get("model", MODEL)
    return {
        "id": "chatcmpl-fixture",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": f"fake ollama reply: {prompt}"},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": max(1, len(prompt.split())),
            "completion_tokens": 4,
            "total_tokens": max(5, len(prompt.split()) + 4),
        },
    }


def openai_stream_events(payload):
    prompt = extract_prompt(payload)
    model = payload.get("model", MODEL)
    created = int(time.time())
    return [
        {
            "id": "chatcmpl-fixture",
            "object": "chat.completion.chunk",
            "created": created,
            "model": model,
            "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}],
        },
        {
            "id": "chatcmpl-fixture",
            "object": "chat.completion.chunk",
            "created": created,
            "model": model,
            "choices": [{"index": 0, "delta": {"content": f"fake ollama reply: {prompt}"}, "finish_reason": None}],
        },
        {
            "id": "chatcmpl-fixture",
            "object": "chat.completion.chunk",
            "created": created,
            "model": model,
            "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
        },
    ]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/tags":
            response_json(self, {"models": [{"name": MODEL, "model": MODEL}]})
            return
        if self.path == "/health":
            response_json(self, {"status": "ok"})
            return
        response_json(self, {"error": "not found", "path": self.path}, status=404)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8")) if raw else {}
        except json.JSONDecodeError:
            response_json(self, {"error": "invalid json"}, status=400)
            return

        if self.path == "/api/chat":
            prompt = extract_prompt(payload)
            response_json(
                self,
                {
                    "model": payload.get("model", MODEL),
                    "created_at": "2026-03-07T00:00:00Z",
                    "message": {"role": "assistant", "content": f"fake ollama reply: {prompt or 'ok'}"},
                    "done": True,
                },
            )
            return

        if self.path == "/api/generate":
            prompt = extract_prompt(payload)
            response_json(
                self,
                {
                    "model": payload.get("model", MODEL),
                    "created_at": "2026-03-07T00:00:00Z",
                    "response": f"fake ollama reply: {prompt}",
                    "done": True,
                },
            )
            return

        if self.path in {"/chat/completions", "/v1/chat/completions"}:
            if payload.get("stream"):
                response_sse(self, openai_stream_events(payload))
            else:
                response_json(self, openai_chat_completion(payload))
            return

        response_json(self, {"error": "not found", "path": self.path}, status=404)

    def log_message(self, *_args):
        return


if __name__ == "__main__":
    HTTPServer((HOST, PORT), Handler).serve_forever()
