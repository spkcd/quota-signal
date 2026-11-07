import { binding } from "./binding.js";
import { readUsagePage } from "./usage.js";

const alarm = "refresh-claude-usage";
const recoveryAlarm = "quota-signal-recovery";
const watchAlarm = "quota-signal-watch";
const backoffs = [30_000, 90_000];
let recoveryTask;
let watchPort;
let watchIdentity;
let watchRetryAvailable = true;

let inFlight;

function queue(operation) {
  const preceding = inFlight;
  const task = (async () => {
    await preceding?.catch(() => {});
    return operation();
  })();
  const completion = task.finally(() => {
    if (inFlight === completion) inFlight = undefined;
  });
  inFlight = completion;
  return completion;
}

function refresh(freshAfter) {
  return inFlight ?? queue(() => sync(typeof freshAfter === "number" ? freshAfter : undefined));
}

function failure(code, message) {
  return Object.assign(new Error(message), { code });
}

async function report(identity, attempt, started, state, detail) {
  if (!identity) return;
  // Telemetry must not prevent a quota reading when an older native host is installed.
  await chrome.runtime.sendNativeMessage("local.quota_signal", {
    kind: "refresh-status", identity, attempt, started, state, detail,
  }).catch(() => {});
}

async function cleanInterruptedSample() {
  const saved = await chrome.storage.local.get("quotaSignalSample");
  const previous = saved.quotaSignalSample;
  if (!previous) return;
  try {
    const tab = await chrome.tabs.get(previous.id);
    // A restored/reused tab ID must never cause a user's own tab to be closed.
    if (tab.url?.includes("quota_signal_sample=" + previous.token)) await chrome.tabs.remove(previous.id);
  } catch {}
  await chrome.storage.local.remove("quotaSignalSample");
}

async function sample(expected) {
  await cleanInterruptedSample();
  const token = crypto.randomUUID();
  const tab = await chrome.tabs.create({ url: "https://claude.ai/new?quota_signal_sample=" + token, active: false });
  try {
    await chrome.storage.local.set({ quotaSignalSample: { id: tab.id, token } });
    for (let attempt = 0; attempt < 20; attempt++) {
      await new Promise(resolve => setTimeout(resolve, 1000));
      if (navigator.onLine === false) {
        throw failure("network", "The browser reports that it is offline.");
      }
      let result;
      try {
        const [frame] = await chrome.scripting.executeScript({
          target: { tabId: tab.id }, func: readUsagePage, args: [expected],
        });
        result = frame.result;
      } catch {
        continue;
      }
      if (result?.error) throw failure(result.code ?? "unavailable", result.error);
      if (result) return result;
    }
    try {
      // A credential-free probe distinguishes a failed connection from a page that could not be parsed.
      await fetch("https://claude.ai/new", {
        method: "HEAD", credentials: "omit", redirect: "manual", signal: AbortSignal.timeout(5000),
      });
    } catch (error) {
      if (error.name !== "TimeoutError" && error.name !== "AbortError") {
        throw failure("network", "The browser could not connect to Claude.");
      }
    }
    throw failure("unavailable", "No verified Claude page was available before the refresh timed out.");
  } finally {
    if (tab.id != null) await chrome.tabs.remove(tab.id).catch(() => {});
    await chrome.storage.local.remove("quotaSignalSample").catch(() => {});
  }
}

async function deliver(pair, options = {}) {
  const saved = await chrome.storage.local.get("quotaSignalIdentity");
  // Pairing deliberately discovers a new workspace. Scheduled refreshes verify their saved target.
  const expected = options.expected ?? (pair ? null : saved.quotaSignalIdentity ?? null);
  const attempt = crypto.randomUUID();
  const started = Date.now() / 1000;
  await report(expected, attempt, started, "refreshing");
  try {
    const reading = await sample(expected);
    const legacy = binding && reading.email === binding.email &&
      reading.workspace === binding.workspace && reading.plan === "Ultra";
    const reply = await chrome.runtime.sendNativeMessage("local.quota_signal", {
      ...reading, pair, attempt, started, command: options.command, account: legacy ? binding.account : undefined,
    });
    if (pair && reply?.alreadyConnected) return null;
    if (!reply?.ok) {
      throw failure("unavailable", pair ? "Open + in Quota Signal again and retry setup." : "Connect this workspace using + in Quota Signal.");
    }
    await chrome.storage.local.set({ quotaSignalIdentity: {
      email: reading.email, workspace: reading.workspace, plan: reading.plan,
    }, quotaSignalLastSuccess: Date.now() });
    await finishRecovery();
    await ensureWatch();
    return reading;
  } catch (error) {
    await report(expected, attempt, started, error.code ?? "unavailable", error.message);
    throw error;
  }
}

