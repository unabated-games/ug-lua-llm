#!/usr/bin/env python3
"""Deterministic local OpenAI-compatible server for transport tests."""

import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


REQUEST_COUNTS = {}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        return

    def _json(self, status, body, headers=None):
        encoded = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(encoded)

    def _sse(self, pieces):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        for piece in pieces:
            try:
                self.wfile.write(piece.encode())
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                break
            time.sleep(0.005)
        self.close_connection = True

    def _raw(self, status, body, headers=None):
        encoded = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"ok": True})
        elif self.path.startswith("/v1/models"):
            query = parse_qs(urlparse(self.path).query)
            models = [
                {"id": "fake-chat"},
                {"id": "fake-stream"},
                {"id": "fake-tools"},
            ]
            if query.get("limit") == ["2"]:
                if query.get("after") == ["fake-stream"]:
                    self._json(200, {"data": models[2:], "has_more": False})
                else:
                    self._json(200, {"data": models[:2], "has_more": True})
            else:
                self._json(200, {"data": models})
        else:
            self._json(404, {"error": {"message": "route not found"}})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        payload = json.loads(self.rfile.read(length) or b"{}")
        model = payload.get("model", "")
        REQUEST_COUNTS[model] = REQUEST_COUNTS.get(model, 0) + 1

        if self.path != "/v1/chat/completions":
            self._json(404, {"error": {"message": "route not found"}})
            return

        if model == "fake-error":
            self._json(400, {
                "error": {
                    "message": "deliberate fake error",
                    "code": "bad_request",
                    "api_key": "must-not-escape",
                },
            }, {
                "X-Request-ID": "req_fake_error",
                "Authorization": "Bearer must-not-escape",
            })
            return

        if model == "fake-rate-limit":
            self._json(429, {"error": {
                "message": "rate limited", "code": "rate_limit",
            }}, {"Retry-After": "0", "X-Request-ID": "req_rate_limit"})
            return

        if model == "fake-no-retry":
            self._json(503, {"error": {"message": "do not retry"}})
            return

        if model == "fake-malformed":
            self._raw(200, "{not valid json")
            return

        if model == "fake-timeout":
            time.sleep(0.2)
            try:
                self._json(200, {"choices": []})
            except (BrokenPipeError, ConnectionResetError):
                pass
            return

        if model == "fake-retry" and REQUEST_COUNTS[model] == 1:
            self._json(503, {"error": {"message": "retry me"}}, {"Retry-After": "0"})
            return

        if model == "fake-hook-retry" and REQUEST_COUNTS[model] == 1:
            self._json(503, {"error": {"message": "hook retry"}}, {
                "X-RateLimit-Reset-Requests": "5ms",
                "X-Request-ID": "req_hook_retry",
            })
            return

        if payload.get("stream") and model == "fake-stream":
            # Mix CRLF, arbitrary write boundaries, a comment, and multiline data.
            self._sse([
                ": keepalive\r\n\r\n",
                "data: {\"id\":\"chat_stream\",\"model\":\"fake-stream\",",
                "\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hel\"}}]}\r\n\r\n",
                "data: {\"choices\":\n",
                "data: [{\"index\":0,\"delta\":{\"content\":\"lo\"},\"finish_reason\":\"stop\"}]}\n\n",
                "data: [DONE]\n\n",
            ])
            return

        if payload.get("stream") and model == "fake-tools":
            events = [
                {"choices": [{"index": 0, "delta": {"tool_calls": [{
                    "index": 0, "id": "call_1", "type": "function",
                    "function": {"name": "get_", "arguments": "{\"city\":"},
                }]}}]},
                {"choices": [{"index": 0, "delta": {"tool_calls": [{
                    "index": 0,
                    "function": {"name": "weather", "arguments": "\"Paris\"}"},
                }]}, "finish_reason": "tool_calls"}]},
            ]
            pieces = ["data: " + json.dumps(event) + "\n\n" for event in events]
            pieces.append("data: [DONE]\n\n")
            self._sse(pieces)
            return

        content = "fake chat works"
        if model == "fake-retry":
            content = "retry succeeded after %d requests" % REQUEST_COUNTS[model]
        self._json(200, {
            "id": "chat_json",
            "model": model,
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": content},
                "finish_reason": "stop",
            }],
            "received_authorization": self.headers.get("Authorization"),
            "received_test_header": self.headers.get("X-Test-Header"),
        })


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    with open(args.port_file, "w", encoding="utf-8") as port_file:
        port_file.write(str(server.server_port))
    server.serve_forever()


if __name__ == "__main__":
    main()
