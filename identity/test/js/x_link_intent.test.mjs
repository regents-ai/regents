import {test} from "node:test";
import assert from "node:assert/strict";
import {createXLinkIntent} from "../../assets/x_link_intent.mjs";

test("X intent survives navigation, binds its owner, expires and is consumed once", () => {
  const values = new Map();
  const storage = {getItem: key => values.get(key) ?? null, setItem: (k, v) => values.set(k, v), removeItem: k => values.delete(k)};
  let time = 100;
  let sequence = 0;
  const options = {now: () => time, nonce: () => String(++sequence)};
  const firstPage = createXLinkIntent(storage, "app", options);
  const callback = subject => ({user: {id: subject}, linkMethod: "twitter", linkedAccount: {type: "twitter_oauth"}});
  const old = firstPage.begin("alice");
  const returnedPage = createXLinkIntent(storage, "app", options);
  assert.equal(returnedPage.claim(callback("bob")), null);
  assert.equal(createXLinkIntent(storage, "other-app", options).claim(callback("alice")), null);
  assert.equal(returnedPage.claim(callback("alice")), "alice");
  assert.equal(returnedPage.claim(callback("alice")), null);
  returnedPage.begin("alice");
  returnedPage.cancel(old);
  assert.equal(returnedPage.claim(callback("alice")), "alice");
  returnedPage.begin("alice");
  time += 300_001;
  assert.equal(returnedPage.claim(callback("alice")), null);
  assert.ok([...values.values()].every(value => !value.includes("token")));
});


test("X intent refuses overlapping flows and fails closed if consumption fails", () => {
  let value = null;
  const storage = {getItem: () => value, setItem: (_key, next) => { value = next; }, removeItem: () => { throw new Error("storage blocked"); }};
  const intent = createXLinkIntent(storage, "app", {nonce: () => "one"});
  intent.begin("alice");
  assert.throws(() => intent.begin("alice"), /link_already_in_progress/);
  const callback = {user: {id: "alice"}, linkMethod: "twitter", linkedAccount: {type: "twitter_oauth"}};
  assert.equal(intent.claim(callback), null);
  assert.equal(intent.claim(callback), null);
});
