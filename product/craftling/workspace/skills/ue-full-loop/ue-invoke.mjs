#!/usr/bin/env node
/**
 * ue-invoke.mjs - thin wrapper for calling OpenClaw UE tools from lobster steps
 *
 * Usage:
 *   node ue-invoke.mjs <toolName> [argsJson]
 *   node ue-invoke.mjs ue_spawn_actor --class <path> --name <label> --loc-x <x> --loc-y <y> --loc-z <z>
 *
 * Reads CLAWD_URL and CLAWD_TOKEN from env.
 * Exits 0 on success (inner ok:true), exits 1 on failure.
 * Prints the inner result as JSON to stdout.
 */

const tool = process.argv[2];
const rawArgs = process.argv.slice(3);

if (!tool) {
  console.error("Usage: node ue-invoke.mjs <toolName> [argsJson]");
  process.exit(1);
}

const url = process.env.CLAWD_URL;
const token = process.env.CLAWD_TOKEN;

if (!url) {
  console.error("CLAWD_URL is not set");
  process.exit(1);
}

function parseScalarArgs(argv) {
  const parsed = {};

  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    const value = argv[i + 1];

    if (!key?.startsWith("--") || value === undefined) {
      console.error(`Invalid flag arguments near: ${argv.slice(i).join(" ")}`);
      process.exit(1);
    }

    parsed[key.slice(2)] = value;
  }

  return parsed;
}

function buildToolArgs(toolName, argv) {
  if (argv.length === 0) {
    return {};
  }

  if (argv[0].startsWith("--")) {
    const flags = parseScalarArgs(argv);

    if (toolName === "ue_spawn_actor") {
      return {
        class: flags.class ?? "",
        name: flags.name ?? "AgentTestActor",
        location: {
          x: Number(flags["loc-x"] ?? 0),
          y: Number(flags["loc-y"] ?? 0),
          z: Number(flags["loc-z"] ?? 100),
        },
      };
    }

    return flags;
  }

  if (argv.length !== 1) {
    console.error(`Expected one JSON argument or flag pairs, got: ${argv.join(" ")}`);
    process.exit(1);
  }

  try {
    return JSON.parse(argv[0]);
  } catch (error) {
    console.error("Invalid argsJson:", error.message);
    process.exit(1);
  }
}

const toolArgs = buildToolArgs(tool, rawArgs);

const endpoint = `${url}/tools/invoke`;
const headers = { "Content-Type": "application/json" };
if (token) {
  headers.Authorization = `Bearer ${token}`;
}

try {
  const res = await fetch(endpoint, {
    method: "POST",
    headers,
    body: JSON.stringify({ tool, action: "execute", args: toolArgs }),
  });

  const text = await res.text();

  if (!res.ok) {
    console.error(`Gateway error ${res.status}: ${text.slice(0, 400)}`);
    process.exit(1);
  }

  const outer = JSON.parse(text);

  if (!outer.ok) {
    const msg = outer.error?.message ?? "unknown gateway error";
    console.error(`Tool error: ${msg}`);
    process.exit(1);
  }

  const contentText = outer.result?.content?.[0]?.text;
  if (!contentText) {
    console.log(JSON.stringify({ ok: true }));
    process.exit(0);
  }

  const inner = JSON.parse(contentText);
  console.log(JSON.stringify(inner));

  // Check for failure at multiple levels:
  // - inner.ok === false (tool-level failure)
  // - inner.body.status >= 400 (UE HTTP-level failure, e.g. class not found)
  // - inner.body.error (UE-side error message)
  if (inner.ok === false) {
    process.exit(1);
  }
  if (inner.body && (inner.body.status >= 400 || inner.body.error)) {
    console.error(`UE error (${inner.body.status ?? 'unknown'}): ${inner.body.error ?? 'unknown error'}`);
    process.exit(1);
  }

  process.exit(0);
} catch (error) {
  console.error("Invoke failed:", error.message);
  process.exit(1);
}
