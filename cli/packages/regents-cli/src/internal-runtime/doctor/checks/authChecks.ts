import { getCurrentAgentIdentity, getMissingAgentIdentityFields } from "../../agent/profile.js";
import { resolveAuthenticatedAgentSigningContext } from "../../techtree/auth.js";
import { buildAuthenticatedFetchInit } from "../../siwa/request-builder.js";
import {
  buildSiwaMessage,
  siwaAudienceStatement,
  SiwaClient,
  siwaMessageLocation,
} from "../../siwa/siwa.js";
import {
  coveredComponentsForAgentHeaders,
  parseSignatureInputHeader,
} from "../../siwa/signing.js";
import {
  buildBackendDetails,
  deriveSignerWalletAddress,
  isPositiveIntegerString,
  isValidAddress,
  skipDueToMissingConfig,
} from "./shared.js";
import type { LocalAgentIdentity } from "../../../internal-types/index.js";
import type { DoctorCheckDefinition } from "../types.js";

const FRESHNESS_THRESHOLD_MS = 5 * 60 * 1000;
type CompleteAgentIdentity = LocalAgentIdentity & {
  registryAddress: `0x${string}`;
  tokenId: string;
};

const identityIncompleteResult = {
  status: "skip",
  message: "SIWA verify probe skipped because protected-route identity is incomplete",
  remediation: "Run `regents identity ensure`",
} as const;

const toCompleteIdentity = (
  identity: LocalAgentIdentity | null,
  missingFields: string[],
): CompleteAgentIdentity | null => {
  if (
    !identity ||
    missingFields.length > 0 ||
    !identity.registryAddress ||
    !identity.tokenId
  ) {
    return null;
  }

  return identity as CompleteAgentIdentity;
};

