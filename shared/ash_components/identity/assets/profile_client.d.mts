// "get" or "update"; any other operation answers invalid_profile_operation and
// sends nothing.
export type ProfileAction = (operation: string,
  input?: {display_name?: string; wallet_address?: string | null},
  options?: {signal?: AbortSignal; expectedProfileId?: string}) => Promise<{
    ok: boolean; status: number | null; body?: any;
    error?: {code: string; outcome_unknown: boolean};
  }>;
export function createProfileClient(options: {
  csrfToken: () => string;
  fetch?: typeof fetch;
}): ProfileAction;
