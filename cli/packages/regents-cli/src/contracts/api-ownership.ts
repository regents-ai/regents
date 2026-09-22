import type { paths as ProfilePaths } from "../generated/profile-openapi.js";
import type { paths as PlatformPaths } from "../generated/platform-openapi.js";
import type { paths as RegentServicePaths } from "../generated/regent-services-openapi.js";

export type ApiContractOwner = "techtree" | "platform" | "shared-services";
export type ApiCommandStatus = "current" | "current-local-and-api" | "local";

export interface ApiCommandGroup {
  readonly commands: readonly string[];
  readonly owner: ApiContractOwner;
  readonly status: ApiCommandStatus;
  readonly note?: string;
  readonly pathTemplates: readonly string[];
}

const definePlatformGroup = <
  const TPaths extends readonly ((keyof PlatformPaths) | (keyof ProfilePaths))[],
>(
  group: Omit<ApiCommandGroup, "pathTemplates"> & {
    readonly pathTemplates: TPaths;
  },
) => group;

const defineSharedServicesGroup = <
  const TPaths extends readonly ((keyof RegentServicePaths) | (keyof PlatformPaths))[],
>(
  group: Omit<ApiCommandGroup, "pathTemplates"> & {
    readonly pathTemplates: TPaths;
  },
) => group;

export const profileApiCommandGroups = [definePlatformGroup({
  commands: ["profile get", "profile sync", "profile update"], owner: "platform", status: "current",
  note: "Regents-owned shared profile contract: identity/contracts/profile.openapi.json; paired Privy proof, independent of SIWA.",
  pathTemplates: ["/api/v1/profile", "/api/v1/profile/sync"],
})] as const satisfies readonly ApiCommandGroup[];

export const techtreeApiCommandGroups = [
  {
    commands: ["techtree notebooks init", "techtree notebooks pair"],
    owner: "techtree",
    status: "local",
    note: "Notebook initialization and pairing execute only in the local Regent runtime.",
    pathTemplates: [],
  },
] as const satisfies readonly ApiCommandGroup[];

