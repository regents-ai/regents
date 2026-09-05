import crypto from "node:crypto";
import fs from "node:fs";
import http, { type IncomingMessage, type ServerResponse } from "node:http";
import os from "node:os";

import qrcodeTerminal from "qrcode-terminal";

import { CliUsageError } from "../cli-usage-error.js";
import * as RegentRuntime from "../internal-runtime/index.js";
import type { RegentVoiceConfig } from "../internal-types/index.js";
import { getFlag, parseIntegerFlag, type ParsedCliArgs } from "../parse.js";

const MAX_BODY_BYTES = 1_048_576;
const OPENAI_CLIENT_SECRETS_URL = "https://api.openai.com/v1/realtime/client_secrets";
const OPENAI_CALLS_URL = "https://api.openai.com/v1/realtime/calls";
// Env var carrying the pairing token, matching the hosted sprite gateway's name.
const GATEWAY_TOKEN_ENV = "HERMES_VOICE_GATEWAY_TOKEN";

/**
 * The pairing token authenticates app->gateway requests. It is NOT the OpenAI
 * API key — it only gates access to the local gateway so nobody else on the
 * network can spend the user's key. Sourced from HERMES_VOICE_GATEWAY_TOKEN
 * when set, otherwise generated per serve session.
 */
export const resolvePairingToken = (): string => {
  const configured = process.env[GATEWAY_TOKEN_ENV]?.trim();
  return configured && configured.length > 0 ? configured : crypto.randomBytes(24).toString("base64url");
};

export interface VoicePairingPayload {
  baseUrl: string;
  token: string;
}

/** The QR payload the app scans: gateway base URL + required pairing token. */
export const buildPairingPayload = (baseUrl: string, token: string): VoicePairingPayload => ({
  baseUrl,
  token,
});

/** Constant-time compare of the bearer token on a request against the expected token. */
const isAuthorized = (req: IncomingMessage, token: string): boolean => {
  const header = req.headers.authorization;
  const value = Array.isArray(header) ? header[0] : header;
  if (!value || !value.startsWith("Bearer ")) {
    return false;
  }
  const provided = Buffer.from(value.slice("Bearer ".length));
  const expected = Buffer.from(token);
  return provided.length === expected.length && crypto.timingSafeEqual(provided, expected);
};

/** First non-internal IPv4 address, so the QR points at a phone-reachable URL. */
const firstLanAddress = (): string | null => {
  for (const addrs of Object.values(os.networkInterfaces())) {
    for (const addr of addrs ?? []) {
      if (addr.family === "IPv4" && !addr.internal) {
        return addr.address;
      }
    }
  }
  return null;
};

// Byte-parity with codex-regents-plugin/assets/voice-tools.json and the hosted
// sprite registry, so local and hosted agents advertise identical voice tools.
// Used as the fallback registry when the configured tool-registry file is absent.
const DEFAULT_VOICE_TOOLS: readonly VoiceTool[] = [
  { name: "hermes_turn", owner: "hermes", description: "Start hosted Hermes work.", requires_approval: false },
  { name: "hermes_steer", owner: "hermes", description: "Send guidance to active Hermes work.", requires_approval: false },
  { name: "hermes_cancel", owner: "hermes", description: "Stop active Hermes work.", requires_approval: false },
  { name: "hermes_status", owner: "hermes", description: "Read hosted Hermes voice status.", requires_approval: false },
  { name: "wait_for_user", owner: "hermes", description: "Pause hosted work until the user responds.", requires_approval: false },
  { name: "ios_status", owner: "ios", description: "Read local phone voice status.", requires_approval: false },
  { name: "ios_approval_request", owner: "ios", description: "Ask the phone owner to approve a sensitive action.", requires_approval: true },
  { name: "ios_tool_result", owner: "ios", description: "Return a phone-owned voice action result.", requires_approval: false },
];

interface VoiceTool {
  name: string;
  owner: "hermes" | "ios";
  description: string;
  requires_approval: boolean;
}

interface SessionRecord {
  id: string;
  agent_id: string;
  status: "active" | "ended";
  active_turn_id: string | null;
  created_at: string;
  expires_at: string;
}

const nowIso = (): string => new Date().toISOString();

const readTools = (voice: RegentVoiceConfig): VoiceTool[] => {
  try {
    const raw = fs.readFileSync(voice.toolRegistryPath, "utf8");
    const parsed = JSON.parse(raw) as unknown;
    if (Array.isArray(parsed)) {
      return parsed as VoiceTool[];
    }
  } catch {
    // Fall through to the bundled byte-parity registry.
  }
  return [...DEFAULT_VOICE_TOOLS];
};

const toolRegistryDigest = (voice: RegentVoiceConfig): string =>
  crypto.createHash("sha256").update(JSON.stringify(readTools(voice))).digest("hex");

