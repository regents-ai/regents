export type ProfileAction = (operation: "get" | "sync" | "update",
  input?: {display_name?: string; wallet_address?: string | null},
  options?: {signal?: AbortSignal; expectedProfileId?: string}) => Promise<{
    ok: boolean; status: number | null; body?: any;
    error?: {code: string; outcome_unknown: boolean};
  }>;
export function createProfileClient(options: {
  acquireProof: (options: {signal: AbortSignal}) => Promise<{
    accessToken: string; identityToken: string; subject: string; isCurrent: () => boolean;
  } | null>;
  fetch?: typeof fetch;
}): ProfileAction;
export function loadProfileAction(load: () => Promise<ProfileAction>, ...args: Parameters<ProfileAction>): ReturnType<ProfileAction>;
