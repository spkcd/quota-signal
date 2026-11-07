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
  const accountMenu = async () => {
    workspace()?.click();
    return await waitFor(() => {
      const id = workspace()?.getAttribute("aria-controls");
      const menu = id && document.getElementById(id);
      return menu && menu.getClientRects().length ? menu : null;
    });
  };
  const menu = await accountMenu();
  if (!menu) return { code: "layout", error: "Claude account menu unavailable" };
  const emails = menu.innerText.split("\n").map(line => line.trim().toLowerCase())
    .filter(line => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(line));
  if (emails.length !== 1 || (expected && emails[0] !== expected.email)) {
    return { code: "mismatch", error: "Claude account does not match" };
  }
  const usage = menu.querySelector('[data-testid="user-menu-usage"]');
  if (!usage) return { code: "layout", error: "Claude Usage menu unavailable" };
  usage.click();

  const meters = await waitFor(() => {
    const matches = [...document.querySelectorAll('[role="meter"]')].filter(element => {
      const label = document.getElementById(element.getAttribute("aria-labelledby"))?.cloneNode(true);
      label?.querySelectorAll('[aria-hidden="true"]').forEach(icon => icon.remove());
      const name = normalize(label?.textContent);
      return name === "This week" || name === "Weekly limit · All models";
    });
    return matches.length ? matches : null;
  });
  const meter = meters?.length === 1 ? meters[0] : null;
  if (!meter || location.hash !== "#settings/usage" || identity().workspace !== workspaceName || identity().plan !== plan) {
    return { code: "layout", error: "The verified workspace's weekly meter was unavailable" };
  }
  const label = document.getElementById(meter.getAttribute("aria-labelledby"));
  let row = meter.parentElement;
  while (row && label && !row.contains(label)) row = row.parentElement;
  const locale = document.documentElement.lang;
  if (locale && !/^en(?:-|$)/i.test(locale)) {
    return { code: "layout", error: "Claude's weekly reset language is unsupported. Use English for usage capture." };
  }
  const resets = row?.innerText.split("\n").map(normalize).filter(line => /^Resets\b/.test(line)) ?? [];
  // Only explicit weekday + local clock formats are supported. Never infer a cycle from a nearby meter.
  const reset = resets.length === 1 && /^Resets (Sun(?:day)?|Mon(?:day)?|Tue(?:sday)?|Wed(?:nesday)?|Thu(?:rsday)?|Fri(?:day)?|Sat(?:urday)?) (\d{1,2}):(\d{2})(?: (AM|PM))?$/.exec(resets[0]);
  const value = meter.getAttribute("aria-valuenow");
  const percent = Number(value);
  const hour = reset && Number(reset[2]);
  const minute = reset && Number(reset[3]);
  if (!reset || !/^\d+(?:\.\d+)?$/.test(value ?? "") || !Number.isFinite(percent) || percent < 0 || percent > 100 ||
      hour < (reset[4] ? 1 : 0) || hour > (reset[4] ? 12 : 23) || minute > 59 ||
      (meter.hasAttribute("aria-valuemin") && meter.getAttribute("aria-valuemin") !== "0") ||
      (meter.hasAttribute("aria-valuemax") && meter.getAttribute("aria-valuemax") !== "100")) {
    return { code: "layout", error: "Claude changed the format of its weekly usage or reset time" };
  }
  const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const now = new Date();
  const date = new Date(now);
  const localHour = reset[4] ? hour % 12 + (reset[4] === "PM" ? 12 : 0) : hour;
  date.setDate(date.getDate() + (days.indexOf(reset[1].slice(0, 3)) - now.getDay() + 7) % 7);
  date.setHours(localHour, minute, 0, 0);
  if (date <= now) date.setDate(date.getDate() + 7);
  if (date.getHours() !== localHour || date.getMinutes() !== minute ||
      date.getDay() !== days.indexOf(reset[1].slice(0, 3)) || date - now > 7 * 86400000 + 3600000) {
    return { code: "layout", error: "Claude's weekly reset time could not be verified in this timezone" };
  }
  // A session can change to an account with the same display name while Usage loads.
  const confirmedMenu = await accountMenu();
  const confirmedEmails = confirmedMenu?.innerText.split("\n").map(line => line.trim().toLowerCase())
    .filter(line => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(line)) ?? [];
  if (confirmedEmails.length !== 1 || confirmedEmails[0] !== emails[0] ||
      identity().workspace !== workspaceName || identity().plan !== plan || location.hash !== "#settings/usage") {
    return { code: "mismatch", error: "Claude account or workspace changed while reading usage" };
  }
  const offerText = document.body.innerText;
  const offer = offerText.includes("No resets right now") ? "None available" : "Unknown";
  return { percent, reset: date.getTime() / 1000, email: emails[0], workspace: workspaceName, plan, offer };
}
