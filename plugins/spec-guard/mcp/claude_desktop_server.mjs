#!/usr/bin/env node
/** Read-only Spec Guard MCP server for Claude Desktop's stdio transport. */

import { existsSync, readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { createInterface } from "node:readline";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const manifest = JSON.parse(readFileSync(join(root, "manifest.json"), "utf8"));
const serverInfo = { name: "spec-guard", version: manifest.version };
const tools = [
  ["phase", "Read the current Spec Guard phase for a project."],
  ["verify", "Read-only validation of Spec Guard artifacts."],
  ["verify_history", "Read-only validation of capability history evidence."],
  ["audit_history", "Read-only semantic audit of capability history claims."],
  ["write_operation", "Explain why a write operation needs explicit CLI or Codex confirmation."],
].map(([name, description]) => ({
  name,
  description,
  inputSchema: {
    type: "object",
    properties: { project: { type: "string" }, ...(name === "write_operation" ? { operation: { type: "string" } } : {}) },
    required: name === "write_operation" ? ["project", "operation"] : ["project"],
  },
}));

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function textResult(text, isError = false) {
  return { content: [{ type: "text", text }], isError };
}

function projectRoot(value) {
  if (typeof value !== "string" || !isAbsolute(value)) return null;
  try {
    const project = realpathSync(value);
    return statSync(project).isDirectory() && existsSync(join(project, ".git")) ? project : null;
  } catch {
    return null;
  }
}

function runHook(project, name, ...args) {
  const result = spawnSync("/bin/bash", [join(root, "hooks", name), ...args], {
    cwd: project,
    env: { ...process.env, CLAUDE_PROJECT_DIR: project },
    encoding: "utf8",
  });
  if (result.error) return textResult(`Could not run ${name}: ${result.error.message}`, true);
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim() || "(no output)";
  return textResult(output, result.status !== 0);
}

function auditHistory(project) {
  const ledger = join(project, "spec", "CAPABILITY-HISTORY.json");
  if (!existsSync(ledger)) return textResult("未验证：没有 capability history ledger");
  const result = spawnSync("python3", [join(root, "hooks", "capability-history.py"), "audit", ledger, project], {
    cwd: project,
    encoding: "utf8",
  });
  if (result.error) return textResult(`Could not run history audit: ${result.error.message}`, true);
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim() || "(no output)";
  return textResult(output, result.status !== 0);
}

function callTool(name, arguments_) {
  const args = arguments_ && typeof arguments_ === "object" ? arguments_ : {};
  if (name === "write_operation") return textResult(`${args.operation ?? "requested operation"}: this MCP server will not execute writes. Use Claude Code or Codex and give explicit confirmation.`, true);
  const project = projectRoot(args.project);
  if (!project) return textResult("project must be an absolute path to an existing Git repository.", true);
  if (name === "phase") return runHook(project, "phase-guard.sh");
  if (name === "verify") return runHook(project, "verify-artifacts.sh");
  if (name === "verify_history") return runHook(project, "verify-history.sh", project);
  if (name === "audit_history") return auditHistory(project);
  return textResult(`Unknown tool: ${name}`, true);
}

function handle(request) {
  const id = request.id;
  const method = request.method;
  if (typeof method !== "string") return { jsonrpc: "2.0", id, error: { code: -32600, message: "Invalid Request" } };
  if (!("id" in request)) return null;
  if (method === "initialize") return { jsonrpc: "2.0", id, result: { protocolVersion: request.params?.protocolVersion ?? "2025-06-18", capabilities: { tools: {} }, serverInfo } };
  if (method === "tools/list") return { jsonrpc: "2.0", id, result: { tools } };
  if (method === "tools/call") return { jsonrpc: "2.0", id, result: callTool(request.params?.name, request.params?.arguments) };
  return { jsonrpc: "2.0", id, error: { code: -32601, message: "Method not found" } };
}

createInterface({ input: process.stdin, crlfDelay: Infinity }).on("line", (line) => {
  try {
    const request = JSON.parse(line);
    if (!request || typeof request !== "object" || Array.isArray(request)) throw new Error("invalid");
    const response = handle(request);
    if (response) send(response);
  } catch {
    send({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } });
  }
});