export const platformApiCommandGroups = [
  definePlatformGroup({
    commands: ["agentbook register", "agentbook sessions watch", "agentbook lookup"],
    owner: "platform",
    status: "current",
    pathTemplates: [
      "/api/platform/agentbook/sessions",
      "/api/platform/agentbook/sessions/{id}",
      "/api/platform/agentbook/lookup",
    ],
  }),
  definePlatformGroup({
    commands: [
      "platform auth login",
      "platform auth status",
      "platform auth logout",
      "platform formation doctor",
      "platform formation status",
      "platform projection",
      "platform billing account",
      "platform billing usage",
      "platform billing spend-controls set",
      "platform billing topup",
      "platform regent runtime",
      "platform regent pause",
      "platform regent resume",
      "agent chat",
    ],
    owner: "platform",
    status: "current",
    pathTemplates: [
      "/api/platform/auth/privy/csrf",
      "/api/platform/auth/privy/session",
      "/api/platform/auth/privy/profile",
      "/api/platform/formation",
      "/api/platform/formation/doctor",
      "/api/platform/projection",
      "/api/platform/billing/account",
      "/api/platform/billing/usage",
      "/api/platform/billing/spend-controls",
      "/api/platform/billing/topups/checkout",
      "/api/platform/agents/{slug}/runtime",
      "/api/platform/sprites/{slug}/pause",
      "/api/platform/sprites/{slug}/resume",
      "/api/platform/sprites/{slug}/message",
    ],
  }),
  definePlatformGroup({
    commands: [
      "service init",
      "service test",
      "service price set",
      "service publish",
      "service pause",
      "service resume",
      "service runs",
      "service logs",
      "service catalog check",
    ],
    owner: "platform",
    status: "current",
    pathTemplates: [
      "/api/platform/agents/{slug}/service-definitions",
      "/api/platform/agents/{slug}/service-definitions/{service_slug}",
      "/api/platform/agents/{slug}/service-definitions/{service_slug}/sandbox-test",
      "/api/platform/agents/{slug}/service-definitions/{service_slug}/pricing",
      "/api/platform/agents/{slug}/service-definitions/{service_slug}/publish",
      "/api/platform/agents/{slug}/service-definitions/{service_slug}/pause",
      "/api/platform/agents/{slug}/service-definitions/{service_slug}/resume",
      "/api/platform/agents/{slug}/service-definitions/{service_slug}/invocations",
      "/api/platform/agents/{slug}/service-definitions/{service_slug}/catalog-readiness",
    ],
  }),
  definePlatformGroup({
    commands: [
      "work create",
      "work list",
      "work get",
      "work run",
      "work cancel",
      "work retry",
      "work watch",
      "work local-loop",
      "runtime create",
      "runtime get",
      "runtime checkpoint",
      "runtime restore",
      "runtime pause",
      "runtime resume",
      "runtime services",
      "runtime health",
      "agent connect hosted-hermes",
      "agent connect openclaw",
      "agent link",
      "agent execution-pool",
    ],
    owner: "platform",
    status: "current",
    pathTemplates: [
      "/api/platform/regents/{regent_id}/rwr/work-items",
      "/api/platform/regents/{regent_id}/rwr/work-items/{work_item_id}",
      "/api/platform/regents/{regent_id}/rwr/work-items/{work_item_id}/runs",
      "/api/platform/regents/{regent_id}/rwr/runs/{run_id}/cancel",
      "/api/platform/regents/{regent_id}/rwr/runs/{run_id}/retry",
      "/api/platform/regents/{regent_id}/rwr/runs/{run_id}/events",
      "/api/platform/regents/{regent_id}/rwr/runs/{run_id}/artifacts",
      "/api/platform/regents/{regent_id}/rwr/runs/{run_id}/delegations",
      "/api/platform/regents/{regent_id}/rwr/runtimes",
      "/api/platform/regents/{regent_id}/rwr/runtimes/{runtime_id}",
      "/api/platform/regents/{regent_id}/rwr/runtimes/{runtime_id}/checkpoint",
      "/api/platform/regents/{regent_id}/rwr/runtimes/{runtime_id}/restore",
      "/api/platform/regents/{regent_id}/rwr/runtimes/{runtime_id}/pause",
      "/api/platform/regents/{regent_id}/rwr/runtimes/{runtime_id}/resume",
      "/api/platform/regents/{regent_id}/rwr/runtimes/{runtime_id}/services",
      "/api/platform/regents/{regent_id}/rwr/runtimes/{runtime_id}/health",
      "/api/platform/regents/{regent_id}/rwr/workers",
      "/api/platform/regents/{regent_id}/rwr/workers/{worker_id}/heartbeat",
      "/api/platform/regents/{regent_id}/rwr/workers/{worker_id}/assignments",
      "/api/platform/regents/{regent_id}/rwr/assignments/{assignment_id}/claim",
      "/api/platform/regents/{regent_id}/rwr/assignments/{assignment_id}/release",
      "/api/platform/regents/{regent_id}/rwr/assignments/{assignment_id}/complete",
      "/api/platform/regents/{regent_id}/rwr/agents/{source_id}/relationships",
      "/api/platform/regents/{regent_id}/rwr/agents/{manager_id}/execution-pool",
    ],
  }),
  definePlatformGroup({
    commands: [
      "regent-staking get",
      "regent-staking account",
      "regent-staking verify",
      "regent-staking stake",
      "regent-staking unstake",
      "regent-staking claim-usdc",
      "regent-staking claim-regent",
      "regent-staking claim-and-restake-regent",
    ],
    owner: "platform",
    status: "current",
    pathTemplates: [
      "/api/shared/regent/staking",
      "/api/shared/regent/staking/account/{address}",
      "/api/shared/regent/staking/stake",
      "/api/shared/regent/staking/unstake",
      "/api/shared/regent/staking/claim-usdc",
      "/api/shared/regent/staking/claim-regent",
      "/api/shared/regent/staking/claim-and-restake-regent",
    ],
  }),
  definePlatformGroup({
    commands: ["bug", "security-report"],
    owner: "platform",
    status: "current",
    pathTemplates: ["/api/platform/v1/agent/bug-report", "/api/platform/v1/agent/security-report"],
  }),
] as const;

export const sharedServicesApiCommandGroups = [
  defineSharedServicesGroup({
    commands: ["identity status"],
    owner: "shared-services",
    status: "current-local-and-api",
    note: "Reads local identity state and shared Regent identity receipt metadata.",
    pathTemplates: ["/api/shared/identity/status"],
  }),
  defineSharedServicesGroup({
    commands: ["identity ensure"],
    owner: "shared-services",
    status: "current-local-and-api",
    note: "Uses local wallet state plus shared Regent SIWA identity issuance.",
    pathTemplates: [
      "/api/shared/identity/status",
      "/api/shared/identity/registration-intents",
      "/api/shared/identity/registration-completions",
      "/api/shared/identity/siwa/nonce",
      "/api/shared/identity/siwa/verify",
    ],
  }),
  defineSharedServicesGroup({
    commands: ["ens set-primary"],
    owner: "shared-services",
    status: "current",
    pathTemplates: ["/api/platform/ens/prepare-primary"],
  }),
] as const;

export const apiCommandOwnership = [
  ...profileApiCommandGroups,
  ...techtreeApiCommandGroups,
  ...platformApiCommandGroups,
  ...sharedServicesApiCommandGroups,
] as const;
