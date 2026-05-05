import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import type { IncomingMessage, ServerResponse } from "node:http";
import { resolveOpenClawAgentDir } from "../agents/agent-paths.js";
import { listProfilesForProvider, upsertAuthProfile } from "../agents/auth-profiles/profiles.js";
import { ensureAuthProfileStore } from "../agents/auth-profiles/store.js";
import type { AuthProfileCredential } from "../agents/auth-profiles/types.js";
import { mutateConfigFile } from "../config/config.js";
import type { OpenClawConfig } from "../config/types.openclaw.js";
import { invalidateModelAuthStatusCache } from "../gateway/server-methods/models-auth-status.js";
import { openUrl } from "../infra/browser-open.js";
import { formatErrorMessage } from "../infra/errors.js";
import { loginOpenAICodexOAuth } from "../plugins/provider-openai-codex-oauth.js";
import { applyDefaultModel } from "../plugins/provider-auth-choice-helpers.js";
import { applyAuthProfileConfig } from "../plugins/provider-auth-helpers.js";
import { buildOauthProviderAuthResult } from "../plugin-sdk/provider-auth-result.js";
import { CRAFTLING_API_BASE_PATH } from "./routes.js";

const OPENAI_CODEX_PROVIDER_ID = "openai-codex";
const OPENAI_CODEX_DEFAULT_MODEL = "openai-codex/gpt-5.4";
const UNREAL_AGENTBRIDGE_PLUGIN_ID = "unreal-agentbridge";
const DEFAULT_AGENTBRIDGE_BASE_URL = "http://127.0.0.1:8080";
const DEFAULT_BUILD_PLATFORM = "Win64";
const DEFAULT_BUILD_CONFIGURATION = "Development";
const MAX_JSON_BODY_BYTES = 64 * 1024;

type JsonObject = Record<string, unknown>;
type CodexOAuthJobStatus = "starting" | "waiting_for_browser" | "succeeded" | "failed";
type CodexOAuthJob = {
  id: string;
  status: CodexOAuthJobStatus;
  startedAt: number;
  authUrl?: string;
  browserOpened?: boolean;
  profile?: {
    profileId: string;
    email?: string;
    displayName?: string;
  };
  defaultModel?: string;
  error?: string;
  promise: Promise<void>;
};

let codexOAuthJob: CodexOAuthJob | null = null;

function sendJson(res: ServerResponse, status: number, body: unknown) {
  res.statusCode = status;
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "content-type");
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(body));
}

function sendMethodNotAllowed(res: ServerResponse, allowed: string) {
  res.statusCode = 405;
  res.setHeader("Allow", allowed);
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify({ ok: false, error: "method_not_allowed" }));
}

async function readJsonBody(req: IncomingMessage): Promise<JsonObject> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += buffer.length;
    if (total > MAX_JSON_BODY_BYTES) {
      throw new Error("request body too large");
    }
    chunks.push(buffer);
  }
  const raw = Buffer.concat(chunks).toString("utf8").trim();
  if (!raw) {
    return {};
  }
  const parsed = JSON.parse(raw) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("JSON body must be an object");
  }
  return parsed as JsonObject;
}

function readStringField(body: JsonObject, name: string): string {
  const value = body[name];
  return typeof value === "string" ? value.trim() : "";
}

function ensureRecord(target: JsonObject, key: string): JsonObject {
  const existing = target[key];
  if (existing && typeof existing === "object" && !Array.isArray(existing)) {
    return existing as JsonObject;
  }
  const next: JsonObject = {};
  target[key] = next;
  return next;
}

function replaceConfigObject(target: OpenClawConfig, source: OpenClawConfig): void {
  for (const key of Object.keys(target) as Array<keyof OpenClawConfig>) {
    delete target[key];
  }
  Object.assign(target, source);
}

function pathExists(filePath: string): boolean {
  try {
    return fs.existsSync(filePath);
  } catch {
    return false;
  }
}

