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
  let lifetime;
  let disposed = false;
  let status = "unsupported";
  const report = value => {
    status = value;
    if (win.document.documentElement) win.document.documentElement.dataset.profileWebmcp = value;
    if (win.CustomEvent) win.dispatchEvent(new win.CustomEvent("regent:profile-webmcp", {detail: {status: value}}));
  };
  const stop = () => {
    const current = lifetime;
    lifetime = undefined;
    current?.abort();
    report("stopped");
  };
  const start = async () => {
    if (disposed || lifetime) return status;
    if (typeof context?.registerTool !== "function") { report("unsupported"); return status; }
    const current = new AbortController();
    lifetime = current;
    report("registering");
    try {
      await Promise.all(profileTools(profile, current.signal).map(tool =>
        Promise.resolve().then(() => {
          if (current.signal.aborted) return;
          const execute = tool.execute;
          return context.registerTool({...tool, execute(...args) {
            if (lifetime !== current || status !== "ready") {
              return Promise.resolve({ok: false, status: null, error: {code: "profile_tools_unavailable", outcome_unknown: false}});
            }
            return execute(...args);
          }}, {signal: current.signal});
        })
      ));
      if (lifetime === current) report("ready");
    } catch {
      // The registration signal owns only this installation's tools. Do not
      // unregister by name: a collision may belong to another installation.
      if (lifetime === current) {
        lifetime = undefined;
        current.abort();
        report("failed");
      }
    }
    return status;
  };
  win.addEventListener("pagehide", stop);
  win.addEventListener("pageshow", start);
  const dispose = () => {
    disposed = true;
    stop();
    win.removeEventListener("pagehide", stop);
    win.removeEventListener("pageshow", start);
  };
  dispose.retry = start;
  dispose.ready = start();
  Object.defineProperty(dispose, "status", {get: () => status});
  return dispose;
}
