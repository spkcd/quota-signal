import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import { webcrypto } from "node:crypto";

const source = (await readFile(new URL("../Chrome/worker.js", import.meta.url), "utf8"))
  .replace(/^import .*;$/gm, "");
const target = { email: "first@example.com", workspace: "Studio", plan: "Ultra" };

async function run(reading, options = {}) {
  const messages = [];
  let retainedReading = options.previousReading;
  const removed = [];
  const created = [];
  const alarms = [];
  const events = {};
  const ports = [];
  let clock = options.now ?? Date.now();
  const values = { quotaSignalIdentity: options.target ?? target, ...options.values };
  let stored = values.quotaSignalIdentity;
  let expected;
  let injects = 0;
  const context = {
    events, ports, URL,
    advance: milliseconds => { clock += milliseconds; },
    Date: class extends Date { static now() { return clock; } },
    binding: null, crypto: webcrypto, navigator: { onLine: options.online ?? true },
    setTimeout: callback => { callback(); }, readUsagePage() {},
    AbortSignal, fetch: async () => {
      if (options.connectionFailed) throw new TypeError("Failed to fetch");
      return {};
    },
    chrome: {
      storage: { local: {
        get: async keys => Object.fromEntries((Array.isArray(keys) ? keys : [keys])
          .filter(key => key in values).map(key => [key, values[key]])),
        set: async value => { Object.assign(values, value); stored = values.quotaSignalIdentity; },
        remove: async key => { delete values[key]; },
      } },
      tabs: { onUpdated: { addListener(listener) { events.updated = listener; } }, get: async () => options.previousTab ?? {},
        create: async options => { created.push(options); return { id: 7 }; }, remove: async id => removed.push(id) },
      scripting: { executeScript: async args => {
        expected = args.args[0];
        injects++;
        return [{ result: reading }];
      } },
      runtime: {
        connectNative: options.watch ? () => {
          const port = {
            onMessage: { addListener(listener) { port.receive = listener; } },
            onDisconnect: { addListener(listener) { port.drop = listener; } },
            postMessage(message) { port.initial = message; },
            disconnect() { port.drop(); },
          };
          ports.push(port);
          return port;
        } : undefined,
        sendNativeMessage: async (_, message) => {
          messages.push(message);
          if (message.kind === "account-command") {
            return { ok: !options.expired, expected: options.commandExpected ?? target, reconnect: options.reconnect ?? false };
          }
          if (message.percent != null && options.nativeOK !== false) retainedReading = message;
          return { ok: options.nativeOK ?? true };
        },
        getURL: value => "chrome-extension://test/" + value,
        onMessage: { addListener() {} }, onInstalled: { addListener() {} }, onStartup: { addListener() {} },
      },
      alarms: { create: async (name, info) => { alarms.push({ name, ...info }); }, clear: async () => {}, onAlarm: { addListener(listener) { events.alarm = listener; } } },
      action: { setBadgeText: async () => {}, setTitle: async () => {}, onClicked: { addListener() {} } },
    },
  };
  vm.createContext(context);
  vm.runInContext(source, context);
  let error;
  let result;
  try { result = await vm.runInContext(options.expression ?? "deliver()", context); } catch (value) { error = value; }
  return { messages, removed, created, stored, expected, injects, error, result, values, alarms, ports, retainedReading };
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

const wakeID = "22222222-2222-4222-8222-222222222222";
const wakeTime = 1_800_000_000_000;
const recovered = await run({ ...target, percent: 30 }, {
  now: wakeTime, expression: `requestRecovery({ id: "${wakeID}", at: Date.now() })`,
});
assert.equal(recovered.created.length, 1);
assert.equal(recovered.values.quotaSignalRecovery, undefined);
const bounded = await run({ code: "network", error: "Offline" }, {
  now: wakeTime, expression: `(async () => {
    await requestRecovery({ id: "${wakeID}", at: Date.now() });
    advance(30000); await requestRecovery();
    advance(90000); await requestRecovery();
    await requestRecovery({ id: crypto.randomUUID(), at: Date.now() });
    return requestRecovery();
  })()`,
});
assert.equal(bounded.created.length, 3);
assert.equal(bounded.values.quotaSignalRecovery.attempts, 3);
assert.equal(bounded.alarms.some(alarm => alarm.when === wakeTime + 30000), true);
assert.equal(bounded.alarms.some(alarm => alarm.when === wakeTime + 120000), true);
const needsSignIn = await run({ code: "signedOut", error: "Sign in" }, {
  now: wakeTime, expression: `(async () => {
    await requestRecovery({ id: "${wakeID}", at: Date.now() });
    advance(30000); await requestRecovery();
  })()`,
});
assert.equal(needsSignIn.created.length, 1);
const colliding = await run({ ...target, percent: 30 }, {
  now: wakeTime, expression: `Promise.all([
    requestRecovery({ id: "${wakeID}", at: Date.now() }),
    requestRecovery({ id: "${wakeID}", at: Date.now() }),
    refresh()
  ])`,
});
assert.equal(colliding.created.length, 1);
const resumed = await run({ code: "network", error: "Offline" }, {
  now: wakeTime, values: { quotaSignalRecovery: {
    id: wakeID, created: wakeTime - 30000, attempts: 1, nextAt: wakeTime, expires: wakeTime + 270000,
  } },
  expression: "requestRecovery()",
});
assert.equal(resumed.values.quotaSignalRecovery.attempts, 2);
const expiredJob = await run({ ...target, percent: 30 }, {
  now: wakeTime, values: { quotaSignalRecovery: {
    id: wakeID, created: wakeTime - 400000, attempts: 1, nextAt: wakeTime, expires: wakeTime - 1,
  } }, expression: "requestRecovery()",
});
assert.equal(expiredJob.created.length, 0);
const oldSignal = await run({ ...target, percent: 30 }, {
  now: wakeTime, expression: `requestRecovery({ id: "${wakeID}", at: Date.now() - 121000 })`,
});
assert.equal(oldSignal.created.length, 0);
const oldTab = { id: 99, token: "interrupted" };
const interrupted = await run({ ...target, percent: 30 }, {
  values: { quotaSignalSample: oldTab },
  previousTab: { url: "https://claude.ai/new?quota_signal_sample=interrupted" },
});
assert.deepEqual(interrupted.removed, [99, 7]);
const reusedID = await run({ ...target, percent: 30 }, {
  values: { quotaSignalSample: oldTab }, previousTab: { url: "https://claude.ai/new" },
});
assert.deepEqual(reusedID.removed, [7]);
console.log("Wake recovery passed bounded backoffs, burst deduplication, sign-out stop, persisted budgets, expiry, and interrupted-tab cleanup.");

const watcher = await run({ ...target, percent: 30 }, {
  now: wakeTime, watch: true, expression: `(async () => {
    await ensureWatch();
    ports[0].receive({ ready: true });
    ports[0].receive({ recovery: "${wakeID}", at: Date.now() });
    return requestRecovery();
  })()`,
});
assert.equal(watcher.ports.length, 1);
assert.equal(watcher.ports[0].initial.kind, "watch-recovery");
assert.equal(watcher.created.length, 1);
const recoveredSession = await run({ ...target, percent: 30 }, {
  now: wakeTime, expression: `(async () => {
    events.updated(1, { status: "complete" }, { active: true, url: "https://claude.ai/new" });
    return requestRecovery();
  })()`,
});
assert.equal(recoveredSession.created.length, 1);
const loginPage = await run({ ...target, percent: 30 }, {
  now: wakeTime, expression: `events.updated(1, { status: "complete" }, { active: true, url: "https://claude.ai/login" })`,
});
assert.equal(loginPage.created.length, 0);
const overdueAlarm = await run({ ...target, percent: 30 }, {
  now: wakeTime, expression: `periodicRefresh({ scheduledTime: Date.now() - 60000 })`,
});
assert.equal(overdueAlarm.created.length, 1);
console.log("Native watch, authenticated navigation, and overdue Chrome alarm entry points passed.");

const periodicDuringBackoff = await run({ code: "network", error: "Offline" }, {
  now: wakeTime, expression: `(async () => {
    await requestRecovery({ id: "${wakeID}", at: Date.now() });
    advance(10000);
    return periodicRefresh({ scheduledTime: Date.now() });
  })()`,
});
assert.equal(periodicDuringBackoff.created.length, 1);
const periodicAfterBudget = await run({ code: "network", error: "Offline" }, {
  now: wakeTime, values: { quotaSignalRecovery: {
    id: wakeID, created: wakeTime - 120000, attempts: 3, nextAt: wakeTime, expires: wakeTime + 180000,
  } }, expression: "periodicRefresh({ scheduledTime: Date.now() })",
});
assert.equal(periodicAfterBudget.created.length, 0);
console.log("Periodic refreshes respect recovery backoff and exhausted budgets.");

const delayedPairingWatch = await run({ ...target, percent: 30 }, {
  watch: true, expression: `(async () => {
    await ensureWatch(); ports[0].drop();
    await ensureWatch(); ports[1].drop();
  })()`,
});
assert.equal(delayedPairingWatch.alarms.filter(event => event.name === "quota-signal-watch").length, 1);
console.log("Native watch reconnection is bounded when initial pairing is delayed or a host is unavailable.");

// Failed parsing must only report health; it cannot replace a last verified quota or cycle.
const lastVerified = { ...target, percent: 88, reset: 1800003600 };
for (const code of ["layout", "mismatch"]) {
  const failedCapture = await run({ code, error: "Fixture identity/cycle verification failed" }, { previousReading: lastVerified });
  assert.deepEqual(failedCapture.retainedReading, lastVerified);
  assert.equal(failedCapture.messages.at(-1).state, code);
  assert.equal(failedCapture.messages.at(-1).detail, "Fixture identity/cycle verification failed");
}
console.log("Parser failures preserve the last verified quota and reset and expose their concrete error.");
