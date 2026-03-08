#!/usr/bin/env python3
import json
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
            messages = payload.get("messages") or []
            prompt = payload.get("prompt") or ""
            if messages and isinstance(messages, list):
                prompt = messages[-1].get("content", prompt)
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
            prompt = payload.get("prompt", "")
            response_json(
                self,
                {
                    "model": payload.get("model", MODEL),
                    "created_at": "2026-03-07T00:00:00Z",
                    "response": f"fake ollama reply: {prompt or 'ok'}",
                    "done": True,
                },
            )
            return

        response_json(self, {"error": "not found", "path": self.path}, status=404)

    def log_message(self, *_args):
        return


if __name__ == "__main__":
    HTTPServer((HOST, PORT), Handler).serve_forever()
