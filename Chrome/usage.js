// Runs in an isolated world on a dedicated Claude page.
export async function readUsagePage(expected) {
  const pause = () => new Promise(resolve => setTimeout(resolve, 100));
  async function waitFor(find) {
    for (let attempt = 0; attempt < 40; attempt++) {
      const item = find();
      if (item) return item;
      await pause();
    }
  }
  const normalize = value => value?.replace(/\s+/g, " ").trim();
  const workspace = () => document.querySelector('[data-testid="user-menu-button"]');
  const identity = () => {
    const button = workspace();
    const name = button?.querySelector(".df-footer-name")?.textContent;
    const plan = button?.querySelector(".df-footer-suffix-text:not([aria-hidden])")?.textContent;
    return { workspace: normalize(name), plan: normalize(plan) };
  };
  if (location.origin !== "https://claude.ai") return;
  if (navigator.onLine === false) return { code: "network", error: "The browser is offline." };
  if (location.pathname === "/login") return { code: "signedOut", error: "Claude sign-in is required." };
  if (!workspace()) return;
  const { workspace: workspaceName, plan } = identity();
  if (!workspaceName || !plan) return { code: "layout", error: "Claude workspace is unavailable" };
  if (expected && (workspaceName !== expected.workspace || plan !== (expected.plan ?? "Ultra"))) {
    return { code: "mismatch", error: "Select the configured Claude workspace" };
  }
  workspace().click();
  const menu = await waitFor(() => {
    const id = workspace()?.getAttribute("aria-controls");
    return id && document.getElementById(id);
  });
  if (!menu) return { code: "layout", error: "Claude account menu unavailable" };
  const emails = menu.innerText.split("\n").map(line => line.trim().toLowerCase())
    .filter(line => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(line));
  if (emails.length !== 1 || (expected && emails[0] !== expected.email)) {
    return { code: "mismatch", error: "Claude account does not match" };
  }
  const usage = menu.querySelector('[data-testid="user-menu-usage"]');
  if (!usage) return { code: "layout", error: "Claude Usage menu unavailable" };
  usage.click();

  const meter = await waitFor(() => [...document.querySelectorAll('[role="meter"]')].find(element => {
    const label = document.getElementById(element.getAttribute("aria-labelledby"))?.cloneNode(true);
    label?.querySelectorAll('[aria-hidden="true"]').forEach(icon => icon.remove());
    const name = normalize(label?.textContent);
    return name === "This week" || name === "Weekly limit · All models";
  }));
  if (!meter || location.hash !== "#settings/usage" || identity().workspace !== workspaceName || identity().plan !== plan) {
    return { code: "layout", error: "The verified workspace's weekly meter was unavailable" };
  }
  const label = document.getElementById(meter.getAttribute("aria-labelledby"));
  let row = meter.parentElement;
  while (row && label && !row.contains(label)) row = row.parentElement;
  const resetLine = row?.innerText.split("\n").map(line => line.trim()).find(line => line.startsWith("Resets "));
  const reset = /^Resets (Sun(?:day)?|Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?) (\d{1,2}):(\d{2}) (AM|PM)$/.exec(resetLine ?? "");
  const value = meter.getAttribute("aria-valuenow");
  const percent = Number(value);
  if (!reset || !value || !Number.isFinite(percent) || percent < 0 || percent > 100 ||
      Number(reset[2]) < 1 || Number(reset[2]) > 12 || Number(reset[3]) > 59) {
    return { code: "layout", error: "Claude changed the format of its weekly usage page" };
  }
  const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const now = new Date();
  const date = new Date(now);
  date.setDate(date.getDate() + (days.indexOf(reset[1].slice(0, 3)) - now.getDay() + 7) % 7);
  date.setHours(Number(reset[2]) % 12 + (reset[4] === "PM" ? 12 : 0), Number(reset[3]), 0, 0);
  if (date <= now) date.setDate(date.getDate() + 7);
  const offerText = document.body.innerText;
  const offer = offerText.includes("No resets right now") ? "None available" : "Unknown";
  return { percent, reset: date.getTime() / 1000, email: emails[0], workspace: workspaceName, plan, offer };
}
