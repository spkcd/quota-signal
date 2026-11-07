const command = location.hash.slice(1);
const target = document.querySelector("#target");
const status = document.querySelector("#status");
const retry = document.querySelector("#retry");
let timer;
let running = false;

async function refresh() {
  if (running) return;
  clearTimeout(timer);
  running = true;
  retry.disabled = true;
  status.textContent = "Checking the requested workspace…";
  try {
    const response = await chrome.runtime.sendMessage({ command });
    if (response?.expected) {
      target.textContent = response.expected.email + " · " + response.expected.workspace;
    }
    if (response?.ok) {
      status.textContent = "Usage refreshed. You can close this tab and return to Quota Signal.";
      retry.hidden = true;
      return;
    }
    status.textContent = response?.error ?? "The request ended. Start Retry or Reconnect again in Quota Signal.";
    if (response?.reconnect) {
      timer = setTimeout(refresh, 5000);
    }
    retry.disabled = response?.expired === true;
  } catch {
    status.textContent = "Update and reload the Quota Signal companion in this Chrome profile, then try again.";
    retry.disabled = false;
  } finally {
    running = false;
  }
}
retry.addEventListener("click", refresh);
void refresh();