async function openUrlWithWindowsFallback(url: string): Promise<boolean> {
  if (process.platform === "win32") {
    const openedViaPowerShell = await new Promise<boolean>((resolve) => {
      const child = spawn(
        "powershell.exe",
        [
          "-NoProfile",
          "-ExecutionPolicy",
          "Bypass",
          "-Command",
          "Start-Process -FilePath $args[0]",
          url,
        ],
        {
          detached: true,
          stdio: "ignore",
          windowsHide: true,
        },
      );
      child.once("error", () => resolve(false));
      child.once("spawn", () => {
        child.unref();
        resolve(true);
      });
    });
    if (openedViaPowerShell) {
      return true;
    }
  }
  return await openUrl(url);
}

function isFile(filePath: string): boolean {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
}

function isDirectory(filePath: string): boolean {
  try {
    return fs.statSync(filePath).isDirectory();
  } catch {
    return false;
  }
}

function normalizeInputPath(input: string): string {
  return path.resolve(input.replace(/^"|"$/g, ""));
}

function deriveEditorTarget(projectFile: string): string {
  const projectDir = path.dirname(projectFile);
  const sourceDir = path.join(projectDir, "Source");
  const projectName = path.basename(projectFile, path.extname(projectFile));
  try {
    const sourceEntries = fs.readdirSync(sourceDir, { withFileTypes: true });
    const targetFiles = sourceEntries
      .filter((entry) => entry.isDirectory())
      .flatMap((entry) => {
        const dir = path.join(sourceDir, entry.name);
        try {
          return fs
            .readdirSync(dir, { withFileTypes: true })
            .filter((file) => file.isFile() && file.name.endsWith(".Target.cs"))
            .map((file) => file.name);
        } catch {
          return [];
        }
      });
    const editorTarget = targetFiles.find((file) => file.endsWith("Editor.Target.cs"));
    if (editorTarget) {
      return editorTarget.slice(0, -".Target.cs".length);
    }
  } catch {
    // Source targets are optional for the first settings save; fall back to the project name.
  }
  return `${projectName}Editor`;
}

function deriveUnrealSettings(body: JsonObject) {
  const engineRootInput = readStringField(body, "engineRoot");
  const projectFileInput = readStringField(body, "projectFile");
  const baseUrl = readStringField(body, "baseUrl") || DEFAULT_AGENTBRIDGE_BASE_URL;
  if (!engineRootInput || !projectFileInput) {
    return {
      ok: false as const,
      errors: ["Unreal Engine directory and .uproject file are required."],
    };
  }

  const engineRoot = normalizeInputPath(engineRootInput);
  const projectFile = normalizeInputPath(projectFileInput);
  const buildBat = path.join(engineRoot, "Engine", "Build", "BatchFiles", "Build.bat");
  const editorExe = path.join(engineRoot, "Engine", "Binaries", "Win64", "UnrealEditor.exe");
  const errors: string[] = [];
  if (!isDirectory(engineRoot)) {
    errors.push(`Unreal Engine directory not found: ${engineRoot}`);
  }
  if (!isFile(buildBat)) {
    errors.push(`Build.bat not found: ${buildBat}`);
  }
  if (!isFile(editorExe)) {
    errors.push(`UnrealEditor.exe not found: ${editorExe}`);
  }
  if (!isFile(projectFile) || path.extname(projectFile).toLowerCase() !== ".uproject") {
    errors.push(`Unreal .uproject file not found: ${projectFile}`);
  }
  if (errors.length > 0) {
    return { ok: false as const, errors };
  }

  const projectDir = path.dirname(projectFile);
  const defaultBuildTarget = deriveEditorTarget(projectFile);
  const agentBridgePluginDir = path.join(projectDir, "Plugins", "AgentBridge");
  return {
    ok: true as const,
    settings: {
      configured: true,
      engineRoot,
      projectDir,
      projectFile,
      buildBat,
      editorExe,
      baseUrl,
      defaultBuildTarget,
      defaultBuildPlatform: DEFAULT_BUILD_PLATFORM,
      defaultBuildConfiguration: DEFAULT_BUILD_CONFIGURATION,
      agentBridgePluginDir,
      agentBridgePluginPresent: pathExists(agentBridgePluginDir),
    },
  };
}

