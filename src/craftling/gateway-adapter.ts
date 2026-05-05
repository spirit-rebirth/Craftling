import { randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import type { WebSocket, WebSocketServer } from "ws";
import { APPROVALS_SCOPE, READ_SCOPE, WRITE_SCOPE } from "../gateway/method-scopes.js";
import { ErrorCodes, errorShape, PROTOCOL_VERSION } from "../gateway/protocol/index.js";
import { handleGatewayRequest } from "../gateway/server-methods.js";
import type {
  GatewayRequestContext,
  GatewayRequestHandlers,
} from "../gateway/server-methods/types.js";
import { loadSessionEntry } from "../gateway/session-utils.js";
import type { GatewayWsClient } from "../gateway/server/ws-types.js";
import { formatForLog } from "../gateway/ws-log.js";
import type { createSubsystemLogger } from "../logging/subsystem.js";
import { resolveRuntimeServiceVersion } from "../version.js";
import { CRAFTLING_WS_PATH } from "./routes.js";

export { CRAFTLING_WS_PATH };

type SubsystemLogger = ReturnType<typeof createSubsystemLogger>;

type CraftlingTaskMessage = {
  type: "task_message";
  taskId?: unknown;
  message?: unknown;
};

type CraftlingApprovalMessage = {
  type: "approval";
  taskId?: unknown;
  resumeToken?: unknown;
  approve?: unknown;
};

type CraftlingIncomingMessage = CraftlingTaskMessage | CraftlingApprovalMessage;

type CraftlingApprovalMethod =
  | "exec.approval.resolve"
  | "plugin.approval.resolve"
  | "lobster.resume";

type CraftlingStreamState = {
  lastRawTextBySession: Map<string, string>;
  lastVisibleTextBySession: Map<string, string>;
  streamedSessions: Set<string>;
  emittedApprovalTokens: Set<string>;
};

type CraftlingProgressWatcher = {
  progressFile: string;
  flush: () => void;
  stop: () => void;
};

function sendCraftling(socket: WebSocket, obj: Record<string, unknown>) {
  try {
    socket.send(JSON.stringify(obj));
  } catch {
    /* ignore */
  }
}

function normalizeTaskId(value: unknown): string {
  const raw = typeof value === "string" ? value.trim() : "";
  return raw || randomUUID();
}

function normalizeText(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function craftlingSessionKey(taskId: string): string {
  return `craftling:${taskId}`;
}

function safeFilePart(value: string): string {
  const safe = value.replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "");
  return safe.slice(0, 80) || randomUUID();
}

function progressFileForTask(taskId: string): string {
  return path.join(
    process.cwd(),
    ".craftling",
    "state",
    "ue-full-loop-progress",
    `${safeFilePart(taskId)}-${Date.now()}.jsonl`,
  ).replace(/\\/g, "/");
}

function extractMessageText(message: unknown): string | undefined {
  if (!message || typeof message !== "object") {
    return undefined;
  }
  const entry = message as Record<string, unknown>;
  if (typeof entry.text === "string") {
    return entry.text;
  }
  const content = entry.content;
  if (!Array.isArray(content)) {
    return undefined;
  }
  const parts: string[] = [];
  for (const item of content) {
    if (!item || typeof item !== "object") {
      continue;
    }
    const block = item as Record<string, unknown>;
    if (typeof block.text === "string") {
      parts.push(block.text);
    }
  }
  const text = parts.join("");
  return text || undefined;
}

function readRecord(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function readString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.map((item) => readString(item)).filter(Boolean);
}

function taskIdForSessionKey(
  sessionToTask: Map<string, string>,
  sessionKey: unknown,
): string | undefined {
  const key = readString(sessionKey);
  if (!key) {
    return undefined;
  }
  return sessionToTask.get(key);
}

function approvalToken(kind: "exec" | "plugin", id: string): string {
  return `${kind}:${id}`;
}

function lobsterApprovalToken(token: string): string {
  return `lobster:${token}`;
}

function parseApprovalToken(
  token: unknown,
): { kind: "exec" | "plugin" | "lobster"; id: string } | null {
  const raw = readString(token);
  const colon = raw.indexOf(":");
  if (colon <= 0 || colon === raw.length - 1) {
    return null;
  }
  const kind = raw.slice(0, colon);
  const id = raw.slice(colon + 1).trim();
  if ((kind === "exec" || kind === "plugin" || kind === "lobster") && id) {
    return { kind, id };
  }
  return null;
}

function requestSessionKey(request: Record<string, unknown>): string {
  const direct = readString(request.sessionKey);
  if (direct) {
    return direct;
  }
  const plan = readRecord(request.systemRunPlan);
  return readString(plan?.sessionKey);
}

function inferEvidenceKind(pathOrText: string): string {
  const lower = pathOrText.toLowerCase();
  if (/\.(png|jpe?g|webp|gif|bmp)$/i.test(lower)) {
    return "screenshot";
  }
  if (/\.(mp4|mov|webm|mkv)$/i.test(lower)) {
    return "video";
  }
  if (/\b(pass|passed|success|succeeded|ok|validat)/i.test(pathOrText)) {
    return "validation";
  }
  return "toolOutput";
}

function computeStreamDelta(params: {
  sessionId: string;
  text: string;
  streamState: CraftlingStreamState;
}): string {
  const visibleText = stripApprovalMarkersForDisplay(params.text);
  const previous = params.streamState.lastVisibleTextBySession.get(params.sessionId) ?? "";
  let delta: string;
  if (visibleText.startsWith(previous)) {
    delta = visibleText.slice(previous.length);
  } else {
    delta = visibleText;
  }
  params.streamState.lastRawTextBySession.set(params.sessionId, params.text);
  params.streamState.lastVisibleTextBySession.set(params.sessionId, visibleText);
  if (delta) {
    params.streamState.streamedSessions.add(params.sessionId);
  }
  return delta;
}

function findJsonObjectEnd(text: string, jsonStart: number): number | null {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = jsonStart; i < text.length; i += 1) {
    const char = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === "\"") {
        inString = false;
      }
      continue;
    }
    if (char === "\"") {
      inString = true;
      continue;
    }
    if (char === "{") {
      depth += 1;
    } else if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        return i + 1;
      }
    }
  }
  return null;
}

