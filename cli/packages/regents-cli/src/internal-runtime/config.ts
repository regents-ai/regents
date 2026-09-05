import fs from "node:fs";
import path from "node:path";

import { z } from "zod";

import type { RegentConfig } from "../internal-types/index.js";

import { ConfigError } from "./errors.js";
import {
  defaultConfigPath as deriveDefaultConfigPath,
  ensureSecureDir,
  expandHome,
  writeJsonFileAtomicSync,
} from "./paths.js";

const logLevelSchema = z.enum(["debug", "info", "warn", "error"]);
const siwaAudienceSchema = z.enum(["platform", "autolaunch", "techtree", "regent-services"]);
const executorHarnessSchema = z.enum(["openclaw", "hermes", "claude_code", "codex", "custom"]);
export const SERVICE_BASE_URL_ERROR =
  "service baseUrl must be an HTTP(S) URL without userinfo, whitespace, or control characters";
const UNSAFE_SERVICE_URL_CHARACTER = /[\s\u0000-\u001f\u007f-\u009f]/u;
const SERVICE_URL_AUTHORITY_WITH_USERINFO = /^[a-z][a-z\d+.-]*:\/\/[^/?#]*@/iu;

export const parseServiceBaseUrl = (value: string): URL => {
  if (
    UNSAFE_SERVICE_URL_CHARACTER.test(value) ||
    SERVICE_URL_AUTHORITY_WITH_USERINFO.test(value)
  ) {
    throw new ConfigError(SERVICE_BASE_URL_ERROR);
  }

  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch (error) {
    throw new ConfigError(SERVICE_BASE_URL_ERROR, error);
  }

  if (
    (parsed.protocol !== "http:" && parsed.protocol !== "https:") ||
    parsed.username !== "" ||
    parsed.password !== ""
  ) {
    throw new ConfigError(SERVICE_BASE_URL_ERROR);
  }

  return parsed;
};

const serviceBaseUrlSchema = z.string().superRefine((value, ctx) => {
  try {
    parseServiceBaseUrl(value);
  } catch {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message: SERVICE_BASE_URL_ERROR,
    });
  }
});

const serviceConfigSchema = z.object({
  baseUrl: serviceBaseUrlSchema,
  requestTimeoutMs: z.number().int().positive(),
}).strict();

const configSchema = z.object({
  runtime: z.object({
    socketPath: z.string().min(1),
    stateDir: z.string().min(1),
    logLevel: logLevelSchema,
  }).strict(),
  auth: z.object({
    audience: siwaAudienceSchema,
    defaultChainId: z.number().int().positive(),
  }).strict(),
  services: z.object({
    siwa: serviceConfigSchema,
    platform: serviceConfigSchema,
    autolaunch: serviceConfigSchema,
    voice: z.object({
      openaiApiKeyEnv: z.string().min(1),
      port: z.number().int().positive(),
      model: z.string().min(1),
      transcriptionModel: z.string().min(1),
      defaultVoice: z.string().min(1),
      reasoningEffort: z.enum(["minimal", "low", "medium", "high", "xhigh"]),
      sessionTtlSeconds: z.number().int().positive(),
      toolRegistryPath: z.string().min(1),
    }).strict(),
  }).strict(),
  wallet: z.object({
    privateKeyEnv: z.string().min(1),
    keystorePath: z.string().min(1),
  }).strict(),
  gossipsub: z.object({
    enabled: z.boolean(),
    listenAddrs: z.array(z.string()),
    bootstrap: z.array(z.string()),
    peerIdPath: z.string().min(1),
  }).strict(),
  agents: z.object({
    defaultHarness: executorHarnessSchema,
    harnesses: z.record(
      z.string().min(1),
      z.object({
        enabled: z.boolean(),
        entrypoint: z.string().min(1),
        workspaceRoot: z.string().min(1),
        profiles: z.array(z.string().min(1)),
      }).strict(),
    ),
  }).strict(),
}).strict();

const configOverrideSchema = z.object({
  runtime: configSchema.shape.runtime.partial().optional(),
  auth: configSchema.shape.auth.partial().optional(),
  services: configSchema.shape.services
    .extend({
      siwa: serviceConfigSchema.partial().optional(),
      platform: serviceConfigSchema.partial().optional(),
      autolaunch: serviceConfigSchema.partial().optional(),
      voice: configSchema.shape.services.shape.voice.partial().optional(),
    })
    .partial()
    .optional(),
  wallet: configSchema.shape.wallet.partial().optional(),
  gossipsub: configSchema.shape.gossipsub.partial().optional(),
  agents: configSchema.shape.agents
    .extend({
      harnesses: z.record(
        z.string().min(1),
        configSchema.shape.agents.shape.harnesses.valueType.partial(),
      ).optional(),
    })
    .partial()
    .optional(),
}).strict();

