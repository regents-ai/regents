import type { DoctorCheckResult, DoctorReport, DoctorStatus } from "../internal-types/index.js";
import {
    CLI_PALETTE,
    isHumanTerminal,
    renderKeyValuePanel,
    renderPanel,
    renderTablePanel,
    type TableRow,
} from "../printer.js";

const ANSI = {
    reset: "\x1b[0m",
    bold: "\x1b[1m",
    charcoalBlue: CLI_PALETTE.chrome,
    yaleBlue: CLI_PALETTE.emphasis,
    ivoryMist: CLI_PALETTE.primary,
    sunlitClay: CLI_PALETTE.accent,
    greyOlive: CLI_PALETTE.secondary,
};
export interface RenderDoctorReportOptions {
    verbose?: boolean;
    quiet?: boolean;
    onlyFailures?: boolean;
    ci?: boolean;
}

const useColor = (): boolean => isHumanTerminal();

const tone = (value: string, color: string, bold = false): string => {
    if (!useColor()) {
        return value;
    }
    return `${bold ? ANSI.bold : ""}${color}${value}${ANSI.reset}`;
};

const reportState = (report: DoctorReport): "blocked" | "degraded" | "ready" => {
    if (report.summary.fail > 0) {
        return "blocked";
    }
    if (report.summary.warn > 0 || report.summary.skip > 0) {
        return "degraded";
    }
    return "ready";
};

const statusMeta = (status: DoctorStatus): { glyph: string; label: string; color: string } => {
    switch (status) {
        case "ok":
            return { glyph: "●", label: "ready", color: ANSI.yaleBlue };
        case "warn":
            return { glyph: "◐", label: "watch", color: ANSI.sunlitClay };
        case "fail":
            return { glyph: "◆", label: "block", color: ANSI.sunlitClay };
        case "skip":
            return { glyph: "○", label: "skip", color: ANSI.greyOlive };
    }
};

const scopeLabel = (report: DoctorReport): string => {
    if (report.mode === "scoped" && report.scope) {
        return `${report.scope} scope`;
    }
    if (report.mode === "full") {
        return "full proof";
    }
    return "default sweep";
};

const renderSummaryBand = (report: DoctorReport): string => {
    return renderTablePanel("◆ SUMMARY LEDGER", [
        { header: "metric", color: ANSI.greyOlive },
        { header: "count", align: "right", color: ANSI.greyOlive },
    ], [
        { cells: ["ok", String(report.summary.ok)], colors: [ANSI.yaleBlue, ANSI.yaleBlue] },
        { cells: ["warn", String(report.summary.warn)], colors: [ANSI.sunlitClay, ANSI.sunlitClay] },
        { cells: ["fail", String(report.summary.fail)], colors: [ANSI.sunlitClay, ANSI.sunlitClay] },
        { cells: ["skip", String(report.summary.skip)], colors: [ANSI.greyOlive, ANSI.greyOlive] },
    ], {
        borderColor: ANSI.charcoalBlue,
        titleColor: ANSI.ivoryMist,
    });
};

const formatCheckRow = (check: DoctorCheckResult, verbose: boolean): TableRow => {
    const status = statusMeta(check.status);
    return {
        cells: [
            status.label.toUpperCase(),
            check.title,
            check.message,
            check.remediation ?? (check.fixApplied ? "local fix applied" : ""),
            `${check.durationMs}ms`,
            ...(verbose ? [check.details ? JSON.stringify(check.details) : ""] : []),
        ],
        colors: [
            status.color,
            ANSI.ivoryMist,
            ANSI.ivoryMist,
            check.remediation || check.fixApplied ? ANSI.sunlitClay : ANSI.greyOlive,
            ANSI.greyOlive,
            ...(verbose ? [ANSI.greyOlive] : []),
        ],
    };
};

