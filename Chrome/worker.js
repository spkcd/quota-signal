import { binding } from "./binding.js";
import { readUsagePage } from "./usage.js";

const alarm = "refresh-claude-usage";
let inFlight;

function refresh() {
  inFlight ??= sync().finally(() => { inFlight = undefined; });
  return inFlight;
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

async function deliver(pair) {
  const saved = await chrome.storage.local.get("quotaSignalIdentity");
  // Pairing deliberately discovers a new workspace. Scheduled refreshes verify their saved target.
  const expected = pair ? null : saved.quotaSignalIdentity ?? null;
  const attempt = crypto.randomUUID();
  const started = Date.now() / 1000;
  await report(expected, attempt, started, "refreshing");
  try {
    const reading = await sample(expected);
    const legacy = binding && reading.email === binding.email &&
      reading.workspace === binding.workspace && reading.plan === "Ultra";
    const reply = await chrome.runtime.sendNativeMessage("local.quota_signal", {
      ...reading, pair, attempt, started, account: legacy ? binding.account : undefined,
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

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.url?.split("#")[0] !== chrome.runtime.getURL("setup.html") ||
      !/^[a-f0-9-]{36}$/i.test(message?.pair ?? "")) return;
  (async () => {
    try {
      await inFlight;
      const reading = await deliver(message.pair);
      reply(reading ? { ok: true, reading } : { alreadyConnected: true });
    } catch (error) {
      reply({ error: error.message });
    }
  })();
  return true;
});
chrome.runtime.onInstalled.addListener(start);
chrome.runtime.onStartup.addListener(start);
chrome.alarms.onAlarm.addListener(event => { if (event.name === alarm) void refresh(); });
chrome.action.onClicked.addListener(refresh);