const normalizePath = (input: string, rootDir?: string): string => {
  const expanded = expandHome(input);
  return path.isAbsolute(expanded)
    ? path.normalize(expanded)
    : path.resolve(rootDir ?? process.cwd(), expanded);
};

const resolveConfigPath = (configPath?: string): string => {
  return configPath ? normalizePath(configPath) : deriveDefaultConfigPath();
};

const resolveConfigRootDir = (configPath?: string): string => {
  return path.dirname(resolveConfigPath(configPath));
};

const deepMerge = <T>(base: T, override: Partial<T>): T => {
  const result: Record<string, unknown> = { ...(base as Record<string, unknown>) };

  for (const [key, value] of Object.entries(override)) {
    if (value === undefined) {
      continue;
    }

    const current = result[key];
    if (
      value !== null &&
      typeof value === "object" &&
      !Array.isArray(value) &&
      current !== null &&
      typeof current === "object" &&
      !Array.isArray(current)
    ) {
      result[key] = deepMerge(current as Record<string, unknown>, value as Record<string, unknown>);
      continue;
    }

    result[key] = value;
  }

  return result as T;
};

const normalizeConfig = (config: RegentConfig, configPath?: string): RegentConfig => {
  const resolvedConfigRootDir = configPath ? path.dirname(normalizePath(configPath)) : undefined;

  return {
    ...config,
    runtime: {
      ...config.runtime,
      socketPath: normalizePath(config.runtime.socketPath, resolvedConfigRootDir),
      stateDir: normalizePath(config.runtime.stateDir, resolvedConfigRootDir),
    },
    auth: {
      ...config.auth,
    },
    services: {
      siwa: { ...config.services.siwa },
      platform: { ...config.services.platform },
      autolaunch: { ...config.services.autolaunch },
      voice: {
        ...config.services.voice,
        toolRegistryPath: normalizePath(config.services.voice.toolRegistryPath, resolvedConfigRootDir),
      },
    },
    wallet: {
      ...config.wallet,
      keystorePath: normalizePath(config.wallet.keystorePath, resolvedConfigRootDir),
    },
    gossipsub: {
      ...config.gossipsub,
      peerIdPath: normalizePath(config.gossipsub.peerIdPath, resolvedConfigRootDir),
    },
    agents: {
      ...config.agents,
      harnesses: Object.fromEntries(
        Object.entries(config.agents.harnesses).map(([name, harness]) => [
          name,
          {
            ...harness,
            workspaceRoot: normalizePath(harness.workspaceRoot, resolvedConfigRootDir),
          },
        ]),
      ),
    },
  };
};

export const agentDefaultsForRoot = (rootDir: string): RegentConfig["agents"] => ({
  defaultHarness: "hermes",
  harnesses: {
    openclaw: {
      enabled: false,
      entrypoint: "openclaw",
      workspaceRoot: path.join(rootDir, "workspaces", "openclaw"),
      profiles: ["owner", "public", "group"],
    },
    hermes: {
      enabled: true,
      entrypoint: "hermes",
      workspaceRoot: path.join(rootDir, "workspaces", "hermes"),
      profiles: ["owner", "public", "group"],
    },
    claude_code: {
      enabled: false,
      entrypoint: "claude",
      workspaceRoot: path.join(rootDir, "workspaces", "claude-code"),
      profiles: ["owner", "public", "group"],
    },
    codex: {
      enabled: false,
      entrypoint: "codex",
      workspaceRoot: path.join(rootDir, "workspaces", "codex"),
      profiles: ["owner", "public", "group"],
    },
    custom: {
      enabled: false,
      entrypoint: "custom-harness",
      workspaceRoot: path.join(rootDir, "workspaces", "custom"),
      profiles: ["custom"],
    },
  },
});

const ensureConfigDirectories = (config: RegentConfig): void => {
  ensureSecureDir(config.runtime.stateDir);
  ensureSecureDir(path.dirname(config.runtime.socketPath));
  ensureSecureDir(path.dirname(config.wallet.keystorePath));
  ensureSecureDir(path.dirname(config.gossipsub.peerIdPath));
  for (const harness of Object.values(config.agents.harnesses)) {
    ensureSecureDir(harness.workspaceRoot);
  }
};

