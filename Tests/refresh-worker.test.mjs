import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import { webcrypto } from "node:crypto";

const source = (await readFile(new URL("../Chrome/worker.js", import.meta.url), "utf8"))
  .replace(/^import .*;$/gm, "");
const target = { email: "first@example.com", workspace: "Studio", plan: "Ultra" };

async function run(reading, options = {}) {
  const messages = [];
  const removed = [];
  let stored = options.target ?? target;
  let expected;
  let injects = 0;
  const context = {
    binding: null, crypto: webcrypto, navigator: { onLine: options.online ?? true },
    setTimeout: callback => { callback(); }, readUsagePage() {},
    AbortSignal, fetch: async () => {
      if (options.connectionFailed) throw new TypeError("Failed to fetch");
      return {};
    },
    chrome: {
      storage: { local: {
        get: async () => ({ quotaSignalIdentity: stored }),
        set: async value => { stored = value.quotaSignalIdentity; },
      } },
      tabs: { create: async () => ({ id: 7 }), remove: async id => removed.push(id) },
      scripting: { executeScript: async args => {
        expected = args.args[0];
        injects++;
        return [{ result: reading }];
      } },
      runtime: {
        sendNativeMessage: async (_, message) => {
          messages.push(message);
          return { ok: options.nativeOK ?? true };
        },
        getURL: value => "chrome-extension://test/" + value,
        onMessage: { addListener() {} }, onInstalled: { addListener() {} }, onStartup: { addListener() {} },
      },
      alarms: { onAlarm: { addListener() {} } },
      action: { onClicked: { addListener() {} } },
    },
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  let error;
  try { await vm.runInContext("deliver()", context); } catch (value) { error = value; }
  return { messages, removed, stored, expected, injects, error };
}

const success = await run({ ...target, percent: 30, reset: Date.now() / 1000 + 3600, offer: "Unknown" });
assert.equal(success.error, undefined);
assert.equal(success.messages[0].state, "refreshing");
assert.equal(success.messages[1].email, target.email);
assert.equal(success.messages[0].attempt, success.messages[1].attempt);
assert.equal(success.expected.email, target.email);
assert.deepEqual(success.removed, [7]);

for (const code of ["signedOut", "layout", "mismatch"]) {
  const result = await run({ code, error: "Fixture " + code });
  assert.equal(result.messages.at(-1).state, code);
  assert.equal(result.messages.at(-1).identity.email, target.email);
  assert.equal(result.messages.filter(message => message.percent != null).length, 0);
  assert.deepEqual(result.removed, [7]);
}

const offline = await run(null, { online: false });
assert.equal(offline.messages.at(-1).state, "network");
assert.equal(offline.injects, 0);
const timeout = await run(null);
assert.equal(timeout.messages.at(-1).state, "unavailable");
assert.notEqual(timeout.messages.at(-1).state, "signedOut");
const rejected = await run({ ...target, percent: 30 }, { nativeOK: false });
assert.equal(rejected.messages.at(-1).state, "unavailable");
console.log("Refresh worker passed success, identity targeting, sign-out, layout, mismatch, offline, timeout, and rejected delivery.");

const connectionFailed = await run(null, { connectionFailed: true });
assert.equal(connectionFailed.messages.at(-1).state, "network");
const parserSource = (await readFile(new URL("../Chrome/usage.js", import.meta.url), "utf8"))
  .replace("export async function", "async function");
for (const [pathname, online, expectedCode] of [
  ["/login", true, "signedOut"], ["/new", false, "network"],
]) {
  const context = { location: { origin: "https://claude.ai", pathname }, navigator: { onLine: online } };
  vm.createContext(context);
  vm.runInContext(parserSource, context);
  const result = await vm.runInContext("readUsagePage(null)", context);
  assert.equal(result.code, expectedCode);
}
console.log("Refresh parser passed confirmed login page and offline state.");