function getUnrealConfig(cfg: OpenClawConfig): JsonObject {
  const entries = cfg.plugins?.entries as JsonObject | undefined;
  const bridge = entries?.[UNREAL_AGENTBRIDGE_PLUGIN_ID] as JsonObject | undefined;
  const config = bridge?.config;
  return config && typeof config === "object" && !Array.isArray(config)
    ? (config as JsonObject)
    : {};
}

function summarizeSettings(cfg: OpenClawConfig) {
  const agentDir = resolveOpenClawAgentDir();
  const store = ensureAuthProfileStore(agentDir, { allowKeychainPrompt: false });
  const codexProfiles = listProfilesForProvider(store, OPENAI_CODEX_PROVIDER_ID).map((profileId) => {
    const credential = store.profiles[profileId];
    return {
      profileId,
      email: typeof credential?.email === "string" ? credential.email : undefined,
      displayName:
        typeof credential?.displayName === "string" ? credential.displayName : undefined,
      type: credential?.type,
    };
  });
  const unrealConfig = getUnrealConfig(cfg);
  const projectFile =
    typeof unrealConfig.projectFile === "string" ? unrealConfig.projectFile : "";
  const buildBat = typeof unrealConfig.buildBat === "string" ? unrealConfig.buildBat : "";
  const editorExe = typeof unrealConfig.editorExe === "string" ? unrealConfig.editorExe : "";
  const engineRoot =
    buildBat && buildBat.endsWith(path.join("Engine", "Build", "BatchFiles", "Build.bat"))
      ? buildBat.slice(0, -path.join("Engine", "Build", "BatchFiles", "Build.bat").length - 1)
      : "";
  return {
    ok: true,
    llm: {
      connected: codexProfiles.length > 0,
      provider: OPENAI_CODEX_PROVIDER_ID,
      defaultModel: cfg.agents?.defaults?.model,
      profiles: codexProfiles,
    },
    unreal: {
      configured: Boolean(projectFile && buildBat && editorExe),
      engineRoot,
      projectFile,
      projectDir: projectFile ? path.dirname(projectFile) : "",
      buildBat,
      editorExe,
      baseUrl:
        typeof unrealConfig.baseUrl === "string"
          ? unrealConfig.baseUrl
          : DEFAULT_AGENTBRIDGE_BASE_URL,
      defaultBuildTarget:
        typeof unrealConfig.defaultBuildTarget === "string"
          ? unrealConfig.defaultBuildTarget
          : "",
      defaultBuildPlatform:
        typeof unrealConfig.defaultBuildPlatform === "string"
          ? unrealConfig.defaultBuildPlatform
          : DEFAULT_BUILD_PLATFORM,
      defaultBuildConfiguration:
        typeof unrealConfig.defaultBuildConfiguration === "string"
          ? unrealConfig.defaultBuildConfiguration
          : DEFAULT_BUILD_CONFIGURATION,
    },
  };
}

async function saveUnrealSettings(body: JsonObject) {
  const derived = deriveUnrealSettings(body);
  if (!derived.ok) {
    return { ok: false, errors: derived.errors };
  }

  await mutateConfigFile({
    base: "runtime",
    mutate: (draft) => {
      const draftRecord = draft as JsonObject;
      const agents = ensureRecord(draftRecord, "agents");
      const defaults = ensureRecord(agents, "defaults");
      defaults.workspace = derived.settings.projectDir;
      defaults.skipBootstrap = true;

      const plugins = ensureRecord(draftRecord, "plugins");
      const entries = ensureRecord(plugins, "entries");
      const bridge = ensureRecord(entries, UNREAL_AGENTBRIDGE_PLUGIN_ID);
      bridge.enabled = true;
      bridge.config = {
        ...(bridge.config && typeof bridge.config === "object" && !Array.isArray(bridge.config)
          ? (bridge.config as JsonObject)
          : {}),
        baseUrl: derived.settings.baseUrl,
        buildBat: derived.settings.buildBat,
        projectFile: derived.settings.projectFile,
        defaultBuildTarget: derived.settings.defaultBuildTarget,
        defaultBuildPlatform: derived.settings.defaultBuildPlatform,
        defaultBuildConfiguration: derived.settings.defaultBuildConfiguration,
        editorExe: derived.settings.editorExe,
      };
    },
  });

  return { ok: true, unreal: derived.settings };
}

