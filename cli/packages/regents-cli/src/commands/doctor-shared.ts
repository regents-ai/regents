import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const currentModuleDir = path.dirname(fileURLToPath(import.meta.url));

const ancestorRoots = (start: string): string[] => {
    const roots: string[] = [];
    let current = path.resolve(start);

    while (true) {
        roots.push(current);
        const parent = path.dirname(current);
        if (parent === current) {
            return roots;
        }
        current = parent;
    }
};

const candidateRoots = (): readonly string[] => [
    ...new Set([
        ...ancestorRoots(process.cwd()),
        ...ancestorRoots(currentModuleDir),
    ]),
];

export const findRepoRoot = (): string => {
    for (const root of candidateRoots()) {
        if (fs.existsSync(path.join(root, "docs", "shared-cli-contract.yaml"))) {
            return root;
        }
    }

    return process.cwd();
};

export const fileExists = (filePath: string): boolean => {
    try {
        return fs.existsSync(filePath) && fs.statSync(filePath).isFile();
    }
    catch {
        return false;
    }
};

export const dirExists = (dirPath: string): boolean => {
    try {
        return fs.existsSync(dirPath) && fs.statSync(dirPath).isDirectory();
    }
    catch {
        return false;
    }
};
