import http from "node:http";
import https from "node:https";
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

const DEFAULT_BASE_URL = "http://127.0.0.1:8080";
const DEFAULT_BUILD_TIMEOUT_MS = 15 * 60 * 1000;
const DEFAULT_BUILD_BAT = "";
const DEFAULT_PROJECT_FILE = "";
const DEFAULT_BUILD_TARGET = "";
const DEFAULT_BUILD_PLATFORM = "Win64";
const DEFAULT_BUILD_CONFIGURATION = "Development";
const DEFAULT_EDITOR_EXE = "";
const DEFAULT_EDITOR_WINDOW_TITLES = [
  "Unreal Editor"
];
const DEFAULT_LIVE_COMPILE_SETTLE_MS = 3000;
const DEBUG_LOG_PATH = process.env.USERPROFILE
  ? path.join(process.env.USERPROFILE, 'openclaw-unreal-agentbridge-debug.log')
  : null;

function debugLog(event, payload = {}) {
  try {
    if (!DEBUG_LOG_PATH) return;
    fs.appendFileSync(DEBUG_LOG_PATH, JSON.stringify({ ts: new Date().toISOString(), event, ...payload }) + "\n", 'utf8');
  } catch {
    // ignore debug logging failures
  }
}

function pluginBaseUrl(api) {
  return api?.pluginConfig?.baseUrl || DEFAULT_BASE_URL;
}

function pluginBuildBat(api) {
  return api?.pluginConfig?.buildBat || process.env.UNREAL_BUILD_BAT || DEFAULT_BUILD_BAT;
}

function pluginProjectFile(api) {
  return api?.pluginConfig?.projectFile || process.env.UNREAL_PROJECT_FILE || DEFAULT_PROJECT_FILE;
}

function pluginDefaultBuildTarget(api) {
  return api?.pluginConfig?.defaultBuildTarget || process.env.UNREAL_BUILD_TARGET || DEFAULT_BUILD_TARGET;
}

function pluginDefaultBuildPlatform(api) {
  return api?.pluginConfig?.defaultBuildPlatform || process.env.UNREAL_BUILD_PLATFORM || DEFAULT_BUILD_PLATFORM;
}

function pluginDefaultBuildConfiguration(api) {
  return api?.pluginConfig?.defaultBuildConfiguration || process.env.UNREAL_BUILD_CONFIGURATION || DEFAULT_BUILD_CONFIGURATION;
}

function deriveEditorExeFromBuildBat(buildBat) {
  if (!buildBat) return DEFAULT_EDITOR_EXE;
  const normalized = path.normalize(buildBat);
  const suffix = path.normalize("Engine\\Build\\BatchFiles\\Build.bat");
  if (normalized.toLowerCase().endsWith(suffix.toLowerCase())) {
    return path.join(normalized.slice(0, normalized.length - suffix.length), "Engine", "Binaries", "Win64", "UnrealEditor.exe");
  }
  return DEFAULT_EDITOR_EXE;
}

function pluginEditorExe(api) {
  return api?.pluginConfig?.editorExe || process.env.UNREAL_EDITOR_EXE || deriveEditorExeFromBuildBat(pluginBuildBat(api));
}

function pluginEditorWindowTitles(api) {
  const configured = api?.pluginConfig?.editorWindowTitles;
  return Array.isArray(configured) && configured.length > 0 ? configured : DEFAULT_EDITOR_WINDOW_TITLES;
}

function pluginLiveCompileSettleMs(api) {
  return api?.pluginConfig?.liveCompileSettleMs || DEFAULT_LIVE_COMPILE_SETTLE_MS;
}

function requestJson(baseUrl, path, { method = "GET", body } = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, baseUrl);
    const transport = url.protocol === "https:" ? https : http;
    const payload = body ? JSON.stringify(body) : null;
    const req = transport.request(
      url,
      {
        method,
        headers: payload
          ? {
              "Content-Type": "application/json",
              "Content-Length": Buffer.byteLength(payload)
            }
          : undefined
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)));
        res.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          let parsed;
          try {
            parsed = text ? JSON.parse(text) : null;
          } catch {
            parsed = text;
          }
          resolve({
            ok: (res.statusCode || 500) >= 200 && (res.statusCode || 500) < 300,
            status: res.statusCode || 500,
            body: parsed
          });
        });
      }
    );
    req.on("error", reject);
    req.setTimeout(5000, () => req.destroy(new Error(`request timed out: ${url.toString()}`)));
    if (payload) req.write(payload);
    req.end();
  });
}

