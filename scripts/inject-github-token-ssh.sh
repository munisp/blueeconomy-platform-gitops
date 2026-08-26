#!/usr/bin/env bash
set -Eeuo pipefail

REMOTE="${REMOTE:?set REMOTE to user@external-host}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
REMOTE_ENV="${REMOTE_ENV:-/etc/blueeconomy/pr-monitor.env}"

[[ -r "$SSH_KEY" ]] || { printf 'ERROR: SSH key is not readable: %s\n' "$SSH_KEY" >&2; exit 1; }
command -v ssh >/dev/null 2>&1 || { printf 'ERROR: ssh is required\n' >&2; exit 127; }

read -r -s -p "GitHub token (input hidden): " token
printf '\n' >&2
[[ -n "$token" ]] || { unset token; printf 'ERROR: token was empty\n' >&2; exit 64; }
[[ "$token" != *$'\n'* && "$token" != *$'\r'* ]] || { unset token; printf 'ERROR: token must be a single line\n' >&2; exit 64; }

# The remote command reads the token only from SSH stdin. It writes an atomic
# mode-600 replacement and does not echo, log, or include the token in argv.
remote_python='import os, pathlib, sys, tempfile
path = pathlib.Path(os.environ.get("REMOTE_ENV", "/etc/blueeconomy/pr-monitor.env"))
token = sys.stdin.read().rstrip("\\n")
if not token or "\\n" in token or "\\r" in token:
    raise SystemExit("token input invalid")
path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
existing = path.read_text() if path.exists() else ""
lines = [line for line in existing.splitlines() if not (line.startswith("GH_TOKEN=") or line.startswith("GITHUB_TOKEN="))]
lines.append("GH_TOKEN=" + token)
fd, temporary = tempfile.mkstemp(prefix=".pr-monitor.", dir=str(path.parent), text=True)
os.fchmod(fd, 0o600)
with os.fdopen(fd, "w") as handle:
    handle.write("\\n".join(lines) + "\\n")
os.replace(temporary, path)
os.chmod(path, 0o600)
print("remote token updated")'

# Pass only the Python program in the command and the token through stdin.
# sudo -n intentionally refuses instead of prompting into the token stream.
encoded_python="$(printf '%s' "$remote_python" | base64 -w0)"
remote_env_quoted="$(printf '%q' "$REMOTE_ENV")"
printf '%s' "$token" | ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes "$REMOTE" \
  "REMOTE_ENV=$remote_env_quoted sudo -n python3 -c \"import base64; exec(base64.b64decode('$encoded_python'))\""
unset token
printf '%s\n' 'Token injected remotely without displaying its value.'