function stripApprovalMarkersForDisplay(text: string): string {
  const marker = "APPROVAL_REQUIRED_JSON:";
  let remaining = stripCraftlingAssistantProgressBlocks(text);
  let visible = "";

  while (remaining.length > 0) {
    const markerIndex = remaining.indexOf(marker);
    if (markerIndex < 0) {
      return visible + remaining;
    }

    visible += remaining.slice(0, markerIndex).trimEnd();
    const jsonStart = remaining.indexOf("{", markerIndex + marker.length);
    if (jsonStart < 0) {
      return visible;
    }

    const jsonEnd = findJsonObjectEnd(remaining, jsonStart);
    if (jsonEnd == null) {
      return visible;
    }

    remaining = remaining.slice(jsonEnd).replace(/^\s+/, "");
    if (visible && remaining && !/\s$/.test(visible) && !/^[\s.,;:!?)}\]]/.test(remaining)) {
      visible += "\n";
    }
  }

  return visible;
}

function stripCraftlingAssistantProgressBlocks(text: string): string {
  if (!text.includes("Skill: ue-full-loop")) {
    return text;
  }
  if (!text.includes("APPROVAL_REQUIRED_JSON:") && !text.includes("Stage: Approval")) {
    return text;
  }

  const lines = text.replace(/\r\n/g, "\n").split("\n");
  const kept: string[] = [];
  for (let i = 0; i < lines.length;) {
    if (lines[i]?.trimStart().startsWith("Stage:")) {
      const lookahead = lines.slice(i, Math.min(i + 4, lines.length));
      if (lookahead.some((line) => line.trim() === "Skill: ue-full-loop")) {
        i += 1;
        while (
          i < lines.length &&
          !lines[i]?.trimStart().startsWith("Stage:") &&
          !lines[i]?.trimStart().startsWith("APPROVAL_REQUIRED_JSON:")
        ) {
          i += 1;
        }
        continue;
      }
    }
    kept.push(lines[i] ?? "");
    i += 1;
  }

  return kept.join("\n").replace(/\n{3,}/g, "\n\n").trimStart();
}

function extractJsonObjectAfterMarker(text: string, marker: string): Record<string, unknown> | null {
  const markerIndex = text.lastIndexOf(marker);
  if (markerIndex < 0) {
    return null;
  }
  const jsonStart = text.indexOf("{", markerIndex + marker.length);
  if (jsonStart < 0) {
    return null;
  }
  const jsonEnd = findJsonObjectEnd(text, jsonStart);
  if (jsonEnd == null) {
    return null;
  }
  try {
    const parsed = JSON.parse(text.slice(jsonStart, jsonEnd));
    return readRecord(parsed) ?? null;
  } catch {
    return null;
  }
}