function quotePowerShellSingle(value) {
  return "'" + String(value).replace(/'/g, "''") + "'";
}

function runPowerShell(script, timeoutMs = 20000) {
  return new Promise((resolve, reject) => {
    const child = spawn("powershell.exe", [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      script
    ], {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error("powershell_timeout_" + timeoutMs));
    }, timeoutMs);

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });

    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });

    child.on("close", (code, signal) => {
      clearTimeout(timer);
      resolve({ ok: code === 0, exitCode: code, signal, stdout, stderr });
    });
  });
}

async function countProcesses(imageName) {
  if (process.platform === "win32") {
    const script = [
      " = Get-Process -Name",
      quotePowerShellSingle(path.parse(imageName).name),
      "-ErrorAction SilentlyContinue",
      "| Measure-Object | Select-Object -ExpandProperty Count"
    ].join(" ");
    const result = await runPowerShell(script, 10000);
    if (!result.ok) return 0;
    const value = Number.parseInt(String(result.stdout || "").trim(), 10);
    return Number.isFinite(value) ? value : 0;
  }

  return await new Promise((resolve) => {
    const child = spawn('tasklist', ['/FI', 'IMAGENAME eq ' + imageName, '/FO', 'CSV', '/NH'], {
      stdio: ['ignore', 'pipe', 'ignore'],
      windowsHide: true,
    });

    let stdout = '';
    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });
    child.on('error', () => resolve(0));
    child.on('close', () => {
      const lines = stdout
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean)
        .filter((line) => !line.startsWith('INFO:'));
      resolve(lines.length);
    });
  });
}

async function waitForProcessCount(imageName, minimumCount, timeoutMs = 15000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    const count = await countProcesses(imageName);

    if (count >= minimumCount) {
      return count;
    }

    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  return 0;
}

function asToolResult(payload) {
  return {
    content: [
      {
        type: "text",
        text: JSON.stringify(payload, null, 2)
      }
    ]
  };
}

function buildPath(path, query) {
  if (!query || Object.keys(query).length === 0) return path;
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === null || value === "") continue;
    params.set(key, String(value));
  }
  const queryString = params.toString();
  return queryString ? `${path}?${queryString}` : path;
}

function extractBuildErrors(text) {
  const lines = text.split(/\r?\n/);
  const matches = [];
  const seen = new Set();
  const patterns = [/\berror C\d+:/i, /\berror LNK\d+:/i, /BUILD FAILED/i, /error:/i];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (!patterns.some((pattern) => pattern.test(trimmed))) continue;
    if (seen.has(trimmed)) continue;
    seen.add(trimmed);
    matches.push(trimmed);
    if (matches.length >= 50) break;
  }
  return matches;
}

function tailLines(text, count = 80) {
  const lines = text.split(/\r?\n/).filter((line) => line.length > 0);
  return lines.slice(-count);
}

function quoteCmdArg(value) {
  const text = String(value ?? "");
  if (!/[\s"]/u.test(text)) return text;
  return `"${text.replace(/"/g, '""')}"`;
}

function runBuild(buildBat, args, timeoutMs) {
  if (!buildBat || !fs.existsSync(buildBat)) {
    return Promise.resolve({
      ok: false,
      timedOut: false,
      exitCode: null,
      signal: null,
      stdout: "",
      stderr: "",
      combined: "",
      tail: [],
      errors: [`UE Build.bat not configured or not found: ${buildBat || "<empty>"}`]
    });
  }
  return new Promise((resolve, reject) => {
    const cmdExe = process.env.ComSpec || "cmd.exe";
    const child = spawn(cmdExe, ["/d", "/c", "call", buildBat, ...args], {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";
    let timedOut = false;

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill();
    }, timeoutMs);

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });

    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });

    child.on("close", (code, signal) => {
      clearTimeout(timer);
      const combined = [stdout, stderr].filter(Boolean).join("\n");
      resolve({
        ok: code === 0 && !timedOut,
        timedOut,
        exitCode: code,
        signal,
        stdout,
        stderr,
        combined,
        tail: tailLines(combined),
        errors: extractBuildErrors(combined)
      });
    });
  });
}

