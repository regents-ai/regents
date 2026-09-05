import {
  runRegentStakingAccount,
  runRegentStakingClaimAndRestakeRegent,
  runRegentStakingClaimRegent,
  runRegentStakingClaimUsdc,
  runRegentStakingGet,
  runRegentStakingStake,
  runRegentStakingUnstake,
} from "../commands/regent-staking.js";
import { runRegentStakingVerify } from "../commands/regent-staking-verify.js";
import type { CliHandlerRegistry } from "./shared.js";

export const regentStakingHandlers: CliHandlerRegistry = {
  "regent-staking get": { run: ({ configPath }) => runRegentStakingGet(configPath) },
  "regent-staking account": { run: ({ parsedArgs, configPath }) => runRegentStakingAccount(parsedArgs, configPath), variadicTail: true },
  "regent-staking verify": { run: ({ parsedArgs, configPath }) => runRegentStakingVerify(parsedArgs, configPath), variadicTail: true },
  "regent-staking stake": { run: ({ parsedArgs, configPath }) => runRegentStakingStake(parsedArgs, configPath) },
  "regent-staking unstake": { run: ({ parsedArgs, configPath }) => runRegentStakingUnstake(parsedArgs, configPath) },
  "regent-staking claim-usdc": { run: ({ parsedArgs, configPath }) => runRegentStakingClaimUsdc(parsedArgs, configPath) },
  "regent-staking claim-regent": { run: ({ parsedArgs, configPath }) => runRegentStakingClaimRegent(parsedArgs, configPath) },
  "regent-staking claim-and-restake-regent": { run: ({ parsedArgs, configPath }) => runRegentStakingClaimAndRestakeRegent(parsedArgs, configPath) },
};