function approvalEventsFromText(params: {
  text: string;
  taskId: string;
  sessionId: string;
  approvalMethods: Map<string, CraftlingApprovalMethod>;
  streamState: CraftlingStreamState;
}): Record<string, unknown>[] {
  const parsed = extractJsonObjectAfterMarker(params.text, "APPROVAL_REQUIRED_JSON:");
  if (!parsed) {
    return [];
  }
  const resumeToken = readString(parsed.resumeToken);
  if (!resumeToken) {
    return [];
  }
  const token = lobsterApprovalToken(resumeToken);
  if (params.streamState.emittedApprovalTokens.has(token)) {
    return [];
  }
  params.streamState.emittedApprovalTokens.add(token);
  params.approvalMethods.set(token, "lobster.resume");
  const gate = readString(parsed.gate) || "Lobster Approval";
  const prompt = readString(parsed.prompt) || "Review and approve this workflow gate.";
  return [{
    type: "approval_required",
    taskId: params.taskId,
    sessionId: params.sessionId,
    message: `${gate}\n\n${prompt}`,
    resumeToken: token,
  }];
}

function localImageEvidenceFromText(params: {
  text: string;
  taskId: string;
  sessionId: string;
}): Record<string, unknown>[] {
  const normalizedText = params.text.replace(/\\\\/g, "\\");
  const matches = normalizedText.match(/[A-Za-z]:\\[^\r\n:*?"<>|]+?\.(?:png|jpe?g|webp|gif|bmp)/gi) ?? [];
  return Array.from(new Set(matches)).map((assetPath) => ({
    type: "evidence",
    taskId: params.taskId,
    sessionId: params.sessionId,
    evidenceId: `image:${params.sessionId}:${assetPath}`,
    kind: "screenshot",
    title: "Screenshot",
    text: assetPath,
    source: "OpenClaw",
    stage: "Visual Evidence",
    assetPath,
    timeAgo: "just now",
  }));
}

function toolEvidenceEvents(params: {
  taskId: string;
  sessionId: string;
  runId: string;
  data: Record<string, unknown>;
  payloadSeq?: unknown;
}): Record<string, unknown>[] {
  const phase = readString(params.data.phase);
  if (phase !== "start" && phase !== "end" && phase !== "error") {
    return [];
  }
  const toolName =
    readString(params.data.toolName) ||
    readString(params.data.tool) ||
    readString(params.data.name) ||
    readString(params.data.title) ||
    "Tool";
  const toolCallId = readString(params.data.toolCallId) || readString(params.payloadSeq) || toolName;
  const title =
    phase === "start"
      ? `${toolName} started`
      : phase === "error"
        ? `${toolName} failed`
        : `${toolName} completed`;
  const text =
    readString(params.data.summary) ||
    readString(params.data.error) ||
    readString(params.data.result) ||
    readString(params.data.title) ||
    title;
  return [{
    type: "evidence",
    taskId: params.taskId,
    sessionId: params.sessionId,
    evidenceId: `tool:${params.runId}:${toolCallId}:${phase}`,
    kind: phase === "error" ? "log" : toolName === "ue_build" && phase === "end" ? "validation" : "toolOutput",
    title,
    text,
    source: "OpenClaw Tool",
    stage: toolName,
    timeAgo: "just now",
  }];
}

function mediaEvidenceEvents(params: {
  taskId: string;
  sessionId: string;
  mediaUrls: string[];
  source: string;
  stage?: string;
}): Record<string, unknown>[] {
  return params.mediaUrls.map((mediaUrl) => ({
    type: "evidence",
    taskId: params.taskId,
    sessionId: params.sessionId,
    evidenceId: `media:${params.sessionId}:${mediaUrl}`,
    kind: inferEvidenceKind(mediaUrl),
    title: inferEvidenceKind(mediaUrl) === "screenshot" ? "Screenshot" : "Media Evidence",
    text: mediaUrl,
    source: params.source,
    stage: params.stage,
    assetPath: mediaUrl,
    timeAgo: "just now",
  }));
}

function progressEvidenceEvent(params: {
  taskId: string;
  sessionId: string;
  progress: Record<string, unknown>;
}): Record<string, unknown> {
  const id = readString(params.progress.id) || randomUUID();
  const stage = readString(params.progress.stage) || "UE Full Loop";
  const tool = readString(params.progress.tool) || "lobster";
  const text = readString(params.progress.text) || `${stage} progress updated.`;
  const screenshotPath =
    readString(params.progress.screenshotPath) ||
    readString(readRecord(params.progress.metadata)?.screenshotPath);
  const assetPath = screenshotPath || undefined;
  const evidenceText = screenshotPath && !text.includes(screenshotPath)
    ? `${text} ${screenshotPath}`
    : text;
  const kind = screenshotPath ? "screenshot" : inferEvidenceKind(evidenceText);

  return {
    type: "evidence",
    taskId: params.taskId,
    sessionId: params.sessionId,
    evidenceId: `ue-progress:${params.sessionId}:${id}`,
    kind,
    title: kind === "screenshot" ? "Screenshot" : `${stage}: ${tool}`,
    text: evidenceText,
    source: "UE Full Loop",
    stage,
    assetPath,
    timeAgo: "just now",
  };
}

function progressStreamDelta(progress: Record<string, unknown>): string {
  const stage = readString(progress.stage) || "UE Full Loop";
  const skill = readString(progress.skill) || "ue-full-loop";
  const tool = readString(progress.tool) || "lobster";
  const text = readString(progress.text) || `${stage} progress updated.`;
  return `\nStage: ${stage}\nSkill: ${skill}\nTool: ${tool}\n${text}\n`;
}

function startProgressWatcher(params: {
  socket: WebSocket;
  taskId: string;
  sessionId: string;
  progressFile: string;
  seenEvidenceIds: Set<string>;
  logGateway: SubsystemLogger;
  initialOffset?: "start" | "end";
}): CraftlingProgressWatcher {
  let offset = 0;
  if (params.initialOffset === "end") {
    try {
      offset = statSync(params.progressFile).size;
    } catch {
      offset = 0;
    }
  }
  let closed = false;

  const flush = () => {
    if (closed) {
      return;
    }
    let size = 0;
    try {
      size = statSync(params.progressFile).size;
    } catch {
      return;
    }
    if (size <= offset) {
      return;
    }

    try {
      const chunk = readFileSync(params.progressFile, "utf8").slice(offset);
      offset = size;
      for (const line of chunk.split(/\r?\n/)) {
        const trimmed = line.trim();
        if (!trimmed) {
          continue;
        }
        let progress: Record<string, unknown> | undefined;
        try {
          progress = readRecord(JSON.parse(trimmed));
        } catch {
          progress = undefined;
        }
        if (!progress) {
          continue;
        }
        const event = progressEvidenceEvent({
          taskId: params.taskId,
          sessionId: params.sessionId,
          progress,
        });
        const id = readString(event.evidenceId);
        if (id && params.seenEvidenceIds.has(id)) {
          continue;
        }
        if (id) {
          params.seenEvidenceIds.add(id);
        }
        sendCraftling(params.socket, {
          type: "stream",
          taskId: params.taskId,
          sessionId: params.sessionId,
          delta: progressStreamDelta(progress),
        });
        sendCraftling(params.socket, event);
      }
    } catch (err) {
      params.logGateway.warn(`craftling progress watcher failed: ${formatForLog(err)}`);
    }
  };

  const timer = setInterval(flush, 1000);
  timer.unref?.();
  return {
    progressFile: params.progressFile,
    flush,
    stop: () => {
      if (closed) {
        return;
      }
      flush();
      closed = true;
      clearInterval(timer);
    },
  };
}

function stopProgressWatcher(
  progressWatchers: Map<string, CraftlingProgressWatcher>,
  taskId: unknown,
  delayMs = 0,
) {
  const key = readString(taskId);
  const watcher = key ? progressWatchers.get(key) : undefined;
  if (!watcher) {
    return;
  }
  if (delayMs > 0) {
    setTimeout(() => {
      watcher.stop();
      progressWatchers.delete(key);
    }, delayMs).unref?.();
    return;
  }
  watcher.stop();
  progressWatchers.delete(key);
}

function ensureProgressWatcher(params: {
  socket: WebSocket;
  taskId: string;
  sessionId: string;
  progressFileByTask: Map<string, string>;
  progressWatchers: Map<string, CraftlingProgressWatcher>;
  seenEvidenceIds: Set<string>;
  logGateway: SubsystemLogger;
  initialOffset?: "start" | "end";
}) {
  const existing = params.progressWatchers.get(params.taskId);
  if (existing) {
    existing.flush();
    return;
  }
  const progressFile = params.progressFileByTask.get(params.taskId);
  if (!progressFile) {
    return;
  }
  params.progressWatchers.set(params.taskId, startProgressWatcher({
    socket: params.socket,
    taskId: params.taskId,
    sessionId: params.sessionId,
    progressFile,
    seenEvidenceIds: params.seenEvidenceIds,
    logGateway: params.logGateway,
    initialOffset: params.initialOffset,
  }));
}

function isTerminalCraftlingEvent(event: Record<string, unknown>): boolean {
  if (event.type === "error") {
    return true;
  }
  return event.type === "final" && readString(event.status) !== "in_progress";
}

function translateGatewayChatEvent(params: {
  frame: unknown;
  sessionToTask: Map<string, string>;
  approvalMethods: Map<string, CraftlingApprovalMethod>;
  streamState: CraftlingStreamState;
}): Record<string, unknown>[] {
  if (!params.frame || typeof params.frame !== "object") {
    return [];
  }
  const frame = params.frame as Record<string, unknown>;
  if (frame.type !== "event" || frame.event !== "chat") {
    return [];
  }
  const payload = frame.payload;
  if (!payload || typeof payload !== "object") {
    return [];
  }
  const chat = payload as Record<string, unknown>;
  const sessionKey = typeof chat.sessionKey === "string" ? chat.sessionKey : "";
  const taskId = params.sessionToTask.get(sessionKey);
  if (!taskId) {
    return [];
  }
  const sessionId = typeof chat.runId === "string" ? chat.runId : sessionKey;
  const messageText = extractMessageText(chat.message);
  if (chat.state === "delta") {
    const delta = computeStreamDelta({
      sessionId,
      text: messageText ?? "",
      streamState: params.streamState,
    });
    return [{
      type: "stream",
      taskId,
      sessionId,
      delta,
    }];
  }
  if (chat.state === "final") {
    const rawText = messageText ?? "";
    const text = stripApprovalMarkersForDisplay(rawText);
    const streamAlreadyDelivered = params.streamState.streamedSessions.has(sessionId);
    params.streamState.lastRawTextBySession.delete(sessionId);
    params.streamState.lastVisibleTextBySession.delete(sessionId);
    params.streamState.streamedSessions.delete(sessionId);
    const approvalEvents = approvalEventsFromText({
      text: rawText,
      taskId,
      sessionId,
      approvalMethods: params.approvalMethods,
      streamState: params.streamState,
    });
    const evidenceEvents = localImageEvidenceFromText({ text, taskId, sessionId });
    if (approvalEvents.length > 0) {
      return [...approvalEvents, ...evidenceEvents];
    }
    return [
      ...evidenceEvents,
      {
      type: "final",
      taskId,
      sessionId,
      message: text,
      ok: true,
      status: "completed",
      streamAlreadyDelivered,
    }];
  }
  if (chat.state === "aborted") {
    return [{
      type: "final",
      taskId,
      sessionId,
      message: messageText ?? "Request aborted.",
      ok: false,
      status: "aborted",
    }];
  }
  if (chat.state === "error") {
    return [{
      type: "error",
      taskId,
      sessionId,
      message:
        typeof chat.errorMessage === "string" && chat.errorMessage.trim()
          ? chat.errorMessage
          : "OpenClaw chat error.",
      ok: false,
      status: "failed",
    }];
  }
  return [];
}

function translateGatewayAgentEvent(params: {
  frame: unknown;
  sessionToTask: Map<string, string>;
  seenEvidenceIds: Set<string>;
  approvalMethods: Map<string, CraftlingApprovalMethod>;
  streamState: CraftlingStreamState;
}): Record<string, unknown>[] {
  const frame = readRecord(params.frame);
  if (!frame || frame.type !== "event") {
    return [];
  }
  const event = readString(frame.event);
  if (event !== "agent" && event !== "session.tool") {
    return [];
  }
  const payload = readRecord(frame.payload);
  if (!payload) {
    return [];
  }
  const sessionKey = readString(payload.sessionKey);
  const taskId = taskIdForSessionKey(params.sessionToTask, sessionKey);
  if (!taskId) {
    return [];
  }

  const runId = readString(payload.runId) || sessionKey;
  const data = readRecord(payload.data) ?? {};
  const stream = readString(payload.stream);
  const mediaUrls = readStringArray(data.mediaUrls);
  const events: Record<string, unknown>[] = [];

  if (stream === "assistant") {
    const rawText = readString(data.text);
    if (rawText) {
      const text = stripApprovalMarkersForDisplay(rawText);
      events.push(
        ...approvalEventsFromText({
          text: rawText,
          taskId,
          sessionId: runId,
          approvalMethods: params.approvalMethods,
          streamState: params.streamState,
        }),
        ...localImageEvidenceFromText({ text, taskId, sessionId: runId }),
      );
    }
  }

  if (mediaUrls.length > 0) {
    events.push(
      ...mediaEvidenceEvents({
        taskId,
        sessionId: runId,
        mediaUrls,
        source: event === "session.tool" ? "OpenClaw Tool" : "OpenClaw Assistant",
        stage: readString(data.phase) || stream || undefined,
      }),
    );
  }

  if (event === "session.tool" || stream === "tool" || stream === "item") {
    events.push(
      ...toolEvidenceEvents({
        taskId,
        sessionId: runId,
        runId,
        data,
        payloadSeq: payload.seq,
      }),
    );
  }

  return events.filter((eventPayload) => {
    const id = readString(eventPayload.evidenceId);
    if (!id) {
      return true;
    }
    if (params.seenEvidenceIds.has(id)) {
      return false;
    }
    params.seenEvidenceIds.add(id);
    return true;
  });
}

function translateGatewayApprovalEvent(params: {
  frame: unknown;
  sessionToTask: Map<string, string>;
  approvalMethods: Map<string, CraftlingApprovalMethod>;
}): Record<string, unknown>[] {
  const frame = readRecord(params.frame);
  if (!frame || frame.type !== "event") {
    return [];
  }
  const event = readString(frame.event);
  if (event !== "exec.approval.requested" && event !== "plugin.approval.requested") {
    return [];
  }
  const payload = readRecord(frame.payload);
  const request = readRecord(payload?.request);
  const id = readString(payload?.id);
  if (!payload || !request || !id) {
    return [];
  }

  const sessionKey = requestSessionKey(request);
  const taskId = taskIdForSessionKey(params.sessionToTask, sessionKey);
  if (!taskId) {
    return [];
  }

  const kind = event.startsWith("exec.") ? "exec" : "plugin";
  const token = approvalToken(kind, id);
  params.approvalMethods.set(
    token,
    kind === "exec" ? "exec.approval.resolve" : "plugin.approval.resolve",
  );

  const title =
    readString(request.title) ||
    readString(request.commandPreview) ||
    readString(request.command) ||
    "Approval Required";
  const description =
    readString(request.description) ||
    readString(request.command) ||
    "Review and approve this workflow gate.";

  return [{
    type: "approval_required",
    taskId,
    sessionId: sessionKey,
    message: `${title}\n\n${description}`,
    resumeToken: token,
  }];
}

function createGatewaySocketAdapter(params: {
  socket: WebSocket;
  sessionToTask: Map<string, string>;
  approvalMethods: Map<string, CraftlingApprovalMethod>;
  seenEvidenceIds: Set<string>;
  streamState: CraftlingStreamState;
  progressWatchers: Map<string, CraftlingProgressWatcher>;
}): WebSocket {
  const adapter = {
    get bufferedAmount() {
      return params.socket.bufferedAmount;
    },
    send(data: unknown) {
      const text = typeof data === "string" ? data : data?.toString?.();
      if (!text) {
        return;
      }
      try {
        const frame = JSON.parse(text);
        const translated = [
          ...translateGatewayChatEvent({
            frame,
            sessionToTask: params.sessionToTask,
            approvalMethods: params.approvalMethods,
            streamState: params.streamState,
          }),
          ...translateGatewayAgentEvent({
            frame,
            sessionToTask: params.sessionToTask,
            seenEvidenceIds: params.seenEvidenceIds,
            approvalMethods: params.approvalMethods,
            streamState: params.streamState,
          }),
          ...translateGatewayApprovalEvent({
            frame,
            sessionToTask: params.sessionToTask,
            approvalMethods: params.approvalMethods,
          }),
        ];
        for (const item of translated) {
          sendCraftling(params.socket, item);
          if (isTerminalCraftlingEvent(item)) {
            stopProgressWatcher(params.progressWatchers, item.taskId, 3000);
          }
        }
      } catch {
        /* ignore malformed upstream frames */
      }
    },
    close(code?: number, reason?: string) {
      params.socket.close(code, reason);
    },
  };
  return adapter as unknown as WebSocket;
}

export function attachCraftlingGatewayAdapter(params: {
  wss: WebSocketServer;
  clients: Set<GatewayWsClient>;
  context: GatewayRequestContext;
  extraHandlers: GatewayRequestHandlers;
  logGateway: SubsystemLogger;
}) {
  params.wss.on("connection", (socket) => {
    const connId = randomUUID();
    const sessionToTask = new Map<string, string>();
    const approvalMethods = new Map<string, CraftlingApprovalMethod>();
    const seenEvidenceIds = new Set<string>();
    const progressWatchers = new Map<string, CraftlingProgressWatcher>();
    const progressFileByTask = new Map<string, string>();
    const streamState: CraftlingStreamState = {
      lastRawTextBySession: new Map<string, string>(),
      lastVisibleTextBySession: new Map<string, string>(),
      streamedSessions: new Set<string>(),
      emittedApprovalTokens: new Set<string>(),
    };
    const gatewayClient: GatewayWsClient = {
      socket: createGatewaySocketAdapter({
        socket,
        sessionToTask,
        approvalMethods,
        seenEvidenceIds,
        streamState,
        progressWatchers,
      }),
      connId,
      usesSharedGatewayAuth: false,
      connect: {
        minProtocol: PROTOCOL_VERSION,
        maxProtocol: PROTOCOL_VERSION,
        role: "operator",
        scopes: [READ_SCOPE, WRITE_SCOPE, APPROVALS_SCOPE],
        client: {
          id: "gateway-client",
          displayName: "Craftling Gateway Adapter",
          mode: "backend",
          version: resolveRuntimeServiceVersion(process.env),
          platform: process.platform,
          instanceId: connId,
        },
      },
    };
    params.clients.add(gatewayClient);
    params.context.subscribeSessionEvents(connId);

    socket.once("close", () => {
      for (const watcher of progressWatchers.values()) {
        watcher.stop();
      }
      progressWatchers.clear();
      params.clients.delete(gatewayClient);
      params.context.unsubscribeAllSessionEvents(connId);
    });
    socket.once("error", (err) => {
      params.logGateway.warn(`craftling adapter websocket error: ${formatForLog(err)}`);
    });

    sendCraftling(socket, {
      type: "system",
      message: "Craftling adapter connected.",
    });

    socket.on("message", (data) => {
      let parsed: CraftlingIncomingMessage;
      try {
        parsed = JSON.parse(data.toString()) as CraftlingIncomingMessage;
      } catch {
        sendCraftling(socket, {
          type: "error",
          message: "Invalid Craftling adapter message.",
          ok: false,
          status: "failed",
        });
        return;
      }

      if (parsed.type === "approval") {
        const taskId = normalizeTaskId(parsed.taskId);
        const parsedToken = parseApprovalToken(parsed.resumeToken);
        const token = readString(parsed.resumeToken);
        const method = token ? approvalMethods.get(token) : undefined;
        if (!parsedToken || !method) {
          sendCraftling(socket, {
            type: "error",
            taskId,
            message: "Approval token is unknown or expired.",
            ok: false,
            status: "failed",
          });
          return;
        }

        if (parsedToken.kind === "lobster") {
          const approved = parsed.approve !== false;
          if (approved) {
            ensureProgressWatcher({
              socket,
              taskId,
              sessionId: loadSessionEntry(craftlingSessionKey(taskId)).canonicalKey,
              progressFileByTask,
              progressWatchers,
              seenEvidenceIds,
              logGateway: params.logGateway,
              initialOffset: "end",
            });
          }
          const req = {
            type: "req" as const,
            id: randomUUID(),
            method: "chat.send",
            params: {
              sessionKey: craftlingSessionKey(taskId),
              message: approved
                ? `The user approved the Lobster gate. Resume the registered lobster workflow now by calling the lobster tool exactly once with {"action":"resume","token":"${parsedToken.id}","approve":true,"cwd":"product/craftling/workspace"}. The cwd is required because the registered pipeline uses relative script paths.`
                : `The user rejected the Lobster gate. Do not resume the Lobster workflow. Report the workflow as rejected by the user.`,
              idempotencyKey: randomUUID(),
            },
          };
          void handleGatewayRequest({
            req,
            client: gatewayClient,
            context: params.context,
            extraHandlers: params.extraHandlers,
            isWebchatConnect: () => false,
            respond: (ok, _payload, error) => {
              sendCraftling(socket, ok
                ? {
                    type: "system",
                    taskId,
                    message: approved
                      ? "Approval sent. Resuming the Lobster workflow."
                      : "Rejection sent. The Lobster workflow will stop.",
                  }
                : {
                    type: "error",
                    taskId,
                    message: error?.message ?? "Approval failed.",
                    ok: false,
                    status: "failed",
                  });
            },
          }).catch((err) => {
            params.logGateway.error(`craftling adapter lobster approval failed: ${formatForLog(err)}`);
            sendCraftling(socket, {
              type: "error",
              taskId,
              message: errorShape(ErrorCodes.UNAVAILABLE, String(err)).message,
              ok: false,
              status: "failed",
            });
          });
          return;
        }

        const req = {
          type: "req" as const,
          id: randomUUID(),
          method,
          params: {
            id: parsedToken.id,
            decision: parsed.approve === false ? "deny" : "allow-once",
          },
        };

        void handleGatewayRequest({
          req,
          client: gatewayClient,
          context: params.context,
          extraHandlers: params.extraHandlers,
          isWebchatConnect: () => false,
          respond: (ok, _payload, error) => {
            if (ok) {
              sendCraftling(socket, {
                type: "system",
                taskId,
                message: "Approval sent. Resuming the workflow.",
              });
              return;
            }
            sendCraftling(socket, {
              type: "error",
              taskId,
              message: error?.message ?? "Approval failed.",
              ok: false,
              status: "failed",
            });
          },
        }).catch((err) => {
          params.logGateway.error(`craftling adapter approval failed: ${formatForLog(err)}`);
          sendCraftling(socket, {
            type: "error",
            taskId,
            message: errorShape(ErrorCodes.UNAVAILABLE, String(err)).message,
            ok: false,
            status: "failed",
          });
        });
        return;
      }

      if (parsed.type !== "task_message") {
        sendCraftling(socket, {
          type: "error",
          message: "Unsupported Craftling adapter message type.",
          ok: false,
          status: "failed",
        });
        return;
      }

      const taskId = normalizeTaskId(parsed.taskId);
      const message = normalizeText(parsed.message);
      if (!message) {
        sendCraftling(socket, {
          type: "error",
          taskId,
          message: "Task message is required.",
          ok: false,
          status: "failed",
        });
        return;
      }

      const sessionKey = craftlingSessionKey(taskId);
      const canonicalSessionKey = loadSessionEntry(sessionKey).canonicalKey;
      const progressFile = progressFileForTask(taskId);
      progressFileByTask.set(taskId, progressFile);
      try {
        mkdirSync(path.dirname(progressFile), { recursive: true });
      } catch {
        /* best effort; the UE workflow also creates the parent directory */
      }
      stopProgressWatcher(progressWatchers, taskId);
      progressWatchers.set(taskId, startProgressWatcher({
        socket,
        taskId,
        sessionId: canonicalSessionKey,
        progressFile,
        seenEvidenceIds,
        logGateway: params.logGateway,
      }));
      sessionToTask.set(sessionKey, taskId);
      sessionToTask.set(canonicalSessionKey, taskId);
      sendCraftling(socket, {
        type: "user",
        taskId,
        sessionId: canonicalSessionKey,
        message,
      });

      const req = {
        type: "req" as const,
        id: randomUUID(),
        method: "chat.send",
        params: {
          sessionKey,
          message: `Craftling routing note: If this is an Unreal implementation-and-verification task, use the ue-full-loop skill and hand off to the registered lobster tool after source edits. Do not call ue_build, ue_editor_open, ue_health, ue_spawn_actor, ue_pie_start, ue_pie_stop, or other direct UE tools yourself for a full-loop task. Runtime progress file path for this request: ${progressFile}. When expanding ue-full-loop.registered.pipeline.md, replace __PROGRESS_FILE__ with exactly this path. The registered pipeline uses relative script paths; call the lobster tool with cwd exactly "product/craftling/workspace" and never with an absolute cwd. Do not render the full Lobster progress list in normal messages because Craftling streams that progress from the progress file automatically.\n\nUser request:\n${message}`,
          idempotencyKey: randomUUID(),
        },
      };

      void handleGatewayRequest({
        req,
        client: gatewayClient,
        context: params.context,
        extraHandlers: params.extraHandlers,
        isWebchatConnect: () => false,
        respond: (ok, payload, error) => {
          if (ok) {
            const runId =
              payload && typeof payload === "object"
                ? (payload as Record<string, unknown>).runId
                : undefined;
            sendCraftling(socket, {
              type: "system",
              taskId,
              sessionId: typeof runId === "string" ? runId : sessionKey,
              message: "OpenClaw run started.",
            });
            return;
          }
          stopProgressWatcher(progressWatchers, taskId);
          sendCraftling(socket, {
            type: "error",
            taskId,
            sessionId: sessionKey,
            message: error?.message ?? "OpenClaw request failed.",
            ok: false,
            status: "failed",
          });
        },
      }).catch((err) => {
        params.logGateway.error(`craftling adapter request failed: ${formatForLog(err)}`);
        stopProgressWatcher(progressWatchers, taskId);
        sendCraftling(socket, {
          type: "error",
          taskId,
          sessionId: sessionKey,
          message: errorShape(ErrorCodes.UNAVAILABLE, String(err)).message,
          ok: false,
          status: "failed",
        });
      });
    });
  });
}
