export function createXLinkIntent(storage: Storage | null, appId: string): {
  begin(subject: string): string;
  claim(payload: {user?: {id: string}; linkMethod?: string; linkedAccount?: {type: string}}): string | null;
  cancel(nonce: string | null): void;
};
