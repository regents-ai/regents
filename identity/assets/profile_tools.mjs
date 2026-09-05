// All products expose this same private profile contract. Credential acquisition
// stays inside the supplied action; tool inputs never contain tokens or actor IDs.
export function profileTools(profile, lifetime) {
  const specs = [
    ["profile_get", "get", "Read your shared profile and last synchronized wallet/X verification.", {}],
    ["profile_sync", "sync", "Explicitly refresh your shared profile from signed Privy evidence. Does not change payment destinations.", {}],
    ["profile_update", "update", "Edit your shared name or choose a linked wallet. Does not change payment destinations or send a transaction.", {
      display_name: {type: "string", maxLength: 80},
      wallet_address: {type: ["string", "null"], description: "A linked Ethereum address, or null to clear the profile selection."},
    }],
  ];
  return specs.map(([name, operation, description, properties]) => ({
    name, description,
    inputSchema: {type: "object", properties, additionalProperties: false, ...(operation === "update" ? {minProperties: 1} : {})},
    annotations: {readOnlyHint: operation === "get", consequentialHint: operation !== "get", untrustedContentHint: true},
    execute(input, {signal}) {
      if (!input || typeof input !== "object" || Array.isArray(input) ||
          Object.entries(input).some(([key, value]) => !Object.hasOwn(properties, key) ||
            (typeof value !== "string" && !(key === "wallet_address" && value === null))) ||
          (operation === "update" && Object.keys(input).length === 0)) {
        return Promise.resolve({ok: false, status: null, error: {code: "invalid_profile_operation", outcome_unknown: false}});
      }
      return profile(operation, input, {signal: AbortSignal.any([lifetime, signal])});
    },
  }));
}

export function installProfileTools(profile, win = window) {
  const context = win.document.modelContext;
  if (!context?.registerTool) return () => {};
  let lifetime;
  const start = () => {
    if (lifetime) return;
    const current = new AbortController();
    lifetime = current;
    for (const tool of profileTools(profile, current.signal)) {
      Promise.resolve().then(() => context.registerTool(tool, {signal: current.signal})).catch(() => {});
    }
  };
  const stop = () => { lifetime?.abort(); lifetime = undefined; };
  win.addEventListener("pagehide", stop);
  win.addEventListener("pageshow", start);
  start();
  return () => { stop(); win.removeEventListener("pagehide", stop); win.removeEventListener("pageshow", start); };
}
