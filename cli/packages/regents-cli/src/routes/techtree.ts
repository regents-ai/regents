import {
  runTechtreeForgeFamilyShow,
  runTechtreeForgeFamilyValidate,
} from "../commands/techtree-forge.js";
import {
  runTechtreeNotebooksInit,
  runTechtreeNotebooksPair,
} from "../commands/techtree-notebooks.js";
import {
  runTechtreeVerifyReceiptShow,
  runTechtreeVerifyRun,
  runTechtreeVerifyStatus,
} from "../commands/techtree-verify.js";
import { runTechtreeUpliftReport } from "../commands/techtree-uplift.js";
import type { CliHandlerRegistry } from "./shared.js";

export const techtreeHandlers: CliHandlerRegistry = {
  "techtree forge family show": { run: () => runTechtreeForgeFamilyShow() },
  "techtree forge family validate": {
    run: ({ parsedArgs }) => runTechtreeForgeFamilyValidate(parsedArgs),
  },
  "techtree verify run": {
    run: ({ parsedArgs, configPath }) => runTechtreeVerifyRun(parsedArgs, configPath),
  },
  "techtree verify status": {
    run: ({ parsedArgs, configPath }) => runTechtreeVerifyStatus(parsedArgs, configPath),
  },
  "techtree verify receipt show": {
    run: ({ parsedArgs, configPath }) => runTechtreeVerifyReceiptShow(parsedArgs, configPath),
  },
  "techtree uplift report": {
    run: ({ parsedArgs, configPath }) => runTechtreeUpliftReport(parsedArgs, configPath),
  },
  "techtree notebooks init": {
    run: ({ parsedArgs, configPath }) => runTechtreeNotebooksInit(parsedArgs, configPath),
  },
  "techtree notebooks pair": {
    run: ({ parsedArgs, configPath }) => runTechtreeNotebooksPair(parsedArgs, configPath),
  },
};
