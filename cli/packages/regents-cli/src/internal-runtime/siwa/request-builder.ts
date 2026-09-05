import type { LocalAgentIdentity, SiwaSession } from "../../internal-types/index.js";

import { buildSignedAgentHeaders, buildSignerBackedAgentHeaders } from "./signing.js";

const AUTH_DEBUG_HEADER_NAMES = [
  "x-siwa-receipt",
  "x-key-id",
  "x-timestamp",
  "x-agent-wallet-address",
  "x-agent-chain-id",
  "x-agent-registry-address",
  "x-agent-token-id",
  "content-digest",
  "signature-input",
  "signature",
  "content-type",
] as const;

type AuthDebugHeaderName = (typeof AUTH_DEBUG_HEADER_NAMES)[number];

export interface ProtectedAgentAuthDebugSnapshot {
  method: AuthenticatedRequestInput["method"];
  signedPath: string;
  finalUrl: string;
  serializedJsonBody: string | null;
  authHeaders: Record<AuthDebugHeaderName, string | null>;
}

export interface ProtectedAgentAuthFailureDebugSnapshot {
  status: number;
  statusText: string;
  responseHeaders: Record<string, string>;
  responseBody: string;
}

export interface AuthenticatedRequestInput {
  method: "GET" | "POST" | "DELETE" | "PATCH" | "PUT";
  path: string;
  body?: unknown;
  session: SiwaSession;
  agentIdentity: LocalAgentIdentity;
  signMessage?(message: string): Promise<`0x${string}`>;
  privateKey?: `0x${string}`;
}

const serializeJsonBody = (body: unknown): string | undefined => (body === undefined ? undefined : JSON.stringify(body));

const requireBoundAgentIdentity = (identity: LocalAgentIdentity): {
  walletAddress: `0x${string}`;
  chainId: number;
  registryAddress: `0x${string}`;
  tokenId: string;
} => {
  if (!identity.registryAddress || !identity.tokenId) {
    throw new Error("This command needs a saved Agent account. Run `regents identity ensure` first.");
  }

  return {
    walletAddress: identity.walletAddress,
    chainId: identity.chainId,
    registryAddress: identity.registryAddress,
    tokenId: identity.tokenId,
  };
};

const headerEntries = (headers: RequestInit["headers"]): [string, string][] => {
  if (headers instanceof Headers) {
    return [...headers.entries()];
  }

  if (Array.isArray(headers)) {
    return headers.map(([key, value]) => [key, Array.isArray(value) ? value.join(", ") : String(value)]);
  }

  return Object.entries(headers ?? {}).map(([key, value]) => [key, Array.isArray(value) ? value.join(", ") : String(value)]);
};

export async function buildAuthenticatedFetchInit(
  input: AuthenticatedRequestInput,
): Promise<{ urlPath: string; serializedJsonBody?: string; init: RequestInit }> {
  const serializedBody = serializeJsonBody(input.body);
  const agentIdentity = requireBoundAgentIdentity(input.agentIdentity);
  const sharedInput = {
    method: input.method,
    path: input.path,
    ...(serializedBody === undefined ? {} : { body: serializedBody }),
    walletAddress: agentIdentity.walletAddress,
    chainId: agentIdentity.chainId,
    registryAddress: agentIdentity.registryAddress,
    tokenId: agentIdentity.tokenId,
    receipt: input.session.receipt,
  };
  const signedHeaders = input.signMessage
    ? await buildSignerBackedAgentHeaders({
        ...sharedInput,
        signMessage: input.signMessage,
      })
    : await buildSignedAgentHeaders({
        ...sharedInput,
        privateKey: input.privateKey as `0x${string}`,
      });

  const headers: Record<string, string> = {
    ...signedHeaders,
  };

  if (serializedBody !== undefined) {
    headers["content-type"] = "application/json";
  }

  return {
    urlPath: input.path,
    ...(serializedBody === undefined ? {} : { serializedJsonBody: serializedBody }),
    init: {
      method: input.method,
      headers,
      ...(serializedBody === undefined ? {} : { body: serializedBody }),
    },
  };
}

export const protectedWriteAuthDebugEnabled = (): boolean => {
  return process.env.REGENT_PROTECTED_WRITE_AUTH_DEBUG === "1";
};

export const buildProtectedAgentAuthDebugSnapshot = (input: {
  method: AuthenticatedRequestInput["method"];
  signedPath: string;
  finalUrl: string;
  serializedJsonBody?: string;
  headers: RequestInit["headers"];
}): ProtectedAgentAuthDebugSnapshot => {
  const lowerCaseHeaders = new Map(
    headerEntries(input.headers).map(([key, value]) => [key.toLowerCase(), value]),
  );

  return {
    method: input.method,
    signedPath: input.signedPath,
    finalUrl: input.finalUrl,
    serializedJsonBody: input.serializedJsonBody ?? null,
    authHeaders: Object.fromEntries(
      AUTH_DEBUG_HEADER_NAMES.map((name) => [name, lowerCaseHeaders.get(name) ?? null]),
    ) as ProtectedAgentAuthDebugSnapshot["authHeaders"],
  };
};

export const emitProtectedWriteAuthDebug = (_event: string, _payload: unknown): void => {
  if (!protectedWriteAuthDebugEnabled()) {
    return;
  }
};

export const captureProtectedWriteAuthFailureDebug = async (
  _response: Response,
): Promise<ProtectedAgentAuthFailureDebugSnapshot | null> => {
  return null;
};