function createHttpOAuthPrompter() {
  return {
    intro: async () => undefined,
    outro: async () => undefined,
    note: async () => undefined,
    select: async () => {
      throw new Error("OAuth select prompts are not supported in Craftling settings.");
    },
    multiselect: async () => {
      throw new Error("OAuth multiselect prompts are not supported in Craftling settings.");
    },
    text: async () =>
      await new Promise<string>(() => {
        // The Flutter settings UI has no stdin-like prompt. Keep the OAuth
        // callback server alive so a manually opened URL can still complete.
      }),
    confirm: async () => true,
    progress: () => ({
      update: () => undefined,
      stop: () => undefined,
    }),
  };
}

function summarizeCodexOAuthJob(job: CodexOAuthJob | null) {
  if (!job) {
    return { running: false, status: "idle" };
  }
  return {
    running: job.status === "starting" || job.status === "waiting_for_browser",
    id: job.id,
    status: job.status,
    authUrl: job.authUrl,
    browserOpened: job.browserOpened,
    profile: job.profile,
    defaultModel: job.defaultModel,
    error: job.error,
  };
}

async function persistCodexCredentials(creds: Awaited<ReturnType<typeof loginOpenAICodexOAuth>>) {
  if (!creds) {
    throw new Error("OAuth cancelled.");
  }
  const result = buildOauthProviderAuthResult({
    providerId: OPENAI_CODEX_PROVIDER_ID,
    defaultModel: OPENAI_CODEX_DEFAULT_MODEL,
    access: creds.access,
    refresh: creds.refresh,
    expires: creds.expires,
    email: typeof creds.email === "string" ? creds.email : undefined,
  });
  const profile = result.profiles[0];
  if (!profile) {
    throw new Error("OAuth profile missing.");
  }

  const agentDir = resolveOpenClawAgentDir();
  upsertAuthProfile({
    profileId: profile.profileId,
    credential: profile.credential as AuthProfileCredential,
    agentDir,
  });

  await mutateConfigFile({
    base: "runtime",
    mutate: (draft) => {
      const next = applyDefaultModel(
        applyAuthProfileConfig(draft, {
          profileId: profile.profileId,
          provider: profile.credential.provider,
          mode: "oauth",
          email: profile.credential.email,
          displayName: profile.credential.displayName,
        }),
        OPENAI_CODEX_DEFAULT_MODEL,
      );
      replaceConfigObject(draft, next);
    },
  });
  invalidateModelAuthStatusCache();

  return {
    profile: {
      profileId: profile.profileId,
      email: profile.credential.email,
      displayName: profile.credential.displayName,
    },
    defaultModel: OPENAI_CODEX_DEFAULT_MODEL,
  };
}

async function connectCodexOAuth() {
  let openedUrl = "";
  const creds = await loginOpenAICodexOAuth({
    prompter: createHttpOAuthPrompter(),
    runtime: {
      log: () => undefined,
      error: () => undefined,
      exit: (code: number) => {
        throw new Error(`exit ${code}`);
      },
    },
    isRemote: false,
    openUrl: async (url) => {
      openedUrl = url;
      await openUrlWithWindowsFallback(url);
    },
    localBrowserMessage: "Complete sign-in in browser...",
  });
  const persisted = await persistCodexCredentials(creds);
  return {
    ok: true,
    authUrl: openedUrl,
    ...persisted,
  };
}

