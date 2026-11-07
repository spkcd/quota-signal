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
  const created = [];
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
      tabs: { create: async options => { created.push(options); return { id: 7 }; }, remove: async id => removed.push(id) },
      scripting: { executeScript: async args => {
        expected = args.args[0];
        injects++;
        return [{ result: reading }];
      } },
      runtime: {
        sendNativeMessage: async (_, message) => {
          messages.push(message);
          if (message.kind === "account-command") {
            return { ok: !options.expired, expected: options.commandExpected ?? target, reconnect: options.reconnect ?? false };
          }
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
  let result;
  try { result = await vm.runInContext(options.expression ?? "deliver()", context); } catch (value) { error = value; }
  return { messages, removed, created, stored, expected, injects, error, result };
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

const commandID = "11111111-1111-4111-8111-111111111111";
const otherTarget = { email: "second@example.com", workspace: "Personal", plan: "Ultra" };
const retryOne = await run({ ...otherTarget, percent: 20 }, {
  commandExpected: otherTarget, expression: `runCommand("${commandID}")`,
});
assert.equal(retryOne.expected.email, otherTarget.email);
assert.equal(retryOne.messages.find(message => message.percent != null).command, commandID);
assert.equal(retryOne.created.filter(tab => tab.active).length, 0);
assert.equal(retryOne.result.ok, true);

const duplicate = await run({ ...target, percent: 10 }, {
  expression: `Promise.all([runCommand("${commandID}"), runCommand("${commandID}")])`,
});
assert.equal(duplicate.messages.filter(message => message.kind === "account-command").length, 1);
assert.equal(duplicate.messages.filter(message => message.percent != null).length, 1);
const expired = await run({ ...target, percent: 10 }, {
  expired: true, expression: `runCommand("${commandID}")`,
});
assert.equal(expired.injects, 0);
assert.equal(expired.result.expired, true);
const reconnect = await run({ code: "signedOut", error: "Sign in to Claude" }, {
  reconnect: true, expression: `(async () => { await runCommand("${commandID}"); return runCommand("${commandID}"); })()`,
});
assert.equal(reconnect.created.filter(tab => tab.active === true).length, 1);
assert.equal(reconnect.result.reconnect, true);
assert.equal(reconnect.messages.filter(message => message.percent != null).length, 0);
console.log("Retry/reconnect passed single-account targeting, command framing, duplicate requests, expiry, and reconnect polling.");
