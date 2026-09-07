#!/usr/bin/env python3
"""Local-only Responses fixture for the native chat tool-loop dogfood check."""
import argparse
import http.server
import json
import time
from pathlib import Path

FIXTURE_DIRECTORY = Path(__file__).resolve().parents[1] / ".build-support" / "ux9-fixture"
MAX_BODY_BYTES = 1_024 * 1_024


class Fixture(http.server.BaseHTTPRequestHandler):
    request_count = 0

    def do_GET(self):
        if self.path.startswith("/slow/"):
            time.sleep(3)
        if self.headers.get("Authorization") != "Bearer fixture-only" or self.path.startswith("/failed/"):
            self.send_error(401)
            return
        if not self.path.endswith("/models"):
            self.send_error(404)
            return
        data = json.dumps({"data": [] if self.path.startswith("/empty/") else [{"id": "trellis-fixture"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

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
        if self.path not in ("/v1/responses", "/v1/chat/completions"):
            self.send_error(404)
            return
        if self.headers.get("Authorization") != "Bearer fixture-only" or body.get("model") != "trellis-fixture":
            self.send_error(401)
            return

        inputs = body.get("input", body.get("messages"))
        if not isinstance(inputs, list):
            self.send_error(400)
            return
        function_outputs = [item for item in inputs if isinstance(item, dict) and (item.get("type") == "function_call_output" or item.get("role") == "tool")]
        user_count = sum(1 for item in inputs if isinstance(item, dict) and item.get("role") == "user")
        snapshot_contains_pid = any(
            has_ux9_pid(content_text(item.get("content")))
            for item in inputs if isinstance(item, dict) and item.get("role") == "user"
        )

        keep_alive = any("STREAM_KEEPALIVE_FIXTURE" in content_text(item.get("content")) for item in inputs if isinstance(item, dict))
        text_fixture = any("STREAM_TEXT_FIXTURE" in content_text(item.get("content")) for item in inputs if isinstance(item, dict))
        last_user = max((i for i, item in enumerate(inputs) if isinstance(item, dict) and item.get("role") == "user"), default=0)
        latest_prompt = content_text(inputs[last_user].get("content"))
        fail_fixture = "STREAM_FAIL_FIXTURE" in latest_prompt
        latest_outputs = [item for item in inputs[last_user + 1:] if isinstance(item, dict) and (item.get("type") == "function_call_output" or item.get("role") == "tool")]
        if "REUSABLE_FIXTURE" in latest_prompt:
            response = completed("The recipe is staged. Open Reusable Tools to review it; saving it does not execute it.") if latest_outputs else named_call("propose_saved_tool", {
                "id": None, "base_hash": None, "name": "Fixture greeting", "description": "Print a harmless greeting in the conversation folder.",
                "executable": "/usr/bin/printf", "arguments": ["Trellis reusable tool works\n"], "directory": "."})
        elif "RUN_SAVED_FIXTURE" in latest_prompt:
            if not latest_outputs:
                response = named_call("list_saved_tools", {})
            elif len(latest_outputs) == 1:
                raw = latest_outputs[0].get("output", latest_outputs[0].get("content", ""))
                try:
                    tool = json.loads(raw.splitlines()[0])
                    response = named_call("run_saved_tool", {"id": tool["id"], "hash": tool["hash"]})
                except (ValueError, KeyError, IndexError, AttributeError):
                    response = completed("No reviewed fixture tool was available.")
            else:
                response = completed("The approved reusable tool ran and its reviewed output was received.")
        elif "TERMINAL_CONTEXT_FIXTURE" in latest_prompt:
            response = completed("The reviewed terminal snapshot was received.") if latest_outputs else named_call("read_terminal_context", {})
        elif "SESSION_INFO_FIXTURE" in latest_prompt:
            response = completed("The reviewed session information was received.") if latest_outputs else named_call("read_session_info", {})
        elif fail_fixture:
            response = completed("Partial reply which must remain marked incomplete.")
        elif keep_alive:
            response = completed("Hello 👋")
        elif text_fixture:
            response = completed("Hello 👋 — this reply arrives incrementally.\n\n## A readable conversation\n- Retain your place\n- Review every tool\n\n[Documentation](https://example.com) and `inline code`.\n\n```swift\nlet greeting = \"Hello 👋\"\nprint(greeting)\n```\n")
        elif not function_outputs:
            response = function_call()
        elif user_count == 1:
            response = completed("Fixture: background tool completed; terminal context reviewed.")
        else:
            response = completed(f"Fixture: retained {user_count} prior user messages and the reviewed tool receipt.")

        if body.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            if keep_alive:
                self.send_header("Connection", "keep-alive")
            self.end_headers()
            try:
                for event in stream_events(response, self.path.endswith("chat/completions")):
                    encoded = ("data: " + (event if isinstance(event, str) else json.dumps(event, ensure_ascii=False)) + "\r\n\r\n").encode()
                    # Split inside UTF-8 and event boundaries, with enough delay to observe partial text.
                    for offset in range(0, len(encoded), 7):
                        self.wfile.write(encoded[offset:offset + 7])
                        self.wfile.flush()
                    if fail_fixture and isinstance(event, dict) and (event.get("type") == "response.output_text.delta" or (event.get("choices") or [{}])[0].get("delta", {}).get("content")):
                        self.close_connection = True
                        return
                    time.sleep(0.04)
                if keep_alive:
                    time.sleep(4)
                    self.close_connection = True
            except (BrokenPipeError, ConnectionResetError):
                return
        else:
            if self.path.endswith("chat/completions"):
                item = response["output"][0]
                if item["type"] == "message":
                    response = {"choices": [{"finish_reason": "stop", "message": {"role": "assistant", "content": item["content"][0]["text"]}}]}
                else:
                    response = {"choices": [{"finish_reason": "tool_calls", "message": {"role": "assistant", "content": None, "tool_calls": [{"id": item["call_id"], "type": "function", "function": {"name": item["name"], "arguments": item["arguments"]}}]}}]}
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


def named_call(name, arguments):
    return {"status": "completed", "output": [{"type": "function_call", "id": "fixture-" + name,
            "call_id": "fixture-" + name, "name": name, "arguments": json.dumps(arguments), "status": "completed"}]}


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


def stream_events(response, chat):
    yield {"choices": []} if chat else {"type": "future.ignored"}
    for item in response["output"]:
        if item["type"] == "message":
            text = item["content"][0]["text"]
            for offset in range(0, len(text), 8):
                delta = text[offset:offset + 8]
                yield {"choices": [{"index": 0, "delta": {"content": delta}, "finish_reason": None}]} if chat else {"type": "response.output_text.delta", "delta": delta}
        elif chat:
            yield {"choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "id": item["call_id"], "type": "function", "function": {"name": item["name"], "arguments": ""}}]}}]}
            for offset in range(0, len(item["arguments"]), 8):
                yield {"choices": [{"index": 0, "delta": {"tool_calls": [{"index": 0, "function": {"arguments": item["arguments"][offset:offset + 8]}}]}}]}
        else:
            yield {"type": "response.output_item.added", "output_index": 0, "item": {**item, "arguments": ""}}
            for offset in range(0, len(item["arguments"]), 8):
                yield {"type": "response.function_call_arguments.delta", "item_id": item["id"], "delta": item["arguments"][offset:offset + 8]}
            yield {"type": "response.output_item.done", "output_index": 0, "item": item}
    if chat:
        finish = "tool_calls" if any(item["type"] == "function_call" for item in response["output"]) else "stop"
        yield {"choices": [{"index": 0, "delta": {}, "finish_reason": finish}]}
        yield "[DONE]"
    else:
        yield {"type": "response.completed", "response": response}


FIXTURE_DIRECTORY.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=0)
server = http.server.ThreadingHTTPServer(("127.0.0.1", parser.parse_args().port), Fixture)
print(f"http://127.0.0.1:{server.server_port}/v1", flush=True)
server.serve_forever()
