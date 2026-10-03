"""Store the Bose tokens in the macOS Keychain (service "SoundbarKeys").

The content is base64-encoded JSON:
    {"access_token", "refresh_token", "azure_refresh_token", "bose_person_id"}

Access goes through /usr/bin/security in interactive mode (-i, commands via stdin) so the
tokens never show up in the process list, and the SoundbarKeys app can read/write the same
items through the same tool without Keychain prompts.
`security -i` only accepts lines up to ~4 KB, so the blob is split across several items:
account "tokens.count" = number of chunks, "tokens.0", "tokens.1", ... = chunks.
"""

import base64
import json
import subprocess

SERVICE = "SoundbarKeys"
CHUNK = 3000


def _security_batch(lines: list[str]) -> None:
    subprocess.run(["/usr/bin/security", "-i"], input="\n".join(lines) + "\n",
                   text=True, check=True, capture_output=True)


def _read(account: str) -> str | None:
    out = subprocess.run(
        ["/usr/bin/security", "find-generic-password", "-s", SERVICE, "-a", account, "-w"],
        text=True, capture_output=True,
    )
    return out.stdout.strip() if out.returncode == 0 else None


def save(tokens: dict) -> None:
    blob = base64.b64encode(json.dumps(tokens).encode()).decode()
    parts = [blob[i:i + CHUNK] for i in range(0, len(blob), CHUNK)]
    add = f"add-generic-password -U -s {SERVICE} -T /usr/bin/security"
    lines = [f"{add} -a tokens.{i} -w {p}" for i, p in enumerate(parts)]
    lines.append(f"{add} -a tokens.count -w {len(parts)}")
    _security_batch(lines)


def load() -> dict:
    count = _read("tokens.count")
    if count is None:
        raise SystemExit("No tokens in the Keychain. Run login.py first.")
    blob = "".join(_read(f"tokens.{i}") or "" for i in range(int(count)))
    return json.loads(base64.b64decode(blob))
