const status = document.querySelector("#status");
const pair = location.hash.slice(1);

async function connect() {
  try {
    const response = await chrome.runtime.sendMessage({ pair });
    if (response?.ok) {
      const { email, workspace, plan, percent } = response.reading;
      status.textContent = `Connected ${workspace} (${plan}) for ${email}. Weekly usage is ${percent}%.`;
      return;
    }
    if (response?.alreadyConnected) {
      status.textContent = "This workspace is already connected. Sign in to or switch to the new workspace.";
    } else {
      status.textContent = response?.error ?? "Waiting for Claude sign-in.";
      if (response?.error?.includes("Open + in Quota Signal")) return;
    }
  } catch {
    status.textContent = "Could not reach the companion. Open + in Quota Signal again.";
    return;
  }
  setTimeout(connect, 5000);
}

status.textContent = "Checking your Claude workspace…";
void connect();
