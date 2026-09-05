import fs from "node:fs";
import path from "node:path";
import { getCurrentAgentIdentity } from "../../agent/profile.js";
import { RegentError } from "../../errors.js";
import { readIdentityReceipt } from "../../identity/cache.js";
import { resolveIdentitySigner, resolveSignerFromReceipt } from "../../identity/providers.js";
import { identityNetworkForChainId } from "../../identity/shared.js";
import type { DoctorCheckContext, DoctorCheckOutcome } from "../types.js";

const ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;
const POSITIVE_INTEGER_STRING_REGEX = /^[1-9][0-9]*$/;

const isRecord = (value: unknown): value is Record<string, unknown> =>
    Boolean(value) && typeof value === "object" && !Array.isArray(value);

export function skipDueToMissingConfig(): DoctorCheckOutcome {
    return {
        status: "skip",
        message: "Config is unavailable; later checks were not attempted",
        remediation: "Fix the config load failure first",
    };
}

export function isValidAddress(value: string): boolean {
    return ADDRESS_REGEX.test(value);
}

export function isPositiveIntegerString(value: string): boolean {
    return POSITIVE_INTEGER_STRING_REGEX.test(value);
}

export async function deriveSignerWalletAddress(ctx: DoctorCheckContext): Promise<`0x${string}` | null> {
    const receipt = readIdentityReceipt();
    if (receipt?.provider === "coinbase-cdp" && ctx.config) {
        return (await resolveSignerFromReceipt(receipt, {
            config: ctx.config,
            timeoutMs: ctx.config.services.siwa.requestTimeoutMs,
        })).address;
    }
    const identity = ctx.stateStore ? getCurrentAgentIdentity(ctx.stateStore) : null;
    if (identity?.walletAddress && typeof identity.chainId === "number" && ctx.config) {
        return (await resolveIdentitySigner({
            provider: "coinbase-cdp",
            network: identityNetworkForChainId(identity.chainId),
            walletHint: identity.walletAddress,
            config: ctx.config,
            timeoutMs: ctx.config.services.siwa.requestTimeoutMs,
            expectedAddress: identity.walletAddress,
        })).address;
    }
    if (!ctx.signer) {
        return null;
    }
    return ctx.signer.address();
}

export function buildBackendDetails(error: unknown): Record<string, unknown> {
    if (error instanceof RegentError) {
        const status = isRecord(error) && typeof error.status === "number" ? error.status : undefined;
        return {
            code: error.code,
            message: error.message,
            ...(status === undefined ? {} : { status }),
        };
    }
    if (error instanceof Error) {
        return {
            message: error.message,
        };
    }
    return {
        message: String(error),
    };
}

export function ensureDirExists(dirPath: string): boolean {
    if (fs.existsSync(dirPath)) {
        return false;
    }
    fs.mkdirSync(dirPath, { recursive: true });
    return true;
}

export function uniquePaths(paths: string[]): string[] {
    return [...new Set(paths.map((value) => path.resolve(value)))];
}
