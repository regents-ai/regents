import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const packageDir = path.join(repoRoot, "packages", "regents-cli");
const forbiddenIdentityPathFragments = [
  ["/v1", "/identity"].join(""),
  ["v1", "/identity"].join(""),
];
const sourceScanRoots = [
  "package.json",
  "pnpm-workspace.yaml",
  "README.md",
  "CHANGELOG.md",
  "docs",
  "scripts",
  "test-support",
  "packages/regents-cli/package.json",
  "packages/regents-cli/README.md",
  "packages/regents-cli/postinstall.cjs",
  "packages/regents-cli/skills",
  "packages/regents-cli/src",
  "packages/regents-cli/test",
];
const historicalReleaseNotePatterns = [
  /^CHANGELOG\.md$/,
  /^docs\/release-audit-\d{4}-\d{2}-\d{2}\.md$/,
];
const textFileExtensions = new Set([
  ".cjs",
  ".js",
  ".json",
  ".mjs",
  ".md",
  ".ts",
  ".txt",
  ".yaml",
  ".yml",
  ".sh",
]);

const toRelative = (filePath) => path.relative(repoRoot, filePath).split(path.sep).join("/");
const isHistoricalReleaseNote = (relativePath) =>
  historicalReleaseNotePatterns.some((pattern) => pattern.test(relativePath));
const isTextFile = (filePath) => {
  const name = path.basename(filePath);
  return name === "LICENSE" || textFileExtensions.has(path.extname(name));
};
const collectTextFiles = (entryPath) => {
  if (!existsSync(entryPath)) {
    return [];
  }

  const stats = statSync(entryPath);
  if (stats.isFile()) {
    return isTextFile(entryPath) ? [entryPath] : [];
  }

  if (!stats.isDirectory()) {
    return [];
  }

  const files = [];
  for (const entry of readdirSync(entryPath, { withFileTypes: true })) {
    if ([".git", "node_modules"].includes(entry.name)) {
      continue;
    }
    files.push(...collectTextFiles(path.join(entryPath, entry.name)));
  }
  return files;
};
const scanFilesForForbiddenIdentityPaths = (label, files) => {
  const failures = [];

  for (const file of files) {
    const relativePath = toRelative(file);
    if (isHistoricalReleaseNote(relativePath)) {
      continue;
    }

    const text = readFileSync(file, "utf8");
    for (const fragment of forbiddenIdentityPathFragments) {
      if (text.includes(fragment)) {
        failures.push(`${label} contains old shared identity route text ${fragment}: ${relativePath}`);
      }
    }
  }

  return failures;
};

const result = spawnSync("npm", ["pack", "--dry-run", "--json"], {
  cwd: packageDir,
  encoding: "utf8",
});

if (result.status !== 0) {
  process.stderr.write(result.stderr || result.stdout || "npm pack --dry-run failed\n");
  process.exit(result.status ?? 1);
}

const stdout = result.stdout.trim();
if (!stdout) {
  throw new Error("npm pack --dry-run returned no output");
}

const jsonStart = stdout.lastIndexOf("\n[");
const jsonPayload = jsonStart >= 0 ? stdout.slice(jsonStart + 1) : stdout;
const payload = JSON.parse(jsonPayload);
if (!Array.isArray(payload) || payload.length !== 1 || !Array.isArray(payload[0]?.files)) {
  throw new Error("unexpected npm pack --dry-run JSON shape");
}

const tarballFiles = payload[0].files.map((entry) => entry.path).sort();
const requiredFiles = [
  "LICENSE",
  "README.md",
  "package.json",
  "postinstall.cjs",
  "dist/index.js",
  "dist/verify-runtime/pyproject.toml",
  "dist/verify-runtime/uv.lock",
  "dist/verify-runtime/verify_runtime/__main__.py",
  "dist/verify-runtime/verify_runtime/adapters/__init__.py",
  "dist/verify-runtime/verify_runtime/adapters/prime/__init__.py",
  "dist/verify-runtime/verify_runtime/adapters/prime/harness.py",
  "dist/verify-runtime/verify_runtime/adapters/prime/lifecycle.py",
  "dist/verify-runtime/verify_runtime/adapters/prime/live.py",
  "dist/verify-runtime/verify_runtime/adapters/prime/normalize.py",
  "dist/verify-runtime/verify_runtime/adapters/prime/packaging.py",
  "dist/verify-runtime/verify_runtime/capsule/resolution.py",
  "dist/verify-runtime/verify_runtime/families/contract_drift.py",
  "dist/verify-runtime/verify_runtime/forge_family.py",
  "dist/verify-runtime/verify_runtime/model/receipt.py",
  "dist/verify-runtime/verify_runtime/model/reproduction.py",
  "dist/verify-runtime/verify_runtime/model/uplift.py",
  "dist/verify-runtime/verify_runtime/protocol/lock.py",
  "dist/verify-runtime/verify_runtime/receipts/_store.py",
  "dist/verify-runtime/verify_runtime/receipts/store.py",
  "dist/verify-runtime/verify_runtime/runner/engine.py",
  "dist/verify-runtime/verify_runtime/uplift/__init__.py",
  "dist/verify-runtime/verify_runtime/uplift/compare.py",
  "dist/verify-runtime/verify_runtime/uplift/errors.py",
  "dist/verify-runtime/verify_runtime/uplift/package.py",
  "dist/verify-runtime/verify_runtime/uplift/report.py",
  "dist/verify-runtime/verify_runtime/uplift/store.py",
  "skills/regents/SKILL.md",
  "skills/regents-platform/SKILL.md",
  "skills/regents-autolaunch/SKILL.md",
  "skills/regents-techtree/SKILL.md",
];
const unexpectedFiles = tarballFiles.filter(
  (file) =>
    file !== "LICENSE" &&
    file !== "README.md" &&
    file !== "package.json" &&
    file !== "postinstall.cjs" &&
    !file.startsWith("dist/") &&
    !file.startsWith("skills/"),
);

const missingFiles = requiredFiles.filter((file) => !tarballFiles.includes(file));

if (unexpectedFiles.length > 0 || missingFiles.length > 0) {
  const lines = ["packed CLI package contents did not match expectations"];

  if (missingFiles.length > 0) {
    lines.push(`missing: ${missingFiles.join(", ")}`);
  }

  if (unexpectedFiles.length > 0) {
    lines.push(`unexpected: ${unexpectedFiles.join(", ")}`);
  }

  throw new Error(lines.join("\n"));
}

const sourceFiles = sourceScanRoots.flatMap((entry) => collectTextFiles(path.join(repoRoot, entry)));
const packedFiles = tarballFiles
  .map((file) => path.join(packageDir, file))
  .filter((file) => existsSync(file) && statSync(file).isFile() && isTextFile(file));
const identityPathFailures = [
  ...scanFilesForForbiddenIdentityPaths("source release surface", sourceFiles),
  ...scanFilesForForbiddenIdentityPaths("packed CLI package", packedFiles),
];

if (identityPathFailures.length > 0) {
  throw new Error(identityPathFailures.join("\n"));
}

process.stdout.write(
  `Packed CLI package contents verified (${tarballFiles.length} files): LICENSE, README.md, package.json, postinstall.cjs, dist/**, skills/**, and no old shared identity route text.\n`,
);
