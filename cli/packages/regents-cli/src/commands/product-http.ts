import {
  ProductHttpError,
  requestProductResponse,
  type ProductHttpMethod,
  type ProductServiceName,
} from "../internal-runtime/product-http-client.js";
import type { SiwaAudience } from "../internal-types/index.js";
import type { RegentConfig } from "../internal-types/config.js";
import { messageWithRetryAfter } from "../internal-runtime/rate-limit-message.js";

import { buildAgentAuthHeaders } from "./agent-auth.js";

export { ProductHttpError, type ProductServiceName };

export interface ProductJsonRequestOptions {
  readonly body?: unknown;
  readonly requireAgentAuth?: boolean;
  readonly authAudience?: SiwaAudience;
  readonly configPath?: string;
  readonly config?: RegentConfig;
  readonly service?: ProductServiceName;
  readonly commandName?: string;
  readonly chainId?: number;
  readonly timeoutMs?: number;
}

interface JsonObject {
  readonly [key: string]: unknown;
}

const objectString = (value: unknown, key: string): string | undefined =>
  value && typeof value === "object" && !Array.isArray(value) && typeof (value as Record<string, unknown>)[key] === "string"
    ? String((value as Record<string, unknown>)[key])
    : undefined;

const parseJsonObject = (text: string): JsonObject => {
  if (!text.trim()) {
    return {};
  }

  const parsed = JSON.parse(text) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Regent returned an unexpected response.");
  }

  return parsed as JsonObject;
};

const errorMessageFromPayload = (payload: JsonObject, status: number, headers: Headers): string => {
  const error = payload.error;
  const errorMessage =
    error && typeof error === "object" && typeof (error as { message?: unknown }).message === "string"
      ? String((error as { message: string }).message)
      : undefined;
  const errorDetail = objectString(error, "detail");
  const phoenixDetail = objectString(payload.errors, "detail");
  const topLevelMessage = objectString(payload, "message") ?? objectString(payload, "statusMessage");

  return messageWithRetryAfter(
    status,
    headers,
    errorMessage ?? errorDetail ?? phoenixDetail ?? topLevelMessage ?? `Regent request failed (${status}).`,
  );
};

export const requestProductJson = async <T>(
  method: ProductHttpMethod,
  path: string,
  options: ProductJsonRequestOptions = {},
): Promise<T> => {
  const audience = options.authAudience ?? "regent-services";
  const service =
    options.service ??
    (audience === "platform" || audience === "autolaunch" ? audience : "siwa");
  const bodyText = options.body === undefined ? undefined : JSON.stringify(options.body);
  const headers = new Headers({ accept: "application/json" });

  if (bodyText !== undefined) {
    headers.set("content-type", "application/json");
  }

  if (options.requireAgentAuth) {
    const authHeaders = await buildAgentAuthHeaders({
      method,
      path,
      ...(bodyText === undefined ? {} : { body: bodyText }),
      configPath: options.configPath,
      audience,
    });

    for (const [key, value] of Object.entries(authHeaders)) {
      headers.set(key, value);
    }
  }

  const { response, requestId } = await requestProductResponse({
    service,
    method,
    path,
    configPath: options.configPath,
    config: options.config,
    commandName: options.commandName,
    chainId: options.chainId,
    timeoutMs: options.timeoutMs,
    headers,
    body: bodyText,
  });
  const text = await response.text();
  const payload = parseJsonObject(text);

  if (!response.ok) {
    throw new ProductHttpError({
      service,
      status: response.status,
      path,
      requestId,
      message: errorMessageFromPayload(payload, response.status, response.headers),
    });
  }

  return payload as T;
};