export const resolveOpenaiApiKey = (voice: RegentVoiceConfig): string => {
  const value = process.env[voice.openaiApiKeyEnv];
  if (!value || !value.trim()) {
    // Hard cutover: one canonical source, no fallback. Fail fast and clearly.
    throw new CliUsageError({
      code: "voice_openai_key_missing",
      message:
        `The OpenAI API key is not set. 'regents voice serve' reads it from the ` +
        `environment variable named by services.voice.openaiApiKeyEnv ` +
        `('${voice.openaiApiKeyEnv}'). Export that variable with your OpenAI API key, then retry.`,
    });
  }
  return value.trim();
};

// The realtime session config the gateway binds to the ephemeral secret at mint
// time. GA shape: model, reasoning.effort, audio.input.transcription,
// audio.output.voice, tools. Ported from the hosted sprite gateway.
const buildSessionConfig = (
  voice: RegentVoiceConfig,
  input: { voice?: string; reasoning_effort?: string },
): Record<string, unknown> => {
  const tools = readTools(voice).map((tool) => ({
    type: "function",
    name: tool.name,
    description: tool.description,
    parameters: { type: "object", additionalProperties: true },
  }));

  return {
    session: {
      type: "realtime",
      model: voice.model,
      reasoning: { effort: input.reasoning_effort || voice.reasoningEffort },
      audio: {
        input: { transcription: { model: voice.transcriptionModel } },
        output: { voice: input.voice || voice.defaultVoice },
      },
      instructions:
        "You are the live voice layer for this user's Hermes agent. Answer ordinary " +
        "conversation directly. Use Hermes tools only for agent work, runtime state, " +
        "long-running work, terminal operations, or explicit requests to ask Hermes. Use " +
        "device tools only for device-owned actions. Never claim a tool result you do not " +
        "have. Money-affecting actions require explicit user approval and the prepared " +
        "wallet-action flow.",
      tools,
    },
  };
};

type MintResult =
  | { ok: true; value: string }
  | { ok: false; status: number; error: string };

const mintRealtimeSecret = async (
  voice: RegentVoiceConfig,
  apiKey: string,
  input: { voice?: string; reasoning_effort?: string },
  safetyIdentifier: string,
): Promise<MintResult> => {
  const response = await fetch(OPENAI_CLIENT_SECRETS_URL, {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
      "OpenAI-Safety-Identifier": safetyIdentifier || "",
    },
    body: JSON.stringify(buildSessionConfig(voice, input)),
  });

  const payload = (await response.json().catch(() => null)) as { value?: unknown } | null;
  if (!response.ok || !payload || typeof payload.value !== "string") {
    return { ok: false, status: 502, error: "provider_unavailable" };
  }

  return { ok: true, value: payload.value };
};

const sendJson = (res: ServerResponse, status: number, payload: unknown): void => {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(payload));
};

const readBody = async (req: IncomingMessage): Promise<Record<string, unknown>> => {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += buffer.byteLength;
    if (total > MAX_BODY_BYTES) {
      throw new Error("request_too_large");
    }
    chunks.push(buffer);
  }
  if (chunks.length === 0) {
    return {};
  }
  try {
    const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : {};
  } catch {
    throw new Error("bad_json");
  }
};

/**
 * Builds the local Hermes voice gateway HTTP server. Mirrors the hosted fly.io
 * sprite gateway's /hermes/voice/* surface so the Regents app's WebRTC client
 * is unchanged. The model (default gpt-realtime-2) is bound to the ephemeral
 * client_secret at mint time; the app POSTs its SDP offer to calls_url with
 * that secret. The API key is passed in already-resolved — this function never
 * reads or persists it beyond the OpenAI mint call.
 *
 * `pairingToken` gates every /hermes/voice/* route except healthz: a request
 * must carry `Authorization: Bearer <pairingToken>` or it is rejected 401
 * before any OpenAI mint. This is the app<->gateway pairing token, distinct
 * from the OpenAI API key.
 */
