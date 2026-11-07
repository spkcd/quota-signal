import { binding } from "./binding.js";
import { readUsagePage } from "./usage.js";

const alarm = "refresh-claude-usage";
let inFlight;

function refresh() {
  inFlight ??= sync().finally(() => { inFlight = undefined; });
  return inFlight;
}

async function sample() {
  const tab = await chrome.tabs.create({ url: "https://claude.ai/new", active: false });
  try {
    for (let attempt = 0; attempt < 20; attempt++) {
      await new Promise(resolve => setTimeout(resolve, 1000));
      let result;
      try {
        const [frame] = await chrome.scripting.executeScript({
          target: { tabId: tab.id }, func: readUsagePage, args: [null],
        });
        result = frame.result;
      } catch {
        continue;
      }
      if (result?.error) throw new Error(result.error);
      if (result) return result;
    }
    throw new Error("Sign in to Claude in this Chrome profile, then try again.");
  } finally {
    if (tab.id != null) await chrome.tabs.remove(tab.id).catch(() => {});
  }
}

async function deliver(pair) {
  const reading = await sample();
  const legacy = binding && reading.email === binding.email &&
    reading.workspace === binding.workspace && reading.plan === "Ultra";
  const reply = await chrome.runtime.sendNativeMessage("local.quota_signal", {
    ...reading, pair, account: legacy ? binding.account : undefined,
  });
  if (pair && reply?.alreadyConnected) return null;
  if (!reply?.ok) {
    throw new Error(pair ? "Open + in Quota Signal again and retry setup." : "Connect this workspace using + in Quota Signal.");
  }
  return reading;
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
