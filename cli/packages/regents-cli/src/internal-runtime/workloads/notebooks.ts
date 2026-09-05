import fs from "node:fs";
import path from "node:path";

export type NotebookKind = "paper" | "freeform";

export interface NotebookWorkspaceActionResult {
  ok: true;
  workspace_path: string;
  notebook_path: string;
  manifest_path: string;
  next: string[];
}

interface NotebookManifest {
  schema: "regents.techtree.notebook.v1";
  kind: NotebookKind;
  title: string;
  source: string | null;
  summary: string;
  notebook_file: string;
  created_at: string;
}

const manifestFile = "notebook.json";
const notebookFile = "analysis.py";

const ensureDirectory = (workspacePath: string): void => {
  fs.mkdirSync(workspacePath, { recursive: true });
};

const writeFileIfMissing = (filePath: string, body: string): void => {
  if (!fs.existsSync(filePath)) {
    fs.writeFileSync(filePath, body);
  }
};

const notebookSource = (title: string): string => `import marimo

__generated_with = "0.9.32"
app = marimo.App(width="medium")


@app.cell
def __():
    import marimo as mo
    mo.md("# ${title.replaceAll('"', '\\"')}")
    return mo,


@app.cell
def __(mo):
    mo.md("Use this notebook to record the question, method, evidence, result, and limits.")
    return


if __name__ == "__main__":
    app.run()
`;

const readManifest = (workspacePath: string): NotebookManifest => {
  const manifestPath = path.join(workspacePath, manifestFile);
  const parsed = JSON.parse(fs.readFileSync(manifestPath, "utf8")) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("invalid notebook manifest");
  }

  const manifest = parsed as NotebookManifest;
  if (manifest.schema !== "regents.techtree.notebook.v1") {
    throw new Error("invalid notebook manifest schema");
  }

  if (manifest.kind !== "paper" && manifest.kind !== "freeform") {
    throw new Error("invalid notebook kind");
  }

  if (!manifest.title || !manifest.notebook_file) {
    throw new Error("notebook manifest is missing required fields");
  }

  return manifest;
};

export async function initNotebookWorkspace(input: {
  workspace_path: string;
  kind: NotebookKind;
  title: string;
  source?: string;
}): Promise<NotebookWorkspaceActionResult> {
  const workspacePath = path.resolve(input.workspace_path);
  ensureDirectory(workspacePath);

  const manifest: NotebookManifest = {
    schema: "regents.techtree.notebook.v1",
    kind: input.kind,
    title: input.title,
    source: input.source ?? null,
    summary: input.kind === "paper"
      ? `Paper notebook for ${input.source ?? input.title}.`
      : "Freeform research notebook.",
    notebook_file: notebookFile,
    created_at: new Date().toISOString(),
  };

  const manifestPath = path.join(workspacePath, manifestFile);
  const notebookPath = path.join(workspacePath, notebookFile);
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  writeFileIfMissing(notebookPath, notebookSource(input.title));
  writeFileIfMissing(path.join(workspacePath, "README.md"), [
    `# ${input.title}`,
    "",
    "Use this folder to capture the research question, method, evidence, and result.",
    "",
  ].join("\n"));

  return {
    ok: true,
    workspace_path: workspacePath,
    notebook_path: notebookPath,
    manifest_path: manifestPath,
    next: [`uvx marimo edit ${notebookPath}`],
  };
}

export async function pairNotebookWorkspace(input: {
  workspace_path: string;
}): Promise<NotebookWorkspaceActionResult> {
  const workspacePath = path.resolve(input.workspace_path);
  const manifest = readManifest(workspacePath);
  const notebookPath = path.join(workspacePath, manifest.notebook_file);

  if (!fs.existsSync(notebookPath)) {
    throw new Error(`notebook file is missing: ${notebookPath}`);
  }

  return {
    ok: true,
    workspace_path: workspacePath,
    notebook_path: notebookPath,
    manifest_path: path.join(workspacePath, manifestFile),
    next: [`uvx marimo edit ${notebookPath}`],
  };
}
