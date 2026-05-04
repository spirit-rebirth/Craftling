#!/usr/bin/env node
/**
 * ue-run-fullloop.mjs — Shell-safe wrapper for invoking the ue-full-loop lobster workflow.
 *
 * Why this exists:
 *   When OpenClaw's exec tool runs `lobster --args-json '{...}'` through PowerShell or cmd.exe,
 *   the JSON double quotes get mangled by shell escaping. This wrapper accepts simple positional
 *   arguments (no JSON, no special characters) and calls lobster programmatically via spawn,
 *   bypassing shell interpretation entirely.
 *
 * Usage:
 *   node ue-run-fullloop.mjs <class> [actor_name] [loc_x] [loc_y] [loc_z]
 *   node ue-run-fullloop.mjs resume <token> approve
 *   node ue-run-fullloop.mjs resume <token> reject
 *
 * Examples:
 *   node ue-run-fullloop.mjs TestLobster12
 *   node ue-run-fullloop.mjs TestLobster12 AgentTestActor 0 0 100
 *   node ue-run-fullloop.mjs resume eyJwcm90... approve
 */

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const WORKFLOW_FILE = join(__dirname, "ue-full-loop.lobster");

const args = process.argv.slice(2);
const firstArg = (args[0] ?? "").replace(/^-+/, "");  // strip any leading dashes

// ── Dispatch ────────────────────────────────────────────────────────────────

if (firstArg === "resume") {
  handleResume();
} else {
  handleRun();
}

// ── Resume mode ─────────────────────────────────────────────────────────────

function handleResume() {
  const token = args[1];
  // Accept: "approve", "--approve", "yes", "reject", "--reject", "no"
  const decisionRaw = (args[2] ?? "").replace(/^-+/, "").toLowerCase();
  const approveMap = { approve: "yes", yes: "yes", y: "yes", reject: "no", no: "no", n: "no" };
  const decision = approveMap[decisionRaw];

  if (!token || !decision) {
    console.error("Usage: node ue-run-fullloop.mjs resume <token> approve|reject");
    console.error("");
    console.error("Examples:");
    console.error("  node ue-run-fullloop.mjs resume eyJwcm90... approve");
    console.error("  node ue-run-fullloop.mjs resume eyJwcm90... reject");
    process.exit(1);
  }

  runLobster(["resume", "--token", token, "--approve", decision]);
}

// ── Run mode ────────────────────────────────────────────────────────────────

function handleRun() {
  const className = args[0];
  const actorName = args[1] || "AgentTestActor";
  const locX = args[2] || "0";
  const locY = args[3] || "0";
  const locZ = args[4] || "100";

  if (!className) {
    console.error("Error: class name is required.");
    console.error("");
    console.error("Usage:");
    console.error("  node ue-run-fullloop.mjs <class> [actor_name] [loc_x] [loc_y] [loc_z]");
    console.error("  node ue-run-fullloop.mjs resume <token> approve|reject");
    console.error("");
    console.error("Examples:");
    console.error("  node ue-run-fullloop.mjs TestLobster12");
    console.error("  node ue-run-fullloop.mjs TestLobster12 AgentTestActor 100 200 300");
    process.exit(1);
  }

  const argsJson = JSON.stringify({
    class: className,
    actor_name: actorName,
    loc_x: locX,
    loc_y: locY,
    loc_z: locZ,
  });

  runLobster(["run", "--mode", "tool", "--file", WORKFLOW_FILE, "--args-json", argsJson]);
}

// ── Helpers ─────────────────────────────────────────────────────────────────

function runLobster(lobsterArgs) {
  // Call node directly with lobster's JS entrypoint.
  // This bypasses .cmd/.ps1 wrappers entirely, so the JSON argument
  // is passed as a clean argv element with no shell interpretation.
  const lobsterJs = join(
    process.env.APPDATA || "",
    "npm", "node_modules", "@clawdbot", "lobster", "bin", "lobster.js"
  );

  const child = spawn(process.execPath, [lobsterJs, ...lobsterArgs], {
    stdio: "inherit",
    env: { ...process.env, MSYS_NO_PATHCONV: "1", MSYS2_ARG_CONV_EXCL: "*" },
  });

  child.on("error", (err) => {
    console.error(`Failed to start lobster: ${err.message}`);
    process.exit(1);
  });

  child.on("close", (code) => {
    process.exit(code ?? 1);
  });
}
