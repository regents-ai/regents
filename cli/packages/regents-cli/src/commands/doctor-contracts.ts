import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import { CLI_COMMANDS } from "../command-registry.js";
import { getBooleanFlag, type ParsedCliArgs } from "../parse.js";
import { printJson, printText } from "../printer.js";
import { renderTablePanel } from "../terminal/table.js";
import { fileExists, findRepoRoot } from "./doctor-shared.js";

type ContractKind = "api" | "cli" | "runtime";

interface LocalContractEntry {
    readonly owner: string;
    readonly kind: ContractKind;
    readonly contractPath: string;
    readonly generatedPaths: readonly string[];
}

interface ContractDoctorFileResult extends LocalContractEntry {
    readonly loaded: boolean;
    readonly version: string | null;
    readonly hash: string | null;
    readonly generatedStatus: "present" | "missing" | "not_applicable";
    readonly commandStatus: "covered" | "missing" | "not_applicable";
    readonly commandCount: number;
    readonly missingCommands: readonly string[];
}

interface ContractDoctorReport {
    readonly ok: boolean;
    readonly command: "regents doctor contracts";
    readonly root: string;
    readonly files: readonly ContractDoctorFileResult[];
    readonly summary: {
        readonly loaded: number;
        readonly missingFiles: number;
        readonly missingGeneratedBindings: number;
        readonly missingCommands: number;
    };
}

const localContractEntries = (root: string): readonly LocalContractEntry[] => [
    {
        owner: "shared-services",
        kind: "api",
        contractPath: path.join(root, "docs/regent-services-contract.openapiv3.yaml"),
        generatedPaths: [path.join(root, "packages/regents-cli/src/generated/regent-services-openapi.ts")],
    },
    {
        owner: "regents-cli",
        kind: "cli",
        contractPath: path.join(root, "docs/shared-cli-contract.yaml"),
        generatedPaths: [
            path.join(root, "packages/regents-cli/src/generated/cli-command-metadata.ts"),
            path.join(root, "docs/regents-cli-command-list.md"),
        ],
    },
    {
        owner: "regents-cli",
        kind: "runtime",
        contractPath: path.join(root, "docs/json-rpc-methods.yaml"),
        generatedPaths: [path.join(root, "docs/json-rpc-methods.md")],
    },
];

const sha256Short = (content: string): string =>
    crypto.createHash("sha256").update(content).digest("hex").slice(0, 12);

const extractVersion = (content: string): string | null => {
    const infoVersion = content.match(/^\s{2}version:\s*["']?([^"'\n]+)["']?\s*$/mu)?.[1];
    return infoVersion?.trim() ?? content.match(/^version:\s*["']?([^"'\n]+)["']?\s*$/mu)?.[1]?.trim() ?? null;
};

const extractContractCommands = (content: string): readonly string[] => {
    const commands = new Set<string>();
    const lines = content.split(/\r?\n/u);
    let commandListIndent: number | null = null;
    for (const line of lines) {
        if (/^\s*$|^\s*#/u.test(line)) continue;
        const indent = line.match(/^\s*/u)?.[0].length ?? 0;
        if (commandListIndent !== null && indent <= commandListIndent && !/^\s*-\s/u.test(line)) {
            commandListIndent = null;
        }
        if (/^\s*commands:\s*$/u.test(line)) {
            commandListIndent = indent;
            continue;
        }
        const command = commandListIndent !== null && indent === commandListIndent + 2
            ? line.match(/^\s*-\s+(.+)$/u)?.[1]?.replace(/\s+#.*$/u, "").replace(/^["']|["']$/gu, "").replace(/^regents?\s+/u, "").trim()
            : undefined;
        if (command && !command.includes(":")) commands.add(command);
    }
    return [...commands].sort();
};

const contractFileResult = (entry: LocalContractEntry): ContractDoctorFileResult => {
    const loaded = fileExists(entry.contractPath);
    const generatedStatus = entry.generatedPaths.length === 0
        ? "not_applicable"
        : entry.generatedPaths.every(fileExists) ? "present" : "missing";
    if (!loaded) {
        return {
            ...entry, loaded, version: null, hash: null, generatedStatus,
            commandStatus: entry.kind === "cli" ? "missing" : "not_applicable",
            commandCount: 0, missingCommands: [],
        };
    }
    const content = fs.readFileSync(entry.contractPath, "utf8");
    const commands = entry.kind === "cli" ? extractContractCommands(content) : [];
    const missingCommands = commands.filter((command) => !CLI_COMMANDS.includes(command as (typeof CLI_COMMANDS)[number]));
    return {
        ...entry,
        loaded,
        version: extractVersion(content),
        hash: sha256Short(content),
        generatedStatus,
        commandStatus: entry.kind === "cli" ? missingCommands.length === 0 ? "covered" : "missing" : "not_applicable",
        commandCount: commands.length,
        missingCommands,
    };
};

export const buildContractDoctorReport = (): ContractDoctorReport => {
    const root = findRepoRoot();
    const files = localContractEntries(root).map(contractFileResult);
    const missingFiles = files.filter((file) => !file.loaded).length;
    const missingGeneratedBindings = files.filter((file) => file.generatedStatus === "missing").length;
    const missingCommands = files.reduce((count, file) => count + file.missingCommands.length, 0);
    return {
        ok: missingFiles === 0 && missingGeneratedBindings === 0 && missingCommands === 0,
        command: "regents doctor contracts",
        root,
        files,
        summary: {
            loaded: files.filter((file) => file.loaded).length,
            missingFiles,
            missingGeneratedBindings,
            missingCommands,
        },
    };
};

const renderContractDoctorReport = (report: ContractDoctorReport): string => renderTablePanel(
    "LOCAL CONTRACTS",
    [
        { header: "owner" }, { header: "kind" }, { header: "contract" }, { header: "version" },
        { header: "hash" }, { header: "generated" }, { header: "commands" },
    ],
    report.files.map((file) => ({
        cells: [
            file.owner,
            file.kind,
            path.relative(report.root, file.contractPath),
            file.version ?? "unknown",
            file.hash ?? "missing",
            file.generatedStatus,
            file.commandStatus === "not_applicable" ? "-" : `${file.commandStatus} (${file.commandCount})`,
        ],
    })),
);

export const runDoctorContractsCommand = (args: ParsedCliArgs, _configPath?: string): number => {
    const report = buildContractDoctorReport();
    if (getBooleanFlag(args, "json")) printJson(report);
    else printText(renderContractDoctorReport(report));
    return report.ok ? 0 : 1;
};
