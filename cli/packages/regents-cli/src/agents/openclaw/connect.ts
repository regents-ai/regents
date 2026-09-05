import path from "node:path";
import { mkdir, writeFile } from "node:fs/promises";

import { expandHome } from "../../internal-runtime/index.js";
import { renderOpenClawRegentsWorkSkill } from "./skill-template.js";

export interface WriteOpenClawSkillInput {
  readonly regentId: string;
  readonly workerId: string;
  readonly workerName: string;
  readonly skillPath?: string;
}

export interface WriteOpenClawSkillResult {
  readonly skillPath: string;
}

export const defaultOpenClawSkillPath = (): string =>
  path.join(process.env.HOME ?? process.env.USERPROFILE ?? "~", ".openclaw", "skills", "regents-work", "SKILL.md");

export const writeOpenClawRegentsWorkSkill = async (
  input: WriteOpenClawSkillInput,
): Promise<WriteOpenClawSkillResult> => {
  const skillPath = path.resolve(expandHome(input.skillPath ?? defaultOpenClawSkillPath()));
  await mkdir(path.dirname(skillPath), { recursive: true });
  await writeFile(
    skillPath,
    renderOpenClawRegentsWorkSkill({
      regentId: input.regentId,
      workerId: input.workerId,
      workerName: input.workerName,
    }),
    "utf8",
  );

  return { skillPath };
};
