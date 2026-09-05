import type { paths as AutolaunchPaths } from "../generated/autolaunch-openapi.js";
import type { paths as PlatformPaths } from "../generated/platform-openapi.js";
import type { paths as RegentServicePaths } from "../generated/regent-services-openapi.js";

export type ApiContractOwner = "techtree" | "autolaunch" | "platform" | "shared-services";
export type ApiCommandStatus = "current" | "current-local-and-api" | "local";

export interface ApiCommandGroup {
  readonly commands: readonly string[];
  readonly owner: ApiContractOwner;
  readonly status: ApiCommandStatus;
  readonly note?: string;
  readonly pathTemplates: readonly string[];
}

const defineAutolaunchGroup = <
  const TPaths extends readonly (keyof AutolaunchPaths)[],
>(
  group: Omit<ApiCommandGroup, "pathTemplates"> & {
    readonly pathTemplates: TPaths;
  },
) => group;

const definePlatformGroup = <
  const TPaths extends readonly (keyof PlatformPaths)[],
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

export const techtreeApiCommandGroups = [
  {
    commands: ["techtree notebooks init", "techtree notebooks pair"],
    owner: "techtree",
    status: "local",
    note: "Notebook initialization and pairing execute only in the local Regent runtime.",
    pathTemplates: [],
  },
] as const satisfies readonly ApiCommandGroup[];

