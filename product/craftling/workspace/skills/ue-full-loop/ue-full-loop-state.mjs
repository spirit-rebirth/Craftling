#!/usr/bin/env node

import { setTimeout as delay } from 'node:timers/promises';
import os from 'node:os';
import path from 'node:path';
import { appendFileSync, mkdirSync, readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';

const stage = process.argv[2];
const rawArgs = process.argv.slice(3);

if (!stage) {
  console.error('Usage: node ue-full-loop-state.mjs <stage> [--flags]');
  process.exit(1);
}

const localConfig = loadLocalOpenClawConfig();
const CLAWD_URL = process.env.CLAWD_URL ?? localConfig.url;
const CLAWD_TOKEN = process.env.CLAWD_TOKEN ?? localConfig.token;
const PROGRESS_FILE = optionValue(rawArgs, 'progress-file') ?? process.env.UE_FULL_LOOP_PROGRESS_FILE ?? positionalProgressFile(rawArgs);


function loadLocalOpenClawConfig() {
  try {
    const configPath = process.env.OPENCLAW_CONFIG_PATH || path.join(os.homedir(), '.openclaw', 'openclaw.json');
    const raw = readFileSync(configPath, 'utf8');
    const config = JSON.parse(raw.replace(/^\uFEFF/, ''));
    const port = config?.gateway?.port ?? 18789;
    const token = config?.gateway?.auth?.token ?? '';
    return {
      url: `http://127.0.0.1:${port}`,
      token,
    };
  } catch {
    return {
      url: 'http://127.0.0.1:18789',
      token: '',
    };
  }
}
async function countUnrealEditorProcesses() {
  if (process.platform === 'win32') {
    return await new Promise((resolve) => {
      const child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', "(Get-Process -Name 'UnrealEditor' -ErrorAction SilentlyContinue | Measure-Object).Count"], {
        stdio: ['ignore', 'pipe', 'ignore'],
        windowsHide: true,
      });

      let stdout = '';
      child.stdout.on('data', (chunk) => {
        stdout += chunk.toString();
      });
      child.on('error', () => resolve(0));
      child.on('close', () => {
        const value = Number.parseInt(stdout.trim(), 10);
        resolve(Number.isFinite(value) ? value : 0);
      });
    });
  }

  return await new Promise((resolve) => {
    const child = spawn('tasklist', ['/FI', 'IMAGENAME eq UnrealEditor.exe', '/FO', 'CSV', '/NH'], {
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
function parseFlags(argv) {
  const flags = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    const value = argv[i + 1];
    if (!key?.startsWith('--') || value === undefined) {
      console.error(`Invalid flag arguments near: ${argv.slice(i).join(' ')}`);
      process.exit(1);
    }
    flags[key.slice(2)] = value;
  }
  return flags;
}

function optionValue(argv, name) {
  const flag = `--${name}`;
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === flag) {
      const value = argv[i + 1];
      return value && !value.startsWith('--') ? value : '';
    }
  }
  return null;
}

function positionalProgressFile(argv) {
  const candidate = argv.at(-1) ?? '';
  return /\.jsonl$/i.test(candidate) ? candidate : '';
}

async function readStdinText() {
  if (process.stdin.isTTY) return '';
  let data = '';
  process.stdin.setEncoding('utf8');
  for await (const chunk of process.stdin) data += chunk;
  return data.trim();
}

async function readState() {
  const raw = await readStdinText();
  if (!raw) return null;
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    console.error(`Invalid stdin JSON: ${error.message}`);
    process.exit(1);
  }
  if (Array.isArray(parsed)) {
    return parsed[0] ?? null;
  }
  return parsed;
}

class ToolInvocationError extends Error {
  constructor(tool, payload) {
    super(formatToolFailure(tool, payload));
    this.name = 'ToolInvocationError';
    this.tool = tool;
    this.payload = payload;
  }
}

function truncateText(value, limit = 600) {
  const text = String(value ?? '').replace(/\r\n/g, '\n').trim();
  if (text.length <= limit) {
    return text;
  }
  return `${text.slice(0, limit)} ... [truncated ${text.length - limit} chars]`;
}

function limitedStringArray(value, limit = 8) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((item) => truncateText(item, 500))
    .filter(Boolean)
    .slice(0, limit);
}

