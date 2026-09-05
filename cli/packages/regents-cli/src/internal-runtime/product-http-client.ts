import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";

import { CliUsageError } from "../cli-usage-error.js";
import { appendStructuredLog } from "./structured-log.js";
import { loadConfig } from "./config.js";
import type { RegentConfig } from "../internal-types/config.js";
import {
  EXPECTED_PLATFORM_CONTRACT_DIGEST,
  SUPPORTED_PLATFORM_CONTRACT_MAJOR,
} from "../generated/platform-contract-digest.js";

export type ProductServiceName = "siwa" | "platform" | "autolaunch";
export type ProductHttpMethod = "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
type ProductHttpHeaders = ConstructorParameters<typeof Headers>[0];
type ProductHttpBody = NonNullable<Parameters<typeof fetch>[1]> extends { readonly body?: infer Body } ? Body : never;

const packageMetadata = JSON.parse(
  readFileSync(new URL("../../package.json", import.meta.url), "utf8"),
) as { readonly version?: unknown };

if (typeof packageMetadata.version !== "string" || packageMetadata.version.trim() === "") {
  throw new Error("@regentslabs/cli package version is required.");
}

export const regentsCliVersion = packageMetadata.version;

export interface ProductHttpRequestOptions {
  readonly service: ProductServiceName;
  readonly method: ProductHttpMethod;
  readonly path: string;
  readonly configPath?: string;
  readonly config?: RegentConfig;
  readonly commandName?: string;
  readonly chainId?: number;
  readonly timeoutMs?: number;
  readonly headers?: ProductHttpHeaders;
  readonly body?: ProductHttpBody | null;
  readonly baseUrlOverride?: string;
  readonly signal?: AbortSignal | null;
}

export interface ProductHttpResponse {
  readonly response: Response;
  readonly requestId: string;
}

export class ProductHttpError extends Error {
  readonly service: ProductServiceName;
  readonly status: number;
  readonly path: string;
  readonly requestId: string;
  readonly timedOut: boolean;

  constructor(args: {
    service: ProductServiceName;
    status: number;
    path: string;
    requestId: string;
    message: string;
    timedOut?: boolean;
  }) {
    super(args.message);
    this.name = "ProductHttpError";
    this.service = args.service;
    this.status = args.status;
    this.path = args.path;
    this.requestId = args.requestId;
    this.timedOut = args.timedOut === true;
  }
}

export const productBaseUrl = (
  config: RegentConfig,
  service: ProductServiceName,
  baseUrlOverride?: string,
): string => {
  if (baseUrlOverride) {
    return baseUrlOverride.replace(/\/+$/u, "");
  }

  if (service === "platform" && process.env.REGENT_PLATFORM_ORIGIN) {
    return process.env.REGENT_PLATFORM_ORIGIN.replace(/\/+$/u, "");
  }

  if (service === "autolaunch" && process.env.AUTOLAUNCH_BASE_URL) {
    return process.env.AUTOLAUNCH_BASE_URL.replace(/\/+$/u, "");
  }

  return config.services[service].baseUrl.replace(/\/+$/u, "");
};

export const requestProductResponse = async (
  options: ProductHttpRequestOptions,
): Promise<ProductHttpResponse> => {
  const config = options.config ?? loadConfig(options.configPath);
  const baseUrl = productBaseUrl(config, options.service, options.baseUrlOverride);
  const requestId = randomUUID();
  const started = performance.now();
  const timeoutMs = options.timeoutMs ?? config.services[options.service].requestTimeoutMs;
  const controller = new AbortController();
  const timeout = timeoutMs > 0 ? setTimeout(() => controller.abort(), timeoutMs) : undefined;
  const externalSignal = options.signal ?? undefined;
  const forwardAbort = (): void => controller.abort();
  const headers = new Headers(options.headers);

  headers.set("x-request-id", requestId);
  headers.set("x-regents-client", "regents-cli");
  headers.set("x-regents-cli-version", regentsCliVersion);

  if (externalSignal) {
    if (externalSignal.aborted) {
      controller.abort();
    } else {
      externalSignal.addEventListener("abort", forwardAbort, { once: true });
    }
  }

  try {
    if (options.service === "platform" && options.method !== "GET") {
      await ensureCompatiblePlatformContract(baseUrl, controller.signal);
    }

    const response = await fetch(`${baseUrl}${options.path}`, {
      method: options.method,
      headers,
      body: options.body,
      signal: controller.signal,
    });

    appendStructuredLog(config, {
      timestamp: new Date().toISOString(),
      level: response.ok ? "info" : "error",
      event: "product_http_request",
      command: options.commandName,
      service: options.service,
      method: options.method,
      path: options.path,
      status: response.status,
      ok: response.ok,
      requestId,
      durationMs: Math.round(performance.now() - started),
      chainId: options.chainId,
      redacted: true,
    });

    return { response, requestId };
  } catch (error) {
    if (error instanceof CliUsageError) {
      throw error;
    }

    const timedOut = error instanceof Error && error.name === "AbortError";
    const message =
      timedOut
        ? `Regent ${options.service} request timed out after ${timeoutMs}ms.`
        : error instanceof Error
          ? error.message
          : "Regent request failed.";

    appendStructuredLog(config, {
      timestamp: new Date().toISOString(),
      level: "error",
      event: "product_http_request",
      command: options.commandName,
      service: options.service,
      method: options.method,
      path: options.path,
      ok: false,
      requestId,
      durationMs: Math.round(performance.now() - started),
      chainId: options.chainId,
      error: message,
      redacted: true,
    });

    throw new ProductHttpError({
      service: options.service,
      status: 0,
      path: options.path,
      requestId,
      message,
      timedOut,
    });
  } finally {
    if (externalSignal) {
      externalSignal.removeEventListener("abort", forwardAbort);
    }
    if (timeout) {
      clearTimeout(timeout);
    }
  }
};

const ensureCompatiblePlatformContract = async (baseUrl: string, signal: AbortSignal): Promise<void> => {
  const response = await fetch(`${baseUrl}/api-contract.openapiv3.yaml`, {
    method: "GET",
    headers: { accept: "application/yaml" },
    signal,
  });

  if (!response.ok) {
    throw new CliUsageError({
      code: "platform_contract_check_failed",
      message: "Platform contract version could not be checked.",
    });
  }

  const major = response.headers.get("x-regents-contract-major");
  const digest = response.headers.get("x-regents-contract-digest");

  if (major !== SUPPORTED_PLATFORM_CONTRACT_MAJOR || digest !== EXPECTED_PLATFORM_CONTRACT_DIGEST) {
    throw new CliUsageError({
      code: "platform_contract_incompatible",
      message: "This Regents CLI needs a matching Platform contract version before it can make changes.",
    });
  }
};