export const autolaunchApiCommandGroups = [
  defineAutolaunchGroup({
    commands: ["autolaunch agents list", "autolaunch agent <id>", "autolaunch agent readiness <id>"],
    owner: "autolaunch",
    status: "current",
    pathTemplates: [
      "/api/autolaunch/v1/agent/agents",
      "/api/autolaunch/v1/agent/agents/{id}",
      "/api/autolaunch/v1/agent/agents/{id}/readiness",
    ],
  }),
  defineAutolaunchGroup({
    commands: ["autolaunch pair", "autolaunch connect start"],
    owner: "autolaunch",
    status: "current",
    pathTemplates: [
      "/api/autolaunch/v1/agent/agent-connections",
      "/api/autolaunch/v1/agent/agent-connections/{id}",
      "/api/autolaunch/v1/app/agent-connections/{code}",
      "/api/autolaunch/v1/app/agent-connections/{code}/confirm",
    ],
  }),
  defineAutolaunchGroup({
    commands: [
      "autolaunch prelaunch wizard",
      "autolaunch prelaunch get",
      "autolaunch prelaunch validate",
      "autolaunch prelaunch publish",
    ],
    owner: "autolaunch",
    status: "current-local-and-api",
    pathTemplates: [
      "/api/autolaunch/v1/agent/prelaunch/plans",
      "/api/autolaunch/v1/agent/prelaunch/plans/{id}",
      "/api/autolaunch/v1/agent/prelaunch/plans/{id}/validate",
      "/api/autolaunch/v1/agent/prelaunch/plans/{id}/publish",
      "/api/autolaunch/v1/agent/prelaunch/plans/{id}/launch",
      "/api/autolaunch/v1/agent/prelaunch/plans/{id}/metadata",
      "/api/autolaunch/v1/agent/prelaunch/plans/{id}/metadata-preview",
      "/api/autolaunch/v1/app/prelaunch/plans",
      "/api/autolaunch/v1/app/prelaunch/plans/{id}",
      "/api/autolaunch/v1/app/prelaunch/plans/{id}/validate",
      "/api/autolaunch/v1/app/prelaunch/plans/{id}/publish",
      "/api/autolaunch/v1/app/prelaunch/plans/{id}/launch",
      "/api/autolaunch/v1/app/prelaunch/plans/{id}/metadata",
      "/api/autolaunch/v1/app/prelaunch/plans/{id}/metadata-preview",
      "/api/autolaunch/v1/app/launch/preview",
      "/api/autolaunch/v1/app/launch/jobs",
    ],
  }),
  defineAutolaunchGroup({
    commands: [
      "autolaunch launch run",
      "autolaunch launch monitor",
      "autolaunch launch finalize",
      "autolaunch jobs watch",
      "autolaunch vesting status",
      "autolaunch vesting release",
      "autolaunch vesting propose-beneficiary-rotation",
      "autolaunch vesting cancel-beneficiary-rotation",
      "autolaunch vesting execute-beneficiary-rotation",
    ],
    owner: "autolaunch",
    status: "current-local-and-api",
    pathTemplates: [
      "/api/autolaunch/v1/agent/prelaunch/plans/{id}/launch",
      "/api/autolaunch/v1/agent/launch/jobs/{id}",
      "/api/autolaunch/v1/agent/lifecycle/jobs/{id}",
      "/api/autolaunch/v1/agent/lifecycle/jobs/{id}/finalize/prepare",
      "/api/autolaunch/v1/agent/lifecycle/jobs/{id}/finalize/register",
      "/api/autolaunch/v1/app/lifecycle/jobs/{id}/vesting",
      "/api/autolaunch/v1/agent/contracts/jobs/{id}/{resource}/{action}/prepare",
    ],
  }),
  defineAutolaunchGroup({
    commands: [
      "autolaunch auctions list",
      "autolaunch auction-returns list",
      "autolaunch auction <id>",
      "autolaunch bids quote",
    ],
    owner: "autolaunch",
    status: "current",
    pathTemplates: [
      "/api/autolaunch/v1/agent/auctions",
      "/api/autolaunch/v1/agent/auction-returns",
      "/api/autolaunch/v1/agent/auctions/{id}",
      "/api/autolaunch/v1/agent/auctions/{id}/bid_quote",
    ],
  }),
  defineAutolaunchGroup({
    commands: [
      "autolaunch subjects by-token",
      "autolaunch subjects get",
      "autolaunch subjects ingress",
      "autolaunch subjects staking",
      "autolaunch subjects sweep-ingress",
      "autolaunch subjects buybacks",
      "autolaunch subjects payment-links",
      "autolaunch subjects verify",
      "autolaunch payment-links create",
      "autolaunch payment-links set-canonical",
      "autolaunch payment-links set-state",
    ],
    owner: "autolaunch",
    status: "current",
    pathTemplates: [
      "/api/autolaunch/v1/agent/subjects/{id}",
      "/api/autolaunch/v1/agent/subjects/by-token/{token}",
      "/api/autolaunch/v1/agent/subjects/{id}/ingress",
      "/api/autolaunch/v1/agent/subjects/{id}/staking",
      "/api/autolaunch/v1/agent/subjects/{id}/buybacks",
      "/api/autolaunch/v1/agent/subjects/{id}/payment-links",
      "/api/autolaunch/v1/agent/contracts/subjects/{id}/{resource}/{action}/prepare",
    ],
  }),
  defineAutolaunchGroup({
    commands: [
      "autolaunch chat list",
      "autolaunch chat read <scope>",
      "autolaunch chat tail [scope...]",
      "autolaunch chat send <scope>",
      "autolaunch chat unread [scope...]",
      "autolaunch chat subscribe add <scope>",
      "autolaunch chat subscribe remove <scope>",
      "autolaunch chat subscribe list",
      "autolaunch dm <subject-id|address>",
      "autolaunch dm list",
    ],
    owner: "autolaunch",
    status: "current-local-and-api",
    note: "Autolaunch chat HTTP routes; DMs are server-stored dm scopes on the agent chat routes.",
    pathTemplates: [
      "/api/autolaunch/v1/chat/channels",
      "/api/autolaunch/v1/chat/messages",
      "/api/autolaunch/v1/chat/stream",
      "/api/autolaunch/v1/agent/chat/messages",
      "/api/autolaunch/v1/agent/chat/dms",
      "/api/autolaunch/v1/app/subjects/{id}",
    ],
  }),
  defineAutolaunchGroup({
    commands: ["autolaunch ens plan", "autolaunch ens prepare-ensip25", "autolaunch ens prepare-erc8004", "autolaunch ens prepare-bidirectional"],
    owner: "autolaunch",
    status: "current",
    pathTemplates: [
      "/api/autolaunch/v1/agent/ens/link/plan",
      "/api/autolaunch/v1/agent/ens/link/prepare-ensip25",
      "/api/autolaunch/v1/agent/ens/link/prepare-erc8004",
      "/api/autolaunch/v1/agent/ens/link/prepare-bidirectional",
    ],
  }),
  defineAutolaunchGroup({
    commands: [
      "autolaunch contracts admin",
      "autolaunch contracts job",
      "autolaunch contracts subject",
      "autolaunch contracts verify",
      "autolaunch strategy migrate",
      "autolaunch auction claim-unused-tokens",
      "autolaunch strategy sweep-token",
      "autolaunch strategy sweep-quote-token",
      "autolaunch fee-registry get",
      "autolaunch fee-vault get",
      "autolaunch fee-vault withdraw-regent",
      "autolaunch splitter get",
      "autolaunch splitter accept-ownership",
      "autolaunch splitter set-paused",
      "autolaunch splitter set-label",
      "autolaunch splitter propose-eligible-revenue-share",
      "autolaunch splitter cancel-eligible-revenue-share",
      "autolaunch splitter activate-eligible-revenue-share",
      "autolaunch splitter propose-treasury-recipient-rotation",
      "autolaunch splitter cancel-treasury-recipient-rotation",
      "autolaunch splitter execute-treasury-recipient-rotation",
      "autolaunch splitter sweep-treasury-residual",
      "autolaunch splitter sweep-treasury-reserved",
      "autolaunch splitter reassign-dust",
      "autolaunch ingress create",
      "autolaunch ingress set-default",
      "autolaunch ingress set-label",
      "autolaunch ingress rescue",
      "autolaunch registry get",
      "autolaunch registry set-subject-manager",
      "autolaunch registry link-identity",
      "autolaunch registry rotate-safe",
      "autolaunch factory revenue-share set-authorized-creator",
      "autolaunch factory revenue-ingress set-authorized-creator",
    ],
    owner: "autolaunch",
    status: "current",
    pathTemplates: [
      "/api/autolaunch/v1/app/contracts/admin",
      "/api/autolaunch/v1/agent/contracts/jobs/{id}",
      "/api/autolaunch/v1/app/contracts/subjects/{id}",
      "/api/autolaunch/v1/agent/contracts/jobs/{id}/{resource}/{action}/prepare",
      "/api/autolaunch/v1/agent/contracts/subjects/{id}/{resource}/{action}/prepare",
      "/api/autolaunch/v1/app/contracts/admin/{resource}/{action}/prepare",
    ],
  }),
] as const;

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
  ...techtreeApiCommandGroups,
  ...autolaunchApiCommandGroups,
  ...platformApiCommandGroups,
  ...sharedServicesApiCommandGroups,
] as const;