async function sync(freshAfter) {
  try {
    if (freshAfter != null) {
      const saved = await chrome.storage.local.get("quotaSignalLastSuccess");
      if (saved.quotaSignalLastSuccess >= freshAfter) return { ok: true };
    }
    await deliver();
    await chrome.action.setBadgeText({ text: "" });
    await chrome.action.setTitle({ title: "Quota Signal · Claude Usage synced" });
    return { ok: true };
  } catch (error) {
    await chrome.action.setBadgeText({ text: "!" });
    await chrome.action.setTitle({ title: "Quota Signal · " + error.message });
    return { ok: false, code: error.code ?? "unavailable" };
  }
}

async function start() {
  if (!(await chrome.alarms.get(alarm))) await chrome.alarms.create(alarm, { periodInMinutes: 5 });
  await ensureWatch();
  await requestRecovery({ id: crypto.randomUUID(), at: Date.now() });
}

async function finishRecovery() {
  await chrome.storage.local.remove("quotaSignalRecovery");
  await chrome.alarms.clear(recoveryAlarm);
}

async function ensureWatch() {
  const saved = await chrome.storage.local.get(["quotaSignalIdentity", "quotaSignalRecoverySignal"]);
  if (!saved.quotaSignalIdentity) return;
  const identity = JSON.stringify(saved.quotaSignalIdentity);
  if (watchPort && watchIdentity === identity) return;
  const previous = watchPort;
  watchPort = undefined;
  previous?.disconnect();
  if (watchIdentity !== identity) watchRetryAvailable = true;
  try {
    const port = chrome.runtime.connectNative("local.quota_signal");
    watchPort = port;
    watchIdentity = identity;
    port.onMessage.addListener(message => {
      if (message.ready) watchRetryAvailable = true;
      if (message.recovery && Number.isFinite(message.at)) {
        void requestRecovery({ id: message.recovery, at: message.at });
      }
    });
    port.onDisconnect.addListener(() => {
      void chrome.runtime.lastError;
      if (watchPort !== port) return;
      watchPort = undefined;
      // Allow one reconnect for a delayed first pairing or a lost established port.
      if (watchRetryAvailable) {
        watchRetryAvailable = false;
        void chrome.alarms.create(watchAlarm, { delayInMinutes: 0.5 });
      }
    });
    port.postMessage({ kind: "watch-recovery", identity: saved.quotaSignalIdentity,
      since: saved.quotaSignalRecoverySignal });
  } catch {
    watchPort = undefined;
  }
}

function requestRecovery(signal) {
  if (recoveryTask) return recoveryTask;
  recoveryTask = recover(signal).finally(() => { recoveryTask = undefined; });
  return recoveryTask;
}