function formatCommand(command) {
  if (!command || typeof command !== 'object') {
    return '';
  }
  const buildBat = command.buildBat ? String(command.buildBat) : '';
  const args = Array.isArray(command.args) ? command.args.map((arg) => String(arg)).join(' ') : '';
  return [buildBat, args].filter(Boolean).join(' ');
}

function formatToolFailure(tool, payload) {
  const summary = payload?.summary || payload?.error || 'tool returned ok=false';
  const lines = [`${tool} failed: ${summary}`];
  const errors = limitedStringArray(payload?.errors, 10);
  if (errors.length > 0) {
    lines.push('Errors:');
    for (const error of errors) {
      lines.push(`- ${error}`);
    }
  }
  const command = formatCommand(payload?.command);
  if (command) {
    lines.push(`Command: ${command}`);
  }
  const tail = limitedStringArray(payload?.outputTail, 12);
  if (tail.length > 0) {
    lines.push('Output tail:');
    for (const line of tail) {
      lines.push(`- ${line}`);
    }
  }
  return lines.join('\n');
}

async function invokeTool(tool, args = {}) {
  if (!CLAWD_URL) {
    throw new Error('CLAWD_URL is not set');
  }
  if (!CLAWD_URL) {
    throw new Error('CLAWD_URL is not set');
  }
  const headers = { 'Content-Type': 'application/json' };
  if (CLAWD_TOKEN) headers.Authorization = `Bearer ${CLAWD_TOKEN}`;

  const res = await fetch(`${CLAWD_URL}/tools/invoke`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ tool, action: 'execute', args }),
  });

  const text = await res.text();
  if (!res.ok) {
    throw new Error(`Gateway error ${res.status}: ${text.slice(0, 400)}`);
  }

  let outer;
  try {
    outer = JSON.parse(text);
  } catch (error) {
    throw new Error(`Invalid gateway JSON: ${error.message}`);
  }

  if (!outer.ok) {
    throw new Error(outer.error?.message ?? 'unknown gateway error');
  }

  const contentText = outer.result?.content?.[0]?.text;
  if (!contentText) return { ok: true };

  let inner;
  try {
    inner = JSON.parse(contentText);
  } catch (error) {
    throw new Error(`Invalid tool JSON: ${error.message}`);
  }

  if (inner.ok === false) {
    throw new ToolInvocationError(tool, inner);
  }
  if (inner.body && (inner.body.status >= 400 || inner.body.error)) {
    throw new Error(`UE error (${inner.body.status ?? 'unknown'}): ${inner.body.error ?? 'unknown error'}`);
  }

  return inner;
}

function requireState(state) {
  if (!state || typeof state !== 'object') {
    console.error('Stage requires state on stdin');
    process.exit(1);
  }
  return state;
}

function printState(state) {
  console.log(JSON.stringify(state));
}

function addProgress(state, id, stageName, toolName, text, extra = {}) {
  if (!Array.isArray(state.progress)) {
    state.progress = [];
  }
  if (state.progress.some((item) => item?.id === id)) {
    return;
  }
  const item = {
    id,
    stage: stageName,
    skill: 'ue-full-loop',
    tool: toolName,
    text,
    ...extra,
  };
  state.progress.push(item);
  writeProgress(item);
}

function writeProgress(item) {
  if (!PROGRESS_FILE) {
    return;
  }
  try {
    mkdirSync(path.dirname(PROGRESS_FILE), { recursive: true });
    appendFileSync(PROGRESS_FILE, `${JSON.stringify(item)}\n`, 'utf8');
  } catch (error) {
    console.error(`[ue-full-loop-progress] failed to write ${PROGRESS_FILE}: ${error?.message ?? String(error)}`);
  }
}

function evidenceRoot() {
  if (process.env.EVIDENCE_ROOT) {
    return process.env.EVIDENCE_ROOT;
  }
  if (PROGRESS_FILE) {
    return path.join(path.dirname(path.dirname(PROGRESS_FILE)), '.craftling-evidence');
  }
  return path.join(process.cwd(), '.craftling-evidence');
}