async function startCodexOAuthJob() {
  if (
    codexOAuthJob &&
    (codexOAuthJob.status === "starting" || codexOAuthJob.status === "waiting_for_browser")
  ) {
    return summarizeCodexOAuthJob(codexOAuthJob);
  }

  let resolveAuthStarted!: () => void;
  const authStarted = new Promise<void>((resolve) => {
    resolveAuthStarted = resolve;
  });

  const job: CodexOAuthJob = {
    id: randomUUID(),
    status: "starting",
    startedAt: Date.now(),
    promise: Promise.resolve(),
  };
  codexOAuthJob = job;

  job.promise = (async () => {
    try {
      const creds = await loginOpenAICodexOAuth({
        prompter: createHttpOAuthPrompter(),
        runtime: {
          log: () => undefined,
          error: () => undefined,
          exit: (code: number) => {
            throw new Error(`exit ${code}`);
          },
        },
        isRemote: false,
        openUrl: async (url) => {
          job.authUrl = url;
          job.status = "waiting_for_browser";
          resolveAuthStarted();
          job.browserOpened = await openUrlWithWindowsFallback(url);
        },
        localBrowserMessage: "Complete sign-in in browser...",
      });
      const persisted = await persistCodexCredentials(creds);
      job.status = "succeeded";
      job.profile = persisted.profile;
      job.defaultModel = persisted.defaultModel;
    } catch (error) {
      job.status = "failed";
      job.error = formatErrorMessage(error);
      resolveAuthStarted();
    }
  })();

  await Promise.race([
    authStarted,
    new Promise<void>((resolve) => setTimeout(resolve, 10_000)),
  ]);
  return summarizeCodexOAuthJob(job);
}

export async function handleCraftlingSettingsHttpRequest(
  req: IncomingMessage,
  res: ServerResponse,
  config: OpenClawConfig,
): Promise<boolean> {
  const url = new URL(req.url ?? "/", "http://localhost");
  if (url.pathname !== CRAFTLING_API_BASE_PATH && !url.pathname.startsWith(`${CRAFTLING_API_BASE_PATH}/`)) {
    return false;
  }

  if ((req.method ?? "GET").toUpperCase() === "OPTIONS") {
    sendJson(res, 204, {});
    return true;
  }

  try {
    if (url.pathname === `${CRAFTLING_API_BASE_PATH}/settings`) {
      if ((req.method ?? "GET").toUpperCase() !== "GET") {
        sendMethodNotAllowed(res, "GET, OPTIONS");
        return true;
      }
      sendJson(res, 200, summarizeSettings(config));
      return true;
    }

    if (url.pathname === `${CRAFTLING_API_BASE_PATH}/settings/unreal`) {
      if ((req.method ?? "GET").toUpperCase() !== "POST") {
        sendMethodNotAllowed(res, "POST, OPTIONS");
        return true;
      }
      const body = await readJsonBody(req);
      const result = await saveUnrealSettings(body);
      sendJson(res, result.ok ? 200 : 400, result);
      return true;
    }

    if (url.pathname === `${CRAFTLING_API_BASE_PATH}/auth/codex`) {
      if ((req.method ?? "GET").toUpperCase() !== "POST") {
        sendMethodNotAllowed(res, "POST, OPTIONS");
        return true;
      }
      const result = await connectCodexOAuth();
      sendJson(res, result.ok ? 200 : 500, result);
      return true;
    }

    if (url.pathname === `${CRAFTLING_API_BASE_PATH}/auth/codex/start`) {
      if ((req.method ?? "GET").toUpperCase() !== "POST") {
        sendMethodNotAllowed(res, "POST, OPTIONS");
        return true;
      }
      const result = await startCodexOAuthJob();
      sendJson(res, 200, { ok: true, ...result });
      return true;
    }

    if (url.pathname === `${CRAFTLING_API_BASE_PATH}/auth/codex/status`) {
      if ((req.method ?? "GET").toUpperCase() !== "GET") {
        sendMethodNotAllowed(res, "GET, OPTIONS");
        return true;
      }
      sendJson(res, 200, { ok: true, ...summarizeCodexOAuthJob(codexOAuthJob) });
      return true;
    }

    sendJson(res, 404, { ok: false, error: "not_found" });
    return true;
  } catch (error) {
    sendJson(res, 500, {
      ok: false,
      error: "craftling_settings_error",
      message: formatErrorMessage(error),
    });
    return true;
  }
}