async function launchEditor(editorExe, projectFile, extraArgs = []) {
  debugLog('launchEditor.start', { editorExe, projectFile, extraArgs });
  if (!fs.existsSync(editorExe)) {
    return {
      ok: false,
      error: "editor_exe_not_found",
      editorExe
    };
  }

  if (!fs.existsSync(projectFile)) {
    return {
      ok: false,
      error: "project_file_not_found",
      projectFile
    };
  }

  const args = [projectFile, ...extraArgs];

  if (process.platform === "win32") {
    const beforeCount = await countProcesses('UnrealEditor.exe');
    const argListLiteral = args.map(quotePowerShellSingle).join(", ");
    const psCommand = [
      "$process = Start-Process",
      "-FilePath",
      quotePowerShellSingle(editorExe),
      "-ArgumentList",
      "@(" + argListLiteral + ")",
      "-WorkingDirectory",
      quotePowerShellSingle(path.dirname(projectFile)),
      "-PassThru",
      "-WindowStyle Normal",
      "; Write-Output $process.Id"
    ].join(" ");

    debugLog('launchEditor.win32.command', { psCommand, beforeCount, args });
    const launched = await runPowerShell(psCommand, 20000);
    debugLog('launchEditor.win32.launched', { launched });
    const pidText = launched.stdout.trim().split(/\r?\n/).filter(Boolean).pop() || "";
    const pid = Number.parseInt(pidText, 10);
    const expectedCount = beforeCount > 0 ? beforeCount : 1;

    debugLog('launchEditor.win32.pid', { pidText, pid });
    if (!launched.ok) {
      return {
        ok: false,
        error: "editor_launch_command_failed",
        editorExe,
        projectFile,
        args,
        launcher: "powershell-start-process",
        exitCode: launched.exitCode,
        stderr: tailLines(launched.stderr || "", 40)
      };
    }

    await new Promise((resolve) => setTimeout(resolve, 2000));
    const detectedCount = await countProcesses('UnrealEditor.exe');
    debugLog('launchEditor.win32.detected', { detectedCount, expectedCount });

    debugLog('launchEditor.win32.success', { pid, detectedCount, expectedCount });
    return {
      ok: true,
      editorExe,
      projectFile,
      args,
      pid: Number.isFinite(pid) ? pid : null,
      launcher: "powershell-start-process",
      existingEditorCountBeforeLaunch: beforeCount,
      detectedEditorCountAfterLaunch: detectedCount,
      expectedEditorCountAfterLaunch: expectedCount
    };
  }

  return await new Promise((resolve, reject) => {
    const child = spawn(editorExe, args, {
      detached: true,
      stdio: "ignore",
      windowsHide: false
    });
    child.once("error", reject);
    child.once("spawn", () => {
      child.unref();
      resolve({
        ok: true,
        editorExe,
        projectFile,
        args,
        pid: child.pid
      });
    });
  });
}

function runLiveCompile(windowTitles, settleMs) {
  return new Promise((resolve, reject) => {
    const windowTitlesJson = JSON.stringify(windowTitles);
    const script = [
      "$ErrorActionPreference = 'Stop'",
      "Add-Type -AssemblyName System.Windows.Forms",
      "Add-Type @'",
      "using System;",
      "using System.Runtime.InteropServices;",
      "public static class OpenClawUser32 {",
      "  [DllImport(\"user32.dll\")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);",
      "  [DllImport(\"user32.dll\")] public static extern bool SetForegroundWindow(IntPtr hWnd);",
      "}",
      "'@",
      "$titles = @()",
      "if ($env:OPENCLAW_WINDOW_TITLES_JSON) {",
      "  $titles = @($env:OPENCLAW_WINDOW_TITLES_JSON | ConvertFrom-Json)",
      "}",
      "$match = $null",
      "$allWindows = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 }",
      "foreach ($title in $titles) {",
      "  $match = $allWindows | Where-Object { $_.MainWindowTitle -eq $title } | Select-Object -First 1",
      "  if ($match) { break }",
      "}",
      "if (-not $match) {",
      "  foreach ($title in $titles) {",
      "    $escaped = [Regex]::Escape($title)",
      "    $match = $allWindows | Where-Object { $_.MainWindowTitle -match $escaped } | Select-Object -First 1",
      "    if ($match) { break }",
      "  }",
      "}",
      "if (-not $match) {",
      "  $match = Get-Process -Name UnrealEditor -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1",
      "}",
      "if (-not $match) {",
      "  @{ ok = $false; error = 'window_not_found'; triedTitles = $titles; visibleWindows = ($allWindows | Select-Object -First 10 ProcessName,Id,MainWindowTitle) } | ConvertTo-Json -Compress",
      "  exit 0",
      "}",
      "[OpenClawUser32]::ShowWindowAsync($match.MainWindowHandle, 9) | Out-Null",
      "Start-Sleep -Milliseconds 250",
      "$foregroundOk = [OpenClawUser32]::SetForegroundWindow($match.MainWindowHandle)",
      "Start-Sleep -Milliseconds 500",
      "[System.Windows.Forms.SendKeys]::SendWait('^%{F11}')",
      `Start-Sleep -Milliseconds ${settleMs}`,
      `@{ ok = $true; activatedTitle = $match.MainWindowTitle; processName = $match.ProcessName; processId = $match.Id; foregroundOk = $foregroundOk; hotkey = 'Ctrl+Alt+F11'; settleMs = ${settleMs}; triedTitles = $titles } | ConvertTo-Json -Compress`
    ].join("\n");

    const child = spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], {
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        OPENCLAW_WINDOW_TITLES_JSON: windowTitlesJson
      }
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });

    child.on("error", (error) => reject(error));
    child.on("close", (code) => {
      const trimmed = stdout.trim();
      let parsed = null;
      if (trimmed) {
        try {
          parsed = JSON.parse(trimmed);
        } catch {
          parsed = null;
        }
      }
      resolve({
        ok: code === 0 && parsed?.ok === true,
        exitCode: code,
        stdout,
        stderr,
        result: parsed || {
          ok: false,
          error: "invalid_live_compile_output",
          rawStdout: trimmed
        }
      });
    });
  });
}

