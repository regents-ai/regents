import path from "node:path";

import { getBooleanFlag, type ParsedCliArgs } from "../parse.js";
import { printJson, printText } from "../printer.js";
import { renderTablePanel } from "../terminal/table.js";
import { fileExists, findRepoRoot } from "./doctor-shared.js";

interface LocalWorkspaceFile {
    readonly label: string;
    readonly path: string;
    readonly loaded: boolean;
}

interface WorkspaceDoctorReport {
    readonly ok: boolean;
    readonly command: "regents doctor workspace";
    readonly root: string;
    readonly files: readonly LocalWorkspaceFile[];
    readonly summary: {
        readonly requiredFiles: number;
        readonly missingFiles: number;
    };
}

const requiredFiles = (root: string): readonly Omit<LocalWorkspaceFile, "loaded">[] => [
    { label: "workspace package", path: path.join(root, "package.json") },
    { label: "CLI package", path: path.join(root, "packages/regents-cli/package.json") },
    { label: "shared CLI contract", path: path.join(root, "docs/shared-cli-contract.yaml") },
    { label: "shared services contract", path: path.join(root, "docs/regent-services-contract.openapiv3.yaml") },
    { label: "runtime contract", path: path.join(root, "docs/json-rpc-methods.yaml") },
    { label: "WalletAction schema", path: path.join(root, "docs/schemas/wallet-action.schema.yaml") },
    { label: "CLI command metadata", path: path.join(root, "packages/regents-cli/src/generated/cli-command-metadata.ts") },
    { label: "Platform copied API binding", path: path.join(root, "packages/regents-cli/src/generated/platform-openapi.ts") },
    { label: "Ash Techtree copied API binding", path: path.join(root, "packages/regents-cli/src/generated/ash-techtree-openapi.ts") },
    { label: "Autolaunch copied API binding", path: path.join(root, "packages/regents-cli/src/generated/autolaunch-openapi.ts") },
    { label: "shared services generated binding", path: path.join(root, "packages/regents-cli/src/generated/regent-services-openapi.ts") },
];

export const buildWorkspaceDoctorReport = (): WorkspaceDoctorReport => {
    const root = findRepoRoot();
    const files = requiredFiles(root).map((file) => ({ ...file, loaded: fileExists(file.path) }));
    const missingFiles = files.filter((file) => !file.loaded).length;
    return {
        ok: missingFiles === 0,
        command: "regents doctor workspace",
        root,
        files,
        summary: { requiredFiles: files.length, missingFiles },
    };
};

const renderWorkspaceDoctorReport = (report: WorkspaceDoctorReport): string => renderTablePanel(
    "LOCAL WORKSPACE",
    [{ header: "input" }, { header: "present" }, { header: "path" }],
    report.files.map((file) => ({
        cells: [file.label, file.loaded ? "yes" : "no", path.relative(report.root, file.path)],
    })),
);

export const runDoctorWorkspaceCommand = (args: ParsedCliArgs, _configPath?: string): number => {
    const report = buildWorkspaceDoctorReport();
    if (getBooleanFlag(args, "json")) printJson(report);
    else printText(renderWorkspaceDoctorReport(report));
    return report.ok ? 0 : 1;
};
