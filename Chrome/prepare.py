"""Prepare a local unpacked companion and Chrome's native host manifest."""
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys

email, workspace = sys.argv[1:]
email = email.casefold()
root = Path(__file__).resolve().parent.parent
exe = (root / ".build/Quota Signal.app/Contents/MacOS/QuotaSignal").resolve(strict=True)
preferences = plistlib.loads(subprocess.check_output(
    ["defaults", "export", "local.quota-signal.widget", "-"]
))
accounts = json.loads(preferences["accounts"])
account, = (item for item in accounts if item["name"].casefold() == email)

destination = root / ".build/Claude Usage Chrome"
destination.mkdir(exist_ok=True)
for filename in ("manifest.json", "worker.js", "usage.js", "setup.html", "setup.js", "command.html", "command.js"):
    shutil.copy2(root / "Chrome" / filename, destination / filename)
binding = {"account": account["id"], "email": email, "workspace": workspace}
(destination / "binding.js").write_text("export const binding = " + json.dumps(binding) + ";\n")

manifest = json.loads((destination / "manifest.json").read_text())
digest = hashlib.sha256(base64.b64decode(manifest["key"])).hexdigest()[:32]
extension_id = digest.translate(str.maketrans("0123456789abcdef", "abcdefghijklmnop"))
host = root / ".build/quota-signal-chrome-host"
host.write_text("#!/bin/sh\nexec " + shlex.join([str(exe), "web-capture"]) + "\n")
host.chmod(0o700)
host_manifest = {
    "name": "local.quota_signal", "description": "Quota Signal local usage bridge",
    "path": str(host), "type": "stdio", "allowed_origins": [f"chrome-extension://{extension_id}/"],
}
(root / ".build/local.quota_signal.json").write_text(json.dumps(host_manifest, indent=2) + "\n")
print(destination)
