import type {
  RegentConfig,
  SiwaNonceRequest,
  SiwaNonceResponse,
  SiwaVerifyRequest,
  SiwaVerifyResponse,
} from "../../internal-types/index.js";

import { parseServiceBaseUrl } from "../config.js";
import { AuthError } from "../errors.js";
import { ProductHttpError, requestProductResponse } from "../product-http-client.js";
import { messageWithRetryAfter } from "../rate-limit-message.js";

const DEFAULT_STATEMENT = siwaAudienceStatement("Regents CLI");
type SiwaRequestBody = NonNullable<Parameters<typeof fetch>[1]> extends { readonly body?: infer Body } ? Body : never;

export function siwaAudienceStatement(audience: string): string {
  return `Sign in to ${audience}.`;
}

export function siwaMessageLocation(platformBaseUrl: string): {
  domain: string;
  uri: string;
} {
  const parsed = parseServiceBaseUrl(platformBaseUrl);
  return {
    domain: parsed.host,
    uri: parsed.origin,
  };
}

export function buildSiwaMessage(input: {
  domain: string;
  uri: string;
  walletAddress: string;
  chainId: number;
  registryAddress: string;
  tokenId: string;
  nonce: string;
  issuedAt?: string;
  statement?: string;
}): string {
  const issuedAt = input.issuedAt ?? new Date().toISOString();
  const statement = input.statement ?? DEFAULT_STATEMENT;

  return [
    `${input.domain} wants you to sign in with your Agent account:`,
    input.walletAddress,
    "",
    statement,
    "",
    `URI: ${input.uri}`,
    "Version: 1",
    `Agent ID: ${input.tokenId}`,
    `Agent Registry: eip155:${input.chainId}:${input.registryAddress}`,
    `Chain ID: ${input.chainId}`,
    `Nonce: ${input.nonce}`,
    `Issued At: ${issuedAt}`,
  ].join("\n");
}

const ensureSuccessEnvelope = <T extends { code?: unknown; data?: unknown }>(
  value: unknown,
  expectedCode: string,
): T => {
  if (
    !value ||
    typeof value !== "object" ||
    (value as { code?: unknown }).code !== expectedCode
  ) {
    throw new AuthError("siwa_invalid_response", "SIWA endpoint returned an unexpected success envelope");
  }

  return value as T;
};

const parseSiwaErrorResponse = async (response: Response): Promise<AuthError> => {
  const text = await response.text();

  try {
    const parsed = JSON.parse(text) as { error?: { code?: unknown; message?: unknown }; message?: unknown };
    const code = typeof parsed.error?.code === "string" ? parsed.error.code : "siwa_request_failed";
    const message =
      typeof parsed.error?.message === "string"
        ? parsed.error.message
        : typeof parsed.message === "string"
          ? parsed.message
          : `SIWA request failed with HTTP ${response.status}`;

    return new AuthError(
      code,
      messageWithRetryAfter(response.status, response.headers, message),
      undefined,
      { status: response.status },
    );
  } catch {
    return new AuthError(
      "siwa_request_failed",
      messageWithRetryAfter(response.status, response.headers, text || `SIWA request failed with HTTP ${response.status}`),
      undefined,
      { status: response.status },
    );
  }
};

export class SiwaClient {
  readonly baseUrl: string;
  readonly timeoutMs: number;
  readonly config?: RegentConfig;

  constructor(baseUrl: string, timeoutMs: number, config?: RegentConfig) {
    this.baseUrl = baseUrl.replace(/\/+$/, "");
    this.timeoutMs = timeoutMs;
    this.config = config;
  }

  async requestNonce(input: SiwaNonceRequest): Promise<SiwaNonceResponse> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}/api/shared/siwa/nonce`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify(input),
    });

    if (!res.ok) {
      throw await parseSiwaErrorResponse(res);
    }

    const payload = ensureSuccessEnvelope<SiwaNonceResponse>(await res.json(), "nonce_issued");
    return payload;
  }

  async verify(input: SiwaVerifyRequest): Promise<SiwaVerifyResponse> {
    const res = await this.fetchWithTimeout(`${this.baseUrl}/api/shared/siwa/verify`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify(input),
    });

    if (!res.ok) {
      throw await parseSiwaErrorResponse(res);
    }

    const payload = ensureSuccessEnvelope<SiwaVerifyResponse>(await res.json(), "siwa_verified");
    return payload;
  }

  static defaultMessageInput(input: {
    config: RegentConfig;
    walletAddress: string;
    chainId: number;
    registryAddress: string;
    tokenId: string;
    nonce: string;
    issuedAt?: string;
    statement?: string;
  }): string {
    const location = siwaMessageLocation(input.config.services.platform.baseUrl);
    return buildSiwaMessage({
      domain: location.domain,
      uri: location.uri,
      walletAddress: input.walletAddress,
      chainId: input.chainId,
      registryAddress: input.registryAddress,
      tokenId: input.tokenId,
      nonce: input.nonce,
      issuedAt: input.issuedAt,
      statement: input.statement,
    });
  }

  private async fetchWithTimeout(url: string, init: RequestInit): Promise<Response> {
    const parsedUrl = new URL(url);

    try {
      const { response } = await requestProductResponse({
        service: "siwa",
        method: init.method === "GET" || init.method === "DELETE" ? init.method : "POST",
        path: `${parsedUrl.pathname}${parsedUrl.search}`,
        config: this.config,
        commandName: "regents siwa",
        chainId: chainIdFromBody(init.body),
        timeoutMs: this.timeoutMs,
        headers: init.headers,
        body: init.body,
        baseUrlOverride: this.baseUrl,
      });
      return response;
    } catch (error) {
      if (error instanceof ProductHttpError && error.timedOut) {
        throw new AuthError("siwa_timeout", `request to ${url} timed out`, error);
      }

      throw new AuthError("siwa_request_failed", `request to ${url} failed`, error);
    }
  }
}

const chainIdFromBody = (body: SiwaRequestBody | null | undefined): number | undefined => {
  if (typeof body !== "string") {
    return undefined;
  }

  try {
    const payload = JSON.parse(body) as { chain_id?: unknown };
    return typeof payload.chain_id === "number" ? payload.chain_id : undefined;
  } catch {
    return undefined;
  }
};
