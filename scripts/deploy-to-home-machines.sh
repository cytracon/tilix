#!/usr/bin/env bash
# Deploy Cytracon Tilix to bbachmann-laptop and multimedia-laptop
set -euo pipefail
TAR="${1:-/tmp/tilix-cytracon-1.9.8-cytracon.4-linux-x86_64.tar.gz}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
[ -f "$KEY" ] || KEY="$HOME/.ssh/id_cytracon2"
USER_NAME="${REMOTE_USER:-bbachmann}"

if [ ! -f "$TAR" ]; then
  echo "Missing package: $TAR" >&2
  echo "Build on desktop first (see scripts)." >&2
  exit 1
fi

deploy() {
  local name="$1" ip="$2"
  echo ">>> $name ($ip)"
  ping -c 1 -W 2 "$ip" >/dev/null || { echo "offline"; return 1; }
  scp -o BatchMode=yes -o ConnectTimeout=8 -o IdentitiesOnly=yes -i "$KEY" \
    "$TAR" "${USER_NAME}@${ip}:/tmp/"
  ssh -o BatchMode=yes -o ConnectTimeout=15 -o IdentitiesOnly=yes -i "$KEY" \
    "${USER_NAME}@${ip}" "cd /tmp && tar -xzf $(basename "$TAR") && cd tilix-cytracon-deploy && ./install-remote.sh"
  echo "OK $name"
}

deploy bbachmann-laptop 192.168.178.162
deploy multimedia-laptop 192.168.178.164
echo "Done."
