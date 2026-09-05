import { runBugReport, runSecurityReport } from "../commands/reports.js";
import type { CliHandlerRegistry } from "./shared.js";

export const reportingHandlers: CliHandlerRegistry = {
  bug: { run: ({ parsedArgs, configPath }) => runBugReport(parsedArgs, configPath) },
  "security-report": { run: ({ parsedArgs, configPath }) => runSecurityReport(parsedArgs, configPath) },
};
