/**
 * OS keychain capability shim. The keychain is an OPTIONAL dependency
 * (`@napi-rs/keyring`): it ships prebuilt native binaries but may be absent
 * (install skipped, unsupported platform, headless container). Every keychain
 * access goes through `loadKeychain()`, which returns `null` when the module or
 * its platform binary cannot be loaded, so callers degrade gracefully instead
 * of crashing.
 */
export interface KeychainApi {
  /** Read a secret, or null when the entry does not exist. */
  get(service: string, account: string): string | null;
  /** Store (or overwrite) a secret. */
  set(service: string, account: string, secret: string): void;
  /** Delete a secret; returns true when an entry was removed. */
  delete(service: string, account: string): boolean;
}

interface NapiEntryConstructor {
  new (service: string, account: string): {
    getPassword(): string;
    setPassword(secret: string): void;
    deletePassword(): boolean;
  };
}

// Test seam: a fake keychain can be injected here so unit tests never touch the
// real OS keychain. Production code leaves this null and uses the native module.
let injectedKeychain: KeychainApi | null | undefined;

/** Test-only: inject a fake keychain (or null to force the unavailable path). */
export const setKeychainForTesting = (keychain: KeychainApi | null): void => {
  injectedKeychain = keychain;
};

/** Test-only: clear any injected keychain and fall back to real capability detection. */
export const resetKeychainForTesting = (): void => {
  injectedKeychain = undefined;
};

const napiEntryToApi = (Entry: NapiEntryConstructor): KeychainApi => ({
  get(service, account) {
    try {
      return new Entry(service, account).getPassword();
    } catch {
      // keyring-rs throws when the entry is missing; treat that as "no value".
      return null;
    }
  },
  set(service, account, secret) {
    new Entry(service, account).setPassword(secret);
  },
  delete(service, account) {
    try {
      return new Entry(service, account).deletePassword();
    } catch {
      return false;
    }
  },
});

/**
 * Load the OS keychain if available. Returns null when the optional dependency
 * or its native binary is missing — callers must handle that (fail closed for
 * the DEK path, never assume a keychain exists).
 */
export const loadKeychain = async (): Promise<KeychainApi | null> => {
  if (injectedKeychain !== undefined) {
    return injectedKeychain;
  }

  try {
    // Indirect specifier so the compiler does not require the optional native
    // module to be present at build time; it is resolved only at runtime.
    const specifier = "@napi-rs/keyring";
    const mod = (await import(specifier)) as unknown as { Entry?: NapiEntryConstructor };
    if (!mod.Entry) {
      return null;
    }

    return napiEntryToApi(mod.Entry);
  } catch {
    return null;
  }
};