const renderCiReport = (report: DoctorReport, checks: DoctorCheckResult[]): string => {
    const scope = report.mode === "scoped" && report.scope ? ` ${report.scope}` : "";
    const stateColor = reportState(report) === "ready" ? ANSI.yaleBlue : ANSI.sunlitClay;
    const rows = checks.map((check) => {
        const status = statusMeta(check.status);
        return {
            cells: [
                status.label.toUpperCase(),
                check.id,
                check.message,
            ],
            colors: [status.color, ANSI.ivoryMist, ANSI.ivoryMist],
        };
    });
    const summary = renderKeyValuePanel("◆ CI SUMMARY", [
        { label: "state", value: `${reportState(report).toUpperCase()}${scope}`, valueColor: stateColor },
        { label: "ok", value: String(report.summary.ok), valueColor: ANSI.yaleBlue },
        { label: "warn", value: String(report.summary.warn), valueColor: ANSI.sunlitClay },
        { label: "fail", value: String(report.summary.fail), valueColor: ANSI.sunlitClay },
        { label: "skip", value: String(report.summary.skip), valueColor: ANSI.greyOlive },
    ], {
        borderColor: ANSI.charcoalBlue,
        titleColor: ANSI.ivoryMist,
    });
    const table = rows.length > 0
        ? renderTablePanel("◆ CI CHECKS", [
            { header: "status", color: ANSI.greyOlive },
            { header: "check", color: ANSI.greyOlive },
            { header: "message", color: ANSI.greyOlive },
        ], rows, {
            borderColor: ANSI.charcoalBlue,
            titleColor: ANSI.ivoryMist,
        })
        : renderPanel("◆ CI CHECKS", ["no failing checks"], {
            borderColor: ANSI.charcoalBlue,
            titleColor: ANSI.ivoryMist,
        });
    return [summary, table, ...(report.nextSteps[0] ? [renderPanel("◆ NEXT STEP", [report.nextSteps[0]], {
        borderColor: ANSI.charcoalBlue,
        titleColor: ANSI.ivoryMist,
    })] : [])].join("\n\n");
};

export function renderDoctorReport(report: DoctorReport, options?: RenderDoctorReportOptions): string {
    const selectedChecks = report.checks.filter((check) => {
        if (options?.onlyFailures) {
            return check.status === "fail";
        }
        return true;
    });
    if (options?.ci) {
        const ciChecks = selectedChecks.filter((check) => check.status !== "ok");
        return renderCiReport(report, ciChecks);
    }
    const state = reportState(report);
    const sections = [renderKeyValuePanel("◆ R E G E N T   D O C T O R", [
            { label: "mode", value: scopeLabel(report), valueColor: ANSI.ivoryMist },
            { label: "state", value: state.toUpperCase(), valueColor: state === "ready" ? ANSI.yaleBlue : ANSI.sunlitClay },
            { label: "generated", value: report.generatedAt, valueColor: ANSI.ivoryMist },
        ], {
            borderColor: ANSI.charcoalBlue,
            titleColor: ANSI.ivoryMist,
        }), renderSummaryBand(report)];
    if (!options?.quiet) {
        const checkRows = selectedChecks.map((check) => formatCheckRow(check, options?.verbose ?? false));
        if (checkRows.length > 0) {
            sections.push(renderTablePanel("◆ CHECK GRID", [
                { header: "status", color: ANSI.greyOlive },
                { header: "check", color: ANSI.greyOlive },
                { header: "message", color: ANSI.greyOlive },
                { header: "fix", color: ANSI.greyOlive },
                { header: "time", align: "right", color: ANSI.greyOlive },
                ...(options?.verbose ? [{ header: "details", color: ANSI.greyOlive }] : []),
            ], checkRows, {
                borderColor: ANSI.charcoalBlue,
                titleColor: ANSI.ivoryMist,
            }));
        }
    }
    const nextStepLines = report.nextSteps.length > 0
        ? report.nextSteps.map((step, index) => `${index === 0 ? tone("▶ now", ANSI.sunlitClay, true) : tone("• later", ANSI.greyOlive)} ${step}`)
        : [tone("no follow-up needed", ANSI.yaleBlue, true)];
    sections.push(renderPanel("◆ NEXT MOVES", nextStepLines, {
        borderColor: ANSI.charcoalBlue,
        titleColor: ANSI.ivoryMist,
    }));
    return sections.join("\n\n");
}
