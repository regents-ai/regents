const operations = {
  get: {method: "GET", path: "/api/v1/profile"},
  update: {method: "PATCH", path: "/api/v1/profile"},
};

// The site's own sign-in says whose profile this is: the browser sends the
// session cookie the site's pages hold, and a change also carries the page's
// forms token in x-csrf-token, read as the change is sent. Nothing here holds a
// credential of its own.
export function createProfileClient({csrfToken, fetch: fetchImpl = globalThis.fetch}) {
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
      const change = operation === "update";
      sent = true;
      const response = await fetchImpl(route.path, {
        method: route.method, credentials: "same-origin", redirect: "error", signal: requestSignal,
        headers: {accept: "application/json",
          ...(change ? {"content-type": "application/json", "x-csrf-token": csrfToken()} : {}),
          ...(expectedProfileId ? {"x-regent-profile-id": expectedProfileId} : {})},
        ...(change ? {body: JSON.stringify(input)} : {}),
      });
      const body = await response.json();
      return {ok: response.ok, status: response.status, body};
    } catch {
      return failure(signal?.aborted ? "cancelled" : "profile_unavailable", sent && operation !== "get");
    }
  };
}

function failure(code, outcomeUnknown = false) {
  return {ok: false, status: null, error: {code, outcome_unknown: outcomeUnknown}};
}
