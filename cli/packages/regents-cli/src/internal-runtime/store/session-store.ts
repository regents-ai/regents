import type { AppSiwaSession, SiwaSession } from "../../internal-types/index.js";

import { StateStore } from "./state-store.js";

export class SessionStore {
  readonly stateStore: StateStore;

  constructor(stateStore: StateStore) {
    this.stateStore = stateStore;
  }

  getSiwaSession(): SiwaSession | null {
    return this.stateStore.read().siwa ?? null;
  }

  setSiwaSession(session: SiwaSession): void {
    this.stateStore.patch({ siwa: session });
  }

  getAppSiwaSession(audience: string): AppSiwaSession | null {
    return this.stateStore.read().appSiwaSessions?.[audience] ?? null;
  }

  getAppSiwaSessions(): AppSiwaSession[] {
    return Object.values(this.stateStore.read().appSiwaSessions ?? {});
  }

  setAppSiwaSession(session: AppSiwaSession): void {
    const current = this.stateStore.read().appSiwaSessions ?? {};
    this.stateStore.patch({
      appSiwaSessions: {
        ...current,
        [session.audience]: session,
      },
    });
  }

  clearSiwaSession(): void {
    this.stateStore.patch({ siwa: undefined, appSiwaSessions: {} });
  }

  clearAppSiwaSession(audience: string): void {
    const current = this.stateStore.read().appSiwaSessions ?? {};
    if (!Object.hasOwn(current, audience)) {
      return;
    }

    const next = { ...current };
    delete next[audience];
    this.stateStore.patch({ appSiwaSessions: next });
  }

  isReceiptExpired(nowUnixSeconds = Math.floor(Date.now() / 1000)): boolean {
    const session = this.getSiwaSession();
    if (!session) {
      return true;
    }

    const expiresAtUnixSeconds = Math.floor(Date.parse(session.receiptExpiresAt) / 1000);
    return !Number.isFinite(expiresAtUnixSeconds) || expiresAtUnixSeconds <= nowUnixSeconds;
  }

  isAppSessionExpired(audience: string, nowUnixSeconds = Math.floor(Date.now() / 1000)): boolean {
    const session = this.getAppSiwaSession(audience);
    if (!session) {
      return true;
    }

    const expiresAtUnixSeconds = Math.floor(Date.parse(session.expiresAt) / 1000);
    return !Number.isFinite(expiresAtUnixSeconds) || expiresAtUnixSeconds <= nowUnixSeconds;
  }
}
