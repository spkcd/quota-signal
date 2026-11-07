import { binding } from "./binding.js";
import { readUsagePage } from "./usage.js";

const alarm = "refresh-claude-usage";
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

function refresh() {
  return inFlight ?? queue(sync);
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

async function sample(expected) {
  const tab = await chrome.tabs.create({ url: "https://claude.ai/new", active: false });
  try {
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
    } });
    return reading;
  } catch (error) {
    await report(expected, attempt, started, error.code ?? "unavailable", error.message);
    throw error;
  }
}

async function sync() {
  try {
    await deliver();
    await chrome.action.setBadgeText({ text: "" });
    await chrome.action.setTitle({ title: "Quota Signal · Claude Usage synced" });
  } catch (error) {
    await chrome.action.setBadgeText({ text: "!" });
    await chrome.action.setTitle({ title: "Quota Signal · " + error.message });
  }
}

async function start() {
  if (!(await chrome.alarms.get(alarm))) await chrome.alarms.create(alarm, { periodInMinutes: 5 });
  await refresh();
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
    return { error: error.message, expected: request.expected, reconnect: request.reconnect };
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
chrome.alarms.onAlarm.addListener(event => { if (event.name === alarm) void refresh(); });
chrome.action.onClicked.addListener(refresh);
