import type { DoctorCheckResult } from "../../internal-types/index.js";

const CHECK_PRIORITY = {
    "runtime.config.load": 0,
    "runtime.paths.ensure": 1,
    "runtime.socket.reachable": 2,
    "runtime.platform.contract": 3,
    "runtime.wallet.source": 4,
    "auth.identity.headers": 5,
    "auth.siwa.nonce.endpoint": 6,
    "auth.siwa.verify.endpoint": 7,
    "auth.session.present": 8,
    "auth.session.freshness": 9,
    "auth.session.binding": 10,
    "auth.http-envelope.build": 11,
    "transports.gossipsub.config": 12,
} as const satisfies Record<string, number>;
const STATUS_PRIORITY = {
    fail: 0,
    warn: 1,
    skip: 2,
    ok: 3,
} as const;

export function deriveNextSteps(checks: DoctorCheckResult[]): string[] {
    const nextSteps = new Set<string>();
    const actionableChecks = [...checks]
        .filter((check) => check.status !== "ok" && check.remediation)
        .sort((left, right) => {
        const byStatus = STATUS_PRIORITY[left.status] - STATUS_PRIORITY[right.status];
        if (byStatus !== 0) {
            return byStatus;
        }
        const leftPriority = CHECK_PRIORITY[left.id as keyof typeof CHECK_PRIORITY] ?? Number.MAX_SAFE_INTEGER;
        const rightPriority = CHECK_PRIORITY[right.id as keyof typeof CHECK_PRIORITY] ?? Number.MAX_SAFE_INTEGER;
        if (leftPriority !== rightPriority) {
            return leftPriority - rightPriority;
        }
        return left.id.localeCompare(right.id);
    });
    for (const check of actionableChecks) {
        if (!check.remediation) {
            continue;
        }
        nextSteps.add(check.remediation);
    }
    return [...nextSteps];
}
