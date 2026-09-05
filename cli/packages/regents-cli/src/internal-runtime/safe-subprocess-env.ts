const allowedBaseEnvNames = new Set([
  "PATH",
  "HOME",
  "USER",
  "USERNAME",
  "USERPROFILE",
  "SYSTEMROOT",
  "WINDIR",
  "APPDATA",
  "LOCALAPPDATA",
  "TMPDIR",
  "TEMP",
  "TMP",
  "SHELL",
  "TERM",
  "NO_COLOR",
  "FORCE_COLOR",
  "CI",
  "LANG",
  "LC_ALL",
  "LC_CTYPE",
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "NO_PROXY",
  "http_proxy",
  "https_proxy",
  "no_proxy",
]);

const blockedNameFragments = [
  "ACCESS_TOKEN",
  "API_KEY",
  "AUTHORIZATION",
  "BEARER",
  "COOKIE",
  "CREDENTIAL",
  "IDENTITY_TOKEN",
  "MNEMONIC",
  "PASSWORD",
  "PAYMENT",
  "PRIVATE_KEY",
  "REFRESH_TOKEN",
  "SECRET",
  "SESSION",
  "TOKEN",
  "WALLET",
  "X_PAYMENT",
];

const blockedNamePrefixes = [
  "AUTOLAUNCH_",
  "CDP_",
  "COINBASE_",
  "PLATFORM_",
  "PRIVY_",
  "REGENT_",
  "SIWA_",
  "TECHTREE_",
];

interface SafeSubprocessEnvOptions {
  readonly trustedOverrideNames?: readonly string[];
}

export const isBlockedSubprocessEnvName = (name: string): boolean => {
  const normalizedName = name.toUpperCase();

  return (
    blockedNamePrefixes.some((prefix) => normalizedName.startsWith(prefix)) ||
    blockedNameFragments.some((fragment) => normalizedName.includes(fragment))
  );
};

export const buildSafeSubprocessEnv = (
  baseEnv: NodeJS.ProcessEnv = process.env,
  overrides: NodeJS.ProcessEnv = {},
  options: SafeSubprocessEnvOptions = {},
): NodeJS.ProcessEnv => {
  const env: NodeJS.ProcessEnv = {};

  for (const [name, value] of Object.entries(baseEnv)) {
    if (value === undefined || !allowedBaseEnvNames.has(name) || isBlockedSubprocessEnvName(name)) {
      continue;
    }

    env[name] = value;
  }

  const trustedOverrideNames = new Set(options.trustedOverrideNames ?? []);

  for (const [name, value] of Object.entries(overrides)) {
    if (value === undefined) {
      continue;
    }

    if (isBlockedSubprocessEnvName(name) && !trustedOverrideNames.has(name)) {
      throw new Error(`refusing to pass sensitive environment variable to workload subprocess: ${name}`);
    }

    env[name] = value;
  }

  return env;
};
