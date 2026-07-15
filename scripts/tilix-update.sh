#!/usr/bin/env bash
# =============================================================================
# tilix-update.sh — keep Cytracon Tilix current from GitHub Releases
#
# Works on every machine (desktop, laptop, multimedia) without building.
# Repo is PUBLIC (https://github.com/cytracon/tilix) — no token required for updates.
# Optional token still helps avoid GitHub API rate limits (60/h unauthenticated).
#
# Optional token lookup:
#   1) $GITHUB_TOKEN / $GH_TOKEN
#   2) ~/.config/tilix/github-token
#   3) ~/.config/gh/hosts.yml
#   4) /root/.github-token
#
# Usage:
#   tilix-update                 # install latest if newer
#   tilix-update --check         # only print status (exit 0=up-to-date, 1=update avail, 2=error)
#   tilix-update --force         # reinstall latest even if same version
#   tilix-update --tag v1.9.8-cytracon.9
#   tilix-update --install-timer # install daily systemd --user timer
#
# Env:
#   TILIX_REPO=cytracon/tilix
#   TILIX_PREFIX=$HOME/.local
#   TILIX_UPDATE_CHANNEL=stable   # reserved
# =============================================================================
set -euo pipefail

REPO="${TILIX_REPO:-cytracon/tilix}"
PREFIX="${TILIX_PREFIX:-$HOME/.local}"
API="https://api.github.com/repos/${REPO}"
CHECK_ONLY=0
FORCE=0
WANT_TAG=""
INSTALL_TIMER=0

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    --tag=*) WANT_TAG="${arg#--tag=}" ;;
    --tag) shift_next=1 ;;
    --install-timer) INSTALL_TIMER=1 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      if [[ "${shift_next:-0}" == 1 ]]; then
        WANT_TAG="$arg"
        shift_next=0
      fi
      ;;
  esac
done

log()  { printf '[tilix-update] %s\n' "$*"; }
err()  { printf '[tilix-update] ERROR: %s\n' "$*" >&2; }
die()  { err "$*"; exit 2; }

resolve_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then echo "$GITHUB_TOKEN"; return; fi
  if [[ -n "${GH_TOKEN:-}" ]]; then echo "$GH_TOKEN"; return; fi
  local f
  for f in \
    "${HOME}/.config/tilix/github-token" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/tilix/github-token" \
    /root/.github-token
  do
    if [[ -f "$f" && -r "$f" ]]; then
      tr -d '[:space:]' < "$f"
      return
    fi
  done
  # gh hosts.yml: oauth_token: ghp_...
  local hosts="${HOME}/.config/gh/hosts.yml"
  if [[ -f "$hosts" ]]; then
    local t
    t="$(sed -n 's/.*oauth_token:[[:space:]]*//p' "$hosts" | head -1 | tr -d '[:space:]')"
    if [[ -n "$t" ]]; then echo "$t"; return; fi
  fi
  return 1
}

api_curl() {
  local url="$1"
  local token="$2"
  if [[ -n "$token" ]]; then
    curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${token}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
  else
    curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$url"
  fi
}

installed_version() {
  local bin=""
  for b in "$PREFIX/libexec/tilix" "$PREFIX/bin/tilix" "$(command -v tilix 2>/dev/null || true)"; do
    if [[ -n "$b" && -x "$b" ]]; then
      # skip shell wrappers that are not ELF
      if file "$b" 2>/dev/null | grep -qi 'ELF'; then
        bin="$b"
        break
      elif [[ -x "$PREFIX/libexec/tilix" ]]; then
        bin="$PREFIX/libexec/tilix"
        break
      fi
    fi
  done
  if [[ -z "$bin" ]]; then
    echo ""
    return
  fi
  "$bin" --version 2>/dev/null \
    | sed -n 's/.*Tilix version:[[:space:]]*//p' \
    | head -1 | tr -d '[:space:]' || true
}

normalize_ver() {
  # strip leading v
  local v="$1"
  v="${v#v}"
  echo "$v"
}

install_timer() {
  local unit_dir="${HOME}/.config/systemd/user"
  mkdir -p "$unit_dir"
  local self
  self="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
  # Prefer installed copy
  if [[ -x "$PREFIX/bin/tilix-update" ]]; then
    self="$PREFIX/bin/tilix-update"
  else
    install -Dm755 "$self" "$PREFIX/bin/tilix-update"
    self="$PREFIX/bin/tilix-update"
  fi

  cat > "$unit_dir/tilix-update.service" << EOF
[Unit]
Description=Update Cytracon Tilix from GitHub Releases
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${self}
Nice=10
EOF

  cat > "$unit_dir/tilix-update.timer" << 'EOF'
[Unit]
Description=Daily Cytracon Tilix update check

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=45m

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now tilix-update.timer
  log "Timer enabled (systemd --user). Status:"
  systemctl --user status tilix-update.timer --no-pager 2>/dev/null | head -12 || true
  log "Manual: systemctl --user start tilix-update.service"
}

if [[ "$INSTALL_TIMER" == 1 ]]; then
  install_timer
  exit 0
fi

TOKEN=""
if ! TOKEN="$(resolve_token)"; then
  TOKEN=""
fi

