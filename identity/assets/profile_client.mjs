const operations = {
  get: {method: "GET", path: "/api/v1/profile"},
  sync: {method: "POST", path: "/api/v1/profile/sync"},
  update: {method: "PATCH", path: "/api/v1/profile"},
};

// Proof stays inside the product's credential adapter. Neither tools nor DOM
// events receive tokens. Acquisition may hydrate, but must never open sign-in.
export function createProfileClient({acquireProof, fetch: fetchImpl = globalThis.fetch}) {
  return async function profile(operation, input = {}, {signal, expectedProfileId} = {}) {
    const route = Object.hasOwn(operations, operation) ? operations[operation] : null;
    if (!route || !input || Array.isArray(input) || typeof input !== "object" ||
        Object.keys(input).some(key => operation !== "update" || !["display_name", "wallet_address"].includes(key))) {
      return failure("invalid_profile_operation");
    }
    let sent = false;
    try {
      signal?.throwIfAborted();
      const requestSignal = AbortSignal.any([AbortSignal.timeout(15_000), ...(signal ? [signal] : [])]);
      const proof = await acquireWithin(acquireProof, requestSignal);
      requestSignal.throwIfAborted();
      signal?.throwIfAborted();
      if (!proof?.accessToken || !proof?.identityToken || typeof proof.subject !== "string" || !proof.subject || typeof proof.isCurrent !== "function" || !proof.isCurrent()) {
        return failure("authentication_required");
      }
      sent = true;
      const response = await fetchImpl(route.path, {
        method: route.method, credentials: "omit", redirect: "error", signal: requestSignal,
        headers: {accept: "application/json", "content-type": "application/json",
          authorization: `Bearer ${proof.accessToken}`, "privy-id-token": proof.identityToken,
          "x-privy-user-id": proof.subject,
          ...(expectedProfileId ? {"x-regent-profile-id": expectedProfileId} : {})},
        ...(operation === "update" ? {body: JSON.stringify(input)} : {}),
      });
      const body = await response.json();
      requestSignal.throwIfAborted();
      if (!proof.isCurrent()) return failure("identity_changed", sent && operation !== "get");
      return {ok: response.ok, status: response.status, body};
    } catch {
      return failure(signal?.aborted ? "cancelled" : "profile_unavailable", sent && operation !== "get");
    }
  };
}

// Lazy SDK startup is also bounded. Cancellation abandons only this call, not
// the shared provider's startup or any independently requested wallet action.
export async function loadProfileAction(load, operation, input = {}, options = {}) {
  let dispatched = false;
  const signal = AbortSignal.any([AbortSignal.timeout(15_000), ...(options.signal ? [options.signal] : [])]);
  try {
    signal.throwIfAborted();
    const action = await acquireWithin(load, signal);
    signal.throwIfAborted();
    dispatched = true;
    return await acquireWithin(() => action(operation, input, {...options, signal}), signal);
  } catch {
    return failure(options.signal?.aborted ? "cancelled" : "profile_unavailable", dispatched && operation !== "get");
  }
}

function acquireWithin(acquireProof, signal) {
  return new Promise((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener("abort", abort, {once: true});
    Promise.resolve().then(() => {
      signal.throwIfAborted();
      return acquireProof({signal});
    }).then(resolve, reject).finally(() => signal.removeEventListener("abort", abort));
  });
}

function failure(code, outcomeUnknown = false) {
  return {ok: false, status: null, error: {code, outcome_unknown: outcomeUnknown}};
}
