import {
  runAuthSiwaLogin,
  runAuthSiwaLogout,
  runAuthSiwaStatus,
} from "../commands/auth.js";
import { runEnsSetPrimary } from "../commands/ens.js";
import { runIdentityGraph } from "../commands/identity-graph.js";
import { runIdentityEnsure, runIdentityStatus } from "../commands/identity.js";
import {
  runWalletAgenticBalance,
  runWalletAgenticFund,
  runWalletAgenticLogin,
  runWalletAgenticStatus,
  runWalletAgenticVerify,
} from "../commands/wallet-agentic.js";
import { runWalletImport, runWalletSetup, runWalletStatus } from "../commands/wallet.js";
import type { CliHandlerRegistry } from "./shared.js";

export const walletIdentityAuthHandlers: CliHandlerRegistry = {
  "auth login": { run: ({ parsedArgs, configPath }) => runAuthSiwaLogin(parsedArgs, configPath) },
  "auth status": { run: ({ configPath }) => runAuthSiwaStatus(configPath) },
  "auth logout": { run: ({ configPath }) => runAuthSiwaLogout(configPath) },
  "identity ensure": { run: ({ parsedArgs, configPath }) => runIdentityEnsure(parsedArgs, configPath) },
  "identity status": { run: ({ parsedArgs, configPath }) => runIdentityStatus(parsedArgs, configPath) },
  "identity graph": { run: ({ parsedArgs, configPath }) => runIdentityGraph(parsedArgs, configPath) },
  "wallet status": { run: ({ parsedArgs, configPath }) => runWalletStatus(parsedArgs, configPath) },
  "wallet import": { run: ({ parsedArgs, configPath }) => runWalletImport(parsedArgs, configPath) },
  "wallet setup": { run: ({ parsedArgs, configPath }) => runWalletSetup(parsedArgs, configPath) },
  "wallet agentic status": { run: ({ parsedArgs }) => runWalletAgenticStatus(parsedArgs) },
  "wallet agentic login": { run: ({ parsedArgs }) => runWalletAgenticLogin(parsedArgs) },
  "wallet agentic verify": { run: ({ parsedArgs }) => runWalletAgenticVerify(parsedArgs) },
  "wallet agentic balance": { run: ({ parsedArgs }) => runWalletAgenticBalance(parsedArgs) },
  "wallet agentic fund": { run: ({ parsedArgs }) => runWalletAgenticFund(parsedArgs) },
  "ens set-primary": { run: ({ parsedArgs, configPath }) => runEnsSetPrimary(parsedArgs, configPath) },
};
