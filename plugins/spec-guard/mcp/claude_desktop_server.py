#!/usr/bin/env python3
"""Read-only Spec Guard MCP server for Claude Desktop's stdio transport."""

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


SERVER_INFO = {"name": "spec-guard", "version": "0.7.49"}
TOOLS = [
    {
        "name": "phase",
        "description": "Read the current Spec Guard phase for a project.",
        "inputSchema": {"type": "object", "properties": {"project": {"type": "string"}}, "required": ["project"]},
    },
    {
        "name": "verify",
        "description": "Read-only validation of Spec Guard artifacts.",
        "inputSchema": {"type": "object", "properties": {"project": {"type": "string"}}, "required": ["project"]},
    },
    {
        "name": "verify_history",
        "description": "Read-only validation of capability history evidence.",
        "inputSchema": {"type": "object", "properties": {"project": {"type": "string"}}, "required": ["project"]},
    },
    {
        "name": "sync_map_preview",
        "description": "Preview tracker synchronization without writes.",
        "inputSchema": {"type": "object", "properties": {"project": {"type": "string"}}, "required": ["project"]},
    },
    {
        "name": "write_operation",
        "description": "Explain why a write operation needs explicit CLI or Codex confirmation.",
        "inputSchema": {
            "type": "object",
            "properties": {"project": {"type": "string"}, "operation": {"type": "string"}},
            "required": ["project", "operation"],
        },
    },
]


def send(message: dict[str, Any]) -> None:
    print(json.dumps(message, ensure_ascii=False, separators=(",", ":")), flush=True)


def text_result(text: str, *, is_error: bool = False) -> dict[str, Any]:
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def project_root(value: Any) -> Path | None:
    if not isinstance(value, str) or not os.path.isabs(value):
        return None
    path = Path(value).resolve()
    if not path.is_dir() or not (path / ".git").exists():
        return None
    return path


def hook_path(name: str) -> Path:
    return Path(__file__).resolve().parents[1] / "hooks" / name


def run_hook(project: Path, name: str, *args: str) -> dict[str, Any]:
    command = ["/bin/bash", str(hook_path(name)), *args]
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = str(project)
    completed = subprocess.run(command, cwd=project, env=env, text=True, capture_output=True, check=False)
    output = (completed.stdout + completed.stderr).strip() or "(no output)"
    return text_result(output, is_error=completed.returncode != 0)


def call_tool(name: Any, arguments: Any) -> dict[str, Any]:
    arguments = arguments if isinstance(arguments, dict) else {}
    if name == "write_operation":
        operation = arguments.get("operation", "requested operation")
        return text_result(f"{operation}: this MCP server will not execute writes. Use Claude Code or Codex and give explicit confirmation.", is_error=True)
    project = project_root(arguments.get("project"))
    if project is None:
        return text_result("project must be an absolute path to an existing Git repository.", is_error=True)
    if name == "phase":
        return run_hook(project, "phase-guard.sh")
    if name == "verify":
        return run_hook(project, "verify-artifacts.sh")
    if name == "verify_history":
        return run_hook(project, "verify-history.sh", str(project))
    if name == "sync_map_preview":
        return text_result("sync_map_preview is not implemented yet.", is_error=True)
    return text_result(f"Unknown tool: {name}", is_error=True)


def handle(request: dict[str, Any]) -> dict[str, Any] | None:
    request_id = request.get("id")
    method = request.get("method")
    if not isinstance(method, str):
        return {"jsonrpc": "2.0", "id": request_id, "error": {"code": -32600, "message": "Invalid Request"}}
    if "id" not in request:
        return None
    if method == "initialize":
        version = request.get("params", {}).get("protocolVersion", "2025-06-18")
        return {"jsonrpc": "2.0", "id": request_id, "result": {"protocolVersion": version, "capabilities": {"tools": {}}, "serverInfo": SERVER_INFO}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": request_id, "result": {"tools": TOOLS}}
    if method == "tools/call":
        params = request.get("params", {})
        return {"jsonrpc": "2.0", "id": request_id, "result": call_tool(params.get("name"), params.get("arguments"))}
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": -32601, "message": "Method not found"}}


def main() -> int:
    for line in sys.stdin:
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                raise ValueError
        except (ValueError, json.JSONDecodeError):
            send({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}})
            continue
        response = handle(request)
        if response is not None:
            send(response)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
