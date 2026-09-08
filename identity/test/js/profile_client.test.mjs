import {test} from "node:test";
import assert from "node:assert/strict";
import {createProfileClient} from "../../assets/profile_client.mjs";
const proof = () => Promise.resolve({accessToken: "fixture-access", identityToken: "fixture-identity", subject: "fixture-subject", isCurrent: () => true});

test("profile operations preserve payload and keep proof out of results", async () => {
  const calls = [];
  const payload = {profile: {profile_id: "canonical-id", x: null, wallet: {address: null, verified: false}}};
  const client = createProfileClient({acquireProof: proof, fetch: async (url, options) => {
    calls.push({url, ...options});
    return {ok: true, status: 200, json: async () => payload};
  }});
  for (const operation of ["get", "sync", "update"]) {
    assert.deepEqual(await client(operation, operation === "update" ? {display_name: "Alice"} : {}), {ok: true, status: 200, body: payload});
  }
  assert.deepEqual(calls.map(call => [call.method, call.url]), [["GET", "/api/v1/profile"], ["POST", "/api/v1/profile/sync"], ["PATCH", "/api/v1/profile"]]);
  for (const call of calls) {
    assert.equal(call.redirect, "error"); assert.equal(call.credentials, "omit");
    assert.equal(call.headers.authorization, "Bearer fixture-access");
    assert.equal(call.headers["x-privy-user-id"], "fixture-subject");
  }
});

test("identity changes discard private replies, and uncertain writes are not retried", async () => {
  let current = true;
  let calls = 0;
  const client = createProfileClient({acquireProof: async () => ({...(await proof()), isCurrent: () => current}), fetch: async () => {
    calls++; current = false;
    return {ok: true, status: 200, json: async () => ({private: "old person's data"})};
  }});
  assert.deepEqual(await client("update", {display_name: "Alice"}), {ok: false, status: null, error: {code: "identity_changed", outcome_unknown: true}});
  assert.equal(calls, 1);
});

test("cancelled or unknown operations do not acquire proof or send requests", async () => {
  const abort = new AbortController(); abort.abort();
  const client = createProfileClient({acquireProof: () => assert.fail("must not acquire"), fetch: () => assert.fail("must not send")});
  assert.equal((await client("get", {}, {signal: abort.signal})).error.code, "cancelled");
  assert.equal((await client("delete")).error.code, "invalid_profile_operation");
  assert.equal((await client("constructor")).error.code, "invalid_profile_operation");
  assert.equal((await client("update", {privy_user_id: "other"})).error.code, "invalid_profile_operation");
});
