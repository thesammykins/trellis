#!/usr/bin/env python3
"""Local-only Responses fixture for the native chat tool-loop dogfood check."""
import http.server
import json
from pathlib import Path

FIXTURE_DIRECTORY = Path(__file__).resolve().parents[1] / ".build-support" / "ux9-fixture"
MAX_BODY_BYTES = 1_024 * 1_024


class Fixture(http.server.BaseHTTPRequestHandler):
    request_count = 0

    def do_POST(self):
        try:
            size = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_error(400)
            return
        if not 0 < size <= MAX_BODY_BYTES:
            self.send_error(413)
            return
        try:
            body = json.loads(self.rfile.read(size))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.send_error(400)
            return
        if not isinstance(body, dict):
            self.send_error(400)
            return
        if self.path != "/v1/responses":
            self.send_error(404)
            return
        if self.headers.get("Authorization") != "Bearer fixture-only" or body.get("model") != "trellis-fixture":
            self.send_error(401)
            return

        inputs = body.get("input")
        if not isinstance(inputs, list):
            self.send_error(400)
            return
        function_outputs = [item for item in inputs if isinstance(item, dict) and item.get("type") == "function_call_output"]
        user_count = sum(1 for item in inputs if isinstance(item, dict) and item.get("role") == "user")
        snapshot_contains_pid = any(
            has_ux9_pid(content_text(item.get("content")))
            for item in inputs if isinstance(item, dict) and item.get("role") == "user"
        )

        if not function_outputs:
            response = function_call()
        elif user_count == 1:
            response = completed("Fixture: background tool completed; terminal context reviewed.")
        else:
            response = completed(f"Fixture: retained {user_count} prior user messages and the reviewed tool receipt.")

        data = json.dumps(response).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        type(self).request_count += 1
        print(
            "proof"
            f" request_count={type(self).request_count}"
            f" snapshotcontainsUX9livePID={str(snapshot_contains_pid).lower()}"
            f" historicalusercount={user_count}"
            f" actualtooloutputreceipt={str(bool(function_outputs)).lower()}",
            flush=True,
        )

    def log_message(self, *_):
        pass


def content_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(part.get("text", "") for part in content if isinstance(part, dict))
    return ""


def has_ux9_pid(text):
    upper = text.upper()
    return "UX9 TWO PID=" in upper or ("UX9" in upper and "PID" in upper)


def function_call():
    arguments = json.dumps({
        "executable": "/usr/bin/printf",
        "arguments": ["UX9 background tool passed\n"],
        "directory": str(FIXTURE_DIRECTORY),
    })
    return {
        "status": "completed",
        "output": [{
            "type": "function_call",
            "id": "fixture-function-1",
            "call_id": "ux9-run-command",
            "name": "run_command",
            "arguments": arguments,
            "status": "completed",
        }],
    }


def completed(text):
    return {
        "status": "completed",
        "output": [{
            "type": "message",
            "id": "fixture-message",
            "role": "assistant",
            "status": "completed",
            "content": [{"type": "output_text", "text": text, "annotations": []}],
        }],
    }


FIXTURE_DIRECTORY.mkdir(parents=True, exist_ok=True)
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
print(f"http://127.0.0.1:{server.server_port}/v1", flush=True)
server.serve_forever()