const EmptyParams = {
  type: "object",
  additionalProperties: false,
  properties: {}
};

const Vector3Params = {
  type: "object",
  additionalProperties: false,
  required: ["x", "y", "z"],
  properties: {
    x: { type: "number" },
    y: { type: "number" },
    z: { type: "number" }
  }
};

const RotatorParams = {
  type: "object",
  additionalProperties: false,
  required: ["pitch", "yaw", "roll"],
  properties: {
    pitch: { type: "number" },
    yaw: { type: "number" },
    roll: { type: "number" }
  }
};

export default definePluginEntry({
  id: "unreal-agentbridge",
  name: "Unreal AgentBridge",
  description: "Registers Unreal Engine AgentBridge HTTP tools for OpenClaw.",
  configSchema: {
    type: "object",
    additionalProperties: false,
    properties: {
      baseUrl: {
        type: "string",
        description: "Base URL for the Unreal AgentBridge HTTP server."
      },
      buildBat: {
        type: "string",
        description: "Absolute path to Unreal Engine Build.bat."
      },
      projectFile: {
        type: "string",
        description: "Absolute path to the Unreal .uproject file."
      },
      editorExe: {
        type: "string",
        description: "Absolute path to UnrealEditor.exe."
      },
      defaultBuildTarget: {
        type: "string",
        description: "Default Unreal build target name."
      },
      defaultBuildPlatform: {
        type: "string",
        description: "Default Unreal build platform."
      },
      defaultBuildConfiguration: {
        type: "string",
        description: "Default Unreal build configuration."
      },
      editorWindowTitles: {
        type: "array",
        items: { type: "string" },
        description: "Ordered Unreal Editor window titles to try when triggering Live Coding."
      },
      liveCompileSettleMs: {
        type: "integer",
        minimum: 0,
        description: "How long to wait after sending the Live Coding hotkey."
      }
    }
  },
  register(api) {
    api.logger.info?.("unreal-agentbridge: register()");

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_health session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_health",
          label: "UE Health",
          description: "Check whether the Unreal AgentBridge plugin is reachable.",
          parameters: EmptyParams,
          async execute() {
            const result = await requestJson(pluginBaseUrl(api), "/api/health");
            return asToolResult(result);
          }
        };
      },
      { name: "ue_health" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_list_actors session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_list_actors",
          label: "UE List Actors",
          description: "List actors in the current Unreal editor level.",
          parameters: EmptyParams,
          async execute() {
            const result = await requestJson(pluginBaseUrl(api), "/api/actors/list");
            return asToolResult(result);
          }
        };
      },
      { name: "ue_list_actors" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_spawn_actor session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_spawn_actor",
          label: "UE Spawn Actor",
          description: "Spawn an actor in the current Unreal editor level through AgentBridge.",
          parameters: {
            type: "object",
            additionalProperties: false,
            required: ["class", "location"],
            properties: {
              class: { type: "string" },
              name: { type: "string" },
              location: Vector3Params,
              rotation: RotatorParams,
              properties: {
                type: "object",
                additionalProperties: true
              }
            }
          },
          async execute(_id, params) {
            const payload = {
              class: params.class,
              name: params.name || "",
              location: params.location,
              rotation: params.rotation || { pitch: 0, yaw: 0, roll: 0 },
              properties: params.properties || undefined
            };
            const result = await requestJson(pluginBaseUrl(api), "/api/actors/spawn", {
              method: "POST",
              body: payload
            });
            return asToolResult(result);
          }
        };
      },
      { name: "ue_spawn_actor" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_delete_actor session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_delete_actor",
          label: "UE Delete Actor",
          description: "Delete an actor in the current Unreal editor level by name or label.",
          parameters: {
            type: "object",
            additionalProperties: false,
            required: ["name"],
            properties: {
              name: { type: "string" }
            }
          },
          async execute(_id, params) {
            const result = await requestJson(pluginBaseUrl(api), "/api/actors/delete", {
              method: "DELETE",
              body: { name: params.name }
            });
            return asToolResult(result);
          }
        };
      },
      { name: "ue_delete_actor" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_modify_actor session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_modify_actor",
          label: "UE Modify Actor",
          description: "Modify an existing actor's transform in the current Unreal editor level.",
          parameters: {
            type: "object",
            additionalProperties: false,
            required: ["name"],
            properties: {
              name: { type: "string" },
              location: Vector3Params,
              rotation: RotatorParams,
              properties: {
                type: "object",
                additionalProperties: true
              },
              scale: Vector3Params
            }
          },
          async execute(_id, params) {
            const payload = { name: params.name };
            if (params.location) payload.location = params.location;
            if (params.rotation) payload.rotation = params.rotation;
            if (params.scale) payload.scale = params.scale;
            const result = await requestJson(pluginBaseUrl(api), "/api/actors/modify", {
              method: "PUT",
              body: payload
            });
            return asToolResult(result);
          }
        };
      },
      { name: "ue_modify_actor" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_pie_start session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_pie_start",
          label: "UE PIE Start",
          description: "Start Play In Editor in Unreal.",
          parameters: EmptyParams,
          async execute() {
            const result = await requestJson(pluginBaseUrl(api), "/api/pie/start", {
              method: "POST"
            });
            return asToolResult(result);
          }
        };
      },
      { name: "ue_pie_start" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_pie_stop session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_pie_stop",
          label: "UE PIE Stop",
          description: "Stop Play In Editor in Unreal.",
          parameters: EmptyParams,
          async execute() {
            const result = await requestJson(pluginBaseUrl(api), "/api/pie/stop", {
              method: "POST"
            });
            return asToolResult(result);
          }
        };
      },
      { name: "ue_pie_stop" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_pie_status session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_pie_status",
          label: "UE PIE Status",
          description: "Check whether Play In Editor is running.",
          parameters: EmptyParams,
          async execute() {
            const result = await requestJson(pluginBaseUrl(api), "/api/pie/status");
            return asToolResult(result);
          }
        };
      },
      { name: "ue_pie_status" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_world_query session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_world_query",
          label: "UE World Query",
          description: "Inspect the current Unreal editor world summary.",
          parameters: EmptyParams,
          async execute() {
            const result = await requestJson(pluginBaseUrl(api), "/api/world/query");
            return asToolResult(result);
          }
        };
      },
      { name: "ue_world_query" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_logs_tail session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_logs_tail",
          label: "UE Logs Tail",
          description: "Read recent Unreal logs, optionally filtered.",
          parameters: {
            type: "object",
            additionalProperties: false,
            properties: {
              count: { type: "integer", minimum: 1 },
              filter: { type: "string" }
            }
          },
          async execute(_id, params) {
            const result = await requestJson(
              pluginBaseUrl(api),
              buildPath("/api/logs/tail", {
                count: params?.count,
                filter: params?.filter
              })
            );
            return asToolResult(result);
          }
        };
      },
      { name: "ue_logs_tail" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_test_status session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_test_status",
          label: "UE Test Status",
          description: "Get Unreal test harness status from the current PIE session.",
          parameters: EmptyParams,
          async execute() {
            const result = await requestJson(pluginBaseUrl(api), "/api/test/status");
            return asToolResult(result);
          }
        };
      },
      { name: "ue_test_status" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_test_results session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_test_results",
          label: "UE Test Results",
          description: "Get Unreal test harness result details from the current PIE session.",
          parameters: EmptyParams,
          async execute() {
            const result = await requestJson(pluginBaseUrl(api), "/api/test/results");
            return asToolResult(result);
          }
        };
      },
      { name: "ue_test_results" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_editor_open session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_editor_open",
          label: "UE Editor Open",
          description: "Launch Unreal Editor for the configured project so AgentBridge becomes available after a CLI build.",
          parameters: {
            type: "object",
            additionalProperties: false,
            properties: {
              editorExe: { type: "string" },
              projectFile: { type: "string" },
              extraArgs: {
                type: "array",
                items: { type: "string" }
              }
            }
          },
          async execute(_id, params) {
            const editorExe = params?.editorExe || pluginEditorExe(api);
            const projectFile = params?.projectFile || pluginProjectFile(api);
            const extraArgs = Array.isArray(params?.extraArgs) ? params.extraArgs : [];
            const result = await launchEditor(editorExe, projectFile, extraArgs);
            return asToolResult(result);
          }
        };
      },
      { name: "ue_editor_open" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_live_compile session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_live_compile",
          label: "UE Live Compile",
          description: "Trigger Unreal Editor Live Coding by focusing the editor window and sending Ctrl+Alt+F11.",
          parameters: {
            type: "object",
            additionalProperties: false,
            properties: {
              windowTitles: {
                type: "array",
                items: { type: "string" }
              },
              settleMs: { type: "integer", minimum: 0 }
            }
          },
          async execute(_id, params) {
            const windowTitles = Array.isArray(params?.windowTitles) && params.windowTitles.length > 0
              ? params.windowTitles
              : pluginEditorWindowTitles(api);
            const settleMs = params?.settleMs ?? pluginLiveCompileSettleMs(api);
            const result = await runLiveCompile(windowTitles, settleMs);
            return asToolResult({
              ok: result.ok,
              exitCode: result.exitCode,
              windowTitles,
              settleMs,
              liveCompile: result.result,
              stderr: result.stderr ? tailLines(result.stderr, 40) : []
            });
          }
        };
      },
      { name: "ue_live_compile" }
    );

    api.registerTool(
      (ctx) => {
        api.logger.info?.(
          `unreal-agentbridge: factory ue_build session=${ctx?.sessionKey ?? "unknown"} agent=${ctx?.agentId ?? "unknown"}`
        );
        return {
          name: "ue_build",
          label: "UE Build",
          description: "Build the Unreal editor target through Build.bat before reopening the editor for verification.",
          parameters: {
            type: "object",
            additionalProperties: false,
            properties: {
              target: { type: "string" },
              platform: { type: "string" },
              configuration: { type: "string" },
              projectFile: { type: "string" },
              timeoutMs: { type: "integer", minimum: 1000 },
              fromMsBuild: { type: "boolean" },
              waitMutex: { type: "boolean" }
            }
          },
          async execute(_id, params) {
            const buildBat = pluginBuildBat(api);
            const projectFile = params?.projectFile || pluginProjectFile(api);
            const target = params?.target || pluginDefaultBuildTarget(api);
            const platform = params?.platform || pluginDefaultBuildPlatform(api);
            const configuration = params?.configuration || pluginDefaultBuildConfiguration(api);
            const timeoutMs = params?.timeoutMs || DEFAULT_BUILD_TIMEOUT_MS;
            const fromMsBuild = params?.fromMsBuild ?? true;
            const waitMutex = params?.waitMutex ?? true;
            if (!projectFile || !fs.existsSync(projectFile)) {
              return asToolResult({
                ok: false,
                summary: "project_file_not_configured",
                error: `Unreal project file not configured or not found: ${projectFile || "<empty>"}`
              });
            }
            if (!target) {
              return asToolResult({
                ok: false,
                summary: "build_target_not_configured",
                error: "defaultBuildTarget or UNREAL_BUILD_TARGET must be configured."
              });
            }
            const args = [target, platform, configuration, `-Project=${projectFile}`];
            if (waitMutex) args.push("-WaitMutex");
            if (fromMsBuild) args.push("-FromMsBuild");

            const result = await runBuild(buildBat, args, timeoutMs);
            return asToolResult({
              ok: result.ok,
              timedOut: result.timedOut,
              exitCode: result.exitCode,
              signal: result.signal,
              command: {
                buildBat,
                args
              },
              summary: result.ok ? "build_succeeded" : result.timedOut ? "build_timed_out" : "build_failed",
              errorCount: result.errors.length,
              errors: result.errors,
              outputTail: result.tail
            });
          }
        };
      },
      { name: "ue_build" }
    );
  }
});
