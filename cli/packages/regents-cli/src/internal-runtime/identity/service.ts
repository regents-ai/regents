import type {
  IdentityRegistrationCompletionRequest,
  IdentityRegistrationCompletionResponse,
  IdentityRegistrationIntentRequest,
  IdentityRegistrationIntentResponse,
  IdentitySiwaNonceRequest,
  IdentitySiwaNonceResponse,
  IdentitySiwaVerifyRequest,
  IdentitySiwaVerifyResponse,
  IdentityStatusRequest,
  IdentityStatusResponse,
  RegentConfig,
} from "../../internal-types/index.js";

import { CommandExitError } from "../errors.js";
import { ProductHttpError, requestProductResponse } from "../product-http-client.js";
import { identityNetworkChainId, normalizeRegentBaseUrl } from "./shared.js";

const ensureOkEnvelope = <T extends { ok?: boolean; error?: unknown }>(payload: unknown): T => {
  if (typeof payload !== "object" || payload === null || !("ok" in payload) || (payload as { ok?: boolean }).ok !== true) {
    throw new Error("unexpected response payload");
  }

  return payload as T;
};

const parseError = async (response: Response): Promise<never> => {
  let payload: unknown = null;
  try {
    payload = await response.json();
  } catch {
    payload = null;
  }

  const envelope = (typeof payload === "object" && payload !== null ? payload : {}) as {
    error?: { code?: string; message?: string };
  };
  const message =
    (typeof envelope.error?.message === "string" && envelope.error.message) ||
    `Shared Regent service request failed with ${response.status}.`;
  const normalizedCode = typeof envelope.error?.code === "string" ? envelope.error.code.toUpperCase() : undefined;

  if (normalizedCode === "UNSUPPORTED_NETWORK") {
    throw new CommandExitError("UNSUPPORTED_NETWORK", message, {
      details: {
        status: response.status,
        error_code: envelope.error?.code,
      },
    });
  }

  if (normalizedCode === "REGISTRATION_FAILED") {
    throw new CommandExitError("REGISTRATION_FAILED", message, {
      details: {
        status: response.status,
        error_code: envelope.error?.code,
      },
    });
  }

  if (normalizedCode === "SIWA_VERIFY_FAILED") {
    throw new CommandExitError("SIWA_VERIFY_FAILED", message, {
      details: {
        status: response.status,
        error_code: envelope.error?.code,
      },
    });
  }

  throw new CommandExitError("SERVICE_UNAVAILABLE", message, {
    details: {
      status: response.status,
      error_code: envelope.error?.code,
    },
  });
};

export class IdentityServiceClient {
  readonly baseUrl: string;
  readonly requestTimeoutMs: number;
  readonly config?: RegentConfig;

  constructor(baseUrl: string, requestTimeoutMs: number, config?: RegentConfig) {
    this.baseUrl = normalizeRegentBaseUrl(baseUrl);
    this.requestTimeoutMs = requestTimeoutMs;
    this.config = config;
  }

  async status(input: IdentityStatusRequest): Promise<IdentityStatusResponse> {
    return this.post("/api/shared/identity/status", input);
  }

  async registrationIntent(input: IdentityRegistrationIntentRequest): Promise<IdentityRegistrationIntentResponse> {
    return this.post("/api/shared/identity/registration-intents", input);
  }

  async registrationCompletion(
    input: IdentityRegistrationCompletionRequest,
  ): Promise<IdentityRegistrationCompletionResponse> {
    return this.post("/api/shared/identity/registration-completions", input);
  }

  async siwaNonce(input: IdentitySiwaNonceRequest): Promise<IdentitySiwaNonceResponse> {
    return this.post("/api/shared/identity/siwa/nonce", input);
  }

  async siwaVerify(input: IdentitySiwaVerifyRequest): Promise<IdentitySiwaVerifyResponse> {
    return this.post("/api/shared/identity/siwa/verify", input);
  }

  private async post<T>(path: string, body: unknown): Promise<T> {
    try {
      const network =
        typeof body === "object" && body !== null && "network" in body
          ? (body as { network?: unknown }).network
          : undefined;
      const chainId = network === "base" || network === "base-sepolia" ? identityNetworkChainId(network) : undefined;
      const { response } = await requestProductResponse({
        service: "siwa",
        method: "POST",
        path,
        config: this.config,
        commandName: "regents identity",
        chainId,
        headers: {
          "content-type": "application/json",
          accept: "application/json",
        },
        body: JSON.stringify(body),
        timeoutMs: this.requestTimeoutMs,
        baseUrlOverride: this.baseUrl,
      });

      if (!response.ok) {
        await parseError(response);
      }

      const payload = ensureOkEnvelope<T & { ok: true }>(await response.json());
      return payload;
    } catch (error) {
      if (error instanceof CommandExitError) {
        throw error;
      }

      if (error instanceof ProductHttpError && error.timedOut) {
        throw new CommandExitError(
          "SERVICE_UNAVAILABLE",
          `Shared Regent service timed out after ${this.requestTimeoutMs}ms.`,
        );
      }

      throw new CommandExitError("SERVICE_UNAVAILABLE", "Shared Regent service unavailable.", {
        cause: error,
      });
    }
  }
}