export function defaultConfig(configPath?: string): RegentConfig {
  const rootDir = resolveConfigRootDir(configPath);

  return {
    runtime: {
      socketPath: path.join(rootDir, "run", "regent.sock"),
      stateDir: path.join(rootDir, "state"),
      logLevel: "info",
    },
    auth: {
      audience: "techtree",
      defaultChainId: 8453,
    },
    services: {
      siwa: {
        baseUrl: "https://siwa-server.fly.dev",
        requestTimeoutMs: 10_000,
      },
      platform: {
        baseUrl: "https://regents.sh",
        requestTimeoutMs: 10_000,
      },
      autolaunch: {
        baseUrl: "https://regents.sh",
        requestTimeoutMs: 10_000,
      },
      voice: {
        openaiApiKeyEnv: "OPENAI_API_KEY",
        port: 8787,
        model: "gpt-realtime-2",
        transcriptionModel: "gpt-realtime-whisper",
        defaultVoice: "marin",
        reasoningEffort: "low",
        sessionTtlSeconds: 60,
        toolRegistryPath: path.join(rootDir, "config", "voice-tools.json"),
      },
    },
    wallet: {
      privateKeyEnv: "REGENT_WALLET_PRIVATE_KEY",
      keystorePath: path.join(rootDir, "keys", "agent-wallet.json"),
    },
    gossipsub: {
      enabled: false,
      listenAddrs: [],
      bootstrap: [],
      peerIdPath: path.join(rootDir, "p2p", "peer-id.json"),
    },
    agents: agentDefaultsForRoot(rootDir),
  };
}

export function loadConfig(configPath?: string): RegentConfig {
  const resolvedConfigPath = resolveConfigPath(configPath);
  const fallback = defaultConfig(resolvedConfigPath);

  if (!fs.existsSync(resolvedConfigPath)) {
    return fallback;
  }

  let rawContent = "";
  try {
    rawContent = fs.readFileSync(resolvedConfigPath, "utf8");
  } catch (error) {
    throw new ConfigError(`unable to read config file at ${resolvedConfigPath}`, error);
  }

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(rawContent);
  } catch (error) {
    throw new ConfigError(`invalid JSON in config file at ${resolvedConfigPath}`, error);
  }

  const validatedOverride = configOverrideSchema.safeParse(parsedJson);
  if (!validatedOverride.success) {
    throw new ConfigError(`config file failed validation: ${validatedOverride.error.message}`);
  }

  const merged = deepMerge(fallback, validatedOverride.data as Partial<RegentConfig>);
  const normalized = normalizeConfig(merged, resolvedConfigPath);
  const validated = configSchema.safeParse(normalized);

  if (!validated.success) {
    throw new ConfigError(`normalized config failed validation: ${validated.error.message}`);
  }

  return validated.data;
}

export function writeConfigReplacement(configPath: string, nextConfig: unknown): RegentConfig {
  const resolvedConfigPath = normalizePath(configPath);
  const validatedInput = configSchema.safeParse(nextConfig);

  if (!validatedInput.success) {
    throw new ConfigError(`replacement config failed validation: ${validatedInput.error.message}`);
  }

  const normalized = normalizeConfig(validatedInput.data, resolvedConfigPath);
  const validatedNormalized = configSchema.safeParse(normalized);

  if (!validatedNormalized.success) {
    throw new ConfigError(`normalized replacement config failed validation: ${validatedNormalized.error.message}`);
  }

  ensureConfigDirectories(validatedNormalized.data);
  writeJsonFileAtomicSync(resolvedConfigPath, validatedNormalized.data);
  return validatedNormalized.data;
}

export function writeInitialConfig(configPath: string, overrides?: Partial<RegentConfig>): void {
  const resolvedConfigPath = normalizePath(configPath);
  const merged = deepMerge(defaultConfig(resolvedConfigPath), overrides ?? {});
  const normalized = normalizeConfig(merged, resolvedConfigPath);
  const validated = configSchema.safeParse(normalized);

  if (!validated.success) {
    throw new ConfigError(`initial config failed validation: ${validated.error.message}`);
  }

  ensureConfigDirectories(validated.data);
  writeJsonFileAtomicSync(resolvedConfigPath, validated.data);
}

export function writeInitialConfigIfMissing(configPath: string, overrides?: Partial<RegentConfig>): boolean {
  const resolvedConfigPath = normalizePath(configPath);
  if (fs.existsSync(resolvedConfigPath)) {
    return false;
  }

  writeInitialConfig(configPath, overrides);
  return true;
}
