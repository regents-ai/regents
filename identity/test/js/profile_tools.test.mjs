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

function registryWindow() {
  const win = new EventTarget();
  const registered = new Map();
  win.document = {documentElement: {dataset: {}}, modelContext: {registerTool(tool, {signal}) {
    if (registered.has(tool.name)) return Promise.reject(new Error("duplicate"));
    if (signal.aborted) return Promise.reject(signal.reason);
    registered.set(tool.name, tool);
    signal.addEventListener("abort", () => registered.delete(tool.name), {once: true});
    return Promise.resolve();
  }}};
  return {win, registered};
}

test("failure removes only owned registrations, reports failure and permits explicit retry", async () => {
  const {win, registered} = registryWindow();
  const other = {name: "profile_sync"};
  registered.set(other.name, other);
  const stop = installProfileTools(async () => ({ok: true}), win);
  assert.equal(await stop.ready, "failed");
  assert.equal(stop.status, "failed");
  assert.equal(win.document.documentElement.dataset.profileWebmcp, "failed");
  assert.deepEqual([...registered.values()], [other]);
  registered.delete(other.name);
  assert.equal(await stop.retry(), "ready");
  assert.equal(registered.size, 3);
  stop();
  assert.equal(registered.size, 0);
  assert.equal(await stop.retry(), "stopped");
});

test("pending batch cannot execute and late completion cannot revive a hidden page", async () => {
  const {win, registered} = registryWindow();
  const register = win.document.modelContext.registerTool;
  const releases = [];
  win.document.modelContext.registerTool = async (...args) => {
    await register(...args);
    await new Promise(resolve => releases.push(resolve));
  };
  let calls = 0;
  const stop = installProfileTools(async () => { calls++; }, win);
  await Promise.resolve();
  const result = await registered.get("profile_get").execute({}, {signal: new AbortController().signal});
  assert.equal(result.error.code, "profile_tools_unavailable");
  assert.equal(calls, 0);
  win.dispatchEvent(new Event("pagehide"));
  releases.splice(0).forEach(resolve => resolve());
  await stop.ready;
  assert.equal(stop.status, "stopped");
  assert.equal(registered.size, 0);
  win.document.modelContext.registerTool = register;
  win.dispatchEvent(new Event("pageshow"));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(stop.status, "ready");
  assert.equal(registered.size, 3);
  stop();
});

test("unsupported browser is reported without affecting the profile client", async () => {
  const win = new EventTarget();
  win.document = {documentElement: {dataset: {}}};
  const stop = installProfileTools(async () => {}, win);
  assert.equal(await stop.ready, "unsupported");
  assert.equal(win.document.documentElement.dataset.profileWebmcp, "unsupported");
  stop();
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