export function authChecks(): DoctorCheckDefinition[] {
  return [
    {
      id: "auth.identity.headers",
      scope: "auth",
      title: "identity fields present",
      run: async (ctx) => {
        if (!ctx.stateStore) {
          return skipDueToMissingConfig();
        }

        const identity = getCurrentAgentIdentity(ctx.stateStore);
        const missingFields = getMissingAgentIdentityFields(ctx.stateStore);

        if (!identity) {
          return {
            status: "warn",
            message: "Protected-route identity is missing",
            details: {
              identity,
              missingFields,
            },
            remediation: "Run `regents identity ensure`",
          };
        }

        if (missingFields.length > 0) {
          return {
            status: "warn",
            message: "Protected-route identity fields are incomplete",
            details: {
              identity,
              missingFields,
            },
            remediation: "Run `regents identity ensure`",
          };
        }

        const completeIdentity = toCompleteIdentity(identity, missingFields);
        if (!completeIdentity) {
          return {
            status: "warn",
            message: "Protected-route identity fields are incomplete",
            details: {
              identity,
              missingFields,
            },
            remediation: "Run `regents identity ensure`",
          };
        }

        const signerWalletAddress = await deriveSignerWalletAddress(ctx).catch(() => null);
        const issues = [
          !isValidAddress(completeIdentity.walletAddress)
            ? "walletAddress must be a 20-byte hex address"
            : undefined,
          !Number.isSafeInteger(completeIdentity.chainId) || completeIdentity.chainId <= 0
            ? "chainId must be a positive integer"
            : undefined,
          !isValidAddress(completeIdentity.registryAddress)
            ? "registryAddress must be a 20-byte hex address"
            : undefined,
          !isPositiveIntegerString(completeIdentity.tokenId)
            ? "tokenId must be a positive integer string"
            : undefined,
          signerWalletAddress !== null &&
          signerWalletAddress.toLowerCase() !== completeIdentity.walletAddress.toLowerCase()
            ? "configured signer wallet does not match the stored agent wallet address"
            : undefined,
        ].filter((value): value is string => value !== undefined);

        if (issues.length > 0) {
          return {
            status: "fail",
            message: "Protected-route identity fields are invalid",
            details: {
              identity,
              signerWalletAddress,
              issues,
            },
            remediation: "Run `regents identity ensure` again",
          };
        }

        return {
          status: "ok",
          message: "Runtime can produce all required protected-route identity headers",
          details: {
            identity,
            signerWalletAddress,
          },
        };
      },
    },
    {
      id: "auth.siwa.nonce.endpoint",
      scope: "auth",
      title: "SIWA nonce endpoint reachable",
      run: async (ctx) => {
        if (!ctx.config || !ctx.stateStore) {
          return skipDueToMissingConfig();
        }

        try {
          const authClient = new SiwaClient(
            ctx.config.services.siwa.baseUrl,
            ctx.config.services.siwa.requestTimeoutMs,
            ctx.config,
          );
          const identity = getCurrentAgentIdentity(ctx.stateStore);
          const missingFields = getMissingAgentIdentityFields(ctx.stateStore);

          const completeIdentity = toCompleteIdentity(identity, missingFields);
          if (!completeIdentity) {
            return {
              status: "skip",
              message:
                "SIWA nonce probe skipped because protected-route identity is incomplete",
              remediation: "Run `regents identity ensure`",
            };
          }

          const response = await authClient.requestNonce({
            wallet_address: completeIdentity.walletAddress,
            chain_id: completeIdentity.chainId,
            registry_address: completeIdentity.registryAddress,
            token_id: completeIdentity.tokenId,
            audience: ctx.config.auth.audience,
          });

          return {
            status: "ok",
            message: "SIWA nonce endpoint responded successfully",
            details: {
              code: response.code,
              walletAddress: response.data.walletAddress,
              chainId: response.data.chainId,
              expiresAt: response.data.expiresAt,
            },
          };
        } catch (error) {
          return {
            status: "fail",
            message: "SIWA nonce endpoint is unreachable or returned an error",
            details: buildBackendDetails(error),
            remediation: "Verify the SIWA service base URL and endpoint availability",
          };
        }
      },
    },
    {
      id: "auth.siwa.verify.endpoint",
      scope: "auth",
      title: "SIWA verify endpoint reachable",
      run: async (ctx) => {
        if (!ctx.config || !ctx.stateStore) {
          return skipDueToMissingConfig();
        }

        const identity = toCompleteIdentity(
          getCurrentAgentIdentity(ctx.stateStore),
          getMissingAgentIdentityFields(ctx.stateStore),
        );

        if (!identity) {
          return identityIncompleteResult;
        }

        const nonce = `doctor-unverifiable-${Date.now()}`;
        const location = siwaMessageLocation(ctx.config.services.platform.baseUrl);
        const message = buildSiwaMessage({
          domain: location.domain,
          uri: location.uri,
          walletAddress: identity.walletAddress,
          chainId: identity.chainId,
          registryAddress: identity.registryAddress,
          tokenId: identity.tokenId,
          nonce,
          statement: siwaAudienceStatement(ctx.config.auth.audience),
        });

        try {
          const authClient = new SiwaClient(
            ctx.config.services.siwa.baseUrl,
            ctx.config.services.siwa.requestTimeoutMs,
            ctx.config,
          );
          const response = await authClient.verify({
            wallet_address: identity.walletAddress,
            chain_id: identity.chainId,
            registry_address: identity.registryAddress,
            token_id: identity.tokenId,
            audience: ctx.config.auth.audience,
            nonce,
            message,
            signature: `0x${"00".repeat(65)}`,
          });

          return {
            status: "warn",
            message:
              "SIWA verify endpoint is reachable but accepted a deliberately invalid probe",
            details: {
              code: response.code,
              walletAddress: response.data.walletAddress,
              chainId: response.data.chainId,
            },
            remediation:
              "Inspect SIWA verify validation on the SIWA service before relying on this environment",
          };
        } catch (error) {
          const details = buildBackendDetails(error);
          const status =
            typeof details.status === "number" ? details.status : undefined;

          if (
            status !== undefined &&
            status >= 400 &&
            status < 500 &&
            status !== 404 &&
            status !== 405
          ) {
            return {
              status: "ok",
              message:
                "SIWA verify endpoint rejected a deliberately invalid probe, confirming route reachability without persisting a session",
              details,
            };
          }

          return {
            status: "fail",
            message:
              "SIWA verify endpoint is unreachable or did not return a usable denial response",
            details,
            remediation: "Verify the SIWA service base URL and verify route behavior",
          };
        }
      },
    },
    {
      id: "auth.session.present",
      scope: "auth",
      title: "SIWA session",
      run: async (ctx) => {
        if (!ctx.sessionStore) {
          return skipDueToMissingConfig();
        }

        const session = ctx.sessionStore.getSiwaSession();
        if (!session) {
          return {
            status: "warn",
            message: "No active SIWA session found",
            remediation: "Run `regents identity ensure`",
          };
        }

        return {
          status: "ok",
          message: "Active SIWA session found",
          details: {
            walletAddress: session.walletAddress,
            chainId: session.chainId,
            receiptExpiresAt: session.receiptExpiresAt,
          },
        };
      },
    },
    {
      id: "auth.session.freshness",
      scope: "auth",
      title: "SIWA session freshness",
      run: async (ctx) => {
        if (!ctx.sessionStore) {
          return skipDueToMissingConfig();
        }

        const session = ctx.sessionStore.getSiwaSession();
        if (!session) {
          return {
            status: "skip",
            message: "No SIWA session is stored locally",
            remediation: "Run `regents identity ensure`",
          };
        }

        const expiresAt = Date.parse(session.receiptExpiresAt);
        if (!Number.isFinite(expiresAt)) {
          return {
            status: "fail",
            message: "Stored SIWA receipt expiry is invalid",
            details: {
              receiptExpiresAt: session.receiptExpiresAt,
            },
            remediation: "Run `regents identity ensure` again",
          };
        }

        const remainingMs = expiresAt - Date.now();
        if (remainingMs <= 0) {
          return {
            status: "fail",
            message: "Stored SIWA receipt is expired",
            details: {
              receiptExpiresAt: session.receiptExpiresAt,
            },
            remediation: "Run `regents identity ensure` again",
          };
        }

        if (remainingMs <= FRESHNESS_THRESHOLD_MS) {
          return {
            status: "warn",
            message: "Stored SIWA receipt expires soon",
            details: {
              receiptExpiresAt: session.receiptExpiresAt,
              remainingMs,
            },
            remediation: "Run `regents identity ensure` again soon",
          };
        }

        return {
          status: "ok",
          message: "Stored SIWA receipt is fresh",
          details: {
            receiptExpiresAt: session.receiptExpiresAt,
            remainingMs,
          },
        };
      },
    },
    {
      id: "auth.session.binding",
      scope: "auth",
      title: "session binding matches local identity",
      run: async (ctx) => {
        if (!ctx.sessionStore || !ctx.stateStore) {
          return skipDueToMissingConfig();
        }

        const session = ctx.sessionStore.getSiwaSession();
        if (!session) {
          return {
            status: "skip",
            message: "No SIWA session is stored locally",
            remediation: "Run `regents identity ensure`",
          };
        }

        const identity = getCurrentAgentIdentity(ctx.stateStore);
        if (!identity) {
          return {
            status: "fail",
            message:
              "A SIWA session exists, but local protected-route identity is missing",
            remediation: "Run `regents identity ensure`",
          };
        }

        const mismatches = [
          session.walletAddress.toLowerCase() !== identity.walletAddress.toLowerCase()
            ? "walletAddress"
            : undefined,
          session.chainId !== identity.chainId ? "chainId" : undefined,
          session.registryAddress &&
          session.registryAddress.toLowerCase() !==
            identity.registryAddress?.toLowerCase()
            ? "registryAddress"
            : undefined,
          session.tokenId && session.tokenId !== identity.tokenId ? "tokenId" : undefined,
        ].filter((value): value is string => value !== undefined);

        if (mismatches.length > 0) {
          return {
            status: "fail",
            message:
              "Stored SIWA session does not match the local protected-route identity",
            details: {
              session: {
                walletAddress: session.walletAddress,
                chainId: session.chainId,
                registryAddress: session.registryAddress,
                tokenId: session.tokenId,
              },
              identity,
              mismatches,
            },
            remediation: "Run `regents identity ensure` again",
          };
        }

        if (!session.registryAddress || !session.tokenId) {
          return {
            status: "warn",
            message: "Stored SIWA session lacks registry/token binding metadata",
            details: {
              session: {
                walletAddress: session.walletAddress,
                chainId: session.chainId,
              },
              identity,
            },
            remediation: "Run `regents identity ensure` again",
          };
        }

        return {
          status: "ok",
          message: "Stored SIWA session matches the local protected-route identity",
          details: {
            walletAddress: session.walletAddress,
            chainId: session.chainId,
            registryAddress: session.registryAddress,
            tokenId: session.tokenId,
          },
        };
      },
    },
    {
      id: "auth.http-envelope.build",
      scope: "auth",
      title: "HTTP auth envelope builds locally",
      run: async (ctx) => {
        if (!ctx.config || !ctx.sessionStore || !ctx.stateStore) {
          return skipDueToMissingConfig();
        }

        let signingContext: Awaited<
          ReturnType<typeof resolveAuthenticatedAgentSigningContext>
        >;

        try {
          signingContext = await resolveAuthenticatedAgentSigningContext(
            ctx.config,
            ctx.sessionStore,
            ctx.stateStore,
            ctx.config.services.siwa.requestTimeoutMs,
          );
        } catch (error) {
          const code =
            typeof error === "object" && error !== null && "code" in error
              ? String(error.code)
              : null;

          if (code === "siwa_session_missing" || code === "siwa_receipt_expired") {
            return {
              status: "skip",
              message: "No SIWA session is stored locally",
              remediation: "Run `regents identity ensure`",
            };
          }

          if (code === "agent_identity_missing") {
            return {
              status: "skip",
              message: "Protected-route identity is unavailable locally",
              remediation: "Run `regents identity ensure`",
            };
          }

          return {
            status: "fail",
            message: "Authenticated HTTP envelope could not be built locally",
            details: buildBackendDetails(error),
            remediation:
              "Inspect local SIWA session state, signer setup, and identity headers",
          };
        }

        const { session, identity, signer } = signingContext;
        if (!session) {
          return {
            status: "skip",
            message: "No SIWA session is stored locally",
            remediation: "Run `regents identity ensure`",
          };
        }

        try {
          const request = await buildAuthenticatedFetchInit({
            method: "GET",
            path: "/api/techtree/v1/agent/opportunities",
            session,
            agentIdentity: identity,
            signMessage: signer.signMessage,
          });
          const headers = (request.init.headers ?? {}) as Record<
            string,
            string | undefined
          >;
          const requiredHeaders = [
            "x-siwa-receipt",
            "x-key-id",
            "x-timestamp",
            "signature-input",
            "signature",
            "x-agent-wallet-address",
            "x-agent-chain-id",
            "x-agent-registry-address",
            "x-agent-token-id",
          ];
          const missing = requiredHeaders.filter((headerName) => !headers[headerName]);
          const parsedSignatureInput = parseSignatureInputHeader(
            headers["signature-input"] ?? "",
          );
          const expectedCoveredComponents = coveredComponentsForAgentHeaders({
            includeContentDigest: false,
          });
          const missingCoveredComponents = expectedCoveredComponents.filter(
            (component) => !parsedSignatureInput?.coveredComponents.includes(component),
          );
          const timestamp = Number.parseInt(headers["x-timestamp"] ?? "", 10);
          const nowUnixSeconds = Math.floor(Date.now() / 1000);
          const expectedSessionKeyId = session.keyId.trim().toLowerCase();
          const expectedWalletKeyId = session.walletAddress.toLowerCase();
          const signatureIssues = [
            parsedSignatureInput === null
              ? "signature-input could not be parsed"
              : undefined,
            parsedSignatureInput?.label !== "sig1"
              ? "signature-input must use the sig1 label"
              : undefined,
            headers["x-key-id"]?.toLowerCase() !== expectedSessionKeyId
              ? "x-key-id does not match the stored SIWA session keyId"
              : undefined,
            expectedSessionKeyId !== expectedWalletKeyId
              ? "stored SIWA session keyId is not bound to the stored SIWA wallet"
              : undefined,
            headers["x-key-id"]?.toLowerCase() !== expectedWalletKeyId
              ? "x-key-id does not match the receipt wallet binding"
              : undefined,
            headers["x-agent-wallet-address"]?.toLowerCase() !==
            session.walletAddress.toLowerCase()
              ? "x-agent-wallet-address does not match the stored SIWA wallet"
              : undefined,
            headers["x-agent-chain-id"] !== String(session.chainId)
              ? "x-agent-chain-id does not match the stored SIWA chain id"
              : undefined,
            session.registryAddress &&
            headers["x-agent-registry-address"]?.toLowerCase() !==
              session.registryAddress.toLowerCase()
              ? "x-agent-registry-address does not match the stored SIWA registry binding"
              : undefined,
            session.tokenId && headers["x-agent-token-id"] !== session.tokenId
              ? "x-agent-token-id does not match the stored SIWA token binding"
              : undefined,
            !Number.isFinite(timestamp)
              ? "x-timestamp is not a valid unix timestamp"
              : undefined,
            parsedSignatureInput?.params.created === undefined
              ? "signature-input is missing created"
              : undefined,
            parsedSignatureInput?.params.expires === undefined
              ? "signature-input is missing expires"
              : undefined,
            !parsedSignatureInput?.params.nonce
              ? "signature-input is missing nonce"
              : undefined,
            !parsedSignatureInput?.params.keyid
              ? "signature-input is missing keyid"
              : undefined,
            parsedSignatureInput?.params.created !== undefined &&
            parsedSignatureInput.params.created !== timestamp
              ? "signature-input created does not match x-timestamp"
              : undefined,
            parsedSignatureInput?.params.keyid !== undefined &&
            parsedSignatureInput.params.keyid !== headers["x-key-id"]
              ? "signature-input keyid does not match x-key-id"
              : undefined,
            parsedSignatureInput?.params.expires !== undefined &&
            parsedSignatureInput.params.created !== undefined &&
            parsedSignatureInput.params.expires <= parsedSignatureInput.params.created
              ? "signature-input expires must be later than created"
              : undefined,
            parsedSignatureInput?.params.expires !== undefined &&
            parsedSignatureInput.params.expires <= nowUnixSeconds
              ? "signature-input expiry is already in the past"
              : undefined,
            Number.isFinite(timestamp) && Math.abs(nowUnixSeconds - timestamp) > 300
              ? "x-timestamp is outside the expected freshness window"
              : undefined,
          ].filter((value): value is string => value !== undefined);

          if (
            missing.length > 0 ||
            missingCoveredComponents.length > 0 ||
            signatureIssues.length > 0
          ) {
            return {
              status: "fail",
              message:
                "Authenticated HTTP envelope does not satisfy the shared SIWA header and binding contract",
              details: {
                missingHeaders: missing,
                missingCoveredComponents,
                signatureIssues,
              },
              remediation:
                "Inspect the local signer and SIWA header builder implementation",
            };
          }

          return {
            status: "ok",
            message: "Authenticated HTTP envelope builds locally",
            details: {
              path: request.urlPath,
              headers: {
                "x-key-id": headers["x-key-id"],
                "x-timestamp": headers["x-timestamp"],
                "signature-input": headers["signature-input"],
              },
              signatureParams: parsedSignatureInput?.params,
            },
          };
        } catch (error) {
          return {
            status: "fail",
            message: "Authenticated HTTP envelope could not be built locally",
            details: buildBackendDetails(error),
            remediation:
              "Inspect local SIWA session state, signer setup, and identity headers",
          };
        }
      },
    },
  ];
}