if [[ -z "$TOKEN" ]]; then
  err "Kein GitHub-Token (Repo ist privat)."
  err "Lege an:  mkdir -p ~/.config/tilix && chmod 700 ~/.config/tilix"
  err "          echo 'ghp_...' > ~/.config/tilix/github-token && chmod 600 ~/.config/tilix/github-token"
  err "Token braucht: Contents (Read) auf cytracon/tilix — Fine-grained PAT oder classic 'repo'."
  exit 2
fi

CUR="$(normalize_ver "$(installed_version)")"
log "Installed: ${CUR:-<none>}"

JSON=""
ASSET_URL=""
REL_TAG=""
REL_NAME=""

if [[ -n "$WANT_TAG" ]]; then
  log "Fetching release tag ${WANT_TAG}…"
  JSON="$(api_curl "${API}/releases/tags/${WANT_TAG}" "$TOKEN")" \
    || die "Release ${WANT_TAG} nicht gefunden (oder Token-Rechte)."
else
  log "Fetching latest release from ${REPO}…"
  JSON="$(api_curl "${API}/releases/latest" "$TOKEN")" \
    || die "Kein latest Release (noch nie published?) oder Token-Rechte fehlen."
fi

# Prefer jq if available, else python3
if command -v jq >/dev/null 2>&1; then
  REL_TAG="$(echo "$JSON" | jq -r '.tag_name // empty')"
  REL_NAME="$(echo "$JSON" | jq -r '.name // empty')"
  ASSET_URL="$(echo "$JSON" | jq -r '[.assets[] | select(.name | test("linux-x86_64\\.tar\\.gz$")) | .url][0] // empty')"
  ASSET_NAME="$(echo "$JSON" | jq -r '[.assets[] | select(.name | test("linux-x86_64\\.tar\\.gz$")) | .name][0] // empty')"
else
  export TILIX_REL_JSON="$JSON"
  eval "$(python3 - <<'PY'
import json, os
j=json.loads(os.environ["TILIX_REL_JSON"])
print("REL_TAG=%r" % (j.get("tag_name") or ""))
print("REL_NAME=%r" % (j.get("name") or ""))
url=""; name=""
for a in j.get("assets") or []:
    n=a.get("name") or ""
    if n.endswith("linux-x86_64.tar.gz"):
        url=a.get("url") or ""; name=n; break
print("ASSET_URL=%r" % url)
print("ASSET_NAME=%r" % name)
PY
)"
  unset TILIX_REL_JSON
fi

[[ -n "$REL_TAG" ]] || die "Release ohne tag_name."
[[ -n "$ASSET_URL" ]] || die "Kein linux-x86_64.tar.gz Asset im Release ${REL_TAG}."

NEW="$(normalize_ver "$REL_TAG")"
log "Latest:    ${NEW} (${ASSET_NAME})"

if [[ "$CHECK_ONLY" == 1 ]]; then
  if [[ -n "$CUR" && "$CUR" == "$NEW" ]]; then
    log "Up to date."
    exit 0
  fi
  log "Update available: ${CUR:-none} → ${NEW}"
  exit 1
fi

if [[ "$FORCE" != 1 && -n "$CUR" && "$CUR" == "$NEW" ]]; then
  log "Already on ${CUR} — nothing to do (use --force to reinstall)."
  exit 0
fi

TMP="$(mktemp -d /tmp/tilix-update.XXXXXX)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

TAR="${TMP}/${ASSET_NAME}"
log "Downloading ${ASSET_NAME}…"
curl -fsSL \
  -H "Accept: application/octet-stream" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -o "$TAR" \
  "$ASSET_URL"

# Basic sanity
[[ -s "$TAR" ]] || die "Download empty."
file "$TAR" | grep -qi 'gzip\|tar' || die "Download is not a tar.gz (got: $(file -b "$TAR"))"

log "Extracting…"
tar -xzf "$TAR" -C "$TMP"
STAGE="$(find "$TMP" -maxdepth 2 -type f -name 'install-remote.sh' -printf '%h\n' | head -1)"
if [[ -z "$STAGE" ]]; then
  STAGE="$(find "$TMP" -maxdepth 2 -type f -name 'install-from-package.sh' -printf '%h\n' | head -1)"
fi
[[ -n "$STAGE" && -d "$STAGE" ]] || die "Package layout unexpected (no install-remote.sh)."

# Prefer install-from-package.sh if present
if [[ -x "$STAGE/install-from-package.sh" ]]; then
  INSTALLER="$STAGE/install-from-package.sh"
elif [[ -x "$STAGE/install-remote.sh" ]]; then
  INSTALLER="$STAGE/install-remote.sh"
else
  die "No installer in package."
fi

# Also drop this updater next to tilix
install -Dm755 "$0" "$PREFIX/bin/tilix-update" 2>/dev/null || true

log "Installing into ${PREFIX}…"
PREFIX="$PREFIX" bash "$INSTALLER"

# Re-copy updater from package if shipped
if [[ -x "$STAGE/bin/tilix-update" ]]; then
  install -Dm755 "$STAGE/bin/tilix-update" "$PREFIX/bin/tilix-update"
fi

NEW_INST="$(normalize_ver "$(installed_version)")"
log "Now running: ${NEW_INST:-?}"
if [[ -n "$NEW_INST" && "$NEW_INST" != "$NEW" ]]; then
  err "Version mismatch after install (expected $NEW, got $NEW_INST)."
  exit 2
fi

log "OK. Fully quit Tilix (pkill -x tilix) and start again to load the new binary."
