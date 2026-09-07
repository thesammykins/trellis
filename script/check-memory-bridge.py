#!/usr/bin/env python3
"""Compile/run fixture for the fixed-scope MCP memory bridge."""
import json
import hashlib
import pathlib
import subprocess
import selectors
import tempfile
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = ROOT / ".build-support" / "check-memory-bridge"

subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "Trellis/MemoryStore.swift", "Helpers/MemoryBridge.swift", "-o", str(BINARY)], cwd=ROOT, check=True)
requests = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "fixture", "version": "1"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "trellis_memory_propose", "arguments": {"title": "Fixture", "body": "Pending review", "kind": "decision", "source": "fixture"}}},
    {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "trellis_memory_search", "arguments": {"query": "Fixture"}}},
    {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "trellis_memory_approve", "arguments": {}}},
    {"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {"name": "trellis_memory_search", "arguments": {"query": "Fixture", "projectID": "other"}}},
]
with tempfile.TemporaryDirectory() as temporary:
    payload = "".join(json.dumps(request) + "\n" for request in requests)
    run = subprocess.run([str(BINARY), "--root", temporary, "--project-id", "fixture-project"], input=payload, text=True, capture_output=True, check=True)
    receipt_files = list(pathlib.Path(temporary).rglob("receipts/*.json"))
    receipt_payloads = [json.loads(path.read_text()) for path in receipt_files]
responses = [json.loads(line) for line in run.stdout.splitlines()]
assert len(responses) == 6
assert responses[0]["result"]["protocolVersion"] == "2024-11-05"
tools = {tool["name"] for tool in responses[1]["result"]["tools"]}
assert tools == {"trellis_memory_search", "trellis_memory_propose"}
assert responses[2]["result"]["content"][0]["text"]
assert json.loads(responses[3]["result"]["content"][0]["text"]) == {"pages": []}
assert responses[4]["error"]["code"] == -32602
assert responses[5]["error"]["code"] == -32602
assert len(receipt_payloads) == 1
assert receipt_payloads[0]["mechanism"] == "mcp"
assert receipt_payloads[0]["pages"] == []
assert receipt_payloads[0]["returnedBytes"] == len(responses[3]["result"]["content"][0]["text"].encode())
print("memory bridge fixture passed")

# The result limit skips an oversized page without suppressing a later page that fits,
# and the receipt describes exactly the JSON returned to MCP.
with tempfile.TemporaryDirectory() as temporary:
    project_id = "bounded-result-project"
    subprocess.run([str(BINARY), "--root", temporary, "--project-id", project_id], input="", text=True,
                   capture_output=True, check=True)
    scope = hashlib.sha256(project_id.encode()).hexdigest()
    wiki = pathlib.Path(temporary) / scope / "Memory" / "wiki"

    def write_page(title, body):
        page_id = uuid.uuid4()
        metadata = {"schemaVersion": 1, "id": str(page_id), "title": title, "projectID": project_id,
                    "kind": "reference", "reviewStatus": "approved", "revision": 1,
                    "provenance": ["fixture"], "reviewedAt": "2026-09-07T00:00:00Z"}
        content = "---\n" + json.dumps(metadata, separators=(",", ":"), sort_keys=True) + "\n---\n\n" + body
        (wiki / f"{str(page_id).lower()}.md").write_text(content)
        return str(page_id).upper()

    write_page("A oversized", "x" * (40 * 1024))
    returned_id = write_page("Z returned", "bounded")
    search = {"jsonrpc": "2.0", "id": 7, "method": "tools/call",
              "params": {"name": "trellis_memory_search", "arguments": {"query": ""}}}
    bounded_run = subprocess.run([str(BINARY), "--root", temporary, "--project-id", project_id],
                                 input=json.dumps(search) + "\n", text=True, capture_output=True, check=True)
    bounded_response = json.loads(bounded_run.stdout)
    returned_text = bounded_response["result"]["content"][0]["text"]
    returned_pages = json.loads(returned_text)["pages"]
    assert [page["id"] for page in returned_pages] == [returned_id]
    bounded_receipts = [json.loads(path.read_text()) for path in pathlib.Path(temporary).rglob("receipts/*.json")]
    assert len(bounded_receipts) == 1
    assert [page["id"].upper() for page in bounded_receipts[0]["pages"]] == [returned_id]
    assert bounded_receipts[0]["returnedBytes"] == len(returned_text.encode()) <= 32 * 1024
    assert set(bounded_receipts[0]) == {"id", "date", "mechanism", "pages", "returnedBytes"}
print("memory bridge bounded-result receipt passed")

# MCP clients keep stdin open. A file-style read that waits for 4096 bytes deadlocks initialization.
with tempfile.TemporaryDirectory() as temporary:
    process = subprocess.Popen([str(BINARY), "--root", temporary, "--project-id", "live-pipe-fixture"],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        process.stdin.write(json.dumps(requests[0]) + "\n")
        process.stdin.flush()
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        assert selector.select(3), "initialize blocked while stdin remained open"
        assert json.loads(process.stdout.readline())["id"] == 1
        selector.close()
    finally:
        process.terminate()
        process.wait(timeout=3)
print("memory bridge live-pipe handshake passed")
