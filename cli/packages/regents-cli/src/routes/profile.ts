import {runProfile} from "../commands/profile.js";
import type {CliHandlerRegistry} from "./shared.js";
export const profileHandlers: CliHandlerRegistry = {
  "profile get": {run: ({parsedArgs}) => runProfile("get", parsedArgs)},
  "profile sync": {run: ({parsedArgs}) => runProfile("sync", parsedArgs)},
  "profile update": {run: ({parsedArgs}) => runProfile("update", parsedArgs)},
};