async function recover(signal) {
  const now = Date.now();
  const saved = await chrome.storage.local.get([
    "quotaSignalRecovery", "quotaSignalRecoverySignal", "quotaSignalLastSuccess",
  ]);
  let job = saved.quotaSignalRecovery;
  if (signal) {
    if (signal.id === saved.quotaSignalRecoverySignal || now - signal.at > 120_000 || signal.at > now + 5000) return;
    await chrome.storage.local.set({ quotaSignalRecoverySignal: signal.id });
    if (now - (saved.quotaSignalLastSuccess ?? 0) < 30_000) return;
    if (!job || now >= job.expires) {
      job = { id: signal.id, created: now, attempts: 0, nextAt: now, expires: now + 300_000 };
    }
  }
  if (!job) return;
  if (saved.quotaSignalLastSuccess >= job.created || now >= job.expires) {
    await finishRecovery();
    return;
  }
  // Never reset the budget for another wake or network signal in the same five-minute window.
  if (job.attempts >= 3) return;
  if (job.nextAt > now) {
    await chrome.alarms.create(recoveryAlarm, { when: job.nextAt });
    return;
  }
  job.attempts += 1;
  job.nextAt = now + 120_000;
  await chrome.storage.local.set({ quotaSignalRecovery: job });
  await chrome.alarms.create(recoveryAlarm, { when: job.nextAt });
  const result = await refresh(job.created);
  const completed = await chrome.storage.local.get("quotaSignalLastSuccess");
  if (result?.ok || completed.quotaSignalLastSuccess >= job.created) {
    await finishRecovery();
    return;
  }
  if (!["network", "unavailable"].includes(result?.code) || job.attempts >= 3) {
    job.attempts = 3;
    await chrome.storage.local.set({ quotaSignalRecovery: job });
    await chrome.alarms.clear(recoveryAlarm);
    return;
  }
  job.nextAt = Date.now() + backoffs[job.attempts - 1];
  await chrome.storage.local.set({ quotaSignalRecovery: job });
  await chrome.alarms.create(recoveryAlarm, { when: job.nextAt });
}

const commandTasks = new Map();
const reconnectTabs = new Set();

async function executeCommand(command) {
  const request = await chrome.runtime.sendNativeMessage("local.quota_signal", {
    kind: "account-command", command,
  });
  if (!request?.ok || !request.expected) {
    return { error: "The request ended. Start Retry or Reconnect again in Quota Signal.", expired: true };
  }
  if (request.reconnect && !reconnectTabs.has(command)) {
    reconnectTabs.add(command);
    await chrome.tabs.create({ url: "https://claude.ai/new", active: true });
  }
  try {
    await deliver(null, { expected: request.expected, command });
    return { ok: true, expected: request.expected };
  } catch (error) {
    return { error: error.message, code: error.code ?? "unavailable",
      expected: request.expected, reconnect: request.reconnect };
  }
}

function runCommand(command) {
  if (commandTasks.has(command)) return commandTasks.get(command);
  const completion = queue(() => executeCommand(command)).finally(() => {
    commandTasks.delete(command);
  });
  commandTasks.set(command, completion);
  return completion;
}

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  const senderPage = sender.url?.split("#")[0];
  if (senderPage === chrome.runtime.getURL("command.html") && /^[a-f0-9-]{36}$/i.test(message?.command ?? "")) {
    runCommand(message.command).then(reply, error => reply({ error: error.message }));
    return true;
  }
  if (senderPage !== chrome.runtime.getURL("setup.html") ||
      !/^[a-f0-9-]{36}$/i.test(message?.pair ?? "")) return;
  queue(() => deliver(message.pair)).then(
    reading => reply(reading ? { ok: true, reading } : { alreadyConnected: true }),
    error => reply({ error: error.message })
  );
  return true;
});
chrome.runtime.onInstalled.addListener(start);
chrome.runtime.onStartup.addListener(start);
async function periodicRefresh(event) {
  await ensureWatch();
  const saved = await chrome.storage.local.get("quotaSignalRecovery");
  if (saved.quotaSignalRecovery && Date.now() < saved.quotaSignalRecovery.expires) {
    await requestRecovery();
  } else if (Date.now() - event.scheduledTime > 30_000) {
    await requestRecovery({ id: crypto.randomUUID(), at: Date.now() });
  } else {
    await refresh();
  }
}

chrome.alarms.onAlarm.addListener(event => {
  if (event.name === recoveryAlarm) { void requestRecovery(); return; }
  if (event.name === watchAlarm) { void ensureWatch(); return; }
  if (event.name === alarm) void periodicRefresh(event);
});
chrome.tabs.onUpdated.addListener((_, change, tab) => {
  if (change.status !== "complete" || !tab.active || !tab.url) return;
  const url = new URL(tab.url);
  if (url.origin === "https://claude.ai" && !url.pathname.startsWith("/login")) {
    void requestRecovery({ id: crypto.randomUUID(), at: Date.now() });
  }
});
void ensureWatch();
chrome.action.onClicked.addListener(refresh);
