import { CliUsageError } from "../cli-usage-error.js";
import { runDoctor, runFullDoctor, runScopedDoctor } from "../internal-runtime/index.js";
import type { DoctorReport, DoctorScope } from "../internal-types/index.js";
import { getBooleanFlag, getFlag, parseIntegerFlag, type ParsedCliArgs } from "../parse.js";
import { printJson, printText } from "../printer.js";
import { renderDoctorReport } from "../printers/doctorPrinter.js";
import { runDoctorContractsCommand } from "./doctor-contracts.js";
import { runDoctorWorkspaceCommand } from "./doctor-workspace.js";

export { CliUsageError } from "../cli-usage-error.js";
export { buildContractDoctorReport, runDoctorContractsCommand } from "./doctor-contracts.js";
export { buildWorkspaceDoctorReport, runDoctorWorkspaceCommand } from "./doctor-workspace.js";

const DOCTOR_SCOPES = ["runtime", "auth", "transports"] as const satisfies readonly DoctorScope[];
type DoctorCommandScope = (typeof DOCTOR_SCOPES)[number] | "contracts" | "workspace";

const DOCTOR_SCOPE_SET = new Set<string>([...DOCTOR_SCOPES, "contracts", "workspace"]);

const isDoctorScope = (value: string): value is DoctorCommandScope => DOCTOR_SCOPE_SET.has(value);

const reportHasInternalFailure = (report: DoctorReport): boolean => {
    return report.checks.some((check) => check.details?.internal === true);
};

const doctorExitCode = (report: DoctorReport): number => {
    if (reportHasInternalFailure(report)) {
        return 3;
    }
    return report.summary.fail > 0 ? 1 : 0;
};

const resolveDoctorScope = (args: ParsedCliArgs): DoctorCommandScope | undefined => {
    const scopeCandidate = args.positionals[1];
    if (!scopeCandidate || scopeCandidate.startsWith("--")) {
        return undefined;
    }
    if (!isDoctorScope(scopeCandidate)) {
        throw new CliUsageError({
            code: "invalid_flag_value",
            message: `invalid doctor scope: ${scopeCandidate}`,
            validValues: [...DOCTOR_SCOPES, "contracts", "workspace"],
        });
    }
    return scopeCandidate;
};

const resolveDoctorParams = (args: ParsedCliArgs) => {
    const full = getBooleanFlag(args, "full");
    return {
        json: getBooleanFlag(args, "json"),
        verbose: getBooleanFlag(args, "verbose"),
        fix: getBooleanFlag(args, "fix"),
        quiet: getBooleanFlag(args, "quiet"),
        onlyFailures: getBooleanFlag(args, "only-failures"),
        ci: getBooleanFlag(args, "ci"),
        full,
        knownParentId: parseIntegerFlag(args, "known-parent-id"),
        cleanupCommentBodyPrefix: getFlag(args, "cleanup-comment-body-prefix"),
    };
};

export async function runDoctorCommand(args: ParsedCliArgs, configPath?: string): Promise<number> {
    const scope = resolveDoctorScope(args);
    const params = resolveDoctorParams(args);
    const { json, verbose, fix, full, quiet, onlyFailures, ci, knownParentId, cleanupCommentBodyPrefix } = params;
    if (scope && full) {
        throw new CliUsageError({
            message: "`regents doctor --full` does not support scoped subcommands",
        });
    }
    if (scope === "contracts") {
        return runDoctorContractsCommand(args, configPath);
    }
    if (scope === "workspace") {
        return runDoctorWorkspaceCommand(args, configPath);
    }
    let report: DoctorReport;
    if (full) {
        report = await runFullDoctor({
            json,
            verbose,
            fix,
            knownParentId,
            cleanupCommentBodyPrefix,
        }, { configPath });
    }
    else if (scope) {
        report = await runScopedDoctor({
                scope,
                json,
                verbose,
                fix,
            }, { configPath });
    }
    else {
        report = await runDoctor({
                json,
                verbose,
                fix,
            }, { configPath });
    }
    if (json) {
        printJson(report);
    }
    else {
        printText(renderDoctorReport(report, { verbose, quiet, onlyFailures, ci }));
    }
    return doctorExitCode(report);
}
