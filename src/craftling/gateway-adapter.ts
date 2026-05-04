import { randomUUID } from "node:crypto";
import type { WebSocket, WebSocketServer } from "ws";
import { WRITE_SCOPE } from "../gateway/method-scopes.js";
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

function translateGatewayChatEvent(params: {
  frame: unknown;
  sessionToTask: Map<string, string>;
}): Record<string, unknown> | null {
  if (!params.frame || typeof params.frame !== "object") {
    return null;
  }
  const frame = params.frame as Record<string, unknown>;
  if (frame.type !== "event" || frame.event !== "chat") {
    return null;
  }
  const payload = frame.payload;
  if (!payload || typeof payload !== "object") {
    return null;
  }
  const chat = payload as Record<string, unknown>;
  const sessionKey = typeof chat.sessionKey === "string" ? chat.sessionKey : "";
  const taskId = params.sessionToTask.get(sessionKey);
  if (!taskId) {
    return null;
  }
  const sessionId = typeof chat.runId === "string" ? chat.runId : sessionKey;
  const messageText = extractMessageText(chat.message);
  if (chat.state === "delta") {
    return {
      type: "stream",
      taskId,
      sessionId,
      delta: messageText ?? "",
    };
  }
  if (chat.state === "final") {
    return {
      type: "final",
      taskId,
      sessionId,
      message: messageText ?? "",
      ok: true,
      status: "completed",
    };
  }
  if (chat.state === "aborted") {
    return {
      type: "final",
      taskId,
      sessionId,
      message: messageText ?? "Request aborted.",
      ok: false,
      status: "aborted",
    };
  }
  if (chat.state === "error") {
    return {
      type: "error",
      taskId,
      sessionId,
      message:
        typeof chat.errorMessage === "string" && chat.errorMessage.trim()
          ? chat.errorMessage
          : "OpenClaw chat error.",
      ok: false,
      status: "failed",
    };
  }
  return null;
}

function createGatewaySocketAdapter(params: {
  socket: WebSocket;
  sessionToTask: Map<string, string>;
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
        const translated = translateGatewayChatEvent({
          frame: JSON.parse(text),
          sessionToTask: params.sessionToTask,
        });
        if (translated) {
          sendCraftling(params.socket, translated);
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
    const gatewayClient: GatewayWsClient = {
      socket: createGatewaySocketAdapter({ socket, sessionToTask }),
      connId,
      usesSharedGatewayAuth: false,
      connect: {
        minProtocol: PROTOCOL_VERSION,
        maxProtocol: PROTOCOL_VERSION,
        role: "operator",
        scopes: [WRITE_SCOPE],
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

    socket.once("close", () => {
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
        sendCraftling(socket, {
          type: "error",
          taskId: normalizeTaskId(parsed.taskId),
          message: "Approval handling is not wired to OpenClaw yet.",
          ok: false,
          status: "failed",
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
          message,
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
