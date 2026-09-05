import {test} from "node:test";
import assert from "node:assert/strict";
import {createProfileClient, loadProfileAction} from "../../assets/profile_client.mjs";
import {profileTools, installProfileTools} from "../../assets/profile_tools.mjs";

test("profile tools share client responses and reject actor/token parameters", async () => {
  const lifetime = new AbortController();
  const calls = [];
  const result = {ok: true, status: 200, body: {profile: {profile_id: "fixture"}}};
  const tools = profileTools(async (...args) => { calls.push(args); return result; }, lifetime.signal);
  assert.equal(await tools[0].execute({}, {signal: lifetime.signal}), result);
  assert.deepEqual(calls[0].slice(0, 2), ["get", {}]);
  for (const tool of tools) {
    const denied = await tool.execute({access_token: "not-a-credential"}, {signal: lifetime.signal});
    assert.equal(denied.ok, false);
  }
  assert.equal(calls.length, 1);
  assert.equal((await tools[2].execute({}, {signal: lifetime.signal})).ok, false);
  await tools[2].execute({wallet_address: null}, {signal: lifetime.signal});
  assert.deepEqual(calls[1].slice(0, 2), ["update", {wallet_address: null}]);
});

test("page lifecycle cancels late tool registration without touching a new page", async () => {
  const win = new EventTarget();
  const registrations = [];
  win.document = {modelContext: {registerTool: (_tool, options) => { registrations.push(options.signal); }}};
  const stop = installProfileTools(async () => {}, win);
  win.dispatchEvent(new Event("pagehide"));
  win.dispatchEvent(new Event("pageshow"));
  await Promise.resolve();
  assert.equal(registrations.length, 6);
  assert.ok(registrations.slice(0, 3).every(signal => signal.aborted));
  assert.ok(registrations.slice(3).every(signal => !signal.aborted));
  stop();
  assert.ok(registrations.every(signal => signal.aborted));
});

test("cancelling a stalled credential provider settles without sending proof", async () => {
  const cancellation = new AbortController();
  let sent = false;
  const profile = createProfileClient({
    acquireProof: () => new Promise(() => {}),
    fetch: async () => { sent = true; },
  });
  const pending = profile("get", {}, {signal: cancellation.signal});
  cancellation.abort();
  const result = await pending;
  assert.equal(result.error.code, "cancelled");
  assert.equal(sent, false);
});

test("cancelling lazy SDK startup settles without canceling the shared startup", async () => {
  const cancellation = new AbortController();
  let ready;
  const startup = new Promise(resolve => { ready = resolve; });
  const pending = loadProfileAction(() => startup, "get", {}, {signal: cancellation.signal});
  cancellation.abort();
  assert.equal((await pending).error.code, "cancelled");
  const action = async () => ({ok: true, status: 200});
  ready(action);
  assert.equal(await startup, action);
});