export function createVoiceGatewayServer(
  voice: RegentVoiceConfig,
  apiKey: string,
  pairingToken: string,
  agentId = process.env.REGENT_COMPANY_ID || process.env.REGENT_RUNTIME_ID || "local-hermes",
): http.Server {
  const sessions = new Map<string, SessionRecord>();

  const health = (): "ok" | "degraded" | "unavailable" => {
    if (!voice.model || !voice.transcriptionModel) {
      return "unavailable";
    }
    return apiKey ? "ok" : "degraded";
  };

  const statusPayload = () => {
    const active = [...sessions.values()]
      .filter((session) => session.status === "active" && Date.parse(session.expires_at) > Date.now())
      .sort((left, right) => right.created_at.localeCompare(left.created_at))[0];
    return {
      enabled: health() !== "unavailable",
      health: health(),
      agent_id: agentId,
      active_session_id: active ? active.id : null,
      active_turn_id: active ? active.active_turn_id : null,
      queue_depth: 0,
      last_event_id: null,
      tool_registry_digest: toolRegistryDigest(voice),
    };
  };

  const createSession = async (req: IncomingMessage, res: ServerResponse): Promise<void> => {
    const input = await readBody(req);
    const safetyHeader = req.headers["openai-safety-identifier"];
    const safetyIdentifier = Array.isArray(safetyHeader) ? safetyHeader[0] : safetyHeader || "";
    const minted = await mintRealtimeSecret(
      voice,
      apiKey,
      {
        voice: typeof input.voice === "string" ? input.voice : undefined,
        reasoning_effort: typeof input.reasoning_effort === "string" ? input.reasoning_effort : undefined,
      },
      safetyIdentifier,
    );
    if (!minted.ok) {
      sendJson(res, minted.status, { ok: false, error: minted.error });
      return;
    }

    const expiresAt = new Date(Date.now() + voice.sessionTtlSeconds * 1000).toISOString();
    const session: SessionRecord = {
      id: crypto.randomUUID(),
      agent_id: agentId,
      status: "active",
      active_turn_id: null,
      created_at: nowIso(),
      expires_at: expiresAt,
    };
    sessions.set(session.id, session);

    // Exact HermesVoiceSession envelope the iOS app + mobile contract expect.
    sendJson(res, 201, {
      session_id: session.id,
      agent_id: session.agent_id,
      expires_at: expiresAt,
      realtime: {
        provider: "openai-realtime",
        model: voice.model,
        client_secret: minted.value,
        client_secret_expires_at: expiresAt,
        calls_url: OPENAI_CALLS_URL,
      },
      tools: readTools(voice),
    });
  };

  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url || "/", "http://localhost");
      const { pathname } = url;
      const { method } = req;

      // healthz is a liveness probe and stays unauthenticated.
      if (pathname === "/hermes/voice/healthz" && method === "GET") {
        sendJson(res, health() === "unavailable" ? 503 : 200, { ok: health() !== "unavailable", health: health() });
        return;
      }

      // Every other /hermes/voice/* route requires the pairing token. Reject
      // before any OpenAI mint so an unpaired client can never spend the key.
      if (!isAuthorized(req, pairingToken)) {
        sendJson(res, 401, { ok: false, error: "unauthorized" });
        return;
      }

      if (pathname === "/hermes/voice/status" && method === "GET") {
        sendJson(res, 200, statusPayload());
        return;
      }
      if (pathname === "/hermes/voice/session" && method === "POST") {
        await createSession(req, res);
        return;
      }
      if (pathname === "/hermes/voice/prewarm" && method === "POST") {
        await readBody(req);
        sendJson(res, 202, { ok: true });
        return;
      }
      if (pathname === "/hermes/voice/disconnect" && method === "POST") {
        const body = await readBody(req);
        const sessionId = typeof body.session_id === "string" ? body.session_id : null;
        if (sessionId) {
          const session = sessions.get(sessionId);
          if (session) {
            session.status = "ended";
          }
        }
        sendJson(res, 200, { ok: true });
        return;
      }
      if (pathname === "/hermes/voice/tool-result" && method === "POST") {
        await readBody(req);
        sendJson(res, 202, { ok: true });
        return;
      }

      sendJson(res, 404, { ok: false, error: "not_found" });
    } catch (error) {
      const code = error instanceof Error ? error.message : "voice_gateway_error";
      const status = code === "request_too_large" || code === "bad_json" ? 400 : 500;
      sendJson(res, status, { ok: false, error: code });
    }
  });
}

/**
 * `regents voice serve` — resolves config + the OpenAI key (env-indirection,
 * fail-fast, no fallback), starts the local Hermes voice gateway, and blocks
 * until the server closes.
 */
export async function runVoiceServe(args: ParsedCliArgs, configPath?: string): Promise<number> {
  const config = RegentRuntime.loadConfig(configPath);
  const voice = config.services.voice;

  // Fail fast at startup if the key is missing — no fallback source (hard cutover).
  const apiKey = resolveOpenaiApiKey(voice);

  const host = getFlag(args, "host") ?? "127.0.0.1";
  const port = parseIntegerFlag(args, "port") ?? voice.port;

  // Pairing token gates app->gateway requests. Distinct from the OpenAI key.
  const pairingToken = resolvePairingToken();
  const server = createVoiceGatewayServer(voice, apiKey, pairingToken);

  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => {
      process.stderr.write(
        `[regents voice] local Hermes voice gateway listening on http://${host}:${port} ` +
          `(model ${voice.model})\n`,
      );
      resolve();
    });
  });

  // The phone can't reach localhost; prefer a LAN address for the QR base URL.
  const reachableHost = host === "127.0.0.1" || host === "0.0.0.0" ? firstLanAddress() ?? host : host;
  const baseUrl = `http://${reachableHost}:${port}`;
  const payload = buildPairingPayload(baseUrl, pairingToken);

  process.stderr.write("\n[regents voice] Scan this QR in the Regents app to pair:\n\n");
  qrcodeTerminal.generate(JSON.stringify(payload), { small: true }, (qr) => {
    process.stderr.write(`${qr}\n`);
  });
  process.stderr.write(`[regents voice] pairing url: ${baseUrl}\n`);

  // Keep the process alive until the server closes.
  await new Promise<void>((resolve) => {
    server.once("close", resolve);
  });

  return 0;
}
