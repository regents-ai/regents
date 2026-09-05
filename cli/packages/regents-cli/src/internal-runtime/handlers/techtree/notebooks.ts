import {
  initNotebookWorkspace,
  pairNotebookWorkspace,
  type NotebookKind,
  type NotebookWorkspaceActionResult,
} from "../../workloads/notebooks.js";

export function handleTechtreeNotebooksInit(params: {
  workspace_path: string;
  kind: NotebookKind;
  title: string;
  source?: string;
}): Promise<NotebookWorkspaceActionResult> {
  return initNotebookWorkspace(params);
}

export function handleTechtreeNotebooksPair(params: {
  workspace_path: string;
}): Promise<NotebookWorkspaceActionResult> {
  return pairNotebookWorkspace(params);
}