function safeFilePart(value) {
  return String(value || 'task')
    .replace(/[^a-zA-Z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 64) || 'task';
}

function screenshotErrorSummary(error) {
  const rawMessage = String(error?.message ?? error ?? '').replace(/\r?\n/g, ' ').trim();
  if (!rawMessage) {
    return 'PIE window screenshot capture failed.';
  }
  if (rawMessage.includes('UnrealEditor window not found')) {
    return 'UnrealEditor window was not found for screenshot capture.';
  }
  if (rawMessage.includes('No visible UnrealEditor windows found')) {
    return 'No visible UnrealEditor window was available for screenshot capture.';
  }
  if (rawMessage.includes('screenshot capture timed out')) {
    return 'PIE window screenshot capture timed out.';
  }
  if (rawMessage.includes('GetWindowThreadProcessId')) {
    return 'PIE window screenshot capture could not enumerate Unreal windows.';
  }
  return rawMessage.slice(0, 180);
}
async function captureUnrealEditorWindow(outputPath) {
  if (process.platform !== 'win32') {
    throw new Error('window screenshot capture is only implemented for Windows');
  }

  const script = String.raw`
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Win32Capture {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
  public const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
try { [Win32Capture]::SetProcessDPIAware() | Out-Null } catch {}
$processes = Get-Process -Name 'UnrealEditor' -ErrorAction SilentlyContinue
if (-not $processes) { throw 'UnrealEditor window not found' }
$script:pidSet = @{}
foreach ($process in $processes) { $script:pidSet[[int]$process.Id] = $true }
$script:windows = New-Object System.Collections.Generic.List[object]
$callback = [Win32Capture+EnumWindowsProc]{
  param([IntPtr]$hWnd, [IntPtr]$lParam)
  if (-not [Win32Capture]::IsWindowVisible($hWnd)) { return $true }
  [uint32]$windowProcessId = 0
  [Win32Capture]::GetWindowThreadProcessId($hWnd, [ref]$windowProcessId) | Out-Null
  if (-not $script:pidSet.ContainsKey([int]$windowProcessId)) { return $true }
  $length = [Win32Capture]::GetWindowTextLength($hWnd)
  $buffer = New-Object System.Text.StringBuilder ([Math]::Max($length + 1, 256))
  [Win32Capture]::GetWindowText($hWnd, $buffer, $buffer.Capacity) | Out-Null
  $title = $buffer.ToString()
  $rect = New-Object Win32Capture+RECT
  [Win32Capture]::GetWindowRect($hWnd, [ref]$rect) | Out-Null
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -lt 80 -or $height -lt 80) { return $true }
  $script:windows.Add([pscustomobject]@{
    Handle = $hWnd
    Pid = [int]$windowProcessId
    Title = $title
    Left = $rect.Left
    Top = $rect.Top
    Width = $width
    Height = $height
    Area = $width * $height
  }) | Out-Null
  return $true
}
[Win32Capture]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
if ($script:windows.Count -eq 0) { throw 'No visible UnrealEditor windows found' }
$foreground = [Win32Capture]::GetForegroundWindow()
$selected = $script:windows |
  Where-Object { $_.Title -match '(?i)(PIE|Play In Editor|Standalone|Preview|Game)' } |
  Sort-Object @{ Expression = { if ($_.Handle -eq $foreground) { 0 } else { 1 } } }, @{ Expression = 'Area'; Descending = $true } |
  Select-Object -First 1
if (-not $selected) {
  $selected = $script:windows | Where-Object { $_.Handle -eq $foreground } | Select-Object -First 1
}
if (-not $selected) {
  $selected = $script:windows | Sort-Object Area -Descending | Select-Object -First 1
}
$hwnd = [IntPtr]$selected.Handle
$topmost = [IntPtr]::new(-1)
$notTopmost = [IntPtr]::new(-2)
$flags = 0x0001 -bor 0x0002 -bor 0x0040
$madeTopmost = $false
$graphics = $null
$bitmap = $null
try {
  [Win32Capture]::ShowWindow($hwnd, 9) | Out-Null
  [Win32Capture]::SetWindowPos($hwnd, $topmost, 0, 0, 0, 0, $flags) | Out-Null
  $madeTopmost = $true
  [Win32Capture]::SetForegroundWindow($hwnd) | Out-Null
  Start-Sleep -Milliseconds 700
  $rect = New-Object Win32Capture+RECT
  $dwmResult = -1
  try {
    $dwmResult = [Win32Capture]::DwmGetWindowAttribute($hwnd, [Win32Capture]::DWMWA_EXTENDED_FRAME_BOUNDS, [ref]$rect, [Runtime.InteropServices.Marshal]::SizeOf([Win32Capture+RECT]))
  } catch {}
  if ($dwmResult -ne 0) {
    [Win32Capture]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
  }
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -le 0 -or $height -le 0) { throw "Invalid UnrealEditor window bounds: $width x $height" }
  [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($env:CAPTURE_OUTPUT)) | Out-Null
  $bitmap = New-Object System.Drawing.Bitmap $width, $height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
  $bitmap.Save($env:CAPTURE_OUTPUT, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  if ($graphics) { $graphics.Dispose() }
  if ($bitmap) { $bitmap.Dispose() }
  if ($madeTopmost) { [Win32Capture]::SetWindowPos($hwnd, $notTopmost, 0, 0, 0, 0, 0x0001 -bor 0x0002) | Out-Null }
}
Write-Output $env:CAPTURE_OUTPUT
`;

  return await new Promise((resolve, reject) => {
    const child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], {
      env: { ...process.env, CAPTURE_OUTPUT: outputPath },
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    });

    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error('screenshot capture timed out'));
    }, 15000);

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });
    child.on('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) {
        resolve(stdout.trim() || outputPath);
        return;
      }
      reject(new Error(stderr.trim() || `PowerShell screenshot capture failed with code ${code}`));
    });
  });
}
async function main() {
  if (stage === 'init') {
    const state = {
      class: rawArgs[0] ?? '',
      actor_name: rawArgs[1] ?? 'AgentTestActor',
      loc_x: Number(rawArgs[2] ?? 0),
      loc_y: Number(rawArgs[3] ?? 0),
      loc_z: Number(rawArgs[4] ?? 100),
      flow: 'ue-full-loop-registered',
      started_at: new Date().toISOString(),
      progress: [],
    };
    addProgress(
      state,
      'analyze',
      'Analyze',
      'lobster',
      `Full-loop verification started for ${state.class}; preparing deterministic Unreal build and runtime validation.`
    );
    printState(state);
    return;
  }

  const state = requireState(await readState());

  if (stage === 'build') {
    try {
      state.build = await invokeTool('ue_build');
    } catch (error) {
      if (error instanceof ToolInvocationError) {
        state.build = { ok: false, ...error.payload };
        addProgress(
          state,
          'build-failed',
          'Build',
          error.tool,
          error.message,
          {
            ok: false,
            failure: true,
            summary: error.payload?.summary ?? error.payload?.error ?? 'tool_failed',
            errors: limitedStringArray(error.payload?.errors, 10),
            outputTail: limitedStringArray(error.payload?.outputTail, 12),
          }
        );
      }
      throw error;
    }
    addProgress(
      state,
      'build',
      'Build',
      'ue_build',
      'Unreal build completed successfully; continuing to editor launch and bridge validation.'
    );
    printState(state);
    return;
  }

  if (stage === 'open-editor') {
    try {
      const health = await invokeTool('ue_health');
      if (health?.ok === true && (health?.body?.status === 'ok' || health?.status === 'ok')) {
        state.open_editor = {
          ok: true,
          skipped: true,
          reason: 'bridge_already_available',
        };
        state.wait_bridge = health;
        addProgress(
          state,
          'open-editor',
          'Open Editor',
          'ue_health',
          'Editor bridge is already reachable; reusing the running editor session.'
        );
        printState(state);
        return;
      }
    } catch {
      // Bridge is not up yet; fall through to process-based guard.
    }

    const existingEditorCount = await countUnrealEditorProcesses();
    if (existingEditorCount > 0) {
      state.open_editor = {
        ok: true,
        skipped: true,
        reason: 'editor_process_already_running',
        existing_editor_count: existingEditorCount,
      };
      addProgress(
        state,
        'open-editor',
        'Open Editor',
        'ue_editor_open',
        'Unreal Editor is already running; continuing to bridge validation.'
      );
      printState(state);
      return;
    }

    state.open_editor = await invokeTool('ue_editor_open');
    if (state.open_editor?.ok !== true) {
      throw new Error('editor_launch_failed:' + JSON.stringify(state.open_editor));
    }
    addProgress(
      state,
      'open-editor',
      'Open Editor',
      'ue_editor_open',
      'Unreal Editor launch was requested successfully; waiting for AgentBridge.'
    );
    printState(state);
    return;
  }

  if (stage === 'wait-bridge') {
    for (let i = 0; i < 30; i++) {
      try {
        const health = await invokeTool('ue_health');
        if (health?.ok === true && (health?.body?.status === 'ok' || health?.status === 'ok')) {
          state.wait_bridge = health;
          addProgress(
            state,
            'wait-bridge',
            'Wait For Bridge',
            'ue_health',
            'AgentBridge is reachable and ready for editor-side validation.'
          );
          printState(state);
          return;
        }
      } catch {
        // keep polling
      }
      await delay(10000);
    }
    throw new Error('bridge_timeout_after_300s');
  }

  if (stage === 'validate-class') {
    if (!state.class || !String(state.class).trim()) {
      throw new Error('class argument is empty. You must pass the actor class name (e.g. TestLobster8 for ATestLobster8).');
    }
    state.validate_class = { ok: true, class: state.class };
    addProgress(
      state,
      'validate-class',
      'Verify Class Availability',
      'lobster',
      `Class argument '${state.class}' is present; proceeding to actor placement.`
    );
    printState(state);
    return;
  }

  if (stage === 'place-actor') {
    state.place_actor = await invokeTool('ue_spawn_actor', {
      class: state.class,
      name: state.actor_name,
      location: { x: state.loc_x, y: state.loc_y, z: state.loc_z },
    });
    addProgress(
      state,
      'place-actor',
      'Place In Level',
      'ue_spawn_actor',
      `Actor '${state.actor_name}' was placed in the level; waiting for human approval before PIE.`
    );
    printState(state);
    return;
  }

  if (stage === 'start-pie') {
    state.start_pie = await invokeTool('ue_pie_start');
    addProgress(
      state,
      'start-pie',
      'Start PIE',
      'ue_pie_start',
      'PIE start was requested; waiting for the play session to become observable.'
    );
    printState(state);
    return;
  }

  if (stage === 'wait-pie') {
    await delay(8000);
    state.wait_pie = { ok: true, waited_ms: 8000 };
    addProgress(
      state,
      'wait-pie',
      'Start PIE',
      'lobster',
      'PIE wait window completed; collecting runtime logs and test status.'
    );
    printState(state);
    return;
  }

  if (stage === 'capture-screenshot') {
    const screenshotDir = path.join(evidenceRoot(), 'screenshots');
    const screenshotPath = path.join(
      screenshotDir,
      `${safeFilePart(state.actor_name || state.class)}-pie-${Date.now()}.png`
    );
    try {
      const capturedPath = await captureUnrealEditorWindow(screenshotPath);
      state.screenshot = { ok: true, path: capturedPath };
      addProgress(
        state,
        'pie-screenshot',
        'Visual Evidence',
        'window_screenshot',
        `PIE window screenshot captured: ${capturedPath}`,
        { screenshotPath: capturedPath }
      );
    } catch (error) {
      state.screenshot = { ok: false, error: screenshotErrorSummary(error) };
      addProgress(
        state,
        'pie-screenshot-skipped',
        'Visual Evidence',
        'window_screenshot',
        `PIE screenshot was skipped: ${state.screenshot.error}`
      );
    }
    printState(state);
    return;
  }

  if (stage === 'collect-evidence') {
    try {
      state.logs = await invokeTool('ue_logs_tail', { count: 60 });
    } catch (error) {
      state.logs = { ok: false, error: String(error.message ?? error) };
    }
    try {
      state.test_status = await invokeTool('ue_test_status');
    } catch (error) {
      state.test_status = { ok: false, error: String(error.message ?? error) };
    }
    try {
      state.test_results = await invokeTool('ue_test_results');
    } catch (error) {
      state.test_results = { ok: false, error: String(error.message ?? error) };
    }
    const logs = state.logs?.body?.logs ?? [];
    const agentLog = Array.isArray(logs)
      ? logs.find((line) => String(line?.message ?? '').includes('[AgentTest]'))
      : null;
    addProgress(
      state,
      'collect-evidence',
      'Verify Runtime Behavior',
      'ue_logs_tail, ue_test_status, ue_test_results',
      agentLog
        ? `Runtime evidence collected; observed log: ${agentLog.message}`
        : 'Runtime evidence was collected from logs and test status.'
    );
    printState(state);
    return;
  }

  if (stage === 'stop-pie') {
    try {
      state.stop_pie = await invokeTool('ue_pie_stop');
    } catch (error) {
      state.stop_pie = { ok: false, error: String(error.message ?? error) };
    }
    addProgress(
      state,
      'stop-pie',
      'Stop PIE',
      'ue_pie_stop',
      'PIE cleanup was requested; waiting for human evaluation of the collected evidence.'
    );
    printState(state);
    return;
  }

  console.error(`Unknown stage: ${stage}`);
  process.exit(1);
}

main().catch((error) => {
  console.error(error.message ?? String(error));
  process.exit(1);
});
